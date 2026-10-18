import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_config.dart';
import '../widgets/start_view.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  final _song = AudioPlayer();
  AudioPool? _tumPool;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<void>? _completeSub;

  /// Runs while the song is audibly playing; its elapsed time is "song time".
  final _songClock = Stopwatch();
  late final Ticker _ticker;

  /// Completes once the song and drum sound are loaded.
  late final Future<void> _ready;

  /// False while the Play button is showing.
  bool _started = false;

  Duration? _firstTap;
  bool _dropPassed = false;

  /// Final distance from the drop; null until decided.
  Duration? _result;
  bool _late = false;

  /// The song ended without any scoring tap.
  bool _missed = false;

  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _stateSub = _song.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.playing && !_songClock.isRunning) {
        _songClock.start();
      }
    });
    _completeSub = _song.onPlayerComplete.listen((_) {
      if (mounted && _result == null) setState(() => _missed = true);
    });
    _ready = _init();
  }

  Future<void> _init() async {
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
  }

  Future<void> _start() async {
    setState(() => _started = true);
    await _ready;
    if (mounted && _started) await _song.resume();
  }

  void _onTick(Duration _) {
    if (!_songClock.isRunning || _result != null || _missed) return;
    if (!_dropPassed && _songClock.elapsed >= GameConfig.dropTime) {
      setState(() {
        _dropPassed = true;
        if (_firstTap != null) {
          _result = GameConfig.dropTime - _firstTap!;
          _late = false;
        }
      });
    } else if (_firstTap != null || _dropPassed) {
      setState(() {}); // refresh the running (early or late) stopwatch
    }
  }

  void _onTap() {
    _tumPool?.start();
    setState(() => _pressed = true);
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) setState(() => _pressed = false);
    });

    if (!_songClock.isRunning || _result != null || _missed) return;
    final now = _songClock.elapsed;
    if (!_dropPassed) {
      _firstTap ??= now;
    } else if (_firstTap == null) {
      _result = now - GameConfig.dropTime;
      _late = true;
    }
  }

  void _resetRound() {
    _songClock
      ..stop()
      ..reset();
    _firstTap = null;
    _dropPassed = false;
    _result = null;
    _late = false;
    _missed = false;
  }

  Future<void> _restart() async {
    await _song.stop();
    setState(_resetRound);
    await _song.resume();
  }

  Future<void> _backToStart() async {
    setState(() {
      _resetRound();
      _started = false;
    });
    await _song.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _stateSub?.cancel();
    _completeSub?.cancel();
    _song.dispose();
    _tumPool?.dispose();
    super.dispose();
  }

  static String _format(Duration d) =>
      (d.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(3);

  static String _rating(Duration d) {
    final ms = d.inMilliseconds.abs();
    if (ms < 50) return 'PERFECT!';
    if (ms < 150) return 'Great';
    if (ms < 400) return 'Good';
    return 'Off beat';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back during a round returns to the Play button instead of exiting.
      canPop: !_started,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToStart();
      },
      child: Scaffold(
        // Matches the drum image's white background.
        backgroundColor: Colors.white,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _started
              ? _buildGame()
              : StartView(key: const ValueKey('start'), onPlay: _start),
        ),
      ),
    );
  }

  Widget _buildGame() {
    final String readout;
    var lateColor = false;
    if (_result != null) {
      readout = '${_late ? '+' : ''}${_format(_result!)}';
      lateColor = _late;
    } else if (_firstTap != null) {
      readout = _format(_songClock.elapsed - _firstTap!);
    } else if (_missed) {
      readout = '';
    } else if (_dropPassed) {
      // No tap yet: count how late the player is.
      readout = '+${_format(_songClock.elapsed - GameConfig.dropTime)}';
      lateColor = true;
    } else {
      readout = 'Tap the drum!';
    }

    return Stack(
      key: const ValueKey('game'),
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _onTap(),
          child: AnimatedScale(
            scale: _pressed ? 0.92 : 1.0,
            duration: const Duration(milliseconds: 80),
            child: Image.asset(GameConfig.drumImageAsset, fit: BoxFit.contain),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 24),
              child: IgnorePointer(
                child: Text(
                  readout,
                  style: TextStyle(
                    color: lateColor ? Colors.red.shade700 : Colors.black87,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_result != null || _missed) _buildResult(),
      ],
    );
  }

  Widget _buildResult() {
    final theme = Theme.of(context);
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_result == null) ...[
              Text('Missed!', style: theme.textTheme.displayMedium),
              const SizedBox(height: 12),
              Text(
                'You never tapped the drum',
                style: theme.textTheme.headlineSmall,
              ),
            ] else ...[
              Text(_rating(_result!), style: theme.textTheme.displayMedium),
              const SizedBox(height: 12),
              Text(
                '${_late ? '+' : ''}${_format(_result!)} s',
                style: theme.textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _late ? Colors.redAccent : null,
                ),
              ),
              Text(
                _late ? 'late' : 'early',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: _late ? Colors.redAccent : null,
                ),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _restart,
              icon: const Icon(Icons.replay),
              label: const Text('Play again'),
            ),
          ],
        ),
      ),
    );
  }
}
