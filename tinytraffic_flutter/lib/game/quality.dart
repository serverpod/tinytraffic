import 'package:flutter_watchos/flutter_watchos.dart';

/// Rendering quality knobs. The game always draws with the fast settings
/// the Apple Watch needs ([lite]); URL query parameters override the rest on
/// the web for tuning, e.g. `?scale=0.6&shadows=0&aa=none&fps=1`.
/// (`?car=van` pins the player's car, see `GameController`.)
class Quality {
  /// Fraction of the device resolution to render at (null: automatic).
  double? renderScale;

  /// Soft round shadows under cars and trees.
  bool shadows;
  bool bloom;
  bool fog;

  /// 'auto', 'none', 'fxaa', 'msaa' or 'smaa'.
  String antiAliasing;

  /// Let the engine lower the resolution when frames run late.
  bool adaptive;

  /// Show a frame rate counter.
  bool showFps;

  /// The fast graphics, always on (they fit the Apple Watch's memory and
  /// power budget, see flutter-watchos's doc/memory.md): no MSAA, bloom,
  /// vignette, glass reflections or explosion light, a third of the
  /// particles and no buildings behind the front row.
  final bool lite = true;

  /// Running on the Apple Watch: its GPU can't hold 60 frames a second, so
  /// the renderer aims for 30 and keeps the resolution up instead.
  final bool watch = FlutterWatchosPlatform.isWatch;

  /// Let the autopilot drive (for testing). Such runs are never ranked.
  bool bot;

  Quality({
    this.renderScale,
    this.shadows = true,
    this.bloom = false,
    this.fog = true,
    this.antiAliasing = 'fxaa',
    this.adaptive = true,
    this.showFps = false,
    this.bot = false,
  });

  factory Quality.fromUrl() {
    final q = Quality();
    Map<String, String> p;
    try {
      p = Uri.base.queryParameters;
    } catch (_) {
      p = const {};
    }
    bool flag(String key, bool fallback) {
      final v = p[key];
      if (v == null) return fallback;
      return v == '1' || v == 'true' || v == 'on';
    }

    q.renderScale = double.tryParse(p['scale'] ?? '');
    q.shadows = flag('shadows', q.shadows);
    q.bloom = flag('bloom', q.bloom);
    q.fog = flag('fog', q.fog);
    q.adaptive = flag('adaptive', q.adaptive);
    q.showFps = flag('fps', q.showFps);
    q.bot = flag('bot', q.bot);
    q.antiAliasing = p['aa'] ?? q.antiAliasing;
    return q;
  }
}
