import 'dart:async';

import 'package:beatdrop_shared/beatdrop_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game_config.dart';
import '../net/room_client.dart';
import '../platform/platform.dart';
import '../theme.dart';
import '../widgets/drum_pad.dart';

/// Link that opens the app straight on the join button for [code].
String? inviteUrl(String code) {
  const public = String.fromEnvironment('PUBLIC_URL');
  final origin = public.isNotEmpty ? public : (kIsWeb ? Uri.base.origin : '');
  return origin.isEmpty ? null : '$origin/r/$code';
}

/// Lobby, round and results for one room, driven by the server's snapshots.
class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.client, required this.sound});

  final RoomClient client;
  final SoundEngine sound;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  StreamSubscription<String>? _errorSub;
  int _scheduledRound = 0;
  bool _closed = false;

  RoomClient get _client => widget.client;

  @override
  void initState() {
    super.initState();
    _client.addListener(_onRoomChanged);
    _errorSub = _client.errors.listen(_toast);
    keepScreenOn(true);
    widget.sound.load();
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void _onRoomChanged() {
    if (_client.closedReason case final reason? when !_closed) {
      _closed = true;
      _toast(reason);
      Navigator.of(context).pop();
      return;
    }
    final room = _client.room;
    if (room == null || !_client.isGm) return;
    if (room.phase == RoomPhase.playing && room.round != _scheduledRound) {
      _scheduledRound = room.round;
      _playSong(room.startAt!);
    } else if (room.phase == RoomPhase.lobby) {
      widget.sound.stopSong();
    }
  }

  /// Host only: play the song at the agreed moment, then report when it was
  /// actually heard so every tap is scored against the real speaker output.
  Future<void> _playSong(int startAt) async {
    final heard = await widget.sound.scheduleSong(_client.toLocal(startAt));
    _client.reportSongStart(_client.toServer(heard));
  }

  @override
  void dispose() {
    _client.removeListener(_onRoomChanged);
    _errorSub?.cancel();
    keepScreenOn(false);
    widget.sound.stopSong();
    if (_client.closedReason == null) {
      _client.leave();
    } else {
      _client.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _client,
      builder: (context, _) {
        final room = _client.room;
        final Widget body = switch (room?.phase) {
          null => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          RoomPhase.lobby => _LobbyView(client: _client, sound: widget.sound),
          RoomPhase.playing when _client.isParticipant => _RoundView(
            key: ValueKey(room!.round),
            client: _client,
            sound: widget.sound,
          ),
          RoomPhase.playing => _ListeningView(client: _client),
          RoomPhase.results => _ResultsView(
            client: _client,
            sound: widget.sound,
          ),
        };
        return Stack(
          children: [
            Positioned.fill(child: body),
            if (!_client.connected && room != null)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(child: Center(child: _ReconnectingPill())),
              ),
          ],
        );
      },
    );
  }
}

class _ReconnectingPill extends StatelessWidget {
  const _ReconnectingPill();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.ink,
      shape: const StadiumBorder(),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 8),
            Text('Reconnecting…', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

/// Scaffold with content on top and a pinned action area at the bottom.
class _Page extends StatelessWidget {
  const _Page({required this.title, required this.body, required this.footer});

  final String title;
  final Widget body;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          tooltip: 'Leave room',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: body,
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.card,
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: footer,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LobbyView extends StatelessWidget {
  const _LobbyView({required this.client, required this.sound});

  final RoomClient client;
  final SoundEngine sound;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = client.room!;
    return _Page(
      title: 'Lobby',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _CodeCard(code: room.code),
          const SizedBox(height: 28),
          Row(
            children: [
              Text(
                'Players',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '${room.players.length} / $maxPlayers',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 16,
            children: [
              for (final p in room.players)
                _PlayerBadge(
                  player: p,
                  isMe: p.id == client.playerId,
                  isHost: p.id == room.gmId,
                  sittingOut: p.id == room.gmId && !room.gmPlays,
                ),
            ],
          ),
        ],
      ),
      footer: client.isGm
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "I'm playing too",
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Switch(value: room.gmPlays, onChanged: client.setGmPlays),
                  ],
                ),
                const SizedBox(height: 6),
                _StartButton(client: client, sound: sound, label: 'Start'),
                const SizedBox(height: 10),
                const Text(
                  "The song plays from this phone's speaker",
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ],
            )
          : const _WaitingForHost(text: 'Waiting for the host to start'),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code});

  final String code;

  void _copy(BuildContext context, String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what copied')));
  }

  @override
  Widget build(BuildContext context) {
    final link = inviteUrl(code);
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'ROOM CODE',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _copy(context, code, 'Code'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FittedBox(
                child: Text(
                  code,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          if (link != null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: accentTint(accent),
                foregroundColor: accent,
                minimumSize: const Size(0, 44),
              ),
              onPressed: () => _copy(context, link, 'Invite link'),
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text('Copy invite link'),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlayerBadge extends StatelessWidget {
  const _PlayerBadge({
    required this.player,
    required this.isMe,
    required this.isHost,
    required this.sittingOut,
  });

  final PlayerInfo player;
  final bool isMe;
  final bool isHost;
  final bool sittingOut;

  @override
  Widget build(BuildContext context) {
    final color = playerColor(player.color);
    return Opacity(
      opacity: player.connected && !sittingOut ? 1 : 0.4,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isMe ? AppColors.ink : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: PlayerAvatar(name: player.name, color: color),
                ),
                if (isHost)
                  const Positioned(
                    top: -6,
                    right: -4,
                    child: Text('👑', style: TextStyle(fontSize: 18)),
                  ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: _SyncDot(
                    rttMs: player.connected ? player.rttMs : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isMe ? 'You' : player.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            if (sittingOut)
              const Text(
                'host only',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
          ],
        ),
      ),
    );
  }
}

/// Connection quality: green is good, amber okay, red slow.
class _SyncDot extends StatelessWidget {
  const _SyncDot({required this.rttMs});

  final int? rttMs;

  @override
  Widget build(BuildContext context) {
    final ms = rttMs;
    final color = switch (ms) {
      null => Colors.grey,
      < 80 => const Color(0xFF2DBE60),
      < 200 => const Color(0xFFF5A623),
      _ => const Color(0xFFE5484D),
    };
    return Tooltip(
      message: ms == null ? 'Connecting' : 'Connection $ms ms',
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.cream, width: 2.5),
        ),
      ),
    );
  }
}

class _WaitingForHost extends StatelessWidget {
  const _WaitingForHost({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}

/// Host's Start button; disabled until the song has been decoded.
class _StartButton extends StatelessWidget {
  const _StartButton({
    required this.client,
    required this.sound,
    required this.label,
  });

  final RoomClient client;
  final SoundEngine sound;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: sound.load(),
      builder: (context, snap) {
        final ready = snap.connectionState == ConnectionState.done;
        return FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          onPressed: ready
              ? () {
                  sound.unlock();
                  client.start();
                }
              : null,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(ready ? label : 'Loading song…'),
        );
      },
    );
  }
}

/// Rebuilds every frame until [startLocal] has passed, showing 3‑2‑1 before
/// it and [builder]'s widget after.
class _Countdown extends StatefulWidget {
  const _Countdown({
    required this.startLocal,
    required this.builder,
    required this.style,
  });

  final int startLocal;
  final WidgetBuilder builder;
  final TextStyle style;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _shown = -1;

  int get _secondsLeft {
    final left = widget.startLocal - perfNowMicros();
    return left <= 0 ? 0 : (left / 1e6).ceil();
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final s = _secondsLeft;
      if (s != _shown) setState(() => _shown = s);
      if (s == 0) _ticker.stop();
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _secondsLeft;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: Tween(begin: 1.4, end: 1.0).animate(anim),
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: s == 0
          ? KeyedSubtree(key: const ValueKey(0), child: widget.builder(context))
          : Text(
              '$s',
              key: ValueKey(s),
              style: widget.style.copyWith(fontSize: 120, height: 1),
            ),
    );
  }
}

class _RoundView extends StatefulWidget {
  const _RoundView({super.key, required this.client, required this.sound});

  final RoomClient client;
  final SoundEngine sound;

  @override
  State<_RoundView> createState() => _RoundViewState();
}

class _RoundViewState extends State<_RoundView>
    with SingleTickerProviderStateMixin {
  late final int _startLocal = widget.client.toLocal(
    widget.client.room!.startAt!,
  );

  /// The host lines the song up to the scheduled start, so the drop lands
  /// here on this phone's clock. Only drives the live readout; the official
  /// score comes from the server.
  late final int _dropLocal = _startLocal + songDropTime.inMicroseconds;

  /// Local time of the scoring tap; null until tapped.
  int? _tapLocal;
  late final Ticker _ticker;

  bool get _frozen {
    final tap = _tapLocal;
    return tap != null && (tap >= _dropLocal || perfNowMicros() >= _dropLocal);
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      setState(() {});
      if (_frozen) _ticker.stop();
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onHit(Duration timeStamp) {
    widget.sound.playTum();
    if (_tapLocal != null) return;
    final local = tapTimeMicros(timeStamp);
    if (local < _startLocal) return; // still counting down
    // Stamped here, on the shared clock; when it reaches the server
    // doesn't matter.
    widget.client.tap(widget.client.toServer(local));
    setState(() => _tapLocal = local);
  }

  /// Big readout plus caption, as in the solo game: counts up from the tap
  /// and freezes at the drop, or counts up in red once the drop has passed.
  (String, String, bool) _readout() {
    final now = perfNowMicros();
    final tap = _tapLocal;
    Duration us(int v) => Duration(microseconds: v);
    if (tap == null) {
      if (now < _dropLocal) {
        return ('Tap on the drop', 'Only your first tap counts', false);
      }
      return ('+${formatSeconds(us(now - _dropLocal))}', 'Tap now!', true);
    }
    if (tap >= _dropLocal) {
      final late = us(tap - _dropLocal);
      return ('+${formatSeconds(late)}', '${rating(late)} · late', true);
    }
    if (now < _dropLocal) {
      return (formatSeconds(us(now - tap)), 'Locked in. Wait for it…', false);
    }
    final early = us(_dropLocal - tap);
    return (formatSeconds(early), '${rating(early)} · early', false);
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.client.room!.players.where(
      (p) => p.id == widget.client.playerId,
    );
    final color = playerColor(me.isEmpty ? 0 : me.first.color);
    final fg = onColor(color);
    final style = TextStyle(
      color: fg,
      fontSize: 34,
      fontWeight: FontWeight.w900,
    );
    return Scaffold(
      backgroundColor: color,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 140, 24, 48),
            child: DrumPad(onHit: _onHit),
          ),
          SafeArea(
            child: IgnorePointer(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  if (me.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: fg.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        me.first.name,
                        style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  _Countdown(
                    startLocal: _startLocal,
                    style: style,
                    builder: (_) {
                      final (title, caption, late) = _readout();
                      final timer = _tapLocal != null || late;
                      return Column(
                        children: [
                          Text(
                            title,
                            style: style.copyWith(
                              color: late ? AppColors.red : fg,
                              fontSize: timer ? 56 : 34,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            caption,
                            style: TextStyle(
                              color: fg.withValues(alpha: 0.75),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What a host who isn't playing sees while the song plays.
class _ListeningView extends StatelessWidget {
  const _ListeningView({required this.client});

  final RoomClient client;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: AppColors.ink,
      fontSize: 34,
      fontWeight: FontWeight.w900,
    );
    return Scaffold(
      body: Center(
        child: _Countdown(
          startLocal: client.toLocal(client.room!.startAt!),
          style: style,
          builder: (_) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(GameConfig.logoImageAsset, height: 96),
              const SizedBox(height: 20),
              const Text('Now playing', style: style),
              const SizedBox(height: 6),
              const Text(
                'Turn this phone up. Results come after the drop.',
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.client, required this.sound});

  final RoomClient client;
  final SoundEngine sound;

  @override
  Widget build(BuildContext context) {
    final room = client.room!;
    final results = room.results ?? const [];
    final colors = {for (final p in room.players) p.id: playerColor(p.color)};
    return _Page(
      title: 'Results',
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        itemCount: results.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _ResultRow(
          rank: i + 1,
          result: results[i],
          color: colors[results[i].id] ?? Colors.grey,
          isMe: results[i].id == client.playerId,
        ),
      ),
      footer: client.isGm
          ? Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                    onPressed: client.reset,
                    child: const Text('Lobby'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _StartButton(
                    client: client,
                    sound: sound,
                    label: 'Play again',
                  ),
                ),
              ],
            )
          : const _WaitingForHost(text: 'Waiting for the host'),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.rank,
    required this.result,
    required this.color,
    required this.isMe,
  });

  final int rank;
  final PlayerResult result;
  final Color color;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final winner = rank == 1 && !r.missed;
    final medal = switch (rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => null,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      decoration: BoxDecoration(
        color: winner ? color : AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isMe ? AppColors.ink : AppColors.line,
          width: isMe ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              r.missed ? '–' : (medal ?? '$rank'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          PlayerAvatar(
            name: r.name,
            size: 40,
            color: winner ? Colors.white : color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Builder(
              builder: (context) {
                final fg = winner ? onColor(color) : AppColors.ink;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMe ? '${r.name} (you)' : r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      r.missed
                          ? 'Never tapped'
                          : '${rating(r.offset!)} · ${r.late ? 'late' : 'early'}',
                      style: TextStyle(color: fg.withValues(alpha: 0.7)),
                    ),
                  ],
                );
              },
            ),
          ),
          if (!r.missed)
            Text(
              '${r.late ? '+' : '−'}${formatSeconds(r.offset!.abs())}s',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: winner
                    ? onColor(color)
                    : (r.late ? AppColors.red : AppColors.ink),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}
