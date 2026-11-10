import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio/backend.dart';
import 'audio/backend_io.dart'
    if (dart.library.js_interop) 'audio/backend_web.dart';

/// Sound effects and music, played as they are (no pitch or speed changes,
/// which not every browser's audio handles). Every call is safe before
/// [init] completes or if audio is unavailable; the game just stays quiet.
class GameAudio {
  final AudioBackend _backend = createAudioBackend();
  bool _ready = false;
  Future<void>? _initFuture;

  Object? _screech;
  Object? _music;
  String? _musicName;

  bool muted = false;

  /// Sound effects play at this share of the volume asked for, to sit
  /// under the music.
  static const double effects = 0.35;

  static const _files = [
    'tire_screech.wav',
    'coin.wav',
    'coin_combo.wav',
    'crash.wav',
    'explosion.wav',
    'whoosh.wav',
    'tip_warning.wav',
    'countdown_beep.wav',
    'countdown_go.wav',
    'ui_tap.wav',
    'new_record.wav',
    'game_over.wav',
    'music.mp3',
  ];

  /// Loads the sounds, and lets them play: browsers only allow that after a
  /// tap or key press, so it is called again on every one (see [unlock]).
  Future<void> init() {
    unlock();
    return _initFuture ??= _init();
  }

  Future<void> _init() async {
    try {
      await _backend.load(_files);
      _ready = true;
    } catch (e) {
      debugPrint('Audio unavailable: $e');
      _initFuture = null;
    }
  }

  /// Lets audio start in a browser; call it from taps and key presses.
  void unlock() {
    try {
      _backend.unlock();
    } catch (_) {}
  }

  bool get isReady => _ready;

  void play(String name, {double volume = 1}) {
    if (!_ready || muted) return;
    try {
      _backend.play(name, volume: volume * effects);
    } catch (_) {}
  }

  /// Starts the music [name] (fading out what played before), or stops it.
  void music(String? name, {double volume = 0.7}) {
    if (!_ready) return;
    if (name == _musicName) return;
    final old = _music;
    if (old != null) _backend.stop(old, const Duration(milliseconds: 600));
    _music = null;
    _musicName = muted ? null : name;
    if (name == null || muted) return;
    final h = _backend.play(name, volume: 0, loop: true);
    if (h == null) return;
    _backend.fade(h, volume, const Duration(milliseconds: 800));
    _music = h;
  }

  /// Starts or updates the tyre squeal: louder the harder the tyres work
  /// ([slide] 0..1).
  void tyres({required double slide, required bool on}) {
    if (!_ready) return;
    final screech = _screech;
    if (!on || muted) {
      if (screech != null) {
        _backend.stop(screech, const Duration(milliseconds: 150));
      }
      _screech = null;
      return;
    }
    final h = screech ?? _backend.play('tire_screech', volume: 0, loop: true);
    _screech = h;
    if (h != null) {
      _backend.setVolume(h, (slide * 0.5).clamp(0.0, 0.5) * effects);
    }
  }

  void setMuted(bool value) {
    muted = value;
    if (value) {
      music(null);
      tyres(slide: 0, on: false);
    }
  }
}
