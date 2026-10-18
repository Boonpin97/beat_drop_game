import 'package:beatdrop_shared/beatdrop_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game_config.dart';
import '../net/room_client.dart';
import '../platform/platform.dart';
import '../theme.dart';
import 'game_screen.dart';
import 'room_screen.dart';

/// Create a room, join one by code, or practise alone.
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key, required this.sound, this.inviteCode});

  final SoundEngine sound;

  /// Code from a shared `/r/<code>` link, if the app was opened from one.
  final String? inviteCode;

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _enter(Future<void> Function(RoomClient) connect) async {
    // Must run inside the button's gesture for browsers to allow sound.
    widget.sound.unlock();
    setState(() => _busy = true);
    final client = RoomClient(Uri.parse(GameConfig.serverUrl));
    try {
      await connect(client);
    } on RoomException catch (e) {
      client.dispose();
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (!mounted) return client.dispose();
    setState(() => _busy = false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoomScreen(client: client, sound: widget.sound),
      ),
    );
  }

  void _create() => _enter((c) => c.create(_name.text.trim()));

  Future<void> _join() async {
    widget.sound.unlock(); // while still inside this button's gesture
    final code = widget.inviteCode ?? await _askForCode();
    if (code == null) return;
    _enter((c) => c.join(code, _name.text.trim()));
  }

  Future<String?> _askForCode() =>
      showDialog<String>(context: context, builder: (_) => const _JoinDialog());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final invite = widget.inviteCode;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: ValueListenableBuilder(
                valueListenable: _name,
                builder: (context, name, _) {
                  final ready = !_busy && name.text.trim().isNotEmpty;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Image.asset(GameConfig.logoImageAsset, height: 88),
                      const SizedBox(height: 12),
                      Text(
                        'Beat Drop',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Hit the drum right on the drop.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: _name,
                        textAlign: TextAlign.center,
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: [LengthLimitingTextInputFormatter(20)],
                        decoration: const InputDecoration(
                          hintText: 'Your name',
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: ready
                            ? (invite != null ? _join : _create)
                            : null,
                        child: Text(
                          invite != null ? 'Join room $invite' : 'Create room',
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: ready
                            ? (invite != null ? _create : _join)
                            : null,
                        child: Text(invite != null ? 'New room' : 'Join room'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      GameScreen(sound: widget.sound),
                                ),
                              ),
                        child: const Text('Practise solo'),
                      ),
                      SizedBox(
                        height: 56,
                        child: _busy
                            ? const Center(
                                child: SizedBox.square(
                                  dimension: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JoinDialog extends StatefulWidget {
  const _JoinDialog();

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  String? _code;

  void _submit() {
    if (_code != null) Navigator.of(context).pop(_code);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join a room', textAlign: TextAlign.center),
      content: SizedBox(
        width: 260,
        child: TextField(
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: 6,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')),
            LengthLimitingTextInputFormatter(roomCodeLength),
            UpperCaseTextFormatter(),
          ],
          onChanged: (v) => setState(() => _code = normalizeRoomCode(v)),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _code == null ? null : _submit,
                child: const Text('Join'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue _, TextEditingValue v) =>
      v.copyWith(text: v.text.toUpperCase());
}
