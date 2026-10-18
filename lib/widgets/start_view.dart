import 'package:flutter/material.dart';

/// The Play button shown before a round starts.
class StartView extends StatelessWidget {
  const StartView({super.key, required this.onPlay});

  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
          textStyle: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        icon: const Icon(Icons.play_arrow, size: 40),
        label: const Text('PLAY'),
        onPressed: onPlay,
      ),
    );
  }
}
