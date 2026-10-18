/// Wire protocol between the app and the room server.
///
/// Every message is a JSON object whose `t` field names its type. All times
/// are integer microseconds on the server's clock unless noted otherwise.
library;

import 'scoring.dart';

const maxPlayers = 12;

/// One palette slot per seat, so every player in a room gets their own.
const playerColorCount = maxPlayers;

/// Time from the start of the song to the beat drop.
const songDropTime = Duration(milliseconds: 11400);

/// Gap between the host pressing Start and the song starting, so every phone
/// has time to receive the start time and count down together.
const countdownLead = Duration(seconds: 3);

/// How long after the drop the round stays open for late taps.
const lateTapWindow = Duration(seconds: 3);

/// Message types (`t` field).
abstract final class Msg {
  // Client -> server.
  static const ping = 'ping'; // {c0, rtt?}
  static const create = 'create'; // {name}
  static const join = 'join'; // {code, name, playerId?}
  static const setGmPlays = 'setGmPlays'; // {gmPlays}
  static const start = 'start'; // {}
  static const songStarted = 'songStarted'; // {at}
  static const tap = 'tap'; // {at}
  static const reset = 'reset'; // {}
  static const leave = 'leave'; // {}

  // Server -> client.
  static const pong = 'pong'; // {c0, s}
  static const joined = 'joined'; // {playerId}
  static const room = 'room'; // RoomSnapshot
  static const error = 'error'; // {msg}
  static const closed = 'closed'; // {msg}
}

enum RoomPhase { lobby, playing, results }

class PlayerInfo {
  const PlayerInfo({
    required this.id,
    required this.name,
    required this.connected,
    required this.color,
    this.rttMs,
  });

  final String id;
  final String name;
  final bool connected;

  /// Index into the app's player palette, unique within the room.
  final int color;

  /// Best round trip to the server, as reported by the player's clock sync.
  final int? rttMs;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'connected': connected,
    'color': color,
    'rttMs': rttMs,
  };

  factory PlayerInfo.fromJson(Map<String, Object?> j) => PlayerInfo(
    id: j['id'] as String,
    name: j['name'] as String,
    connected: j['connected'] as bool,
    color: j['color'] as int,
    rttMs: j['rttMs'] as int?,
  );
}

/// Everything a client needs to render the room; broadcast on every change.
class RoomSnapshot {
  const RoomSnapshot({
    required this.code,
    required this.gmId,
    required this.gmPlays,
    required this.phase,
    required this.round,
    required this.players,
    this.startAt,
    this.participants = const [],
    this.results,
  });

  final String code;
  final String gmId;
  final bool gmPlays;
  final RoomPhase phase;

  /// Increments with every started round.
  final int round;
  final List<PlayerInfo> players;

  /// When the song becomes audible, on the server clock.
  final int? startAt;

  /// Player ids with a drum in the current round.
  final List<String> participants;
  final List<PlayerResult>? results;

  Map<String, Object?> toJson() => {
    't': Msg.room,
    'code': code,
    'gmId': gmId,
    'gmPlays': gmPlays,
    'phase': phase.name,
    'round': round,
    'players': [for (final p in players) p.toJson()],
    'startAt': startAt,
    'participants': participants,
    'results': results == null ? null : [for (final r in results!) r.toJson()],
  };

  factory RoomSnapshot.fromJson(Map<String, Object?> j) => RoomSnapshot(
    code: j['code'] as String,
    gmId: j['gmId'] as String,
    gmPlays: j['gmPlays'] as bool,
    phase: RoomPhase.values.byName(j['phase'] as String),
    round: j['round'] as int,
    players: [
      for (final p in j['players'] as List)
        PlayerInfo.fromJson((p as Map).cast()),
    ],
    startAt: j['startAt'] as int?,
    participants: (j['participants'] as List).cast<String>(),
    results: (j['results'] as List?)
        ?.map((r) => PlayerResult.fromJson((r as Map).cast()))
        .toList(),
  );
}
