import 'package:beatdrop_server/room_server.dart';
import 'package:beatdrop_shared/beatdrop_shared.dart';
import 'package:test/test.dart';

class FakeClient {
  FakeClient(RoomServer server) {
    session = Session(inbox.add);
    _server = server;
  }

  late final Session session;
  late final RoomServer _server;
  final inbox = <Json>[];

  void send(Json msg) => _server.handle(session, msg);

  Json last(String type) => inbox.lastWhere((m) => m['t'] == type);
  RoomSnapshot get room => RoomSnapshot.fromJson(last(Msg.room));
  String get playerId => last(Msg.joined)['playerId'] as String;
}

void main() {
  late int clock;
  late RoomServer server;

  setUp(() {
    clock = 1000000000;
    server = RoomServer(clock: () => clock);
  });

  FakeClient client() => FakeClient(server);

  test('pong echoes c0 with server time', () {
    final c = client()..send({'t': Msg.ping, 'c0': 42});
    expect(c.last(Msg.pong), {'t': Msg.pong, 'c0': 42, 's': clock});
  });

  test('create and join share one room', () {
    final gm = client()..send({'t': Msg.create, 'name': 'Host'});
    final code = gm.room.code;
    final p = client()
      ..send({'t': Msg.join, 'code': code.toLowerCase(), 'name': 'Ann'});
    expect(p.room.players.map((p) => p.name), ['Host', 'Ann']);
    expect(gm.room.gmId, gm.playerId);
  });

  test('gives every player a distinct colour and reuses freed ones', () {
    final gm = client()..send({'t': Msg.create});
    final code = gm.room.code;
    final a = client()..send({'t': Msg.join, 'code': code});
    client().send({'t': Msg.join, 'code': code});
    expect(gm.room.players.map((p) => p.color), [0, 1, 2]);
    a.send({'t': Msg.leave});
    client().send({'t': Msg.join, 'code': code});
    expect(gm.room.players.map((p) => p.color), [0, 2, 1]);
  });

  test('rejects unknown rooms and the 13th player', () {
    final c = client()..send({'t': Msg.join, 'code': 'ZZZZZZ'});
    expect(c.last(Msg.error)['msg'], 'Room not found');

    final gm = client()..send({'t': Msg.create});
    for (var i = 1; i < maxPlayers; i++) {
      client().send({'t': Msg.join, 'code': gm.room.code});
    }
    final extra = client()..send({'t': Msg.join, 'code': gm.room.code});
    expect(extra.last(Msg.error)['msg'], startsWith('Room is full'));
  });

  test('scores taps against the reported song start', () async {
    final gm = client()..send({'t': Msg.create, 'name': 'Host'});
    final p = client()
      ..send({'t': Msg.join, 'code': gm.room.code, 'name': 'Ann'});
    gm.send({'t': Msg.setGmPlays, 'gmPlays': false});
    gm.send({'t': Msg.start});

    final room = p.room;
    expect(room.phase, RoomPhase.playing);
    expect(room.participants, [p.playerId]);
    expect(room.startAt, clock + countdownLead.inMicroseconds);

    // The host's speaker actually started 40 ms after the scheduled time.
    final songStart = room.startAt! + 40000;
    gm.send({'t': Msg.songStarted, 'at': songStart});

    final drop = songStart + songDropTime.inMicroseconds;
    clock = drop + 600000;
    p.send({'t': Msg.ping, 'c0': 0, 'rtt': 300});
    // Tapped 25 ms early; the message only arrives 600 ms after the drop.
    p.send({'t': Msg.tap, 'at': drop - 25000});

    await Future<void>.delayed(Duration.zero);
    final results = p.room.results!;
    expect(p.room.phase, RoomPhase.results);
    expect(results.single.offset, const Duration(milliseconds: -25));
  });

  test('clamps taps claiming to be from the future or long ago', () async {
    final gm = client()..send({'t': Msg.create});
    final a = client()
      ..send({'t': Msg.join, 'code': gm.room.code, 'name': 'A'});
    final b = client()
      ..send({'t': Msg.join, 'code': gm.room.code, 'name': 'B'});
    gm.send({'t': Msg.setGmPlays, 'gmPlays': false});
    gm.send({'t': Msg.start});
    final drop = gm.room.startAt! + songDropTime.inMicroseconds;

    clock = drop + 1000000;
    a.send({'t': Msg.ping, 'c0': 0, 'rtt': 50});
    b.send({'t': Msg.ping, 'c0': 0, 'rtt': 50});
    a.send({'t': Msg.tap, 'at': drop + 5000000}); // future
    b.send({'t': Msg.tap, 'at': drop}); // pretends it was perfect

    await Future<void>.delayed(Duration.zero);
    final byName = {for (final r in gm.room.results!) r.name: r.offset};
    expect(byName['A'], const Duration(seconds: 1));
    // Can be at most 2 x 50 ms + 250 ms before arriving.
    expect(byName['B'], const Duration(milliseconds: 650));
  });

  test('reconnecting with the same playerId keeps the seat', () {
    final gm = client()..send({'t': Msg.create});
    final p = client()
      ..send({'t': Msg.join, 'code': gm.room.code, 'name': 'Ann'});
    server.disconnect(p.session);
    expect(gm.room.players.last.connected, isFalse);

    final again = client()
      ..send({
        't': Msg.join,
        'code': gm.room.code,
        'name': 'Ann',
        'playerId': p.playerId,
      });
    expect(again.playerId, p.playerId);
    expect(gm.room.players.length, 2);
    expect(gm.room.players.last.connected, isTrue);
  });

  test('closes the room when the host leaves', () {
    final gm = client()..send({'t': Msg.create});
    final p = client()..send({'t': Msg.join, 'code': gm.room.code});
    gm.send({'t': Msg.leave});
    expect(p.last(Msg.closed)['msg'], isNotEmpty);
    expect(server.roomCount, 0);
  });
}
