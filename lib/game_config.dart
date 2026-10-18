import 'package:beatdrop_shared/beatdrop_shared.dart';

/// Edit these to match the assets you drop into `assets/`.
class GameConfig {
  // Paths are relative to `assets/` (audioplayers convention).
  static const songAsset = 'audio/song.mp3';
  static const tumAsset = 'audio/tum.wav';

  // Full asset path for Image.asset.
  static const drumImageAsset = 'assets/images/drum.png';
  static const logoImageAsset = 'assets/images/logo.png';

  /// Time from the start of [songAsset] to the beat drop. Lives in the
  /// shared package because the room server scores against it too.
  static const dropTime = songDropTime;

  /// Room server WebSocket endpoint; pass
  /// `--dart-define=SERVER_URL=wss://<service>.run.app/ws` for deployed builds.
  static const serverUrl = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: 'ws://localhost:8080/ws',
  );
}
