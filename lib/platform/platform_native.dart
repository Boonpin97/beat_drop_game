import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../game_config.dart';

final _clock = Stopwatch()..start();

/// Monotonic local clock in microseconds.
int perfNowMicros() => _clock.elapsedMicroseconds;

/// Native apps already keep the screen on via immersive mode.
Future<void> keepScreenOn(bool on) async {}

/// `audioplayers` fallback. It can't schedule sounds precisely, so the song's
/// start is taken as the moment the player reports it's playing, as the solo
/// game always did.
class SoundEngine {
  final _song = AudioPlayer();
  AudioPool? _tumPool;
  Duration? _songDuration;
  Future<void>? _loading;

  void unlock() {}

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    _tumPool = await AudioPool.create(
      source: AssetSource(GameConfig.tumAsset),
      minPlayers: 3,
      maxPlayers: 8,
      playerMode: PlayerMode.lowLatency,
      // Without this the drum would steal audio focus and pause the song.
      audioContext: AudioContext(
        android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
      ),
    );
    // Keep the song loaded after stop() so every round can start instantly.
    await _song.setReleaseMode(ReleaseMode.stop);
    await _song.setSource(AssetSource(GameConfig.songAsset));
    _songDuration = await _song.getDuration();
  }

  Duration? get songDuration => _songDuration;

  void playTum() => _tumPool?.start();

  Future<int> scheduleSong(int localStart) async {
    await load();
    await _song.stop();
    final wait = localStart - perfNowMicros();
    if (wait > 0) await Future<void>.delayed(Duration(microseconds: wait));

    final playing = Completer<int>();
    final sub = _song.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.playing && !playing.isCompleted) {
        playing.complete(perfNowMicros());
      }
    });
    await _song.resume();
    final at = await playing.future.timeout(
      const Duration(seconds: 2),
      onTimeout: perfNowMicros,
    );
    await sub.cancel();
    return at;
  }

  void stopSong() => _song.stop();
}
