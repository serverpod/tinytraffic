import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

/// The light of a time of day: sun, sky, fog, exposure, and how brightly
/// windows, street lamps and car lights glow. The game is always played in
/// [TimeOfDay.day].
///
/// Colours are linear RGB. Directions are in engine space, where the road
/// mostly heads toward +z (away from the camera).
class TimeOfDay {
  final String name;

  /// Elevation of the sun (or moon) above the horizon and its bearing, in
  /// degrees. Bearing 0 is straight ahead (+z), positive turns toward +x.
  final double sunElevation, sunBearing;
  final vm.Vector3 sunColor;
  final double sunIntensity;

  /// How large and bright the disc is drawn in the sky (0 hides it).
  final double sunDisc;

  final vm.Vector3 zenith, horizon, ground;

  /// Fog matches the horizon unless given.
  final vm.Vector3? fogColor;
  final double fogStart, fogEnd;

  final double exposure;

  /// Scales the light the scene takes from the sky (ambient and reflections).
  final double ambient;
  final double saturation, contrast, temperature;
  final double bloomThreshold, bloomIntensity;
  final double vignette;

  /// 0..1: lit windows and street lamps in the buildings.
  final double windowGlow;

  /// 0..1: how strongly car lamps glow.
  final double carGlow;

  /// Opacity of the soft shadows under cars and trees.
  final double shadow;

  const TimeOfDay({
    required this.name,
    required this.sunElevation,
    required this.sunBearing,
    required this.sunColor,
    required this.sunIntensity,
    this.sunDisc = 1,
    required this.zenith,
    required this.horizon,
    required this.ground,
    this.fogColor,
    this.fogStart = 70,
    this.fogEnd = 190,
    this.exposure = 1.0,
    this.ambient = 1.0,
    this.saturation = 1.15,
    this.contrast = 1.08,
    this.temperature = 0,
    this.bloomThreshold = 0.95,
    this.bloomIntensity = 0.22,
    this.vignette = 0.28,
    this.windowGlow = 0,
    this.carGlow = 0.25,
    this.shadow = 0.5,
  });

  /// Direction toward the sun.
  vm.Vector3 get towardSun {
    final e = sunElevation * vm.degrees2Radians;
    final b = sunBearing * vm.degrees2Radians;
    return vm.Vector3(
      math.cos(e) * math.sin(b),
      math.sin(e),
      math.cos(e) * math.cos(b),
    )..normalize();
  }

  /// A bright summer day, the only light the game is played in: easy to
  /// read, and cheap to draw (no glowing windows to bloom).
  static final day = TimeOfDay(
    name: 'day',
    sunElevation: 52,
    sunBearing: 140,
    sunColor: vm.Vector3(1.0, 0.95, 0.86),
    sunIntensity: 3.4,
    zenith: vm.Vector3(0.03, 0.17, 0.78),
    horizon: vm.Vector3(0.2, 0.45, 0.95),
    ground: vm.Vector3(0.45, 0.55, 0.42),
    fogColor: vm.Vector3(0.25, 0.48, 0.92),
    fogStart: 80,
    fogEnd: 220,
    exposure: 1.0,
    ambient: 0.8,
    saturation: 1.22,
    contrast: 1.1,
    temperature: 0.03,
    carGlow: 0.2,
    shadow: 0.55,
  );
}

/// Toy-box car paints, picked at random for every car.
final List<vm.Vector3> carPaints = [
  _srgb(0xE63B2E), // cherry
  _srgb(0xF2762E), // tangerine
  _srgb(0xF5C02C), // sunflower
  _srgb(0x7BC74D), // apple
  _srgb(0x2E9E6B), // jade
  _srgb(0x2BB3B1), // teal
  _srgb(0x3D8BEB), // sky
  _srgb(0x2846C8), // cobalt
  _srgb(0x7A4FD1), // grape
  _srgb(0xEE6FA8), // bubblegum
  _srgb(0xF1EDE4), // cream
  _srgb(0x3A3F4B), // graphite
  _srgb(0x8C2B3A), // wine
  _srgb(0xA9C9E8), // powder blue
];

/// Facade colours for repainting buildings.
final List<vm.Vector3> facadePaints = [
  _srgb(0xE8735A), // coral
  _srgb(0x84CDB0), // mint
  _srgb(0xF2CC6B), // butter
  _srgb(0x8EB8E5), // sky
  _srgb(0xB49ADB), // lilac
  _srgb(0xEE9DB4), // pink
  _srgb(0xB5553A), // terracotta
  _srgb(0xA6BF8C), // sage
  _srgb(0xF4B183), // peach
  _srgb(0x3F8C8A), // teal
  _srgb(0x9C3B2E), // brick
  _srgb(0xEFE3C8), // cream
  _srgb(0x5D6E9E), // slate blue
  _srgb(0xD9A441), // ochre
];

/// Leaf colours: summer greens, plus one autumn shade used now and then.
final List<vm.Vector3> leafPaints = [
  _srgb(0x6FAE3E), // spring
  _srgb(0x2F7A3A), // deep
  _srgb(0x8FB84A), // lime
];
final vm.Vector3 autumnLeaves = _srgb(0xD9822B);

vm.Vector3 _srgb(int hex) {
  double c(int v) {
    final x = v / 255;
    return x <= 0.04045
        ? x / 12.92
        : math.pow((x + 0.055) / 1.055, 2.4).toDouble();
  }

  return vm.Vector3(
    c((hex >> 16) & 0xff),
    c((hex >> 8) & 0xff),
    c(hex & 0xff),
  );
}
