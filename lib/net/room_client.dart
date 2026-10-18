import 'dart:async';
import 'dart:convert';

import 'package:beatdrop_shared/beatdrop_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../platform/platform.dart';

class RoomException implements Exception {
  RoomException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One player's connection to a room: keeps the local clock in step with
/// the server's, mirrors the room state and sends this player's actions.
///
/// Times passed in and out are server microseconds unless named `local`.
class RoomClient extends ChangeNotifier {
  RoomClient(this.url);

  final Uri url;
  final sync = ClockSyncEstimator();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Completer<void>? _joining;
  final _errors = StreamController<String>.broadcast();

  String _name = '';
  bool _disposed = false;

  RoomSnapshot? room;
  String? playerId;

  /// False while a dropped connection is being retried.
  bool connected = false;

  /// Set once the room is gone for good.
  String? closedReason;

  /// Problems worth a toast, like starting with nobody in the room.
  Stream<String> get errors => _errors.stream;

  bool get isGm => room != null && room!.gmId == playerId;
  bool get isParticipant => room?.participants.contains(playerId) ?? false;

  /// Best round trip to the server in ms; null before the first sample.
  int? get rttMs => switch (sync.bestRtt) {
    final int us => (us / 1000).round(),
    null => null,
  };

  int serverNow() => toServer(perfNowMicros());
  int toServer(int local) => local + (sync.hasEstimate ? sync.offset : 0);
  int toLocal(int server) => server - (sync.hasEstimate ? sync.offset : 0);

  Future<void> create(String name) {
    _name = name;
    return _request({'t': Msg.create, 'name': name});
  }

  Future<void> join(String code, String name) {
    _name = name;
    return _request({'t': Msg.join, 'code': code, 'name': name});
  }

  void setGmPlays(bool gmPlays) =>
      _send({'t': Msg.setGmPlays, 'gmPlays': gmPlays});
  void start() => _send({'t': Msg.start});
  void reset() => _send({'t': Msg.reset});
  void reportSongStart(int at) => _send({'t': Msg.songStarted, 'at': at});
  void tap(int at) => _send({'t': Msg.tap, 'at': at});

  void leave() {
    _send({'t': Msg.leave});
    dispose();
  }

  Future<void> _request(Map<String, Object?> msg) async {
    final joining = _joining = Completer<void>();
    try {
      await _connect();
    } catch (_) {
      _joining = null;
      throw RoomException("Can't reach the game server");
    }
    _send(msg);
    return joining.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw RoomException('The game server did not answer'),
    );
  }

  Future<void> _connect() async {
    if (_channel != null) return;
    final channel = _channel = WebSocketChannel.connect(url);
    try {
      await channel.ready;
    } catch (_) {
      _channel = null;
      rethrow;
    }
    _sub = channel.stream.listen(
      _onMessage,
      onDone: _onDisconnect,
      onError: (_) {},
    );
    connected = true;
    // A quick burst fills the clock filter, then a steady trickle tracks
    // drift and catches the occasional fast round trip.
    var burst = 10;
    _ping();
    _pingTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (--burst > 0) return _ping();
      t.cancel();
      _pingTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _ping(),
      );
    });
    _notify();
  }

  void _ping() => _send({'t': Msg.ping, 'c0': perfNowMicros(), 'rtt': rttMs});

  void _send(Map<String, Object?> msg) => _channel?.sink.add(jsonEncode(msg));

  void _onMessage(dynamic data) {
    final msg = (jsonDecode(data as String) as Map).cast<String, Object?>();
    switch (msg['t']) {
      case Msg.pong:
        sync.addSample(msg['c0'] as int, msg['s'] as int, perfNowMicros());
      case Msg.joined:
        playerId = msg['playerId'] as String;
        _joining?.complete();
        _joining = null;
      case Msg.room:
        room = RoomSnapshot.fromJson(msg);
        _notify();
      case Msg.error:
        final text = msg['msg'] as String;
        if (_joining case final joining?) {
          _joining = null;
          joining.completeError(RoomException(text));
          // Rejoining after a drop failed: the room is gone.
          if (room != null) _close(text);
        } else {
          _errors.add(text);
        }
      case Msg.closed:
        _close(msg['msg'] as String);
    }
  }

  void _onDisconnect() {
    _teardownSocket();
    if (_disposed || closedReason != null) return;
    if (_joining case final joining?) {
      _joining = null;
      joining.completeError(RoomException('Lost connection to the server'));
    }
    if (room == null) return;
    connected = false;
    _notify();
    _reconnect(const Duration(seconds: 1));
  }

  /// Keeps retrying, then rejoins as the same player so the seat (and any
  /// tap already sent) is kept.
  void _reconnect(Duration delay) {
    _reconnectTimer = Timer(delay, () async {
      if (_disposed) return;
      try {
        await _request({
          't': Msg.join,
          'code': room!.code,
          'name': _name,
          'playerId': playerId,
        });
      } on RoomException {
        if (closedReason != null) return;
        final next = delay * 2;
        _reconnect(next > const Duration(seconds: 8) ? delay : next);
      }
    });
  }

  void _close(String reason) {
    closedReason = reason;
    _teardownSocket();
    _notify();
  }

  void _teardownSocket() {
    _pingTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    connected = false;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _teardownSocket();
    _errors.close();
    super.dispose();
  }
}
