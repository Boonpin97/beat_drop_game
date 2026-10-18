/// Clock, audio and screen helpers with a precise Web Audio implementation in
/// the browser and an `audioplayers` fallback on native platforms.
library;

export 'platform_native.dart' if (dart.library.js_interop) 'platform_web.dart';

import 'platform_native.dart' if (dart.library.js_interop) 'platform_web.dart';

/// Local time of a tap, in [perfNowMicros] units.
///
/// In the browser a pointer event's timestamp shares `performance.now()`'s
/// time base and marks the moment the finger landed, before any frame delay,
/// so prefer it whenever it looks sane. Elsewhere the bases differ and the
/// check falls back to now.
int tapTimeMicros(Duration eventTimeStamp) {
  final now = perfNowMicros();
  final age = now - eventTimeStamp.inMicroseconds;
  return age >= 0 && age < 500000 ? eventTimeStamp.inMicroseconds : now;
}
