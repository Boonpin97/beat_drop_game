/// Estimates the offset between a local monotonic clock and the server clock
/// from NTP-style ping/pong samples.
///
/// Round trips are rarely symmetric, and the asymmetry is the error in the
/// estimate. It can be at most half the round trip, so samples with the
/// shortest round trips are the most trustworthy: the estimate is the median
/// offset of the [bestOf] fastest of the last [window] samples.
class ClockSyncEstimator {
  ClockSyncEstimator({this.window = 20, this.bestOf = 5});

  final int window;
  final int bestOf;

  final _samples = <({int rtt, int offset})>[];

  /// Records one exchange: the local time the ping was sent ([c0]), the
  /// server time in the pong ([s]) and the local time the pong arrived
  /// ([c1]), all in microseconds.
  void addSample(int c0, int s, int c1) {
    final rtt = c1 - c0;
    if (rtt < 0) return;
    _samples.add((rtt: rtt, offset: s - (c0 + rtt ~/ 2)));
    if (_samples.length > window) _samples.removeAt(0);
  }

  bool get hasEstimate => _samples.isNotEmpty;
  int get sampleCount => _samples.length;

  /// Server time minus local time, in microseconds.
  int get offset {
    if (_samples.isEmpty) throw StateError('No clock samples yet');
    final best =
        (_samples.toList()..sort((a, b) => a.rtt - b.rtt))
            .take(bestOf)
            .map((s) => s.offset)
            .toList()
          ..sort();
    return best[best.length ~/ 2];
  }

  /// Shortest recent round trip, in microseconds; null before any sample.
  int? get bestRtt => _samples.isEmpty
      ? null
      : _samples.map((s) => s.rtt).reduce((a, b) => a < b ? a : b);

  void clear() => _samples.clear();
}
