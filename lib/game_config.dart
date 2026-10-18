/// Edit these to match the assets you drop into `assets/`.
class GameConfig {
  // Paths are relative to `assets/` (audioplayers convention).
  static const songAsset = 'audio/song.mp3';
  static const tumAsset = 'audio/tum.wav';

  // Full asset path for Image.asset.
  static const drumImageAsset = 'assets/images/drum.png';

  /// Time from the start of [songAsset] to the beat drop.
  static const dropTime = Duration(milliseconds: 11400);
}
