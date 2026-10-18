import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import '../game_config.dart';

/// Monotonic local clock in microseconds (`performance.now()`).
int perfNowMicros() => (web.window.performance.now() * 1000).round();

web.WakeLockSentinel? _wakeLock;

/// Stops the phone from dimming mid-round. Best effort: not every browser
/// supports the Wake Lock API, and it's released when the tab is hidden.
Future<void> keepScreenOn(bool on) async {
  try {
    if (on) {
      _wakeLock ??= await web.window.navigator.wakeLock
          .request('screen')
          .toDart;
    } else {
      await _wakeLock?.release().toDart;
      _wakeLock = null;
    }
  } catch (_) {
    _wakeLock = null;
  }
}

/// Song and drum playback through Web Audio, which, unlike an `<audio>`
/// element, can start a sound at an exact, known moment.
class SoundEngine {
  web.AudioContext? _ctx;
  web.AudioBuffer? _song;
  web.AudioBuffer? _tum;
  web.AudioBufferSourceNode? _playing;
  Future<void>? _loading;

  web.AudioContext get _context => _ctx ??= web.AudioContext();

  /// Browsers only allow sound after a user gesture; call this synchronously
  /// from a button handler before the first sound is needed.
  void unlock() {
    final ctx = _context;
    ctx.resume();
    // iOS also wants something actually played inside the gesture.
    final silence = ctx.createBufferSource()
      ..buffer = ctx.createBuffer(1, 1, 22050);
    silence.connect(ctx.destination);
    silence.start();
  }

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    _song = await _decode(GameConfig.songAsset);
    _tum = await _decode(GameConfig.tumAsset);
  }

  Future<web.AudioBuffer> _decode(String asset) async {
    final data = await rootBundle.load('assets/$asset');
    // decodeAudioData takes ownership of the buffer, so hand it a copy.
    final bytes = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    return _context.decodeAudioData(bytes.buffer.toJS).toDart;
  }

  Duration? get songDuration => _song == null
      ? null
      : Duration(microseconds: (_song!.duration * 1e6).round());

  void playTum() {
    final tum = _tum;
    if (tum == null) return;
    final src = _context.createBufferSource()..buffer = tum;
    src.connect(_context.destination);
    src.start();
  }

  /// Plays the song so that its first sample comes out of the speaker at
  /// local time [localStart] (in [perfNowMicros] units). If that moment has
  /// already passed, starts partway in so the song stays in step with it.
  ///
  /// Returns the local time the song's start is (or would have been) heard,
  /// which is [localStart] unless the browser can't report its latency.
  Future<int> scheduleSong(int localStart) async {
    await load();
    stopSong();
    final ctx = _context;
    await ctx.resume().toDart;

    // Map between the audio clock and performance.now(). The output
    // timestamp includes the speaker latency; otherwise estimate it.
    double ctxTime;
    double perfMs;
    final ts = _outputTimestamp(ctx);
    if (ts != null) {
      (ctxTime, perfMs) = ts;
    } else {
      ctxTime = ctx.currentTime;
      perfMs =
          web.window.performance.now() +
          (_num(ctx, 'outputLatency') ?? _num(ctx, 'baseLatency') ?? 0) * 1000;
    }

    var when = ctxTime + (localStart / 1000 - perfMs) / 1000;
    var skip = 0.0;
    final earliest = ctx.currentTime + 0.01;
    if (when < earliest) {
      skip = earliest - when;
      when = earliest;
    }
    final src = _playing = ctx.createBufferSource()..buffer = _song;
    src.connect(ctx.destination);
    src.start(when, skip);
    return ((perfMs + (when - skip - ctxTime) * 1000) * 1000).round();
  }

  void stopSong() {
    try {
      _playing?.stop();
    } catch (_) {
      // Already stopped or never started.
    }
    _playing = null;
  }

  static (double, double)? _outputTimestamp(web.AudioContext ctx) {
    try {
      if (!ctx.has('getOutputTimestamp')) return null;
      final ts = ctx.getOutputTimestamp();
      // Zero until the output device has actually started.
      if (ts.contextTime > 0 && ts.performanceTime > 0) {
        return (ts.contextTime, ts.performanceTime);
      }
    } catch (_) {}
    return null;
  }

  static double? _num(JSObject o, String key) {
    final v = o.getProperty<JSAny?>(key.toJS);
    return v.isA<JSNumber>() ? (v as JSNumber).toDartDouble : null;
  }
}
