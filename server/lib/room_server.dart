import 'dart:async';
import 'dart:math';

import 'package:beatdrop_shared/beatdrop_shared.dart';

typedef Json = Map<String, Object?>;

/// Server time in microseconds.
typedef Clock = int Function();

/// Monotonic server clock: wall time at boot plus a stopwatch, so NTP
/// adjustments on the host can't make it jump mid-round.
Clock monotonicClock() {
  final boot = DateTime.now().microsecondsSinceEpoch;
  final sw = Stopwatch()..start();
  return () => boot + sw.elapsedMicroseconds;
}

/// One WebSocket connection.
class Session {
  Session(this.send);

  final void Function(Json) send;
  _Player? _player;
  _Room? _room;
}

class _Player {
  _Player(this.id, this.name, this.color);

  final String id;
  String name;
  final int color;
  Session? session;
  int? rttMs;
  Timer? removeTimer;

  bool get connected => session != null;
}

class _Room {
  _Room(this.code, this.gmId);

  final String code;
  final String gmId;
  bool gmPlays = true;
  RoomPhase phase = RoomPhase.lobby;
  int round = 0;
  final players = <String, _Player>{};

  /// Lowest palette slot nobody in the room is using.
  int freeColor() {
    final used = {for (final p in players.values) p.color};
    var c = 0;
    while (used.contains(c)) {
      c++;
    }
    return c % playerColorCount;
  }

  int? startAt;

  /// When the song became audible, as reported by the host. Starts out as
  /// [startAt] in case the report never arrives.
  int? songStart;
  List<String> participants = [];
  final taps = <String, int>{};
  List<PlayerResult>? results;
  Timer? finishTimer;

  RoomSnapshot snapshot() => RoomSnapshot(
    code: code,
    gmId: gmId,
    gmPlays: gmPlays,
    phase: phase,
    round: round,
    players: [
      for (final p in players.values)
        PlayerInfo(
          id: p.id,
          name: p.name,
          connected: p.connected,
          color: p.color,
          rttMs: p.rttMs,
        ),
    ],
    startAt: startAt,
    participants: participants,
    results: results,
  );
}

/// Room state and game rules, independent of the transport so it can be
/// tested without sockets.
class RoomServer {
  RoomServer({
    Clock? clock,
    this.disconnectGrace = const Duration(seconds: 60),
    Random? random,
  }) : now = clock ?? monotonicClock(),
       _random = random ?? Random.secure();

  final Clock now;

  /// How long a dropped player keeps their seat, so a phone that briefly
  /// loses signal or backgrounds the tab can rejoin as the same player.
  final Duration disconnectGrace;
  final Random _random;
  final _rooms = <String, _Room>{};

  int get roomCount => _rooms.length;

  void handle(Session s, Json msg) {
    switch (msg['t']) {
      case Msg.ping:
        _onPing(s, msg);
      case Msg.create:
        _onCreate(s, msg);
      case Msg.join:
        _onJoin(s, msg);
      case Msg.setGmPlays:
        _onSetGmPlays(s, msg);
      case Msg.start:
        _onStart(s);
      case Msg.songStarted:
        _onSongStarted(s, msg);
      case Msg.tap:
        _onTap(s, msg);
      case Msg.reset:
        _onReset(s);
      case Msg.leave:
        final room = s._room;
        final player = s._player;
        _detach(s);
        if (room != null && player != null) _removePlayer(room, player);
    }
  }

  void disconnect(Session s) {
    final room = s._room;
    final player = s._player;
    _detach(s);
    if (room == null || player == null) return;
    player.removeTimer = Timer(
      disconnectGrace,
      () => _removePlayer(room, player),
    );
    _broadcast(room);
  }

  void _onPing(Session s, Json msg) {
    s.send({'t': Msg.pong, 'c0': msg['c0'], 's': now()});
    final player = s._player;
    final rtt = msg['rtt'];
    if (player == null || rtt is! int) return;
    final old = player.rttMs;
    player.rttMs = rtt;
    // Only rebroadcast noticeable changes; pings arrive every half second.
    if (old == null || (old - rtt).abs() >= 10) _broadcast(s._room!);
  }

  void _onCreate(Session s, Json msg) {
    _leaveCurrent(s);
    String code;
    do {
      code = generateRoomCode(_random);
    } while (_rooms.containsKey(code));
    final gm = _Player(_newId(), _cleanName(msg['name'], 1), 0);
    final room = _rooms[code] = _Room(code, gm.id);
    _attach(s, room, gm);
  }

  void _onJoin(Session s, Json msg) {
    final code = normalizeRoomCode('${msg['code'] ?? ''}');
    final room = code == null ? null : _rooms[code];
    if (room == null) return _error(s, 'Room not found');

    final existing = room.players[msg['playerId']];
    if (existing != null) {
      if (existing.session != null && existing.session != s) {
        _detach(existing.session!);
      }
      _leaveCurrent(s, except: room);
      existing.removeTimer?.cancel();
      _attach(s, room, existing);
      return;
    }
    if (room.players.length >= maxPlayers) {
      return _error(s, 'Room is full ($maxPlayers players)');
    }
    _leaveCurrent(s);
    final player = _Player(
      _newId(),
      _cleanName(msg['name'], room.players.length + 1),
      room.freeColor(),
    );
    _attach(s, room, player);
  }

  void _onSetGmPlays(Session s, Json msg) {
    final room = _gmRoom(s);
    if (room == null || room.phase == RoomPhase.playing) return;
    room.gmPlays = msg['gmPlays'] == true;
    _broadcast(room);
  }

  void _onStart(Session s) {
    final room = _gmRoom(s);
    if (room == null || room.phase == RoomPhase.playing) return;
    final participants = [
      for (final p in room.players.values)
        if (p.connected && (room.gmPlays || p.id != room.gmId)) p.id,
    ];
    if (participants.isEmpty) return _error(s, 'Nobody is playing yet');

    final startAt = now() + countdownLead.inMicroseconds;
    room
      ..phase = RoomPhase.playing
      ..round += 1
      ..startAt = startAt
      ..songStart = startAt
      ..participants = participants
      ..results = null
      ..taps.clear();
    // Extra second in case the host's songStarted report is delayed.
    _scheduleFinish(
      room,
      _dropAt(room) + lateTapWindow.inMicroseconds + 1000000,
    );
    _broadcast(room);
  }

  void _onSongStarted(Session s, Json msg) {
    final room = _gmRoom(s);
    final at = msg['at'];
    if (room == null || room.phase != RoomPhase.playing || at is! int) return;
    // Ignore nonsense; the scheduled start is a fine fallback.
    if ((at - room.startAt!).abs() > 2000000) return;
    room.songStart = at;
    _scheduleFinish(room, _dropAt(room) + lateTapWindow.inMicroseconds);
  }

  void _onTap(Session s, Json msg) {
    final room = s._room;
    final player = s._player;
    final at = msg['at'];
    if (room == null ||
        player == null ||
        at is! int ||
        room.phase != RoomPhase.playing ||
        !room.participants.contains(player.id) ||
        room.taps.containsKey(player.id)) {
      return;
    }
    // The client stamps the tap itself, so a slow network can't hurt it. In
    // return, keep the stamp plausible: not in the future, and not older
    // than the trip here could have taken.
    final received = now();
    final rtt = (player.rttMs ?? 300) * 1000;
    room.taps[player.id] = at.clamp(received - (2 * rtt + 250000), received);
    _finishEarlyIfAllTapped(room);
  }

  void _onReset(Session s) {
    final room = _gmRoom(s);
    if (room == null || room.phase != RoomPhase.results) return;
    room
      ..phase = RoomPhase.lobby
      ..results = null;
    _broadcast(room);
  }

  int _dropAt(_Room room) => room.songStart! + songDropTime.inMicroseconds;

  void _finishEarlyIfAllTapped(_Room room) {
    if (!room.participants.every(room.taps.containsKey)) return;
    // Still reveal nothing before the drop has been heard.
    _scheduleFinish(room, max(now(), _dropAt(room) + 500000));
  }

  void _scheduleFinish(_Room room, int at) {
    room.finishTimer?.cancel();
    room.finishTimer = Timer(
      Duration(microseconds: max(0, at - now())),
      () => _finish(room),
    );
  }

  void _finish(_Room room) {
    if (room.phase != RoomPhase.playing) return;
    room
      ..phase = RoomPhase.results
      ..results = rankResults([
        for (final id in room.participants)
          if (room.players[id] case final p?)
            PlayerResult(
              id: id,
              name: p.name,
              offset: switch (tapOffsetMicros(
                tapAt: room.taps[id],
                songStart: room.songStart!,
              )) {
                final int us => Duration(microseconds: us),
                null => null,
              },
            ),
      ]);
    _broadcast(room);
  }

  void _attach(Session s, _Room room, _Player player) {
    room.players[player.id] = player;
    player.session = s;
    s
      .._room = room
      .._player = player;
    s.send({'t': Msg.joined, 'playerId': player.id});
    _broadcast(room);
  }

  void _detach(Session s) {
    s._player?.session = null;
    s
      .._room = null
      .._player = null;
  }

  void _leaveCurrent(Session s, {_Room? except}) {
    final room = s._room;
    final player = s._player;
    if (room == null || player == null || room == except) return;
    _detach(s);
    _removePlayer(room, player);
  }

  void _removePlayer(_Room room, _Player player) {
    player.removeTimer?.cancel();
    if (room.players.remove(player.id) == null) return;
    if (player.id == room.gmId || room.players.isEmpty) {
      return _closeRoom(room, 'The host left the room');
    }
    if (room.phase == RoomPhase.playing) {
      room.participants = [...room.participants]..remove(player.id);
      _finishEarlyIfAllTapped(room);
    }
    _broadcast(room);
  }

  void _closeRoom(_Room room, String reason) {
    room.finishTimer?.cancel();
    _rooms.remove(room.code);
    for (final p in room.players.values) {
      p.removeTimer?.cancel();
      final s = p.session;
      if (s == null) continue;
      _detach(s);
      s.send({'t': Msg.closed, 'msg': reason});
    }
  }

  _Room? _gmRoom(Session s) {
    final room = s._room;
    return room != null && s._player?.id == room.gmId ? room : null;
  }

  void _broadcast(_Room room) {
    final snapshot = room.snapshot().toJson();
    for (final p in room.players.values) {
      p.session?.send(snapshot);
    }
  }

  void _error(Session s, String msg) => s.send({'t': Msg.error, 'msg': msg});

  String _newId() => [
    for (var i = 0; i < 12; i++) _random.nextInt(16).toRadixString(16),
  ].join();

  static String _cleanName(Object? name, int n) {
    final s = '${name ?? ''}'.trim();
    if (s.isEmpty) return 'Player $n';
    return s.length > 20 ? s.substring(0, 20) : s;
  }
}
