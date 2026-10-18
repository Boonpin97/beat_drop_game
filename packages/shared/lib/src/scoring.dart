import 'protocol.dart';

/// Signed distance from the drop: negative is early, positive is late.
/// Null when the player never tapped.
int? tapOffsetMicros({required int? tapAt, required int songStart}) =>
    tapAt == null ? null : tapAt - (songStart + songDropTime.inMicroseconds);

String rating(Duration d) {
  final ms = d.inMilliseconds.abs();
  if (ms < 50) return 'PERFECT!';
  if (ms < 150) return 'Great';
  if (ms < 400) return 'Good';
  return 'Off beat';
}

/// Seconds with millisecond precision, e.g. `1.234`.
String formatSeconds(Duration d) =>
    (d.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(3);

class PlayerResult {
  const PlayerResult({required this.id, required this.name, this.offset});

  final String id;
  final String name;

  /// Null means the player missed (never tapped).
  final Duration? offset;

  bool get missed => offset == null;
  bool get late => offset != null && offset! > Duration.zero;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'offset': offset?.inMicroseconds,
  };

  factory PlayerResult.fromJson(Map<String, Object?> j) => PlayerResult(
    id: j['id'] as String,
    name: j['name'] as String,
    offset: switch (j['offset']) {
      final int us => Duration(microseconds: us),
      _ => null,
    },
  );
}

/// Early (or exact) taps first, closest to the drop first; then late taps,
/// least late first; misses last. Any late tap ranks below every early one.
List<PlayerResult> rankResults(Iterable<PlayerResult> results) {
  int group(PlayerResult r) => r.missed ? 2 : (r.late ? 1 : 0);
  return results.toList()..sort((a, b) {
    final byGroup = group(a) - group(b);
    if (byGroup != 0 || a.missed) return byGroup;
    return a.offset!.abs().compareTo(b.offset!.abs());
  });
}
