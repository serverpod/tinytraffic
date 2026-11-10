// ignore_for_file: avoid_print

/// Tiny Traffic procedural audio synthesizer.
///
/// Generates every sound effect of the game from scratch, and the two music
/// loops it used to ship. (The game's music is now `reference/music/`, as
/// `assets/audio/music.mp3`; the loops are only rendered when named.)
/// Oscillators (band-limited with polyBLEP), noise, envelopes, state-variable
/// filters, FM, reverb, delay and a look-ahead limiter are all implemented
/// below in plain Dart -- no package dependencies.
///
/// Output goes to `assets/audio/`:
///  * sound effects as mono 16-bit PCM WAV (44.1 kHz),
///  * music as stereo Ogg Vorbis (encoded with ffmpeg + libvorbis, which
///    stores the exact sample count, so loops stay seamless).
///
/// Usage (from the `tinytraffic_flutter` directory):
///
///     dart run tool/synth_audio.dart              # render everything
///     dart run tool/synth_audio.dart coin crash   # render only some assets
///
/// Every asset has its own `synth*` / `render*` function. Tweak the constants
/// at the top of the file or the function bodies and re-run.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

// =============================================================================
// Global configuration
// =============================================================================

const int sampleRate = 44100;

/// Peak level every file is normalized to.
const double peakDb = -1.0;

const String ffmpegPath = '/opt/homebrew/bin/ffmpeg';

/// libvorbis VBR quality (0..10). 4 is ~128 kbit/s for stereo.
const double vorbisQuality = 4.0;

// --- Engine loop -------------------------------------------------------------
/// Samples per cycle of the engine fundamental: 441 samples = exactly 100 Hz.
const int engineCyclePeriod = 441;

/// Number of fundamental cycles in the loop: 150 * 441 = 66150 = 1.5 s.
const int engineCycles = 150;

// --- Tire screech ------------------------------------------------------------
const double screechSeconds = 1.5;
const double screechPitchHz = 1750.0;

// --- Driving music -----------------------------------------------------------
const double musicBpm = 128; // 32 bars at 128 BPM = exactly 60.0 s
const int musicBars = 32;
const int musicKey = 2; // semitones above C major (2 = D major)
const int musicLeadShift = -12; // melodies below are written an octave high

// --- Menu music --------------------------------------------------------------
const double menuBpm = 90; // 1 beat = exactly 29400 samples
const int menuBars = 16; // 16 bars at 90 BPM = 42.667 s
const int menuKey = 0; // C major / D dorian flavoured ii-V-I

// =============================================================================
// Entry point
// =============================================================================

typedef MonoSynth = Float64List Function();

final Map<String, MonoSynth> soundEffects = {
  'engine_loop': synthEngineLoop,
  'coin': synthCoin,
  'coin_combo': synthCoinCombo,
  'crash': synthCrash,
  'explosion': synthExplosion,
  'tire_screech': synthTireScreech,
  'whoosh': synthWhoosh,
  'tip_warning': synthTipWarning,
  'countdown_beep': synthCountdownBeep,
  'countdown_go': synthCountdownGo,
  'ui_tap': synthUiTap,
  'new_record': synthNewRecord,
  'game_over': synthGameOver,
};

const Set<String> loopingEffects = {'engine_loop', 'tire_screech'};

final Map<String, List<Float64List> Function()> musicTracks = {
  'music_loop': renderMusicLoop,
  'menu_music': renderMenuMusic,
};

Future<void> main(List<String> args) async {
  final outDir = _outputDir();
  outDir.createSync(recursive: true);
  final only = args.toSet();
  bool wanted(String name) => only.isEmpty || only.contains(name);
  final produced = <String>[];

  for (final entry in soundEffects.entries) {
    if (!wanted(entry.key)) continue;
    final sw = Stopwatch()..start();
    final x = entry.value();
    final path = '${outDir.path}/${entry.key}.wav';
    writeWav(path, [x]);
    produced.add(path);
    print(
      '\n${entry.key}.wav  (${sw.elapsedMilliseconds} ms to render)',
    );
    printStats([x], loop: loopingEffects.contains(entry.key));
  }

  for (final entry in musicTracks.entries) {
    if (!only.contains(entry.key)) continue;
    final sw = Stopwatch()..start();
    final stereo = entry.value();
    final tmp = Directory.systemTemp.createTempSync('tt_synth_');
    final wavPath = '${tmp.path}/${entry.key}.wav';
    writeWav(wavPath, stereo);
    final oggPath = '${outDir.path}/${entry.key}.ogg';
    await encodeVorbis(wavPath, oggPath);
    tmp.deleteSync(recursive: true);
    produced.add(oggPath);
    print('\n${entry.key}.ogg  (${sw.elapsedMilliseconds} ms to render)');
    print('  source PCM:');
    printStats(stereo, loop: true);
    final decoded = await decodeToPcm(oggPath, channels: 2);
    print(
      '  decoded Ogg: ${decoded[0].length} frames '
      '(source ${stereo[0].length}, '
      '${decoded[0].length == stereo[0].length ? 'exact match' : 'MISMATCH'})',
    );
    printStats(decoded, loop: true);
  }

  print('\nFiles:');
  for (final p in produced) {
    final f = File(p);
    print(
      '  ${p.split('/').last.padRight(22)} '
      '${(f.lengthSync() / 1024).toStringAsFixed(1).padLeft(8)} KB',
    );
  }
}

Directory _outputDir() {
  try {
    final script = File.fromUri(Platform.script);
    if (script.existsSync()) {
      return Directory('${script.parent.parent.path}/assets/audio');
    }
  } catch (_) {}
  return Directory('assets/audio');
}

// =============================================================================
// Sound effects
// =============================================================================

/// Cartoonish small-car engine hum, perfectly periodic.
///
/// The fundamental is exactly 100 Hz (441 samples) and the loop is exactly
/// [engineCycles] cycles long. Every component is periodic over the loop:
/// harmonics are integer multiples of 50 Hz (a lopsided "4-stroke" firing
/// cycle), noise is filtered circularly, and the flutter LFOs complete an
/// integer number of cycles. The result can be pitch shifted freely.
Float64List synthEngineLoop() {
  const period = engineCyclePeriod;
  const n = period * engineCycles;
  const superCycle = period * 2; // 50 Hz lopsided firing pattern
  final f0 = sampleRate / period;
  final rnd = Noise(101);

  // 1) Additive buzz. Low harmonics phase aligned -> punchy firing pulses.
  final table = Float64List(superCycle);
  for (var h = 1; h <= 200; h++) {
    final f = h * f0 / 2;
    if (f > 7000) break;
    final k = h / 2;
    var a = h.isEven ? 1.0 / math.pow(k, 0.8) : 0.20 / math.pow(k, 1.1);
    // Body / muffler resonances, then a soft roll-off.
    a *=
        1.0 +
        1.8 * _bell(f, 300, 0.45) +
        1.0 * _bell(f, 1150, 0.35) +
        0.35 * _bell(f, 2600, 0.3);
    a /= 1.0 + math.pow(f / 1800, 2.0);
    final ph = h <= 10 ? 0.0 : rnd.range(0, _twoPi);
    for (var i = 0; i < superCycle; i++) {
      table[i] += a * math.cos(_twoPi * h * i / superCycle + ph);
    }
  }
  normalizePeak(table);

  // 2) Exhaust "chuff": noise gated by the firing pulse, band-passed.
  final white = Float64List(n);
  for (var i = 0; i < n; i++) {
    white[i] = rnd.white();
  }
  final bp = Svf();
  final chuff = normalizePeak(
    circular(n, (i) {
      final c = 0.5 + 0.5 * math.cos(_twoPi * (i % period) / period);
      return bp.bandpass(white[i] * c * c * c * c, 900, 1.2);
    }),
  );

  // 3) Low rumble.
  final lp = Svf();
  final rumble = normalizePeak(
    circular(n, (i) => lp.lowpass(white[(i * 7 + 13) % n], 75, 0.9)),
  );

  // 4) Mix with a gentle, loop-periodic flutter.
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = i / n;
    final flutter =
        1.0 +
        0.035 * math.sin(_twoPi * 6 * t) +
        0.02 * math.sin(_twoPi * 11 * t + 1.0);
    final v =
        table[i % superCycle] * flutter + 0.10 * chuff[i] + 0.16 * rumble[i];
    out[i] = _tanh(1.3 * v);
  }

  final dc = DcBlock(20);
  final res = circular(n, (i) => dc.process(out[i]));
  return normalizePeak(res, peakDb);
}

/// Bright, round coin pickup: B5 -> E6 with a sparkly tail.
Float64List synthCoin() {
  final x = Float64List(secs(0.38));
  const step = 0.072;
  _mix(x, coinTone(mtof(83), step, decay: 0.25, square: 0.30), 0, 0.85);
  _mix(x, coinTone(mtof(88), 0.30, decay: 0.11, square: 0.30), step, 1.0);

  // Sparkles: tiny high bell pings from the E major pentatonic.
  final rnd = Noise(7);
  const sparkleNotes = [100, 104, 107, 109, 112]; // E7 G#7 B7 C#8 E8
  final times = [0.10, 0.145, 0.19, 0.24, 0.29];
  for (var j = 0; j < times.length; j++) {
    final f = mtof(sparkleNotes[rnd.intRange(0, sparkleNotes.length)]);
    _mix(x, ping(f, 0.035), times[j], 0.13 * math.pow(0.8, j));
  }

  final echo = FeedbackDelay(0.055, 0.28, lpHz: 5000);
  final hp = Svf();
  for (var i = 0; i < x.length; i++) {
    final v = x[i] + 0.22 * echo.process(x[i]);
    x[i] = hp.highpass(v, 150, 0.7);
  }
  return finishOneShot(x, fadeOutMs: 40);
}

/// Higher, sparklier coin for streaks: E6 G#6 B6 E7 arpeggio + glitter.
Float64List synthCoinCombo() {
  final x = Float64List(secs(0.45));
  const notes = [88, 92, 95, 100];
  const step = 0.045;
  for (var j = 0; j < notes.length; j++) {
    final last = j == notes.length - 1;
    _mix(
      x,
      coinTone(
        mtof(notes[j]),
        last ? 0.32 : step,
        decay: last ? 0.12 : 0.2,
        square: last ? 0.10 : 0.18,
      ),
      j * step,
      last ? 0.9 : 0.75,
    );
  }
  final rnd = Noise(9);
  const sparkleNotes = [104, 107, 109, 112, 114, 116]; // G#7 .. G#8 (E maj)
  for (var j = 0; j < 9; j++) {
    final t = 0.14 + j * 0.032 + rnd.range(-0.008, 0.008);
    final f = mtof(sparkleNotes[rnd.intRange(0, sparkleNotes.length)]);
    _mix(x, ping(f, 0.03), t, 0.12 * math.pow(0.85, j));
  }
  final echo = FeedbackDelay(0.047, 0.32, lpHz: 6000);
  final hp = Svf();
  for (var i = 0; i < x.length; i++) {
    final v = x[i] + 0.25 * echo.process(x[i]);
    x[i] = hp.highpass(v, 200, 0.7);
  }
  return finishOneShot(x, fadeOutMs: 45);
}

/// Cartoon crash: thump + crunchy noise + metallic clang + bouncing debris.
Float64List synthCrash() {
  final x = Float64List(secs(1.2));
  final rnd = Noise(5);

  // 1) Low thump.
  {
    var ph = 0.0;
    final n = secs(0.45);
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final f = 45 + 115 * math.exp(-t / 0.035);
      ph += f / sampleRate;
      x[i] +=
          0.9 * math.sin(_twoPi * ph) * _attack(t, 0.001) * math.exp(-t / 0.13);
    }
  }

  // 2) Crunch: sample-and-hold grit through a closing low-pass, driven.
  {
    final lp = Svf();
    var held = 0.0;
    final n = secs(0.7);
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      if (i % 3 == 0) held = rnd.white();
      final v = 0.5 * rnd.white() + 0.5 * held;
      final env =
          _attack(t, 0.0015) *
          (0.75 * math.exp(-t / 0.06) + 0.25 * math.exp(-t / 0.22));
      final y = lp.lowpass(v, 900 + 7000 * math.exp(-t / 0.08), 0.9);
      x[i] += 0.75 * _tanh(2.5 * y * env);
    }
  }

  // 3) Crumple grains (crushed panels).
  for (var g = 0; g < 14; g++) {
    final start = rnd.range(0.0, 0.32);
    final len = rnd.range(0.008, 0.025);
    final fc = rnd.range(1500, 5000);
    final bp = Svf();
    final n = secs(len);
    final at = secs(start);
    final amp = 0.35 * (1 - start / 0.4);
    for (var i = 0; i < n && at + i < x.length; i++) {
      final p = i / n;
      final env = math.sin(math.pi * p);
      x[at + i] += amp * env * bp.bandpass(rnd.white(), fc, 3);
    }
  }

  // 4) Metallic clang (modal synthesis, with a beating pair).
  {
    const base = 410.0;
    const ratios = [1.0, 1.0068, 2.32, 2.756, 4.25, 5.4, 6.63, 8.9];
    const amps = [0.5, 0.4, 0.35, 0.3, 0.25, 0.18, 0.12, 0.08];
    const decays = [0.45, 0.45, 0.35, 0.3, 0.22, 0.16, 0.12, 0.08];
    final at = secs(0.008);
    for (var m = 0; m < ratios.length; m++) {
      final f = base * ratios[m];
      final n = secs(decays[m] * 5);
      final ph0 = rnd.range(0, _twoPi);
      for (var i = 0; i < n && at + i < x.length; i++) {
        final t = i / sampleRate;
        x[at + i] +=
            0.38 *
            amps[m] *
            _attack(t, 0.001) *
            math.exp(-t / decays[m]) *
            math.sin(_twoPi * f * t + ph0);
      }
    }
  }

  // 5) Debris tinks bouncing to rest.
  const tinkTimes = [0.30, 0.47, 0.60, 0.70, 0.78, 0.84, 0.885, 0.92];
  for (var k = 0; k < tinkTimes.length; k++) {
    final f = rnd.range(2200, 5200);
    _mix(x, tink(f, rnd), tinkTimes[k], 0.32 * math.pow(0.8, k));
  }

  // 6) Small room.
  final out = applyRoom(x, wet: 0.18, size: 0.55, room: 0.6);
  final hp = Svf();
  for (var i = 0; i < out.length; i++) {
    out[i] = hp.highpass(out[i], 30, 0.7);
  }
  return finishOneShot(out, fadeOutMs: 90);
}

/// Car explosion: sub boom + saturated blast + rumbling tail + fire crackle
/// + falling debris, in a bigger space than the crash.
Float64List synthExplosion() {
  final x = Float64List(secs(2.8));
  final rnd = Noise(11);

  // 1) Boom with a falling pitch, saturated so its harmonics carry it on
  //    small speakers (a watch or a laptop can't play the fundamental).
  {
    var ph = 0.0;
    final n = secs(1.4);
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final f = 48 + 120 * math.exp(-t / 0.11);
      ph += f / sampleRate;
      final env = _attack(t, 0.002) * math.exp(-t / 0.45);
      x[i] += 0.9 * _tanh(2.6 * math.sin(_twoPi * ph)) * env;
    }
  }

  // 1b) Whump: the body of the blast, low noise opening a little and
  //     settling, the part a small speaker hears as "boom".
  {
    final lp = Svf();
    final n = secs(1.8);
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final env = _attack(t, 0.004) * math.exp(-t / 0.38);
      final fc = 180 + 520 * math.exp(-t / 0.2);
      x[i] += 1.4 * env * lp.lowpass(rnd.white(), fc, 1.1) * 2.2;
    }
  }

  // 2) Blast: noise through a low-pass that snaps open, then closes, driven
  //    hard for grit.
  {
    final lp = Svf();
    final n = secs(1.6);
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final env =
          _attack(t, 0.003) *
          (0.7 * math.exp(-t / 0.12) + 0.3 * math.exp(-t / 0.55));
      final fc = 250 + 6500 * math.exp(-t / 0.09);
      final y = lp.lowpass(rnd.white(), fc, 0.8);
      x[i] += 0.9 * _tanh(3.2 * y * env);
    }
  }

  // 3) Rumbling tail: filtered noise, slowly fading.
  {
    final lp = Svf();
    final n = x.length;
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final env = _attack(t, 0.06) * math.exp(-t / 0.95);
      x[i] += 0.7 * env * lp.lowpass(rnd.white(), 220, 0.7) * 3;
    }
  }

  // 4) Fire crackle: sharp pops, thinning out.
  for (var k = 0; k < 46; k++) {
    final start = 0.12 + math.pow(rnd.range(0, 1), 1.7) * 2.0;
    final f = rnd.range(1800, 6000);
    final bp = Svf();
    final n = secs(rnd.range(0.003, 0.009));
    final at = secs(start);
    final amp = 0.28 * (1 - start / 2.3);
    for (var i = 0; i < n && at + i < x.length; i++) {
      final env = math.exp(-i / (n * 0.3));
      x[at + i] += amp * env * bp.bandpass(rnd.white(), f, 2);
    }
  }

  // 5) Debris raining down.
  const debris = [0.45, 0.62, 0.75, 0.9, 1.02, 1.15, 1.31, 1.5];
  for (var k = 0; k < debris.length; k++) {
    _mix(
      x,
      tink(rnd.range(1600, 4200), rnd),
      debris[k],
      0.2 * math.pow(0.85, k),
    );
  }

  final out = applyRoom(x, wet: 0.28, size: 0.9, room: 0.8);
  final hp = Svf();
  for (var i = 0; i < out.length; i++) {
    // Squash it for loudness: a blast should feel big, not just peak.
    out[i] = _tanh(1.6 * hp.highpass(out[i], 30, 0.7));
  }
  return finishOneShot(out, fadeOutMs: 300);
}

/// Seamless tire squeal: wobbling tonal squeal + narrowband noise.
Float64List synthTireScreech() {
  final n = secs(screechSeconds);
  final rnd = Noise(23);
  // Wobble LFOs complete an integer number of cycles over the loop.
  double wob(int i) {
    final t = i / n;
    return 0.6 * math.sin(_twoPi * 11 * t) +
        0.3 * math.sin(_twoPi * 17 * t + 1.3) +
        0.25 * math.sin(_twoPi * 4 * t + 0.4);
  }

  // Tonal squeal with closed phase (integer number of cycles per loop).
  final freqs = Float64List(n);
  for (var i = 0; i < n; i++) {
    freqs[i] = screechPitchHz * (1 + 0.035 * wob(i));
  }
  final phase = closedPhase(freqs);

  // Periodic roughness (tyre chatter) and noise.
  final white = Float64List(n);
  for (var i = 0; i < n; i++) {
    white[i] = rnd.white();
  }
  final chatterLp = Svf();
  final chatter = normalizePeak(
    circular(n, (i) => chatterLp.lowpass(white[(i * 3 + 7) % n], 45, 0.8)),
  );
  final bp1 = Svf(), bp2 = Svf();
  final hiss = normalizePeak(
    circular(
      n,
      (i) =>
          bp1.bandpass(white[i], 1900, 4) +
          0.6 * bp2.bandpass(white[(i * 5 + 1) % n], 2600, 3),
    ),
  );

  final raw = Float64List(n);
  for (var i = 0; i < n; i++) {
    final p = phase[i];
    final tonal =
        math.sin(_twoPi * p) +
        0.35 * math.sin(_twoPi * 2 * p + 0.5) +
        0.12 * math.sin(_twoPi * 3 * p + 1.1);
    final am = 1.0 + 0.35 * chatter[i] + 0.12 * wob(i);
    raw[i] = 0.55 * tonal * am + 0.45 * hiss[i] * (1 + 0.2 * wob(i));
  }
  final lp = Svf();
  final dc = DcBlock(40);
  final out = circular(n, (i) => dc.process(lp.lowpass(raw[i], 7000, 0.7)));
  return normalizePeak(out, peakDb);
}

/// Near-miss whoosh with a doppler-ish pitch drop.
Float64List synthWhoosh() {
  final x = Float64List(secs(0.5));
  final rnd = Noise(31);
  const tc = 0.21; // moment the other car passes
  final bp = Svf(), air = Svf(), toneLp = Svf();
  final saw = Osc();
  for (var i = 0; i < x.length; i++) {
    final t = i / sampleRate;
    final s = 1.0 / (1.0 + math.exp(-(t - tc) / 0.035)); // 0 -> 1 at pass
    final fc = 2800 * math.pow(650 / 2800, s);
    final env = t < tc
        ? math.pow(t / tc, 2.2).toDouble()
        : math.exp(-(t - tc) / 0.085);
    final noise = bp.bandpass(rnd.pink(), fc.toDouble(), 1.1);
    final hiss = air.highpass(rnd.white(), 5000, 0.7);
    final tone = toneLp.lowpass(saw.saw(210 * (1 - s) + 150 * s), 1000, 0.7);
    x[i] = env * (noise * 1.0 + hiss * 0.06 + tone * 0.10);
  }
  return finishOneShot(x, fadeInMs: 3, fadeOutMs: 40);
}

/// Comedic wobbly spring "boing" with a creak when the car tips.
Float64List synthTipWarning() {
  final x = Float64List(secs(0.4));
  final rnd = Noise(41);

  // Boing: FM twang with a rising, wobbling pitch.
  {
    var pc = 0.0, pm = 0.0;
    for (var i = 0; i < x.length; i++) {
      final t = i / sampleRate;
      final f =
          180 +
          140 * (1 - math.exp(-t / 0.04)) +
          55 * math.sin(_twoPi * 13 * t) * math.exp(-t / 0.3);
      final index = 1.4 * math.exp(-t / 0.08) + 0.2;
      pm += f / sampleRate;
      pc += f / sampleRate;
      final v = math.sin(_twoPi * pc + index * math.sin(_twoPi * pm));
      x[i] += 0.7 * v * _attack(t, 0.005) * math.exp(-t / 0.17);
    }
  }

  // Creak: irregular click train through two wooden resonances.
  {
    final r1 = Svf(), r2 = Svf();
    var next = 0.0;
    for (var i = 0; i < x.length; i++) {
      final t = i / sampleRate;
      var impulse = 0.0;
      if (t >= next && t < 0.3) {
        impulse = 1.0;
        final rate = 45 + 30 * t / 0.3;
        next = t + (1 / rate) * rnd.range(0.7, 1.3);
      }
      final env = math.sin(math.pi * clamp01(t / 0.32));
      final y =
          r1.bandpass(impulse, 900, 8) + 0.7 * r2.bandpass(impulse, 1700, 6);
      x[i] += 0.9 * y * env;
    }
  }
  final hp = Svf();
  for (var i = 0; i < x.length; i++) {
    x[i] = hp.highpass(x[i], 80, 0.7);
  }
  return finishOneShot(x, fadeOutMs: 40);
}

/// Countdown "3-2-1" beep (A5).
Float64List synthCountdownBeep() {
  final x = Float64List(secs(0.15));
  final o1 = Osc(), o2 = Osc();
  final lp = Svf();
  const f = 880.0;
  for (var i = 0; i < x.length; i++) {
    final t = i / sampleRate;
    final v = 0.65 * o1.sine(f) + 0.3 * o2.pulse(f, 0.5);
    final env = adsr(t, 0.11, 0.003, 0.08, 0.75, 0.035);
    x[i] = lp.lowpass(v, 4000, 0.7) * env;
  }
  return finishOneShot(x, fadeOutMs: 5);
}

/// Brighter "GO!": A major stack with a pitch blip and vibrato.
Float64List synthCountdownGo() {
  final x = Float64List(secs(0.5));
  const notes = [81, 85, 88, 93]; // A5 C#6 E6 A6
  const gains = [0.9, 0.55, 0.6, 0.5];
  for (var j = 0; j < notes.length; j++) {
    final f0 = mtof(notes[j]);
    final o1 = Osc(j * 0.1), o2 = Osc(j * 0.37);
    final lp = Svf();
    for (var i = 0; i < x.length; i++) {
      final t = i / sampleRate;
      final blip = math.pow(2, (-2 * math.exp(-t / 0.012)) / 12).toDouble();
      final vib =
          1 + 0.004 * math.sin(_twoPi * 6 * t) * clamp01((t - 0.1) / 0.1);
      final f = f0 * blip * vib;
      final v = 0.55 * o1.saw(f) + 0.45 * o2.pulse(f * 1.003, 0.5);
      final env = adsr(t, 0.34, 0.004, 0.2, 0.7, 0.15);
      final cut = 2500 + 4000 * math.exp(-t / 0.12);
      x[i] += gains[j] * lp.lowpass(v, cut, 0.8) * env;
    }
  }
  return finishOneShot(x, fadeOutMs: 20);
}

/// Soft UI click / pop.
Float64List synthUiTap() {
  final x = Float64List(secs(0.08));
  final rnd = Noise(51);
  final lp = Svf();
  var ph = 0.0;
  for (var i = 0; i < x.length; i++) {
    final t = i / sampleRate;
    final f = 500 + 700 * math.exp(-t / 0.012);
    ph += f / sampleRate;
    final body =
        math.sin(_twoPi * ph) * _attack(t, 0.0008) * math.exp(-t / 0.018);
    final click = lp.lowpass(rnd.white(), 3500, 0.7) * math.exp(-t / 0.0015);
    x[i] = body + 0.25 * click;
  }
  return finishOneShot(x, fadeInMs: 0.5, fadeOutMs: 10);
}

/// Celebratory new-high-score fanfare (C major, brassy, with glitter).
Float64List synthNewRecord() {
  final x = Float64List(secs(1.5));
  // Arpeggio pickup -> held top note.
  const melody = [
    (0.00, 67, 0.08), // G4
    (0.08, 72, 0.08), // C5
    (0.16, 76, 0.08), // E5
    (0.24, 79, 0.16), // G5
    (0.42, 76, 0.07), // E5
    (0.50, 79, 0.85), // G5 (held)
  ];
  for (final (t, m, d) in melody) {
    _mix(x, brassVoice(mtof(m + 12), d, 1.0), t, 0.55);
    _mix(x, brassVoice(mtof(m), d, 0.9, detune: 1.004), t, 0.35);
  }
  // Supporting chord + bass.
  for (final m in [60, 64, 67]) {
    _mix(x, brassVoice(mtof(m), 0.8, 0.7, detune: 0.997), 0.50, 0.22);
  }
  _mix(x, brassVoice(mtof(48), 0.2, 0.9), 0.0, 0.3);
  _mix(x, brassVoice(mtof(48), 0.8, 0.9), 0.50, 0.3);

  // Timpani-ish hit and cymbal swell on the downbeat.
  _mix(x, drumKick(hi: 140, lo: 65, decay: 0.35, click: 0.1), 0.50, 0.55);
  final cym = drumCrash(decay: 0.7);
  _mix(x, cym, 0.50, 0.18);

  // Glitter.
  final rnd = Noise(61);
  const glitter = [96, 100, 103, 108, 112, 115]; // C7 E7 G7 C8 E8 G8
  for (var j = 0; j < 14; j++) {
    final t = 0.52 + j * 0.06 + rnd.range(-0.015, 0.015);
    _mix(
      x,
      ping(mtof(glitter[rnd.intRange(0, glitter.length)]), 0.05),
      t,
      0.07 * (1 - j / 16),
    );
  }
  final out = applyRoom(x, wet: 0.22, size: 0.8, room: 0.75);
  return finishOneShot(out, fadeOutMs: 120);
}

/// Playful descending "wah-wah" jingle.
Float64List synthGameOver() {
  final x = Float64List(secs(1.2));
  const notes = [
    (0.00, 70, 0.20), // Bb4
    (0.24, 69, 0.20), // A4
    (0.48, 68, 0.20), // Ab4
    (0.72, 67, 0.40), // G4 (long, wobbling)
  ];
  for (var j = 0; j < notes.length; j++) {
    final (t, m, d) = notes[j];
    _mix(x, wahVoice(mtof(m), d, last: j == notes.length - 1), t, 0.8);
  }
  final out = applyRoom(x, wet: 0.15, size: 0.6, room: 0.6);
  return finishOneShot(out, fadeOutMs: 60);
}

// =============================================================================
// SFX building blocks
// =============================================================================

/// Coin tone: rounded square + sine with a bright attack.
Float64List coinTone(
  double f,
  double gate, {
  required double decay,
  required double square,
}) {
  final rel = 0.015;
  final n = secs(gate + rel + 0.002);
  final out = Float64List(n);
  final o1 = Osc(), o2 = Osc(), o3 = Osc();
  final lp = Svf();
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final v =
        square * o1.pulse(f, 0.5) +
        (1 - square) * o2.sine(f) +
        0.2 * o3.sine(2 * f) * math.exp(-t / 0.04);
    var env = _attack(t, 0.0015) * math.exp(-t / decay);
    if (t > gate) env *= math.max(0.0, 1 - (t - gate) / rel);
    out[i] = lp.lowpass(v, 2800 + 4000 * math.exp(-t / 0.05), 0.7) * env;
  }
  return out;
}

/// Tiny high sine ping (sparkle).
Float64List ping(double f, double decay) {
  final n = secs(decay * 6);
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    out[i] =
        _attack(t, 0.001) *
        (math.sin(_twoPi * f * t) * math.exp(-t / decay) +
            0.25 *
                math.sin(_twoPi * 2.01 * f * t) *
                math.exp(-t / (decay * 0.5)));
  }
  return out;
}

/// Small metallic debris tink.
Float64List tink(double f, Noise rnd) {
  const ratios = [1.0, 1.47, 2.09, 2.56];
  const amps = [1.0, 0.6, 0.4, 0.25];
  const decays = [0.05, 0.035, 0.025, 0.02];
  final n = secs(0.3);
  final out = Float64List(n);
  for (var m = 0; m < ratios.length; m++) {
    final ph = rnd.range(0, _twoPi);
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      out[i] +=
          amps[m] *
          math.exp(-t / decays[m]) *
          math.sin(_twoPi * f * ratios[m] * t + ph);
    }
  }
  for (var i = 0; i < secs(0.0015); i++) {
    out[i] += 0.5 * rnd.white() * (1 - i / secs(0.0015));
  }
  for (var i = 0; i < secs(0.001); i++) {
    out[i] *= i / secs(0.001);
  }
  return out;
}

/// Brassy fanfare voice: detuned saws + pulse with an opening filter.
Float64List brassVoice(
  double f,
  double dur,
  double vel, {
  double detune = 1.0,
}) {
  const rel = 0.14;
  final n = secs(dur + rel);
  final out = Float64List(n);
  final o1 = Osc(0.1), o2 = Osc(0.6), o3 = Osc(0.3);
  final lp = Svf();
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final vib = t > 0.18
        ? 0.006 * math.sin(_twoPi * 5.5 * t) * clamp01((t - 0.18) / 0.2)
        : 0.0;
    final ff = f * detune * (1 + vib);
    final v =
        0.4 * o1.saw(ff * 1.0035) +
        0.4 * o2.saw(ff * 0.9965) +
        0.3 * o3.pulse(ff, 0.4);
    final fenv = _attack(t, 0.02) * math.exp(-t / 0.25);
    final cut = math.min(f * 1.5 + 600 + 3500 * fenv * vel, 12000.0);
    out[i] =
        lp.lowpass(v, cut, 0.9) * adsr(t, dur, 0.012, 0.15, 0.8, rel) * vel;
  }
  return out;
}

/// Muted-trombone style "wah" voice for the game-over jingle.
Float64List wahVoice(double f, double dur, {bool last = false}) {
  const rel = 0.08;
  final n = secs(dur + rel);
  final out = Float64List(n);
  final o1 = Osc(), o2 = Osc(0.5);
  final lp = Svf();
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    double ff = f;
    double wah;
    if (last) {
      final vib = 0.35 * math.sin(_twoPi * 6 * t) * clamp01(t / 0.08);
      final slide = -1.2 * clamp01((t - dur * 0.6) / (dur * 0.5));
      ff = f * math.pow(2, (vib + slide) / 12).toDouble();
      wah = 0.5 + 0.5 * math.sin(_twoPi * 6 * t - math.pi / 2);
    } else {
      wah = math.pow(math.sin(math.pi * clamp01(t / dur)), 1.5).toDouble();
    }
    final v = 0.6 * o1.saw(ff) + 0.4 * o2.pulse(ff, 0.5);
    final cut = 350 + 2000 * wah;
    out[i] = lp.lowpass(v, cut, 2.2) * adsr(t, dur, 0.015, 0.1, 0.85, rel);
  }
  return out;
}

// =============================================================================
// Music: driving loop
// =============================================================================

// Melodies: one string per bar, tokens `note/sixteenths`, `r` = rest.
const List<String> melodyA = [
  'E5/2 G5/2 C6/3 B5/1 C6/2 G5/2 E5/2 G5/2', // C
  'D6/3 C6/1 B5/2 G5/2 D5/4 r/2 G5/2', // G
  'C6/2 B5/2 A5/2 E5/2 A5/3 B5/1 C6/2 E6/2', // Am
  'D6/3 C6/1 A5/4 F5/2 A5/2 C6/2 A5/2', // F
  'E5/2 G5/2 C6/3 B5/1 C6/2 E6/2 G6/2 E6/2', // C
  'D6/4 B5/2 G5/2 B5/2 D6/2 G6/4', // G
  'A5/3 C6/1 F6/4 E6/2 D6/2 C6/2 A5/2', // F
  'D6/4 B5/2 G5/2 A5/2 B5/2 C6/2 D6/2', // G
];

const List<String> melodyB = [
  'C6/2 r/2 C6/2 D6/2 E6/4 C6/2 G5/2', // C
  'B5/2 r/2 B5/2 C6/2 D6/4 B5/2 G5/2', // G
  'A5/2 r/2 A5/2 B5/2 C6/2 E6/2 D6/2 C6/2', // Am
  'C6/6 A5/2 F5/4 G5/2 A5/2', // F
  'G5/2 C6/2 E6/2 G6/2 E6/2 C6/2 G5/2 C6/2', // C
  'B5/2 D6/2 G6/2 D6/2 B5/2 G5/2 B5/2 D6/2', // G
  'C6/3 A5/1 C6/2 F6/4 E6/2 D6/2 C6/2', // F
  'D6/6 r/2 G5/2 A5/2 B5/2 D6/2', // G
];

const List<String> melodyBridge = [
  'E6/6 D6/2 C6/4 B5/4', // Am
  'C6/6 A5/2 F5/8', // F
  'G5/6 C6/2 E6/4 D6/4', // C
  'D6/6 B5/2 G5/8', // G
  'E6/6 D6/2 C6/4 E6/4', // Am
  'F6/6 E6/2 C6/4 A5/4', // F
  'D6/4 F6/4 A6/4 F6/4', // Dm
  'G6/4 F6/2 E6/2 D6/2 C6/2 B5/2 D6/2', // G
];

const List<String> progMain = ['C', 'G', 'Am', 'F', 'C', 'G', 'F', 'G'];
const List<String> progBridge = ['Am', 'F', 'C', 'G', 'Am', 'F', 'Dm', 'G'];

/// Upbeat chiptune / synth-pop driving loop: 32 bars, A B C(bridge) D.
List<Float64List> renderMusicLoop() {
  final seq = Seq(musicBpm, musicBars);
  final n = seq.length;
  final drums = Bus(n), bass = Bus(n), lead = Bus(n), arp = Bus(n);
  final pad = Bus(n), fx = Bus(n), send = Bus(n);
  final duck = Float64List(n);
  const k = musicKey;
  final sixteenth = seq.secPerBeat / 4;

  final kick = drumKick();
  final snare = drumSnare();
  final clap = drumClap();
  final hatC = drumHat(0.035);
  final hatO = drumHat(0.2);
  final crash = drumCrash();

  void hitKick(double beat, double vel) {
    final at = seq.at(beat);
    drums.add(kick, at, gain: 0.95 * vel);
    addDuck(duck, at, vel, 0.085);
  }

  void hitSnare(double beat, double vel) {
    final at = seq.at(beat);
    drums.add(snare, at, gain: 0.55 * vel);
    send.add(snare, at, gain: 0.18 * vel);
  }

  void hitClap(double beat, double vel) {
    final at = seq.at(beat);
    drums.add(clap, at, gain: 0.35 * vel, pan: 0.1);
    send.add(clap, at, gain: 0.15 * vel);
  }

  void hitHat(double beat, double vel) =>
      drums.add(hatC, seq.at(beat), gain: 0.2 * vel, pan: 0.25);
  void hitOpenHat(double beat, double vel) =>
      drums.add(hatO, seq.at(beat), gain: 0.16 * vel, pan: 0.25);

  final chords = [...progMain, ...progMain, ...progBridge, ...progMain];

  for (var bar = 0; bar < musicBars; bar++) {
    final sec = bar ~/ 8; // 0=A 1=B 2=C(bridge) 3=D
    final inBar = bar % 8;
    final chord = chords[bar];

    // --- Drums -------------------------------------------------------------
    String kickPat = 'x...x...x...x...';
    String snarePat = '....x.......x...';
    String clapPat = '................';
    String hatPat = 'o.x.o.x.o.x.o.x.';
    String openPat = '................';
    switch (sec) {
      case 0:
        if (inBar == 7) snarePat = '....x.......x.xx';
      case 1:
        clapPat = '....x.......x...';
        hatPat = 'ooXoooXoooXoooXo';
        if (inBar == 7) snarePat = '....x.......xxxx';
      case 2:
        kickPat = 'x.........x.....';
        snarePat = '........x.......';
        hatPat = 'o.o.o.o.o.o.o.o.';
        if (inBar == 6) {
          kickPat = 'x...x...x...x...';
          snarePat = 'o...o...o...o...';
          hatPat = 'oooooooooooooooo';
        } else if (inBar == 7) {
          kickPat = 'x...x...x...x...';
          snarePat = 'o.o.o.o.xxxxXXXX';
          hatPat = 'oooooooooooooooo';
        }
      case 3:
        clapPat = '....x.......x...';
        hatPat = 'oo.ooo.ooo.ooo.o';
        openPat = '..X...X...X...X.';
        if (inBar == 7) snarePat = '....x...x.x.xXXX';
    }
    steps(kickPat, bar, hitKick);
    steps(snarePat, bar, hitSnare);
    steps(clapPat, bar, hitClap);
    steps(hatPat, bar, hitHat);
    steps(openPat, bar, hitOpenHat);
    if (inBar == 0) {
      final vel = sec == 2 ? 0.5 : (sec == 0 ? 0.7 : 0.9);
      drums.add(crash, seq.at(bar * 4.0), gain: 0.22 * vel, pan: -0.25);
      send.add(crash, seq.at(bar * 4.0), gain: 0.05 * vel);
    }

    // --- Bass --------------------------------------------------------------
    final root = 36 + noteClass(chord) + k;
    var bassPat = switch (sec) {
      0 => 'R-R-R-R-R-R-R-O-',
      2 => 'R-----R-----R-O-',
      _ => 'R-O-R-O-R-O-F-O-',
    };
    if (sec == 2 && inBar == 7) bassPat = 'R-R-R-R-RRRRRRRR';
    for (final (step, len, offset) in parseStepLine(bassPat)) {
      final f = mtof(root + offset);
      bass.add(
        bassVoice(f, len * sixteenth * 0.92, step % 4 == 0 ? 1.0 : 0.85),
        seq.at(bar * 4 + step / 4),
      );
    }

    // --- Pad ---------------------------------------------------------------
    final tones = [for (final t in triad(chord)) t + k];
    final padGain = const [0.55, 0.6, 1.0, 0.7][sec];
    for (final t in [...tones, tones[0] - 12]) {
      final f = mtof(t);
      final dur = seq.secPerBeat * 4 * 0.98;
      pad.add(
        padVoice(f, dur, 1.0006),
        seq.at(bar * 4.0),
        gain: padGain,
        pan: -0.5,
      );
      pad.add(
        padVoice(f, dur, 0.9994),
        seq.at(bar * 4.0),
        gain: padGain,
        pan: 0.5,
      );
    }

    // --- Arpeggio ------------------------------------------------------------
    final arpTones = [...tones, tones[0] + 12];
    final arpOrder = switch (sec) {
      0 => const [0, 1, 2, 1],
      2 => const [0, 2, 1, 2],
      _ => const [0, 1, 2, 3],
    };
    final arpVel = const [0.65, 0.85, 0.6, 0.95][sec];
    final stepsPerBar = sec == 2 ? 8 : 16;
    for (var s = 0; s < stepsPerBar; s++) {
      final beat = bar * 4 + s * 4 / stepsPerBar;
      final note = arpTones[arpOrder[s % arpOrder.length]];
      final accent = (s % (stepsPerBar ~/ 4) == 0) ? 1.0 : 0.75;
      arp.add(
        pluckVoice(mtof(note), (4 / stepsPerBar) * seq.secPerBeat * 0.8),
        seq.at(beat),
        gain: arpVel * accent,
        pan: s.isEven ? -0.3 : 0.3,
      );
    }
  }

  // --- Lead melody ----------------------------------------------------------
  final leadDry = Bus(n);
  void playMelody(
    List<String> bars,
    int startBar,
    double vel, {
    bool double = false,
  }) {
    for (final note in parseMelody(bars, startBar: startBar)) {
      final m = note.midi + k + musicLeadShift;
      final dur = note.len * seq.secPerBeat - 0.015;
      leadDry.add(leadVoice(mtof(m), dur, vel), seq.at(note.beat));
      if (double) {
        leadDry.add(
          softVoice(mtof(m + 12), dur),
          seq.at(note.beat),
          gain: 0.22 * vel,
        );
      }
    }
  }

  playMelody(melodyA, 0, 0.85);
  playMelody(melodyB, 8, 0.95);
  playMelody(melodyBridge, 16, 0.8);
  playMelody(melodyA, 24, 1.0, double: true);

  // Riser into the final section.
  fx.add(riser(seq.secPerBeat * 8), seq.at(22 * 4.0), gain: 0.5);

  // --- Effects -------------------------------------------------------------
  // Sidechain pumping.
  bass.duck(duck, 0.35);
  pad.duck(duck, 0.6);
  arp.duck(duck, 0.3);

  // Ping-pong dotted-eighth delay on the lead (circular = seamless).
  final pp = PingPong(secs(seq.secPerBeat * 0.75), 0.38, lpHz: 4500);
  final delayed = Bus(n);
  for (var pass = 0; pass < 2; pass++) {
    for (var i = 0; i < n; i++) {
      pp.process(0.5 * (leadDry.l[i] + leadDry.r[i]));
      if (pass == 1) {
        delayed.l[i] = pp.outL;
        delayed.r[i] = pp.outR;
      }
    }
  }
  lead.addBus(leadDry, 1.0);
  lead.addBus(delayed, 0.22);

  send.addBus(lead, 0.18);
  send.addBus(arp, 0.25);
  send.addBus(pad, 0.3);
  send.addBus(fx, 0.3);
  final wet = reverbBus(send, room: 0.78, damp: 0.35, hpHz: 250);

  // --- Mix -----------------------------------------------------------------
  final busGains = <String, (Bus, double)>{
    'drums': (drums, 1.0),
    'bass': (bass, 0.6),
    'lead': (lead, 0.75),
    'arp': (arp, 0.5),
    'pad': (pad, 0.12),
    'fx': (fx, 0.6),
    'reverb': (wet, 0.22),
  };
  return masterBus(busGains, n, targetRmsDb: -15.0);
}

// =============================================================================
// Music: menu loop (chill lo-fi)
// =============================================================================

/// Lo-fi chord voicings (without bass): Dm9 G13 Cmaj9 Am9.
const List<List<int>> lofiChords = [
  [53, 57, 60, 64], // Dm9: F A C E
  [53, 59, 64, 69], // G13: F B E A
  [52, 55, 59, 62], // Cmaj9: E G B D
  [55, 59, 60, 64], // Am9: G B C E
];
const List<int> lofiBass = [38, 43, 36, 45]; // D2 G2 C2 A2

const List<String> lofiMelody1 = [
  'A4/4 C5/2 D5/2 E5/6 r/2', // Dm9
  'D5/3 C5/1 B4/4 G4/4 r/4', // G13
  'E5/4 G5/2 E5/2 D5/4 B4/4', // Cmaj9
  'C5/6 B4/2 A4/6 r/2', // Am9
];
const List<String> lofiMelody2 = [
  'F5/4 E5/2 D5/2 C5/4 A4/4', // Dm9
  'B4/3 C5/1 D5/4 F5/4 E5/4', // G13
  'E5/6 D5/2 G5/4 E5/4', // Cmaj9
  'C5/4 B4/2 A4/2 E4/8', // Am9
];

List<Float64List> renderMenuMusic() {
  final seq = Seq(menuBpm, menuBars);
  final n = seq.length;
  final keys = Bus(n), bass = Bus(n), drums = Bus(n), mel = Bus(n);
  final vinyl = Bus(n), send = Bus(n);
  final duck = Float64List(n);
  const k = menuKey;
  final rnd = Noise(77);
  const swing = 0.22; // fraction of a 16th the off-16ths are delayed

  // Slow tape "wow": integer number of cycles over the loop.
  final loopSec = n / sampleRate;
  final wowHz = (0.45 * loopSec).roundToDouble() / loopSec;

  final kick = drumKick(hi: 120, lo: 46, decay: 0.34, click: 0.08, drive: 1.2);
  final snare = drumSnare(
    tone: 175,
    noiseDecay: 0.16,
    bright: 5000,
    toneAmt: 0.7,
  );
  final hat = drumHat(0.03, hpHz: 6500, lpHz: 9000);
  final shaker = drumHat(0.06, hpHz: 5000, lpHz: 8000, metal: 0.1);

  for (var bar = 0; bar < menuBars; bar++) {
    final c = bar % 4;
    final intro = bar < 4;

    // Electric piano: two strummed hits per bar.
    for (final (beat, len, vel) in [(0.0, 1.9, 0.9), (2.5, 1.4, 0.7)]) {
      final startBeat = bar * 4 + beat;
      final voicing = lofiChords[c];
      for (var j = 0; j < voicing.length; j++) {
        final f = mtof(voicing[j] + k);
        final at = seq.at(startBeat) + secs(0.012 * j);
        final t0 = at / sampleRate;
        keys.add(
          epVoice(
            f,
            len * seq.secPerBeat,
            vel * rnd.range(0.85, 1.0),
            wowHz: wowHz,
            startSec: t0,
          ),
          at,
          gain: 0.5,
          pan: -0.35 + 0.7 * j / (voicing.length - 1),
        );
      }
    }

    // Bass.
    final root = lofiBass[c] + k;
    for (final (beat, len, off) in [
      (0.0, 1.75, 0),
      (2.5, 1.3, 0),
      (3.5, 0.45, 7),
    ]) {
      final at = seq.at(bar * 4 + beat);
      bass.add(
        lofiBassVoice(mtof(root + off), len * seq.secPerBeat),
        at,
        gain: off == 0 ? 1.0 : 0.6,
      );
    }

    // Drums (swung 16ths).
    void hitKick(double b, double v) {
      final at = seq.at(b);
      drums.add(kick, at, gain: 0.9 * v);
      addDuck(duck, at, v, 0.12);
    }

    void hitSnare(double b, double v) {
      final at = seq.at(b);
      drums.add(snare, at, gain: 0.42 * v, pan: -0.05);
      send.add(snare, at, gain: 0.25 * v);
    }

    void hitHat(double b, double v) => drums.add(
      hat,
      seq.at(b) + secs(rnd.range(0, 0.006)),
      gain: 0.16 * v * rnd.range(0.8, 1.0),
      pan: 0.3,
    );
    void hitShaker(double b, double v) =>
        drums.add(shaker, seq.at(b), gain: 0.08 * v, pan: -0.3);

    if (intro) {
      steps('o.o.o.o.o.o.o.o.', bar, hitHat, swing: swing);
    } else if (bar == menuBars - 1) {
      steps('x...............', bar, hitKick, swing: swing);
      steps('o.o.o.o.o.o.oooo', bar, hitHat, swing: swing);
    } else {
      steps('X......x..x.....', bar, hitKick, swing: swing);
      steps('....X.......X...', bar, hitSnare, swing: swing);
      steps('x.oxx.o.x.oxx.oo', bar, hitHat, swing: swing);
      steps('..o...o...o...o.', bar, hitShaker, swing: swing);
    }
  }

  // Melody (kalimba / mallet).
  void playMelody(List<String> bars, int startBar, double vel) {
    for (final note in parseMelody(bars, startBar: startBar)) {
      final dur = note.len * seq.secPerBeat;
      final at = seq.at(note.beat);
      final v = malletVoice(mtof(note.midi + k), dur);
      mel.add(v, at, gain: vel, pan: 0.1);
    }
  }

  playMelody(lofiMelody1, 4, 0.8);
  playMelody(lofiMelody2, 8, 0.85);
  playMelody([...lofiMelody1.take(3), lofiMelody2[3]], 12, 0.8);

  // Vinyl crackle + hiss (circularly filtered so the loop stays seamless).
  {
    final raw = Float64List(n);
    for (var i = 0; i < n; i++) {
      raw[i] = 0.02 * rnd.white();
      if (rnd.next() < 7 / sampleRate) {
        raw[i] += math.pow(rnd.next(), 3) * (rnd.next() < 0.5 ? -1 : 1);
      }
    }
    final bp = Svf(), lp = Svf();
    final crackle = circular(
      n,
      (i) =>
          bp.bandpass(raw[i], 2500, 0.6) + 0.5 * lp.lowpass(raw[i], 900, 0.7),
    );
    vinyl.add(crackle, 0, gain: 0.25);
  }

  keys.duck(duck, 0.2);
  bass.duck(duck, 0.25);
  send.addBus(keys, 0.35);
  send.addBus(mel, 0.45);
  final wet = reverbBus(send, room: 0.86, damp: 0.5, hpHz: 200);

  final mix = masterBus(
    {
      'keys': (keys, 0.6),
      'bass': (bass, 0.45),
      'drums': (drums, 0.8),
      'melody': (mel, 0.6),
      'vinyl': (vinyl, 8.0),
      'reverb': (wet, 0.28),
    },
    n,
    targetRmsDb: -17.0,
    lowpassHz: 7500,
    saturate: 1.4,
  );
  return mix;
}

// =============================================================================
// Instrument voices
// =============================================================================

/// Chiptune lead: 25% pulse + saw, filter envelope, delayed vibrato.
Float64List leadVoice(double f, double dur, double vel) {
  const rel = 0.09;
  final n = secs(dur + rel);
  final out = Float64List(n);
  final o1 = Osc(), o2 = Osc(0.3);
  final lp = Svf();
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final vibAmt = t > 0.14 ? 0.22 * clamp01((t - 0.14) / 0.15) : 0.0;
    final ff = f * (1 + 0.0578 * vibAmt * math.sin(_twoPi * 5.6 * t));
    final v = 0.6 * o1.pulse(ff, 0.25) + 0.4 * o2.saw(ff * 1.004);
    final cut = math.min(f * 3 + 1200 + 2500 * math.exp(-t / 0.12), 12000.0);
    out[i] =
        lp.lowpass(v, cut, 0.8) * adsr(t, dur, 0.004, 0.15, 0.7, rel) * vel;
  }
  return out;
}

/// Soft triangle voice used to double the lead an octave up.
Float64List softVoice(double f, double dur) {
  const rel = 0.08;
  final n = secs(dur + rel);
  final out = Float64List(n);
  final o = Osc();
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    out[i] = o.tri(f) * adsr(t, dur, 0.006, 0.2, 0.6, rel);
  }
  return out;
}

/// Plucky arp: saw/pulse with a fast filter envelope.
Float64List pluckVoice(double f, double dur) {
  const rel = 0.06;
  final n = secs(dur + rel);
  final out = Float64List(n);
  final o1 = Osc(), o2 = Osc(0.5);
  final lp = Svf();
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final v = 0.6 * o1.saw(f) + 0.4 * o2.pulse(f * 2, 0.5) * 0.5;
    final cut = math.min(f * 2 + 3000 * math.exp(-t / 0.05), 12000.0);
    var env = _attack(t, 0.002) * math.exp(-t / 0.12);
    if (t > dur) env *= math.max(0.0, 1 - (t - dur) / rel);
    out[i] = lp.lowpass(v, cut, 1.2) * env;
  }
  return out;
}

/// Punchy synth bass: square + saw + sub sine, enveloped filter, soft drive.
Float64List bassVoice(double f, double dur, double vel) {
  const rel = 0.04;
  final n = secs(dur + rel);
  final out = Float64List(n);
  final o1 = Osc(), o2 = Osc(), sub = Osc();
  final lp = Svf();
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final v = 0.45 * o1.pulse(f, 0.5) + 0.45 * o2.saw(f) + 0.7 * sub.sine(f);
    final cut = 250 + 1600 * math.exp(-t / 0.07) * vel;
    final y = lp.lowpass(v, cut, 1.1) * adsr(t, dur, 0.003, 0.2, 0.75, rel);
    out[i] = _tanh(1.5 * y) * vel;
  }
  return out;
}

/// Warm pad: two detuned saws, slow attack, low-passed.
Float64List padVoice(double f, double dur, double detune) {
  const rel = 0.35;
  final n = secs(dur + rel);
  final out = Float64List(n);
  final o1 = Osc(detune > 1 ? 0.13 : 0.71), o2 = Osc(detune > 1 ? 0.42 : 0.9);
  final lp = Svf();
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final v =
        0.5 * o1.saw(f * detune) + 0.5 * o2.saw(f * (2 - detune) * 1.0008);
    out[i] = lp.lowpass(v, 1800, 0.6) * adsr(t, dur, 0.08, 0.6, 0.8, rel);
  }
  return out;
}

/// FM electric piano (Rhodes-ish) with slow tape wow.
Float64List epVoice(
  double f,
  double dur,
  double vel, {
  required double wowHz,
  required double startSec,
}) {
  const rel = 0.35;
  final n = secs(dur + rel);
  final out = Float64List(n);
  var pc = 0.0, pm = 0.0, pt = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final wow = 1 + 0.0025 * math.sin(_twoPi * wowHz * (startSec + t));
    final ff = f * wow;
    final index = 0.25 + 1.5 * vel * math.exp(-t / 0.35);
    final c = math.sin(_twoPi * pc + index * math.sin(_twoPi * pm));
    final tine = 0.1 * vel * math.sin(_twoPi * pt) * math.exp(-t / 0.03);
    pc += ff / sampleRate;
    pm += ff / sampleRate;
    pt += ff * 7.0 / sampleRate;
    var env = _attack(t, 0.003) * math.exp(-t / 1.6);
    if (t > dur) env *= math.exp(-(t - dur) / 0.08) * (1 - (t - dur) / rel);
    out[i] = (c + tine) * env * vel;
  }
  return out;
}

/// Round lo-fi bass: sine + a touch of triangle, low-passed.
Float64List lofiBassVoice(double f, double dur) {
  const rel = 0.08;
  final n = secs(dur + rel);
  final out = Float64List(n);
  final o1 = Osc(), o2 = Osc();
  final lp = Svf();
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final v = o1.sine(f) + 0.25 * o2.tri(f);
    out[i] = lp.lowpass(v, 600, 0.7) * adsr(t, dur, 0.006, 0.3, 0.8, rel);
  }
  return out;
}

/// Kalimba-like mallet for the menu melody.
Float64List malletVoice(double f, double dur) {
  final n = secs(math.max(dur, 0.2) + 0.9);
  final out = Float64List(n);
  const ratios = [1.0, 3.0, 5.95];
  const amps = [1.0, 0.16, 0.1];
  const decays = [0.9, 0.2, 0.04];
  for (var m = 0; m < ratios.length; m++) {
    final ff = f * ratios[m];
    if (ff > 16000) continue;
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      var env = math.exp(-t / decays[m]);
      if (t > dur) env *= math.exp(-(t - dur) / 0.25);
      out[i] += amps[m] * env * math.sin(_twoPi * ff * t);
    }
  }
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    out[i] =
        _tanh(1.2 * out[i] * _attack(t, 0.002)) *
        (i > n - secs(0.01) ? (n - i) / secs(0.01) : 1.0);
  }
  return out;
}

// =============================================================================
// Drum voices
// =============================================================================

Float64List drumKick({
  double hi = 170,
  double lo = 50,
  double pitchTau = 0.03,
  double decay = 0.3,
  double click = 0.3,
  double drive = 1.6,
}) {
  final n = secs(decay * 3.2);
  final out = Float64List(n);
  final rnd = Noise(1);
  final lp = Svf();
  var ph = 0.0;
  final norm = _tanh(drive);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final f = lo + (hi - lo) * math.exp(-t / pitchTau);
    ph += f / sampleRate;
    final body =
        math.sin(_twoPi * ph) * _attack(t, 0.0015) * math.exp(-t / decay);
    final clk =
        lp.lowpass(rnd.white(), 3500, 0.7) * math.exp(-t / 0.004) * click;
    out[i] = _tanh(drive * (body + clk)) / norm;
  }
  return fadeEdges(out, inMs: 0, outMs: 8);
}

Float64List drumSnare({
  double tone = 185,
  double noiseDecay = 0.13,
  double bright = 8000,
  double toneAmt = 0.55,
}) {
  final n = secs(0.45);
  final out = Float64List(n);
  final rnd = Noise(2);
  final hp = Svf(), lp = Svf();
  var p1 = 0.0, p2 = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final tf = tone * (1 + 0.5 * math.exp(-t / 0.01));
    p1 += tf / sampleRate;
    p2 += tf * 1.75 / sampleRate;
    final tn =
        (0.7 * math.sin(_twoPi * p1) + 0.4 * math.sin(_twoPi * p2)) *
        math.exp(-t / 0.06);
    final nz =
        lp.lowpass(hp.highpass(rnd.white(), 1200, 0.7), bright, 0.7) *
        math.exp(-t / noiseDecay);
    out[i] = (toneAmt * tn + nz) * _attack(t, 0.001);
  }
  return fadeEdges(out, inMs: 0, outMs: 20);
}

Float64List drumClap() {
  final n = secs(0.35);
  final out = Float64List(n);
  final rnd = Noise(3);
  final bp = Svf(), hp = Svf();
  const bursts = [0.0, 0.011, 0.022, 0.034];
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    var env = 0.0;
    for (final b in bursts) {
      if (t >= b) env = math.max(env, math.exp(-(t - b) / 0.006));
    }
    if (t >= bursts.last) {
      env = math.max(env, 0.8 * math.exp(-(t - bursts.last) / 0.09));
    }
    final v = bp.bandpass(rnd.white(), 1300, 1.5);
    out[i] = hp.highpass(v, 600, 0.7) * env;
  }
  return fadeEdges(normalizePeak(out), inMs: 0.3, outMs: 20);
}

const List<double> _metalFreqs = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0];

Float64List drumHat(
  double decay, {
  double hpHz = 7000,
  double lpHz = 15000,
  double metal = 0.55,
}) {
  final n = secs(decay * 5 + 0.01);
  final out = Float64List(n);
  final rnd = Noise(4);
  final oscs = [for (var j = 0; j < 6; j++) Osc(j * 0.17)];
  final hp = Svf(), lp = Svf();
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    var m = 0.0;
    for (var j = 0; j < 6; j++) {
      m += oscs[j].pulse(_metalFreqs[j] * 1.5, 0.5);
    }
    final v = metal * m / 6 + 0.6 * rnd.white();
    final y = lp.lowpass(hp.highpass(v, hpHz, 0.8), lpHz, 0.7);
    out[i] = y * _attack(t, 0.0005) * math.exp(-t / decay);
  }
  return fadeEdges(normalizePeak(out), inMs: 0, outMs: 5);
}

Float64List drumCrash({double decay = 0.6}) {
  final n = secs(decay * 3.5);
  final out = Float64List(n);
  final rnd = Noise(6);
  final oscs = [for (var j = 0; j < 6; j++) Osc(j * 0.21)];
  final hp = Svf(), lp = Svf(), bp = Svf();
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    var m = 0.0;
    for (var j = 0; j < 6; j++) {
      m += oscs[j].pulse(_metalFreqs[j] * 2.7, 0.5);
    }
    final w = rnd.white();
    final v = 0.4 * m / 6 + 0.7 * w + 0.4 * bp.bandpass(w, 6000, 2);
    final y = lp.lowpass(hp.highpass(v, 4000, 0.7), 13000, 0.7);
    out[i] =
        y *
        _attack(t, 0.001) *
        (0.6 * math.exp(-t / 0.05) + 0.5 * math.exp(-t / decay));
  }
  return fadeEdges(normalizePeak(out), inMs: 0, outMs: 50);
}

/// Noise riser: band-pass sweeping up with rising volume.
Float64List riser(double seconds) {
  final n = secs(seconds);
  final out = Float64List(n);
  final rnd = Noise(8);
  final bp = Svf();
  for (var i = 0; i < n; i++) {
    final p = i / n;
    final fc = 300 * math.pow(7000 / 300, math.pow(p, 1.5));
    out[i] = bp.bandpass(rnd.white(), fc.toDouble(), 2.0) * p * p;
  }
  return fadeEdges(normalizePeak(out), inMs: 5, outMs: 15);
}

// =============================================================================
// Sequencing helpers
// =============================================================================

class Seq {
  Seq(this.bpm, this.bars);
  final double bpm;
  final int bars;
  double get spb => sampleRate * 60.0 / bpm;
  double get secPerBeat => 60.0 / bpm;
  int get length => (bars * 4 * spb).round();
  int at(double beat) => (beat * spb).round();
}

class MelodyNote {
  MelodyNote(this.beat, this.len, this.midi);
  final double beat, len;
  final int midi;
}

/// Parses bars of `note/sixteenths` tokens (`r` for rest).
List<MelodyNote> parseMelody(List<String> bars, {int startBar = 0}) {
  final notes = <MelodyNote>[];
  for (var b = 0; b < bars.length; b++) {
    var pos = 0.0;
    for (final tok in bars[b].trim().split(RegExp(r'\s+'))) {
      final parts = tok.split('/');
      final d = double.parse(parts[1]);
      if (parts[0] != 'r') {
        notes.add(
          MelodyNote((startBar + b) * 4 + pos / 4, d / 4, noteNumber(parts[0])),
        );
      }
      pos += d;
    }
    if (pos != 16) {
      throw StateError('Bar ${b + 1} has $pos sixteenths: "${bars[b]}"');
    }
  }
  return notes;
}

/// Parses a 16-step bass line: R=root O=octave F=fifth, '-' sustains.
/// Returns (step, lengthInSteps, semitoneOffset).
List<(int, int, int)> parseStepLine(String pat) {
  final out = <(int, int, int)>[];
  for (var s = 0; s < pat.length; s++) {
    final c = pat[s];
    if (!'ROF'.contains(c)) continue;
    var len = 1;
    while (s + len < pat.length && pat[s + len] == '-') {
      len++;
    }
    out.add((
      s,
      len,
      switch (c) {
        'O' => 12,
        'F' => 7,
        _ => 0,
      },
    ));
  }
  return out;
}

/// Calls [hit] for every step of a 16-step drum pattern.
/// '.' = off, 'o' = soft, 'x' = normal, 'X' = accent.
void steps(
  String pat,
  int bar,
  void Function(double beat, double vel) hit, {
  double swing = 0,
}) {
  assert(pat.length == 16, 'pattern must have 16 steps: $pat');
  for (var s = 0; s < 16; s++) {
    final v = switch (pat[s]) {
      'X' => 1.0,
      'x' => 0.75,
      'o' => 0.45,
      _ => 0.0,
    };
    if (v == 0) continue;
    var beat = bar * 4 + s / 4;
    if (s.isOdd) beat += swing / 4;
    hit(beat, v);
  }
}

/// Adds a kick-triggered sidechain envelope into [duck] (circular).
void addDuck(Float64List duck, int at, double vel, double releaseSec) {
  final n = duck.length;
  final len = secs(releaseSec * 4);
  final atk = secs(0.004);
  for (var i = 0; i < len; i++) {
    final env = i < atk
        ? i / atk
        : math.exp(-(i - atk) / (releaseSec * sampleRate));
    final idx = (at + i) % n;
    final d = env * vel;
    if (d > duck[idx]) duck[idx] = d;
  }
}

int noteNumber(String s) {
  const base = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
  var n = base[s[0]]!;
  var i = 1;
  if (s[i] == '#') {
    n++;
    i++;
  } else if (s[i] == 'b') {
    n--;
    i++;
  }
  return 12 * (int.parse(s.substring(i)) + 1) + n;
}

int noteClass(String chord) {
  const base = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
  var n = base[chord[0]]!;
  if (chord.length > 1 && chord[1] == '#') n++;
  if (chord.length > 1 && chord[1] == 'b') n--;
  return n % 12;
}

/// Close triad voiced between F3 and A4 ("Am", "F", "C#", ...).
List<int> triad(String chord) {
  final pc = noteClass(chord);
  final minor = chord.endsWith('m');
  final root = 60 + pc - (pc >= 5 ? 12 : 0);
  return [root, root + (minor ? 3 : 4), root + 7];
}

// =============================================================================
// Mixing helpers
// =============================================================================

class Bus {
  Bus(int n) : l = Float64List(n), r = Float64List(n);
  final Float64List l, r;
  int get length => l.length;

  /// Adds a mono voice at sample [at]; wraps around the loop end so tails of
  /// the last notes continue at the start (seamless loop).
  void add(Float64List v, int at, {double gain = 1.0, double pan = 0.0}) {
    final a = (pan.clamp(-1.0, 1.0) + 1.0) * math.pi / 4;
    final gl = math.cos(a) * math.sqrt2 * gain;
    final gr = math.sin(a) * math.sqrt2 * gain;
    final n = l.length;
    var idx = at % n;
    for (var j = 0; j < v.length; j++) {
      l[idx] += v[j] * gl;
      r[idx] += v[j] * gr;
      if (++idx >= n) idx = 0;
    }
  }

  void addBus(Bus o, double gain) {
    for (var i = 0; i < l.length; i++) {
      l[i] += o.l[i] * gain;
      r[i] += o.r[i] * gain;
    }
  }

  void duck(Float64List env, double depth) {
    for (var i = 0; i < l.length; i++) {
      final g = 1 - depth * env[i];
      l[i] *= g;
      r[i] *= g;
    }
  }

  double rmsDb() {
    var s = 0.0;
    for (var i = 0; i < l.length; i++) {
      s += l[i] * l[i] + r[i] * r[i];
    }
    return gainToDb(math.sqrt(s / (2 * l.length)));
  }
}

/// Runs a stereo reverb over a loop circularly (warm-up pass + real pass),
/// so the reverb tail of the loop end rings into the loop start.
Bus reverbBus(
  Bus send, {
  double room = 0.8,
  double damp = 0.3,
  double hpHz = 200,
}) {
  final n = send.length;
  final out = Bus(n);
  final rev = Reverb(room: room, damp: damp);
  final hpL = Svf(), hpR = Svf();
  for (var pass = 0; pass < 2; pass++) {
    for (var i = 0; i < n; i++) {
      rev.process(
        hpL.highpass(send.l[i], hpHz, 0.7),
        hpR.highpass(send.r[i], hpHz, 0.7),
      );
      if (pass == 1) {
        out.l[i] = rev.outL;
        out.r[i] = rev.outR;
      }
    }
  }
  return out;
}

/// Sums buses, applies optional low-pass/saturation, DC removal, loudness
/// gain, a circular look-ahead limiter and peak normalization.
List<Float64List> masterBus(
  Map<String, (Bus, double)> buses,
  int n, {
  required double targetRmsDb,
  double? lowpassHz,
  double saturate = 0,
}) {
  final l = Float64List(n), r = Float64List(n);
  print('  bus levels (RMS, after bus gain):');
  for (final e in buses.entries) {
    final (bus, g) = e.value;
    print(
      '    ${e.key.padRight(8)} ${(bus.rmsDb() + gainToDb(g)).toStringAsFixed(1)} dB',
    );
    for (var i = 0; i < n; i++) {
      l[i] += bus.l[i] * g;
      r[i] += bus.r[i] * g;
    }
  }
  final dcL = DcBlock(25), dcR = DcBlock(25);
  final lpL = Svf(), lpR = Svf();
  var outL = circular(n, (i) {
    final v = dcL.process(l[i]);
    return lowpassHz == null ? v : lpL.lowpass(v, lowpassHz, 0.7);
  });
  var outR = circular(n, (i) {
    final v = dcR.process(r[i]);
    return lowpassHz == null ? v : lpR.lowpass(v, lowpassHz, 0.7);
  });
  if (saturate > 0) {
    final p = peakOf([outL, outR]);
    final norm = _tanh(saturate);
    for (var i = 0; i < n; i++) {
      outL[i] = _tanh(saturate * outL[i] / p) / norm * p;
      outR[i] = _tanh(saturate * outR[i] / p) / norm * p;
    }
  }
  // Loudness: bring RMS to target, then limit peaks to the ceiling.
  final rms = rmsOf([outL, outR]);
  final g = dbToGain(targetRmsDb) / rms;
  for (var i = 0; i < n; i++) {
    outL[i] *= g;
    outR[i] *= g;
  }
  final gr = limit([outL, outR], ceilingDb: peakDb - 0.1, circularLoop: true);
  print('  limiter max gain reduction: ${gr.toStringAsFixed(2)} dB');
  normalizePeak2([outL, outR], peakDb);
  return [outL, outR];
}

// =============================================================================
// DSP primitives
// =============================================================================

const double _twoPi = 2 * math.pi;

double mtof(num midi) => 440.0 * math.pow(2.0, (midi - 69) / 12.0);
double dbToGain(num db) => math.pow(10.0, db / 20.0).toDouble();
double gainToDb(num g) => g <= 0 ? -200.0 : 20 * math.log(g) / math.ln10;
int secs(num s) => (s * sampleRate).round();
double clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);
double _attack(double t, double a) => a <= 0 || t >= a ? 1.0 : t / a;

double _tanh(double x) {
  if (x > 20) return 1;
  if (x < -20) return -1;
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}

/// Gaussian bump on a log-frequency axis (width in octaves).
double _bell(double f, double center, double widthOct) {
  final d = math.log(f / center) / math.ln2 / widthOct;
  return math.exp(-d * d);
}

/// ADSR: linear attack, exponential decay to sustain, smooth release.
double adsr(double t, double gate, double a, double d, double s, double r) {
  double held(double t) {
    if (t <= 0) return 0;
    if (t < a) return t / a;
    return s + (1 - s) * math.exp(-(t - a) * 4.6 / d);
  }

  if (t < gate) return held(t);
  final x = (t - gate) / r;
  if (x >= 1) return 0;
  return held(gate) * math.exp(-3.0 * x) * (1 - x);
}

/// PolyBLEP residual for band-limited discontinuities.
double polyBlep(double t, double dt) {
  if (t < dt) {
    final x = t / dt;
    return x + x - x * x - 1.0;
  }
  if (t > 1.0 - dt) {
    final x = (t - 1.0) / dt;
    return x * x + x + x + 1.0;
  }
  return 0.0;
}

/// Phase-accumulator oscillator with polyBLEP saw and pulse.
class Osc {
  Osc([this.phase = 0.0]);
  double phase;

  void _advance(double dt) {
    phase += dt;
    if (phase >= 1.0) phase -= phase.floorToDouble();
  }

  double sine(double freq) {
    final v = math.sin(_twoPi * phase);
    _advance(freq / sampleRate);
    return v;
  }

  double saw(double freq) {
    final dt = freq / sampleRate;
    final v = 2.0 * phase - 1.0 - polyBlep(phase, dt);
    _advance(dt);
    return v;
  }

  /// Band-limited pulse, DC-free for any duty cycle.
  double pulse(double freq, [double duty = 0.5]) {
    final dt = freq / sampleRate;
    var v = phase < duty ? 1.0 : -1.0;
    v += polyBlep(phase, dt);
    var p2 = phase - duty;
    if (p2 < 0) p2 += 1.0;
    v -= polyBlep(p2, dt);
    _advance(dt);
    return v - (2 * duty - 1);
  }

  /// Triangle (harmonics fall off at 12 dB/oct, aliasing is negligible).
  double tri(double freq) {
    final v = 4.0 * (phase - 0.5).abs() - 1.0;
    _advance(freq / sampleRate);
    return v;
  }
}

/// Seeded noise source (white + Paul Kellet's economy pink).
class Noise {
  Noise(int seed) : _r = math.Random(seed);
  final math.Random _r;
  double _b0 = 0, _b1 = 0, _b2 = 0;

  double next() => _r.nextDouble();
  double white() => _r.nextDouble() * 2.0 - 1.0;
  double range(double a, double b) => a + (b - a) * _r.nextDouble();
  int intRange(int a, int b) => a + _r.nextInt(b - a);

  double pink() {
    final w = white();
    _b0 = 0.99765 * _b0 + w * 0.0990460;
    _b1 = 0.96300 * _b1 + w * 0.2965164;
    _b2 = 0.57000 * _b2 + w * 1.0526913;
    return (_b0 + _b1 + _b2 + w * 0.1848) * 0.25;
  }
}

/// Zero-delay-feedback state-variable filter (Simper/Cytomic). Stable under
/// fast cutoff modulation.
class Svf {
  double _ic1 = 0, _ic2 = 0;
  double _f = -1, _q = -1;
  double _k = 1, _a1 = 0, _a2 = 0, _a3 = 0;

  void _set(double fc, double q) {
    if (fc == _f && q == _q) return;
    _f = fc;
    _q = q;
    final f = fc.clamp(10.0, sampleRate * 0.45);
    final g = math.tan(math.pi * f / sampleRate);
    _k = 1 / q;
    _a1 = 1 / (1 + g * (g + _k));
    _a2 = g * _a1;
    _a3 = g * _a2;
  }

  /// Returns (low, band, high).
  (double, double, double) _tick(double v0) {
    final v3 = v0 - _ic2;
    final v1 = _a1 * _ic1 + _a2 * v3;
    final v2 = _ic2 + _a2 * _ic1 + _a3 * v3;
    _ic1 = 2 * v1 - _ic1;
    _ic2 = 2 * v2 - _ic2;
    return (v2, v1, v0 - _k * v1 - v2);
  }

  double lowpass(double x, double fc, [double q = 0.7071]) {
    _set(fc, q);
    return _tick(x).$1;
  }

  /// Band-pass normalized to unity gain at the centre frequency.
  double bandpass(double x, double fc, [double q = 1.0]) {
    _set(fc, q);
    return _tick(x).$2 * _k;
  }

  double highpass(double x, double fc, [double q = 0.7071]) {
    _set(fc, q);
    return _tick(x).$3;
  }
}

class DcBlock {
  DcBlock([double hz = 20]) : _r = math.exp(-_twoPi * hz / sampleRate);
  final double _r;
  double _x1 = 0, _y1 = 0;
  double process(double x) {
    final y = x - _x1 + _r * _y1;
    _x1 = x;
    _y1 = y;
    return y;
  }
}

/// Mono feedback delay with a low-pass in the loop.
class FeedbackDelay {
  FeedbackDelay(double seconds, this.feedback, {this.lpHz = 5000})
    : _buf = Float64List(math.max(1, secs(seconds)));
  final Float64List _buf;
  final double feedback, lpHz;
  final Svf _lp = Svf();
  int _i = 0;

  double process(double x) {
    final d = _buf[_i];
    _buf[_i] = x + _lp.lowpass(d, lpHz) * feedback;
    if (++_i >= _buf.length) _i = 0;
    return d;
  }
}

/// Stereo ping-pong delay (mono in).
class PingPong {
  PingPong(int samples, this.feedback, {this.lpHz = 5000})
    : _l = Float64List(samples),
      _r = Float64List(samples);
  final Float64List _l, _r;
  final double feedback, lpHz;
  final Svf _lpL = Svf(), _lpR = Svf();
  int _i = 0;
  double outL = 0, outR = 0;

  void process(double x) {
    final dl = _l[_i], dr = _r[_i];
    _l[_i] = x + _lpR.lowpass(dr, lpHz) * feedback;
    _r[_i] = _lpL.lowpass(dl, lpHz);
    outL = dl;
    outR = dr;
    if (++_i >= _l.length) _i = 0;
  }
}

class _Comb {
  _Comb(int len, this.feedback, this.damp) : _buf = Float64List(len);
  final Float64List _buf;
  final double feedback, damp;
  int _i = 0;
  double _store = 0;

  double process(double x) {
    final y = _buf[_i];
    _store = y * (1 - damp) + _store * damp;
    _buf[_i] = x + _store * feedback;
    if (++_i >= _buf.length) _i = 0;
    return y;
  }
}

class _Allpass {
  _Allpass(int len) : _buf = Float64List(len);
  final Float64List _buf;
  int _i = 0;

  double process(double x) {
    final b = _buf[_i];
    _buf[_i] = x + b * 0.5;
    if (++_i >= _buf.length) _i = 0;
    return b - x;
  }
}

/// Freeverb-style stereo reverb.
class Reverb {
  Reverb({
    double room = 0.8,
    double damp = 0.3,
    double size = 1.0,
    this.width = 1.0,
  }) {
    final fb = 0.7 + 0.28 * room;
    int len(int base) => math.max(1, (base * size).round());
    _cl = [for (final c in _combs) _Comb(len(c), fb, damp)];
    _cr = [for (final c in _combs) _Comb(len(c + 23), fb, damp)];
    _al = [for (final a in _aps) _Allpass(len(a))];
    _ar = [for (final a in _aps) _Allpass(len(a + 23))];
  }

  static const _combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
  static const _aps = [556, 441, 341, 225];
  final double width;
  late final List<_Comb> _cl, _cr;
  late final List<_Allpass> _al, _ar;
  double outL = 0, outR = 0;

  void process(double inL, double inR) {
    final input = (inL + inR) * 0.015;
    var l = 0.0, r = 0.0;
    for (final c in _cl) {
      l += c.process(input);
    }
    for (final c in _cr) {
      r += c.process(input);
    }
    for (final a in _al) {
      l = a.process(l);
    }
    for (final a in _ar) {
      r = a.process(r);
    }
    final w1 = width / 2 + 0.5, w2 = (1 - width) / 2;
    outL = (l * w1 + r * w2) * 3;
    outR = (r * w1 + l * w2) * 3;
  }
}

/// Adds a small mono room to a one-shot (the buffer is extended for the tail
/// only if it fits; one-shots are sized to include the tail).
Float64List applyRoom(
  Float64List x, {
  double wet = 0.2,
  double size = 0.6,
  double room = 0.6,
}) {
  final rev = Reverb(room: room, damp: 0.4, size: size);
  final out = Float64List(x.length);
  final hp = Svf();
  for (var i = 0; i < x.length; i++) {
    rev.process(hp.highpass(x[i], 300, 0.7), 0);
    out[i] = x[i] + wet * 0.5 * (rev.outL + rev.outR);
  }
  return out;
}

/// Runs a stateful per-sample generator twice over a loop and keeps the
/// second pass, so filters/delays reach their periodic steady state and the
/// output loops seamlessly (given a periodic input).
Float64List circular(int n, double Function(int i) f) {
  for (var i = 0; i < n; i++) {
    f(i);
  }
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = f(i);
  }
  return out;
}

/// Integrates an instantaneous frequency (Hz) into phase (cycles), nudged so
/// the total over the buffer is an exact integer number of cycles.
Float64List closedPhase(Float64List freqs) {
  final n = freqs.length;
  final ph = Float64List(n);
  var acc = 0.0;
  for (var i = 0; i < n; i++) {
    ph[i] = acc;
    acc += freqs[i] / sampleRate;
  }
  final err = acc.roundToDouble() - acc;
  for (var i = 0; i < n; i++) {
    ph[i] += err * i / n;
  }
  return ph;
}

/// Mixes [src] into [dst] starting at [startSec].
void _mix(Float64List dst, Float64List src, double startSec, double gain) {
  final at = secs(startSec);
  for (var j = 0; j < src.length && at + j < dst.length; j++) {
    dst[at + j] += src[j] * gain;
  }
}

double peakOf(List<Float64List> ch) {
  var p = 0.0;
  for (final c in ch) {
    for (final v in c) {
      final a = v.abs();
      if (a > p) p = a;
    }
  }
  return p;
}

double rmsOf(List<Float64List> ch) {
  var s = 0.0;
  var n = 0;
  for (final c in ch) {
    for (final v in c) {
      s += v * v;
    }
    n += c.length;
  }
  return math.sqrt(s / n);
}

/// Scales in place so the peak is at [db] dBFS (default 0 dBFS = 1.0).
Float64List normalizePeak(Float64List x, [double db = 0]) {
  final p = peakOf([x]);
  if (p == 0) return x;
  final g = dbToGain(db) / p;
  for (var i = 0; i < x.length; i++) {
    x[i] *= g;
  }
  return x;
}

void normalizePeak2(List<Float64List> ch, double db) {
  final p = peakOf(ch);
  final g = dbToGain(db) / p;
  for (final c in ch) {
    for (var i = 0; i < c.length; i++) {
      c[i] *= g;
    }
  }
}

/// Raised-cosine fades to avoid clicks.
Float64List fadeEdges(Float64List x, {double inMs = 1.0, double outMs = 20}) {
  final ni = math.min(secs(inMs / 1000), x.length);
  final no = math.min(secs(outMs / 1000), x.length);
  for (var i = 0; i < ni; i++) {
    x[i] *= 0.5 - 0.5 * math.cos(math.pi * i / ni);
  }
  for (var i = 0; i < no; i++) {
    x[x.length - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / no);
  }
  return x;
}

/// DC removal, edge fades and normalization for one-shot effects.
Float64List finishOneShot(
  Float64List x, {
  double fadeInMs = 1.0,
  double fadeOutMs = 20,
}) {
  final dc = DcBlock(15);
  for (var i = 0; i < x.length; i++) {
    x[i] = dc.process(x[i]);
  }
  fadeEdges(x, inMs: fadeInMs, outMs: fadeOutMs);
  return normalizePeak(x, peakDb);
}

/// Look-ahead peak limiter (in place). With [circularLoop] the gain curve
/// wraps around so the loop stays seamless. Returns max gain reduction (dB).
double limit(
  List<Float64List> ch, {
  double ceilingDb = -1.0,
  double lookaheadMs = 2.0,
  double releaseMs = 120,
  bool circularLoop = false,
}) {
  final n = ch[0].length;
  final ceil = dbToGain(ceilingDb);
  final la = math.max(1, secs(lookaheadMs / 1000));
  int wrap(int i) => circularLoop ? i % n : i.clamp(0, n - 1);

  // Windowed minimum of the required gain over [i - la, i + la].
  final m = Float64List(n)..fillRange(0, n, 1.0);
  var minGain = 1.0;
  for (var i = 0; i < n; i++) {
    var p = 0.0;
    for (final c in ch) {
      final a = c[i].abs();
      if (a > p) p = a;
    }
    if (p <= ceil) continue;
    final req = ceil / p;
    if (req < minGain) minGain = req;
    for (var k = i - la; k <= i + la; k++) {
      final j = wrap(k);
      if (req < m[j]) m[j] = req;
    }
  }
  if (minGain >= 1.0) return 0;

  // Instant attack (already looking ahead), exponential release.
  final rel = math.exp(-1 / (releaseMs / 1000 * sampleRate));
  final r = Float64List(n);
  var g = 1.0;
  for (var pass = 0; pass < (circularLoop ? 2 : 1); pass++) {
    for (var i = 0; i < n; i++) {
      final target = m[i];
      g = target < g ? target : target + (g - target) * rel;
      r[i] = g;
    }
  }

  // Smooth with a centred box filter (stays below the required gain).
  final w = 2 * la + 1;
  var sum = 0.0;
  for (var k = -la; k <= la; k++) {
    sum += r[wrap(k)];
  }
  for (var i = 0; i < n; i++) {
    final gain = sum / w;
    for (final c in ch) {
      c[i] *= gain;
    }
    sum += r[wrap(i + la + 1)] - r[wrap(i - la)];
  }
  return -gainToDb(minGain);
}

// =============================================================================
// File I/O and verification
// =============================================================================

void writeWav(String path, List<Float64List> channels) {
  final n = channels[0].length;
  final nc = channels.length;
  final dataBytes = n * nc * 2;
  final b = ByteData(44 + dataBytes);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + dataBytes, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, nc, Endian.little);
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * nc * 2, Endian.little);
  b.setUint16(32, nc * 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, dataBytes, Endian.little);
  var o = 44;
  for (var i = 0; i < n; i++) {
    for (var c = 0; c < nc; c++) {
      final v = (channels[c][i] * 32767).round().clamp(-32768, 32767);
      b.setInt16(o, v, Endian.little);
      o += 2;
    }
  }
  File(path).writeAsBytesSync(b.buffer.asUint8List());
}

Future<void> encodeVorbis(String wavPath, String oggPath) async {
  final res = await Process.run(ffmpegPath, [
    '-y',
    '-hide_banner',
    '-loglevel',
    'error',
    '-i',
    wavPath,
    '-c:a',
    'libvorbis',
    '-q:a',
    '$vorbisQuality',
    oggPath,
  ]);
  if (res.exitCode != 0) {
    throw ProcessException(ffmpegPath, [], '${res.stderr}', res.exitCode);
  }
}

Future<List<Float64List>> decodeToPcm(String path, {int channels = 2}) async {
  final res = await Process.run(
    ffmpegPath,
    [
      '-hide_banner',
      '-loglevel',
      'error',
      '-i',
      path,
      '-f',
      's16le',
      '-ac',
      '$channels',
      '-ar',
      '$sampleRate',
      '-',
    ],
    stdoutEncoding: null,
  );
  if (res.exitCode != 0) {
    throw ProcessException(ffmpegPath, [], '${res.stderr}', res.exitCode);
  }
  final bytes = Uint8List.fromList(res.stdout as List<int>);
  final bd = ByteData.sublistView(bytes);
  final frames = bytes.length ~/ (2 * channels);
  final out = [for (var c = 0; c < channels; c++) Float64List(frames)];
  for (var i = 0; i < frames; i++) {
    for (var c = 0; c < channels; c++) {
      out[c][i] = bd.getInt16((i * channels + c) * 2, Endian.little) / 32768.0;
    }
  }
  return out;
}

/// Prints duration, peak, RMS, edge levels and (for loops) seam continuity.
void printStats(List<Float64List> ch, {bool loop = false}) {
  final n = ch[0].length;
  final peak = peakOf(ch);
  print(
    '  ${(n / sampleRate).toStringAsFixed(3)} s ($n frames, ${ch.length} ch), '
    'peak ${gainToDb(peak).toStringAsFixed(2)} dBFS, '
    'RMS ${gainToDb(rmsOf(ch)).toStringAsFixed(1)} dBFS',
  );
  if (!loop) {
    final first = ch.map((c) => c.first.abs()).reduce(math.max);
    final last = ch.map((c) => c.last.abs()).reduce(math.max);
    print(
      '  edges: first |s| ${first.toStringAsFixed(5)}, '
      'last |s| ${last.toStringAsFixed(5)}',
    );
    return;
  }
  for (var c = 0; c < ch.length; c++) {
    final x = ch[c];
    // Distribution of first and second differences inside the file.
    final d1 = Float64List(n - 1);
    final d2 = Float64List(n - 2);
    for (var i = 0; i < n - 1; i++) {
      d1[i] = (x[i + 1] - x[i]).abs();
    }
    for (var i = 0; i < n - 2; i++) {
      d2[i] = (x[i + 2] - 2 * x[i + 1] + x[i]).abs();
    }
    final seam1 = (x[0] - x[n - 1]).abs();
    final seam2 = (x[0] - 2 * x[n - 1] + x[n - 2]).abs();
    final seam2b = (x[1] - 2 * x[0] + x[n - 1]).abs();
    final curv = math.max(seam2, seam2b);
    // Rank of the seam step among all steps inside the file: a click would
    // sit far above every in-file step (rank 100%, beyond the max).
    final rank1 = _rank(d1, seam1), rank2 = _rank(d2, curv);
    final maxd1 = _percentile(d1, 1.0), maxd2 = _percentile(d2, 1.0);
    final ok =
        seam1 <= _percentile(d1, 0.999) && curv <= _percentile(d2, 0.999);
    print(
      '  loop seam ch$c: step ${seam1.toStringAsFixed(5)} '
      '(${(rank1 * 100).toStringAsFixed(1)}th pct, in-file max ${maxd1.toStringAsFixed(5)}), '
      'curvature ${curv.toStringAsFixed(5)} '
      '(${(rank2 * 100).toStringAsFixed(1)}th pct, max ${maxd2.toStringAsFixed(5)}) '
      '-> ${ok ? 'SEAMLESS' : 'CHECK'}',
    );
  }
}

double _rank(Float64List v, double x) {
  var below = 0;
  for (final e in v) {
    if (e < x) below++;
  }
  return below / v.length;
}

double _percentile(Float64List v, double q) {
  final s = Float64List.fromList(v)..sort();
  return s[((s.length - 1) * q).round()];
}
