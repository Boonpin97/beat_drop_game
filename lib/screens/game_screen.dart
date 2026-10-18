import 'package:beatdrop_shared/beatdrop_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_config.dart';
import '../platform/platform.dart';
import '../theme.dart';
import '../widgets/drum_pad.dart';
import '../widgets/start_view.dart';

/// Single-player practice round.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.sound});

  final SoundEngine sound;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// Local time the song is heard from; null until scheduled.
  int? _songStart;

  /// False while the Play button is showing.
  bool _started = false;

  Duration? _firstTap;
  bool _dropPassed = false;

  /// Final distance from the drop; null until decided.
  Duration? _result;
  bool _late = false;

  /// The song ended without any scoring tap.
  bool _missed = false;

  SoundEngine get _sound => widget.sound;

  /// Position in the song; null while it isn't audibly playing.
  Duration? get _songTime {
    final start = _songStart;
    if (start == null) return null;
    final us = perfNowMicros() - start;
    return us < 0 ? null : Duration(microseconds: us);
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _sound.load();
  }

  Future<void> _start() async {
    _sound.unlock();
    setState(() => _started = true);
    await _playSong();
  }

  Future<void> _playSong() async {
    await _sound.load();
    if (!mounted || !_started) return;
    final start = await _sound.scheduleSong(perfNowMicros() + 100000);
    if (mounted && _started) _songStart = start;
  }

  void _onTick(Duration _) {
    final now = _songTime;
    if (now == null || _result != null || _missed) return;
    if (now >= (_sound.songDuration ?? const Duration(minutes: 5))) {
      setState(() => _missed = true);
    } else if (!_dropPassed && now >= GameConfig.dropTime) {
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

  void _onTap(Duration timeStamp) {
    _sound.playTum();
    final start = _songStart;
    if (start == null || _result != null || _missed) return;
    final us = tapTimeMicros(timeStamp) - start;
    if (us < 0) return;
    final now = Duration(microseconds: us);
    if (!_dropPassed) {
      _firstTap ??= now;
    } else if (_firstTap == null) {
      _result = now - GameConfig.dropTime;
      _late = true;
    }
  }

  void _resetRound() {
    _songStart = null;
    _firstTap = null;
    _dropPassed = false;
    _result = null;
    _late = false;
    _missed = false;
  }

  Future<void> _restart() async {
    _sound.stopSong();
    setState(_resetRound);
    await _playSong();
  }

  void _backToStart() {
    _sound.stopSong();
    setState(() {
      _resetRound();
      _started = false;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sound.stopSong();
    super.dispose();
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
        backgroundColor: AppColors.cream,
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
    final now = _songTime ?? Duration.zero;
    final String readout;
    var lateColor = false;
    if (_result != null) {
      readout = '${_late ? '+' : ''}${formatSeconds(_result!)}';
      lateColor = _late;
    } else if (_firstTap != null) {
      readout = formatSeconds(now - _firstTap!);
    } else if (_missed) {
      readout = '';
    } else if (_dropPassed) {
      // No tap yet: count how late the player is.
      readout = '+${formatSeconds(now - GameConfig.dropTime)}';
      lateColor = true;
    } else {
      readout = 'Tap the drum!';
    }

    return Stack(
      key: const ValueKey('game'),
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 120, 24, 48),
          child: DrumPad(onHit: _onTap),
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
    // Light text on the dimmed drum.
    final theme = ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: AppColors.red,
    );
    return ColoredBox(
      color: Colors.black87,
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
              Text(rating(_result!), style: theme.textTheme.displayMedium),
              const SizedBox(height: 12),
              Text(
                '${_late ? '+' : ''}${formatSeconds(_result!)} s',
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
