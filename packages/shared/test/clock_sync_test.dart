import 'dart:math';

import 'package:beatdrop_shared/beatdrop_shared.dart';
import 'package:test/test.dart';

void main() {
  test('symmetric round trips give the exact offset', () {
    final sync = ClockSyncEstimator();
    const trueOffset = 5000000;
    for (var i = 0; i < 10; i++) {
      final c0 = i * 1000;
      // 20 ms each way.
      sync.addSample(c0, c0 + 20000 + trueOffset, c0 + 40000);
    }
    expect(sync.offset, trueOffset);
    expect(sync.bestRtt, 40000);
  });

  test('jittery, asymmetric samples stay within a few ms', () {
    final r = Random(1);
    final sync = ClockSyncEstimator();
    const trueOffset = -123456789;
    var local = 0;
    for (var i = 0; i < 20; i++) {
      // 15 ms each way plus, most of the time, up to 250 ms of one-sided
      // jitter, as on a busy 4G link.
      final up = 15000 + (r.nextDouble() < 0.7 ? r.nextInt(250000) : 0);
      final down = 15000 + (r.nextDouble() < 0.7 ? r.nextInt(250000) : 0);
      local += 500000;
      sync.addSample(local, local + up + trueOffset, local + up + down);
    }
    expect((sync.offset - trueOffset).abs(), lessThan(5000));
  });

  test('keeps only the last window of samples', () {
    final sync = ClockSyncEstimator(window: 3);
    for (var i = 0; i < 5; i++) {
      sync.addSample(0, 100, 10);
    }
    expect(sync.sampleCount, 3);
  });
}
