import 'package:flutter/material.dart';

import '../game_config.dart';

/// The full-screen drum. Reports the raw pointer-down timestamp so callers
/// can time the tap from when the finger landed rather than when a frame ran.
class DrumPad extends StatefulWidget {
  const DrumPad({super.key, required this.onHit});

  final ValueChanged<Duration> onHit;

  @override
  State<DrumPad> createState() => _DrumPadState();
}

class _DrumPadState extends State<DrumPad> {
  bool _pressed = false;

  void _onPointerDown(PointerDownEvent e) {
    widget.onHit(e.timeStamp);
    setState(() => _pressed = true);
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) setState(() => _pressed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 80),
        // Drawn smaller than the pad; tapping anywhere still counts.
        child: FractionallySizedBox(
          widthFactor: 0.7,
          heightFactor: 0.7,
          child: Image.asset(GameConfig.drumImageAsset, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
