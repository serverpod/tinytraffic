import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import 'backend.dart';

AudioBackend createAudioBackend() => _Players();

/// Sounds played with audioplayers: AVFoundation on the Apple Watch (through
/// audioplayers_watchos) and on phones. Short effects come from a small pool
/// each, so they can overlap; loops (the music, the tyre squeal) get a player
/// of their own.
class _Players implements AudioBackend {
  final AudioCache _cache = AudioCache(prefix: 'assets/audio/');
  final Map<String, String> _files = {};
  final Map<String, AudioPool> _pools = {};

  /// The loops playing (the music, the tyre squeal).
  final Set<AudioPlayer> _loops = {};

  /// Pauses the loops while the app is in the background (the watch's
  /// screen off, another app in front), and picks them up again after.
  late final AppLifecycleListener lifecycle;

  _Players() {
    lifecycle = AppLifecycleListener(
      onHide: () {
        for (final p in _loops) {
          unawaited(p.pause());
        }
      },
      onShow: () {
        for (final p in _loops) {
          unawaited(p.resume());
        }
      },
    );
  }

  @override
  Future<void> load(List<String> files) async {
    // Play alongside other apps' audio, and even with the watch's silent
    // mode on: it is a game the player started.
    await AudioPlayer.global.setAudioContext(
      AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
    );
    await Future.wait(
      files.map((f) async {
        final name = f.split('.').first;
        _files[name] = f;
        await _cache.load(f);
        // The music only ever plays as a loop.
        if (f.endsWith('.mp3')) return;
        _pools[name] = await AudioPool.create(
          source: AssetSource(f),
          maxPlayers: 3,
          audioCache: _cache,
        );
      }),
    );
  }

  @override
  void unlock() {}

  @override
  Object? play(String name, {double volume = 1, bool loop = false}) {
    if (!loop) {
      unawaited(_pools[name]?.start(volume: volume));
      return null;
    }
    final file = _files[name];
    if (file == null) return null;
    final player = AudioPlayer()..audioCache = _cache;
    _loops.add(player);
    unawaited(() async {
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource(file), volume: volume);
    }());
    return player;
  }

  @override
  void setVolume(Object handle, double volume) {
    _fades.remove(handle)?.cancel();
    unawaited((handle as AudioPlayer).setVolume(volume));
  }

  final Map<Object, Timer> _fades = {};

  @override
  void fade(Object handle, double volume, Duration time) {
    final player = handle as AudioPlayer;
    _fades.remove(handle)?.cancel();
    final from = player.volume;
    const step = Duration(milliseconds: 50);
    final steps = (time.inMilliseconds / step.inMilliseconds).ceil();
    var i = 0;
    _fades[handle] = Timer.periodic(step, (timer) {
      i++;
      final t = steps == 0 ? 1.0 : (i / steps).clamp(0.0, 1.0);
      unawaited(player.setVolume(from + (volume - from) * t));
      if (t >= 1) {
        timer.cancel();
        _fades.remove(handle);
      }
    });
  }

  @override
  void stop(Object handle, Duration time) {
    fade(handle, 0, time);
    Timer(time, () async {
      _fades.remove(handle)?.cancel();
      final player = handle as AudioPlayer;
      _loops.remove(player);
      await player.stop();
      await player.dispose();
    });
  }
}
