import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:web/web.dart' as web;

import 'backend.dart';

AudioBackend createAudioBackend() => _WebAudio();

class _Playing {
  final web.AudioBufferSourceNode source;
  final web.GainNode gain;
  _Playing(this.source, this.gain);
}

/// Sounds decoded and played with the Web Audio API.
class _WebAudio implements AudioBackend {
  final web.AudioContext _context = web.AudioContext();
  final Map<String, web.AudioBuffer> _buffers = {};

  _WebAudio() {
    // The audio would play on with the tab in the background or the browser
    // closed to the home screen (mobile browsers keep the page alive), so
    // it goes quiet whenever the page is hidden, and carries on when it is
    // back.
    web.document.addEventListener(
      'visibilitychange',
      ((web.Event _) {
        if (web.document.hidden) {
          _context.suspend();
        } else {
          _context.resume();
        }
      }).toJS,
    );
    web.window.addEventListener(
      'pagehide',
      ((web.Event _) => _context.suspend()).toJS,
    );
  }

  @override
  Future<void> load(List<String> files) async {
    await Future.wait(
      files.map((f) async {
        final data = await rootBundle.load('assets/audio/$f');
        // Decoding takes the buffer over, so hand it a copy.
        final bytes = Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        _buffers[f.split('.').first] = await _context
            .decodeAudioData(bytes.buffer.toJS)
            .toDart;
      }),
    );
  }

  @override
  void unlock() {
    if (_context.state != 'running' && !web.document.hidden) {
      _context.resume();
    }
  }

  @override
  Object? play(String name, {double volume = 1, bool loop = false}) {
    final buffer = _buffers[name];
    if (buffer == null) return null;
    final source = _context.createBufferSource()
      ..buffer = buffer
      ..loop = loop;
    final gain = _context.createGain();
    gain.gain.value = volume;
    source.connect(gain);
    gain.connect(_context.destination);
    source.start();
    return _Playing(source, gain);
  }

  @override
  void setVolume(Object handle, double volume) {
    final g = (handle as _Playing).gain.gain;
    g.cancelScheduledValues(_context.currentTime);
    g.value = volume;
  }

  @override
  void fade(Object handle, double volume, Duration time) {
    final g = (handle as _Playing).gain.gain;
    final now = _context.currentTime;
    g.cancelScheduledValues(now);
    g.setValueAtTime(g.value, now);
    g.linearRampToValueAtTime(volume, now + time.inMilliseconds / 1000);
  }

  @override
  void stop(Object handle, Duration time) {
    fade(handle, 0, time);
    (handle as _Playing).source.stop(
      _context.currentTime + time.inMilliseconds / 1000,
    );
  }
}
