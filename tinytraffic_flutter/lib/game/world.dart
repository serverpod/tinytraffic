import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter_scene/scene.dart';
import 'package:tinytraffic_game/tinytraffic_game.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'assets.dart';
import 'car_view.dart';
import 'city.dart';
import 'fx.dart';
import 'look.dart';
import 'quality.dart';
import 'reflections.dart';
import 'tumble.dart';

/// Height of the asphalt's top face (the kerbs are at 0).
const double kRoadY = -0.03;

// The simulation's map has x pointing east and z south. flutter_scene's
// world is left-handed, so seen from behind a car heading +z, +x is on the
// right of the screen, not the left. Showing the map with x mirrored keeps
// the simulation's left and right where the player sees them.

/// Engine x for a simulation x.
double ex(double simX) => -simX;

/// Yaw that turns an imported model to face the simulation heading
/// (hx, hz). Imported glTF models face -z in flutter_scene.
double yawFor(double hx, double hz) => math.atan2(hx, -hz);

/// Renders a [GameSimulation]: keeps the 3D world in step with it, and owns
/// the camera and all purely visual effects.
class GameWorld {
  final GameAssets assets;
  final Scene scene = Scene();
  final PerspectiveCamera camera = PerspectiveCamera(
    fovRadiansY: 55 * vm.degrees2Radians,
    fovFar: 420,
  );

  GameWorld(this.assets);

  final Quality quality = Quality.fromUrl();

  late final Node _ground;

  /// The player's car for the current run.
  late CarView player;
  late final ParticlePool smoke;
  late final ParticlePool sparkles;
  late final ParticlePool sparks;
  late final ParticlePool fire;

  /// The burnt-out player car shown after the explosion.
  late CarView _wreck;
  late final Node _shockwave;
  late final UnlitMaterial _shockwaveMaterial;
  late final PointLight _blastLight;
  late final Node _blastLightNode;
  late final SkidMarks skids;
  late final Material _charred;

  // Soft shadows under cars and trees.
  final Geometry _quad = PlaneGeometry(width: 1, depth: 1);
  late final UnlitMaterial _shadowMaterial;

  late final GradientSkySource _sky;

  /// What car and building glass reflect, built once while loading (see
  /// [prepareReflections]). The watch goes without: they take memory.
  (EnvironmentMap, EnvironmentMap)? _reflections;
  Future<void>? _preparing;

  /// The light the game is played in.
  final TimeOfDay look = TimeOfDay.day;

  /// Called when the player's car lifts onto two wheels in a corner.
  void Function()? onLift;

  /// Where the HUD shows each running power-up: the centre in normalized
  /// device coordinates (x right, y up, -1..1) and the height as a fraction
  /// of the view's. The model spins there (see [_poseBadges]).
  final Map<PowerUp, (double, double, double)> badgeSlots = {};
  final Map<PowerUp, Node> _badges = {};

  GameSimulation? _sim;
  CityPlanner? _city;

  final Map<String, List<Node>> _free = {};
  final Map<int, Node> _roadNodes = {};
  final List<(CellDressing, List<Node>)> _dressing = [];
  final Map<int, Node> _coinNodes = {};
  final Map<int, (CarView, String)> _trafficViews = {};
  final Map<int, Node> _obstacleNodes = {};

  /// How high each coin has hopped to clear traffic passing under it.
  final Map<int, double> _coinLift = {};

  /// How high a coin has to hop to clear each kind of traffic (m).
  static const Map<TrafficModel, double> _heights = {
    TrafficModel.hatchback: 1.95,
    TrafficModel.sedan: 1.85,
    TrafficModel.suv: 2.1,
    TrafficModel.pickup: 2.0,
    TrafficModel.bus: 3.35,
    TrafficModel.barrier: 1.8,
    TrafficModel.cone: 2.3,
  };
  final List<_PoppingCoin> _popping = [];

  /// Viewport aspect ratio (width / height) and shortest side, for framing.
  double aspect = 16 / 9;
  double shortestSide = 800;

  double _time = 0;

  // Camera state.
  final vm.Vector3 _camFwd = vm.Vector3(0, 0, 1);
  final vm.Vector3 _camPos = vm.Vector3(0, 6, -10);
  final vm.Vector3 _camTarget = vm.Vector3.zero();
  double _trauma = 0;
  double _fovKick = 0;

  /// 0 while driving, rising to 1 on the title screen for a wider, slowly
  /// orbiting shot.
  double attractBlend = 0;

  // Crash tumble (cosmetic).
  CrashTumble? _tumble;

  Future<void> setUp() async {
    await _setUpLook();

    // Endless grass, following the camera.
    final grass =
        PhysicallyBasedMaterial(
            baseColorTexture: await _grassTexture(),
          )
          ..roughnessFactor = 1
          ..metallicFactor = 0
          ..depthLayer = -1
          ..baseColorTextureTransform = TextureTransform(
            scale: vm.Vector2.all(_groundSize / 24),
          );
    _ground = Node(
      name: 'ground',
      mesh: Mesh(
        PlaneGeometry(width: _groundSize, depth: _groundSize),
        grass,
      ),
    )..shadowCastingMode = ShadowCastingMode.off;
    // Below the asphalt from the first frame on (see [update]).
    _ground.position = vm.Vector3(0, -0.06, 0);
    scene.add(_ground);

    final dot = await softDotTexture();
    _shadowMaterial =
        UnlitMaterial(colorTexture: await softDotTexture(size: 32))
          ..baseColorFactor = vm.Vector4(0, 0, 0, 0.5)
          ..alphaMode = AlphaMode.blend
          ..depthLayer = 1;
    _charred = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.035, 0.032, 0.03, 1)
      ..metallicFactor = 0.2
      ..roughnessFactor = 0.95;
    player = _playerView(GameAssets.cars.first, 0);
    _wreck = _wreckView(GameAssets.cars.first);

    // Coins glow a little (see [applyLook]). Without glass reflections
    // (the fast graphics) a mirror-like metal would look dull, so they are
    // only half metal and lit from within.
    for (final n in assets.template('pickup_coin').meshNodes) {
      for (final p in n.mesh!.primitives) {
        final m = p.material;
        if (m is PhysicallyBasedMaterial) {
          m.baseColorFactor = vm.Vector4(1.0, 0.7, 0.12, 1);
          m.emissiveFactor = vm.Vector4(1.0, 0.62, 0.1, 1);
          m.metallicFactor = quality.lite ? 0.35 : 1;
          m.roughnessFactor = quality.lite ? 0.3 : 0.12;
          _coinMaterials.add(m);
        }
      }
    }

    // The power-ups' models, spinning in the HUD while they last.
    for (final p in PowerUp.values) {
      final n = Node(name: 'badge')
        ..add(assets.instance(_powerModel(p)))
        ..visible = false;
      _badges[p] = n;
      scene.add(n);
    }

    // The watch has little memory and time to spare: far fewer particles.
    final n = quality.lite ? 0.3 : 1.0;
    final star = await sparkleTexture();
    smoke = ParticlePool(capacity: (400 * n).round(), texture: dot);
    sparkles = ParticlePool(
      capacity: (300 * n).round(),
      texture: star,
      additive: true,
    );
    sparks = ParticlePool(
      capacity: (300 * n).round(),
      texture: dot,
      additive: true,
      facing: BillboardFacing.velocityStretched,
    );
    fire = ParticlePool(
      capacity: (360 * n).round(),
      texture: dot,
      additive: true,
    );
    skids = SkidMarks();
    scene.add(skids.node);
    scene.add(smoke.node);
    scene.add(sparkles.node);
    scene.add(sparks.node);
    scene.add(fire.node);

    // Explosion pieces, hidden until needed.
    _shockwaveMaterial = UnlitMaterial()
      ..baseColorFactor = vm.Vector4(1, 0.85, 0.6, 0.6)
      ..alphaMode = AlphaMode.blend
      ..depthLayer = 3;
    _shockwave =
        Node(
            name: 'shockwave',
            mesh: Mesh(
              RingGeometry(innerRadius: 0.82, outerRadius: 1, segments: 48),
              _shockwaveMaterial,
            ),
          )
          ..visible = false
          ..shadowCastingMode = ShadowCastingMode.off;
    scene.add(_shockwave);
    // A point light makes every material in its reach costlier to draw; the
    // watch does without the flash.
    _blastLight = PointLight(
      color: vm.Vector3(1, 0.55, 0.2),
      intensity: 0,
      range: 30,
    );
    _blastLightNode = Node(name: 'blastLight');
    if (!quality.lite) {
      _blastLightNode.addComponent(PointLightComponent(_blastLight));
    }
    scene.add(_blastLightNode);
  }

  /// [count] particles, fewer on the watch.
  int _n(int count) =>
      quality.lite ? math.max(1, (count * 0.3).round()) : count;

  /// Every material of a model swapped for [burnt].
  Node _scorch(Node model, Material burnt) {
    for (final n in model.meshNodes.toList()) {
      n.mesh = Mesh.primitives(
        primitives: [
          for (final p in n.mesh!.primitives) MeshPrimitive(p.geometry, burnt),
        ],
      );
    }
    return model;
  }

  static const double _groundSize = 1200;

  Future<void> _setUpLook() async {
    final q = quality;
    if (q.renderScale != null) scene.renderScale = q.renderScale!;
    scene.renderQuality.adaptive = q.adaptive;
    scene.renderQuality.minRenderScale = 0.45;
    if (q.watch) {
      // Chasing 60 fps would halve the resolution on the watch; 30 fps keeps
      // the small screen sharp, and the anti-aliasing stays on.
      scene.renderQuality
        ..targetFrameRate = 30
        ..minRenderScale = 0.75
        ..adaptiveTiers = false;
    }
    final aa = switch (q.antiAliasing) {
      'none' => AntiAliasingMode.none,
      'fxaa' => AntiAliasingMode.fxaa,
      'msaa' => AntiAliasingMode.msaa,
      'smaa' => AntiAliasingMode.smaa,
      _ => AntiAliasingMode.auto,
    };
    if (Scene.isAntiAliasingModeSupported(aa)) scene.antiAliasingMode = aa;
    _sky = GradientSkySource();
    // Reflection cubes of 256 pixels a face (the engine's default is 512)
    // hold the 1024-wide reflection panoramas at full detail in a quarter of
    // the memory.
    EnvironmentMap.radianceCubeSize = 256;
  }

  /// Builds what glass reflects, unless it is already built. It takes a
  /// moment, so it is done while loading.
  Future<void> prepareReflections() {
    if (quality.lite || _reflections != null) return Future.value();
    return _preparing ??= () async {
      final t = look;
      final car = await cityReflections(t, width: 1024, height: 512);
      final building = await cityReflections(
        t,
        glints: 0.3,
        width: 1024,
        height: 512,
      );
      _reflections = (car, building);
      _applyReflections();
    }();
  }

  void _applyReflections() {
    final maps = _reflections;
    if (maps == null) return;
    final (car, building) = maps;
    for (final m in assets.carGlass) {
      m.environment = car;
    }
    for (final m in assets.buildingGlass) {
      m.environment = building;
    }
    // Coins mirror the same glints, so they flash as they spin.
    for (final m in _coinMaterials) {
      m.environment = car;
    }
  }

  /// Lights the world for a time of day: sun, sky, fog, and the lamps in
  /// windows and cars.
  void applyLook(TimeOfDay t) {
    final q = quality;
    final toward = t.towardSun;
    scene.directionalLight = DirectionalLight(
      direction: -toward,
      color: t.sunColor,
      intensity: t.sunIntensity,
      castsShadow: false,
    );
    _sky
      ..zenithColor = t.zenith
      ..horizonColor = t.horizon
      ..groundColor = t.ground
      ..sunDirection = toward
      ..sunColor = t.sunColor * (t.sunIntensity * 1.6 * t.sunDisc)
      ..sunSharpness = 900;
    // The sky also lights the scene. A fresh binding bakes it at once (a
    // re-bake of the old one would take a few frames to show).
    final env = SkyEnvironment(
      _sky,
      faceResolution: q.lite ? 32 : 64,
      equirectWidth: q.lite ? 128 : 256,
    );
    final fog = t.fogColor ?? t.horizon;
    scene.environmentSettings = EnvironmentSettings(
      skybox: Skybox(_sky),
      skyEnvironment: env,
      toneMapping: ToneMappingMode.aces,
      exposure: t.exposure,
      environmentIntensity: t.ambient,
      colorGradingEnabled: true,
      saturation: t.saturation,
      contrast: t.contrast,
      brightness: 1.0,
      temperature: t.temperature,
      bloomEnabled: q.bloom,
      bloomThreshold: t.bloomThreshold,
      bloomIntensity: t.bloomIntensity,
      bloomScatter: 0.75,
      vignetteEnabled: !q.lite,
      vignetteIntensity: t.vignette,
      fogEnabled: q.fog,
      fogMode: FogMode.linear,
      fogColor: fog,
      fogStart: t.fogStart,
      fogEnd: t.fogEnd,
    );

    // Lit windows and shop lamps come on as it gets dark.
    for (final m in assets.litWindows) {
      m
        ..emissiveFactor = vm.Vector4(1.0, 0.7, 0.36, 1)
        ..emissiveStrength = 2.4 * t.windowGlow;
    }
    for (final m in assets.lamps) {
      final c = m.baseColorFactor;
      m
        ..emissiveFactor = vm.Vector4(c.x, c.y, c.z, 1)
        ..emissiveStrength = 0.4 + 4.0 * t.windowGlow;
    }
    // Car lamps are always on; they shine brighter (and bloom) in the dark.
    for (final m in assets.headlights) {
      m
        ..emissiveFactor = vm.Vector4(1.0, 0.92, 0.78, 1)
        ..emissiveStrength = 1.2 + 4.5 * t.carGlow;
    }
    for (final m in assets.taillights) {
      m
        ..emissiveFactor = vm.Vector4(1.0, 0.0, 0.0, 1)
        ..emissiveStrength = 0.6 + 2.6 * t.carGlow;
    }
    for (final m in assets.indicators) {
      m
        ..emissiveFactor = vm.Vector4(1.0, 0.45, 0.05, 1)
        ..emissiveStrength = 0.6 + 1.6 * t.carGlow;
    }
    _applyReflections();
    // A little glow so bloom picks the coins up; most of their shine is the
    // glints they mirror. Bloom picks up more in the dark, so less there.
    for (final m in _coinMaterials) {
      m.emissiveStrength = (q.lite ? 0.3 : 0.35) - 0.15 * t.windowGlow;
    }
    _shadowMaterial.baseColorFactor = vm.Vector4(0, 0, 0, t.shadow);
  }

  final List<PhysicallyBasedMaterial> _coinMaterials = [];
  bool _lit = false;

  /// Sizes the simulation gives traffic, as scales of the car models
  /// (2 m wide, 4.5 m long).
  static vm.Vector3 _fit(double halfWidth, double halfLength) {
    final sx = halfWidth, sz = halfLength * 2 / 4.5;
    return vm.Vector3(sx, (sx + sz) / 2, sz);
  }

  CarView _carView(String model, int colour, vm.Vector3 scale) {
    final bus = model == 'vehicle_bus';
    final v = CarView(
      assets.car(model, colour),
      wheelRadius: GameAssets.wheelRadius[model]!,
      halfTrack: (bus ? 1.1 : 0.8) * scale.x,
      scale: scale,
    );
    if (quality.shadows) {
      v.addShadow(
        _quad,
        _shadowMaterial,
        width: bus ? 3.0 : 2.6,
        length: bus ? 11 : 5.4,
      );
    }
    scene.add(v.root);
    return v;
  }

  final Map<String, CarView> _playerViews = {};
  final Map<String, CarView> _wreckViews = {};

  CarView _playerView(String model, int colour) {
    final view = _playerViews.putIfAbsent(
      '$model#$colour',
      () => _carView(model, colour, _fit(kCarHalfWidth, kCarHalfLength)),
    );
    view.root.visible = false;
    return view;
  }

  CarView _wreckView(String model) {
    return _wreckViews.putIfAbsent(model, () {
      final v = CarView(
        _scorch(assets.instance(model), _charred),
        wheelRadius: GameAssets.wheelRadius[model]!,
        scale: _fit(kCarHalfWidth, kCarHalfLength),
      );
      v.root.visible = false;
      scene.add(v.root);
      return v;
    });
  }

  Future<Texture2D> _grassTexture() async {
    const size = 128;
    final px = Uint8List(size * size * 4);
    final rng = math.Random(4);
    final noise = List.generate(16 * 16, (_) => rng.nextDouble());
    double smooth(double x, double y) {
      final x0 = x.floor(), y0 = y.floor();
      final fx = x - x0, fy = y - y0;
      double n(int i, int j) => noise[(j % 16) * 16 + (i % 16)];
      final a = n(x0, y0) + (n(x0 + 1, y0) - n(x0, y0)) * fx;
      final b = n(x0, y0 + 1) + (n(x0 + 1, y0 + 1) - n(x0, y0 + 1)) * fx;
      return a + (b - a) * fy;
    }

    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final v =
            smooth(x / 16, y / 16) * 0.6 +
            smooth(x / 4 + 3, y / 4 + 7) * 0.25 +
            rng.nextDouble() * 0.15;
        final i = (y * size + x) * 4;
        px[i] = (92 + v * 40).round();
        px[i + 1] = (160 + v * 45).round();
        px[i + 2] = (62 + v * 25).round();
        px[i + 3] = 255;
      }
    }
    return Texture2D.fromPixels(px, size, size);
  }

  // ---------- Pools ----------

  Node _take(String model) {
    final list = _free[model];
    if (list != null && list.isNotEmpty) {
      final n = list.removeLast()..visible = true;
      return n;
    }
    final wrapper = Node(name: model)..add(assets.instance(model));
    for (final n in wrapper.meshNodes) {
      n.shadowCastingMode = ShadowCastingMode.off;
    }
    // A soft shadow under each tree's crown.
    if (model.startsWith('tree_') && quality.shadows && !quality.lite) {
      wrapper.add(
        Node(name: 'shadow', mesh: Mesh(_quad, _shadowMaterial))
          ..localTransform = vm.Matrix4.compose(
            vm.Vector3(0, 0.02, 0),
            vm.Quaternion.identity(),
            vm.Vector3(5.5, 1, 5.5),
          ),
      );
    }
    scene.add(wrapper);
    return wrapper;
  }

  void _give(String model, Node node) {
    node.visible = false;
    (_free[model] ??= []).add(node);
  }

  /// Places a node at simulation coordinates, turned by an engine [yaw].
  void _place(
    Node n,
    double x,
    double y,
    double z,
    double yaw, [
    double s = 1,
  ]) {
    n.localTransform = vm.Matrix4.compose(
      vm.Vector3(ex(x), y, z),
      vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw),
      vm.Vector3.all(s),
    );
  }

  // ---------- Following a simulation ----------

  /// Starts rendering [sim], clearing whatever was shown before, with the
  /// player in car [model] painted [colour].
  void attach(
    GameSimulation sim, {
    required String model,
    required int colour,
  }) {
    _detachAll();
    _sim = sim;
    _city = CityPlanner(sim.seed, backBuildings: !quality.lite);
    _tumble = null;
    _exploded = false;
    _explosionTime = 0;
    player.root.visible = false;
    _wreck.root.visible = false;
    player = _playerView(model, colour)..shadow = true;
    _wreck = _wreckView(model);
    player.root.visible = true;
    if (!_lit) {
      applyLook(look);
      _lit = true;
    }
    _visualRoll = 0;
    _rollVel = 0;
    _lifted = false;
    _bump = 0;
    _shockwave.visible = false;
    _blastLight.intensity = 0;
    fire.clear();
    smoke.clear();
    sparkles.clear();
    sparks.clear();
    skids.clear();
    _skidFrom = null;
    sim.onTileAdded = _addTile;
    sim.onTileRemoved = _removeTile;
    // Register every existing road before dressing any of the city around
    // it, or lots would be planned on roads not known yet.
    for (final t in sim.track.tiles) {
      _addTile(t, dress: false);
    }
    _dressRows();
    // Snap the camera behind the car.
    _posePlayer(sim, 1, 0);
    _updateCamera(0, snap: true);
  }

  void _detachAll() {
    final sim = _sim;
    if (sim != null) {
      sim.onTileAdded = null;
      sim.onTileRemoved = null;
    }
    for (final e in _roadNodes.entries.toList()) {
      _give(e.value.name, e.value);
    }
    _roadNodes.clear();
    for (final (d, nodes) in _dressing) {
      for (var i = 0; i < nodes.length; i++) {
        _give(d.props[i].model, nodes[i]);
      }
    }
    _dressing.clear();
    for (final n in _coinNodes.values) {
      _give(n.name, n);
    }
    _coinNodes.clear();
    _coinLift.clear();
    for (final p in _popping) {
      _give(p.node.name, p.node);
    }
    _popping.clear();
    for (final v in _trafficViews.values) {
      v.$1.root.visible = false;
      (_freeTraffic[v.$2] ??= []).add(v.$1);
    }
    _trafficViews.clear();
    for (final n in _obstacleNodes.values) {
      _give(n.name, n);
    }
    _obstacleNodes.clear();
  }

  void _addTile(Tile t, {bool dress = true}) {
    final model = switch (t.kind) {
      TileKind.straight => 'road_straight',
      TileKind.crosswalk => 'road_crosswalk',
      TileKind.corner => 'road_corner',
    };
    final n = _take(model);
    _place(n, t.cx, 0, t.cz, _roadYaw(t));
    _roadNodes[t.index] = n;
    _city!.addRoad(t);
    if (dress) _dressRows();
  }

  void _removeTile(Tile t) {
    final n = _roadNodes.remove(t.index);
    if (n != null) _give(n.name, n);
    _dressing.removeWhere((entry) {
      final (d, nodes) = entry;
      if (d.lastRoadIndex > t.index) return false;
      for (var i = 0; i < nodes.length; i++) {
        _give(d.props[i].model, nodes[i]);
      }
      return true;
    });
    _city!.forgetBefore(t.gz - 3);
  }

  void _dressRows() {
    final sim = _sim!;
    final last = sim.track.tile(sim.track.lastIndex);
    for (final d in _city!.dressFinalRows(last.gz)) {
      final nodes = <Node>[];
      for (final p in d.props) {
        final n = _take(p.model);
        _place(n, p.x, p.y, p.z, p.yaw, p.scale);
        nodes.add(n);
      }
      _dressing.add((d, nodes));
    }
  }

  /// Road tile rotation. Straights run along z. Imported, the corner piece
  /// joins engine +x and -z; find the quarter turn that makes it join the
  /// sides this tile connects.
  static double _roadYaw(Tile t) {
    if (!t.isCorner) {
      return t.dirIn.dx != 0 ? math.pi / 2 : 0;
    }
    (int, int) engineDir(Dir d) => (-d.dx, d.dz);
    final a = engineDir(t.dirIn.opposite), b = engineDir(t.dirOut);
    var e = (1, 0), n = (0, -1);
    for (var k = 0; k < 4; k++) {
      if ((e == a && n == b) || (e == b && n == a)) return k * math.pi / 2;
      // A quarter turn of positive yaw maps (x, z) to (z, -x).
      e = (e.$2, -e.$1);
      n = (n.$2, -n.$1);
    }
    return 0;
  }

  // ---------- Per frame ----------

  final Map<String, List<CarView>> _freeTraffic = {};

  /// Updates everything. [alpha] (0..1) interpolates between the previous
  /// and current simulation step.
  void update(double dt, double alpha) {
    _time += dt;
    final sim = _sim;
    if (sim == null) return;
    final car = sim.car;

    // Coins and power-ups. Traffic keeps to its lane and drives on past
    // them, so a coin hops up over anything that comes through its spot.
    final under = [
      for (final t in sim.traffic)
        (
          t.lane,
          t.distanceOn(sim.track),
          t.model.halfLength,
          _heights[t.model]!,
        ),
    ];
    final live = <int>{};
    for (final coin in sim.coins) {
      live.add(coin.id);
      var n = _coinNodes[coin.id];
      if (n == null) {
        n = _take(_pickupModel(coin));
        _coinNodes[coin.id] = n;
      }
      var over = 0.0;
      for (final (lane, at, half, height) in under) {
        // A little ahead of time, so it is up before the car gets there.
        if (lane == coin.lane && (at - coin.at).abs() < half + 2.5) {
          over = math.max(over, height);
        }
      }
      final was = _coinLift[coin.id] ?? 0;
      final lift = was + (over - was) * math.min(1.0, dt * 14);
      _coinLift[coin.id] = lift;
      if (coin.power != null) {
        final bob = math.sin(_time * 4 + coin.id) * 0.25;
        _place(n, coin.x, 0.2 + bob + lift, coin.z, _time * 3.2);
        // A glitter around power-ups so they can be seen from afar.
        if (!quality.lite && _rand.nextDouble() < dt * 14) {
          _glitter(coin.x, 1.2 + bob, coin.z, coin.power!);
        }
      } else {
        final bob = math.sin(_time * 3 + coin.id) * 0.15;
        _place(
          n,
          coin.x,
          0.35 + bob + lift,
          coin.z,
          _time * 3 + coin.id * 0.7,
        );
      }
    }
    for (final id in _coinNodes.keys.toList()) {
      if (!live.contains(id)) {
        final n = _coinNodes.remove(id)!;
        _coinLift.remove(id);
        _give(n.name, n);
      }
    }
    for (final p in _popping.toList()) {
      p.t += dt;
      final k = p.t / 0.35;
      if (k >= 1) {
        _popping.remove(p);
        _give(p.node.name, p.node);
        continue;
      }
      final s = 1 + k * 0.6 - k * k * 1.5;
      _place(
        p.node,
        p.x + (car.x - p.x) * k * 0.6,
        0.6 + k * 2.6,
        p.z + (car.z - p.z) * k * 0.6,
        _time * 18,
        math.max(0.05, s),
      );
    }

    // Traffic and roadworks.
    final liveTraffic = <int>{};
    for (final t in sim.traffic) {
      liveTraffic.add(t.id);
      if (t.model.parked) {
        final model = t.model == TrafficModel.barrier
            ? 'obstacle_barrier'
            : 'obstacle_cone';
        final n = _obstacleNodes[t.id] ??= _take(model);
        _place(n, t.x, kRoadY, t.z, yawFor(t.hx, t.hz));
        continue;
      }
      var view = _trafficViews[t.id];
      if (view == null) {
        // Each size of car in the simulation has a model or two that
        // look the part; the paint is random.
        final looks = switch (t.model) {
          TrafficModel.hatchback => const ['car_hatchback', 'car_coupe'],
          TrafficModel.sedan => const ['car_sedan', 'car_wagon'],
          TrafficModel.suv => const ['car_suv', 'car_van'],
          TrafficModel.pickup => const ['car_pickup'],
          TrafficModel.bus => const ['vehicle_bus'],
          TrafficModel.barrier || TrafficModel.cone => const <String>[],
        };
        final hash = (t.id * 2654435761 + sim.seed) & 0x7fffffff;
        final model = looks[hash % looks.length];
        final colour = (hash ~/ 7) % carPaints.length;
        final key = '${t.model.name}/$model#$colour';
        final pool = _freeTraffic[key];
        CarView v;
        if (pool != null && pool.isNotEmpty) {
          v = pool.removeLast();
          v.root.visible = true;
        } else {
          v = _carView(
            model,
            colour,
            t.model == TrafficModel.bus
                ? vm.Vector3.all(1)
                : _fit(t.model.halfWidth, t.model.halfLength),
          );
        }
        view = (v, key);
        _trafficViews[t.id] = view;
      }
      final x = t.prevX + (t.x - t.prevX) * alpha;
      final z = t.prevZ + (t.z - t.prevZ) * alpha;
      final hx = t.prevHx + (t.hx - t.prevHx) * alpha;
      final hz = t.prevHz + (t.hz - t.prevHz) * alpha;
      view.$1.pose(
        position: vm.Vector3(ex(x), kRoadY, z),
        yaw: yawFor(hx, hz),
        speed: t.speed,
        dt: dt,
        roll: 0,
      );
    }
    for (final id in _trafficViews.keys.toList()) {
      if (!liveTraffic.contains(id)) {
        final v = _trafficViews.remove(id)!;
        v.$1.root.visible = false;
        (_freeTraffic[v.$2] ??= []).add(v.$1);
      }
    }
    for (final id in _obstacleNodes.keys.toList()) {
      if (!liveTraffic.contains(id)) {
        final n = _obstacleNodes.remove(id)!;
        _give(n.name, n);
      }
    }
    // Roadworks lamps flash.
    final blink = (_time * 2.6) % 1 < 0.5;
    for (final m in assets.blinkLamps) {
      m.emissiveStrength = blink ? 3.5 : 0.15;
    }

    // Player.
    final tumble = _tumble;
    if (tumble != null) {
      tumble.update(dt);
      (_exploded ? _wreck : player).root.localTransform = vm.Matrix4.compose(
        tumble.pos,
        tumble.rot,
        vm.Vector3.all(1),
      );
      if (_exploded) _updateExplosion(dt, tumble.pos);
    } else {
      _posePlayer(sim, alpha, dt);
    }

    _updateCamera(dt);
    _poseBadges();
    _turnReflections(dt);

    // Ground follows the camera in whole-tile steps so the texture holds
    // still.
    final gx = (_camPos.x / 24).round() * 24.0;
    final gz = (_camPos.z / 24).round() * 24.0;
    _ground.position = vm.Vector3(gx, -0.06, gz);

    smoke.update(dt);
    sparkles.update(dt);
    sparks.update(dt);
    fire.update(dt);
  }

  /// Puts each running power-up's model in front of the camera, where the
  /// HUD keeps a slot for it, turning slowly about its upright.
  void _poseBadges() {
    // Close enough to stay in front of the world, far enough not to cost
    // depth precision (the near plane fits the closest thing drawn).
    const distance = 6.0;
    const modelHeight = 1.9;
    final f = camera.forward, r = camera.right;
    final u = f.cross(r)..normalize();
    final tanY = math.tan(camera.fovRadiansY / 2);
    final tanX = tanY * aspect;
    for (final MapEntry(key: power, value: node) in _badges.entries) {
      final slot = badgeSlots[power];
      if (slot == null || _tumble != null) {
        node.visible = false;
        continue;
      }
      final (nx, ny, height) = slot;
      final s = height * 2 * distance * tanY / modelHeight;
      final centre =
          camera.position +
          f * distance +
          r * (nx * tanX * distance) +
          u * (ny * tanY * distance);
      // Face the camera (imported models face -z), upright on the screen.
      final x = u.cross(f)..normalize();
      final facing = vm.Quaternion.fromRotation(
        vm.Matrix3.columns(x, u, f),
      );
      final spin = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _time * 2.6);
      node
        ..visible = true
        ..localTransform = vm.Matrix4.compose(
          centre - u * (modelHeight / 2 * s),
          facing * spin,
          vm.Vector3.all(s),
        );
    }
  }

  // The player's heading, unwrapped, and a slow drift of the reflections.
  double? _lastHeading;
  double _heading = 0;
  double _reflectionDrift = 0;

  /// Turns what glass reflects along with most of the player's turning, and
  /// a little more all the time. Fixed in the world, the glints would sweep
  /// across the windows at the car's full rate of turn and flicker; this way
  /// they slide by slowly, and still move when driving straight.
  void _turnReflections(double dt) {
    if (_tumble == null) {
      final forward =
          player.root.localTransform.getRotation() * vm.Vector3(0, 0, 1);
      final a = math.atan2(forward.x, forward.z);
      final last = _lastHeading;
      if (last != null) {
        var d = a - last;
        while (d > math.pi) {
          d -= math.pi * 2;
        }
        while (d < -math.pi) {
          d += math.pi * 2;
        }
        _heading += d;
      }
      _lastHeading = a;
    }
    _reflectionDrift += dt * 0.03;
    // Environment lookups are rotated by this matrix: undoing 85% of the
    // car's heading keeps the glints nearly still on its windows.
    scene.environmentTransform.setFrom(
      vm.Matrix3.rotationY(_reflectionDrift - 0.85 * _heading),
    );
  }

  double _visualRoll = 0;
  double _rollVel = 0;
  bool _lifted = false;
  double _pitch = 0;
  double _pitchVel = 0;
  double _lastSpeed = 0;
  double _smokeAcc = 0;

  /// A sideways shove from bumping the kerb, decaying (m).
  double _bump = 0;
  double _bumpVel = 0;

  /// How hard the tyres are working, 0..1, for the tyre squeal.
  double slide = 0;

  /// Where the camera follows: the car, pulled most of the way back to the
  /// road's centre line so changing lanes moves the car across the screen.
  final vm.Vector3 _follow = vm.Vector3.zero();

  void _posePlayer(GameSimulation sim, double alpha, double dt) {
    final c = sim.car;
    var x = c.prevX + (c.x - c.prevX) * alpha;
    var z = c.prevZ + (c.z - c.prevZ) * alpha;
    final hx = c.prevHx + (c.hx - c.prevHx) * alpha;
    final hz = c.prevHz + (c.hz - c.prevHz) * alpha;
    final rx = -hz, rz = hx;
    _follow.setValues(ex(x - rx * c.lat * 0.65), 0, z - rz * c.lat * 0.65);

    // Kerb bump: a quick shove toward the kerb and back.
    _bumpVel += (-_bump * 260 - _bumpVel * 16) * dt;
    _bump += _bumpVel * dt;
    x += rx * _bump;
    z += rz * _bump;

    // Body roll: flung outward in the corners, up onto two wheels, and
    // rocked by lane changes. A springy, underdamped wobble.
    final lateral = c.groundSpeed * c.groundSpeed * c.turn;
    final target = (lateral / 38).clamp(-1.0, 1.0) * 0.45;
    _rollVel += ((target - _visualRoll) * 130 - _rollVel * 8.5) * dt;
    _visualRoll += _rollVel * dt;
    final r = _visualRoll.abs();
    final lift = ((r - 0.1) / 0.12).clamp(0.0, 1.0);
    final up = r > 0.16;
    if (up != _lifted) {
      _lifted = up;
      if (up) {
        _trauma = math.min(1, _trauma + 0.12);
        onLift?.call();
      }
    }
    slide = ((lateral.abs() - 25) / 45).clamp(0.0, 1.0);

    // Pitch: squat under acceleration, with a springy settle.
    final accel = dt > 0 ? (c.speed - _lastSpeed) / dt : 0.0;
    _lastSpeed = c.speed;
    final pitchTarget = accel * 0.006;
    _pitchVel += ((pitchTarget - _pitch) * 90 - _pitchVel * 9) * dt;
    _pitch += _pitchVel * dt;

    // Point the nose where it is going while changing lanes, plus a slight
    // drift angle in corners.
    final ground = math.max(c.groundSpeed, 6.0);
    final swerve = math.atan(c.latVelocity / ground) * 0.55;
    final drift = (lateral / 60).clamp(-1.0, 1.0) * 0.12;

    player.pose(
      position: vm.Vector3(ex(x), kRoadY, z),
      yaw: yawFor(hx, hz),
      roll: _visualRoll,
      lift: lift,
      pitch: _pitch,
      steer: swerve * 0.9 + (c.turn * 2.6).clamp(-0.5, 0.5),
      speed: c.groundSpeed,
      dt: dt,
      extraYaw: swerve + drift,
    );

    // Tyre marks and a little smoke when on two wheels.
    _laySkids(x, z, hx, hz, slide > 0.3);
    if (up && slide > 0) {
      _smokeAcc += dt * (quality.lite ? 6 : 26) * slide;
      while (_smokeAcc > 1) {
        _smokeAcc -= 1;
        // The tyres still on the ground: the outside of the turn.
        final side = c.turn > 0 ? -1.0 : 1.0;
        final px = x - hx * 1.4 + rx * side * 0.85;
        final pz = z - hz * 1.4 + rz * side * 0.85;
        smoke.emit(
          x: ex(px),
          y: 0.25,
          z: pz,
          vx: (_rand.nextDouble() - 0.5) * 1.2,
          vy: 0.6 + _rand.nextDouble() * 0.6,
          vz: (_rand.nextDouble() - 0.5) * 1.2,
          life: 0.7 + _rand.nextDouble() * 0.4,
          size: 0.7,
          endSize: 2.6,
          r: 0.92,
          g: 0.92,
          b: 0.95,
          a: 0.32,
          rotation: _rand.nextDouble() * 6,
          spin: (_rand.nextDouble() - 0.5) * 2,
          drag: 1.5,
        );
      }
    }
  }

  final math.Random _rand = math.Random();

  /// Where the rear tyres were when the last skid strip ended.
  List<double>? _skidFrom;

  void _laySkids(double x, double z, double hx, double hz, bool on) {
    if (!on) {
      _skidFrom = null;
      return;
    }
    final rx = -hz, rz = hx;
    final pts = <double>[];
    for (final side in [-1.0, 1.0]) {
      pts
        ..add(ex(x - hx * 1.45 + rx * side * 0.82))
        ..add(z - hz * 1.45 + rz * side * 0.82);
    }
    final from = _skidFrom;
    if (from == null) {
      _skidFrom = pts;
      return;
    }
    final dx = pts[0] - from[0], dz = pts[1] - from[1];
    if (dx * dx + dz * dz < 0.36) return;
    for (var i = 0; i < 4; i += 2) {
      skids.add(from[i], from[i + 1], pts[i], pts[i + 1], kRoadY + 0.004);
    }
    _skidFrom = pts;
  }

  /// Where the car has been, most recent last (engine coordinates). The
  /// chase camera rides along this trail, which is always over the road, so
  /// it doesn't swing out into the buildings on corners.
  final List<vm.Vector3> _trail = [];

  void _resetTrail(vm.Vector3 carPos, vm.Vector3 fwd) {
    _trail.clear();
    for (var d = 40.0; d > 0; d -= 1) {
      _trail.add(carPos - fwd * d);
    }
    _trail.add(carPos.clone());
  }

  /// The point [dist] metres back along the trail from [from].
  vm.Vector3 _trailBack(vm.Vector3 from, double dist) {
    var prev = from;
    var left = dist;
    for (var i = _trail.length - 1; i >= 0; i--) {
      final p = _trail[i];
      final seg = (prev - p).length;
      if (seg >= left && seg > 0) {
        return prev + (p - prev) * (left / seg);
      }
      left -= seg;
      prev = p;
    }
    // Ran out of trail: continue straight back.
    final fwd = _trail.length > 1
        ? (_trail.last - _trail.first).normalized()
        : vm.Vector3(0, 0, 1);
    return prev - fwd * left;
  }

  void _updateCamera(double dt, {bool snap = false}) {
    final sim = _sim;
    if (sim == null) return;
    final c = sim.car;
    final carPos =
        _tumble?.pos.clone() ??
        vm.Vector3(_follow.x, player.root.position.y, _follow.z);
    final speed = _tumble == null ? c.speed : 0.0;
    final fwd = vm.Vector3(ex(c.hx), 0, c.hz);

    if (snap) {
      _camFwd.setFrom(fwd);
      _resetTrail(carPos, fwd);
    } else if (_tumble == null) {
      final k = 1 - math.exp(-dt * 4.5);
      _camFwd.setFrom(_camFwd + (fwd - _camFwd) * k);
      _camFwd.normalize();
      final flat = vm.Vector3(carPos.x, 0, carPos.z);
      final last = _trail.last;
      if ((flat - vm.Vector3(last.x, 0, last.z)).length > 0.5) {
        _trail.add(flat);
        if (_trail.length > 160) _trail.removeAt(0);
      }
    }

    // Tall or tiny screens get a higher, more top-down view.
    final portrait = aspect < 1 ? ((1 - aspect) / 0.55).clamp(0.0, 1.0) : 0.0;
    final small = (1 - (shortestSide - 200) / 400).clamp(0.0, 1.0);
    // The framing of the title screen's demo, also used while playing: high
    // and a little further back, looking down on the car more than ahead.
    // Behind and above the car, looking well down the road so the next
    // rows of traffic are in view. Tiny screens (the watch) come in closer
    // and look further ahead, so the car sits low and the road fills the
    // screen.
    final dist = 9.5 + speed * 0.1 + portrait * 3 - small * 1.5;
    var height = 7.2 + speed * 0.05 + portrait * 6 + small * 1.5;
    var lookAhead = 6 + speed * 0.3 + portrait * 4 + small * 3;

    final flatCar = vm.Vector3(carPos.x, 0, carPos.z);
    var anchor = _trailBack(flatCar, dist);

    // Title screen: the shot slowly sways.
    if (attractBlend > 0) {
      final a = math.sin(_time * 0.15) * 0.08 * attractBlend;
      final off = anchor - flatCar;
      anchor =
          flatCar +
          vm.Vector3(
            off.x * math.cos(a) + off.z * math.sin(a),
            0,
            -off.x * math.sin(a) + off.z * math.cos(a),
          );
    }
    if (_tumble != null) {
      anchor = _trailBack(flatCar, 13);
      height = 11;
      lookAhead = 0;
    }

    final desired = anchor + vm.Vector3(0, height, 0);
    final target = carPos + _camFwd * lookAhead + vm.Vector3(0, 1.0, 0);
    if (snap) {
      _camPos.setFrom(desired);
      _camTarget.setFrom(target);
    } else {
      final kp = 1 - math.exp(-dt * (_tumble != null ? 1.5 : 9));
      _camPos.setFrom(_camPos + (desired - _camPos) * kp);
      final kt = 1 - math.exp(-dt * (_tumble != null ? 3 : 12));
      _camTarget.setFrom(_camTarget + (target - _camTarget) * kt);
    }

    // Shake.
    _trauma = math.max(0, _trauma - dt * 1.4);
    final shake = _trauma * _trauma;
    final sx = (math.sin(_time * 47) + math.sin(_time * 31)) * 0.25 * shake;
    final sy = (math.sin(_time * 53) + math.sin(_time * 23)) * 0.25 * shake;

    // Field of view: widen with speed, and keep at least ~64 degrees
    // horizontally so tall screens still see the road's edges.
    _fovKick = math.max(0, _fovKick - dt * 2);
    var fov = 50 + speed * 0.5 - small * 6 + _fovKick * 8;
    final minH = (50 - small * 8 + speed * 0.3) * vm.degrees2Radians;
    final forWidth =
        2 * math.atan(math.tan(minH / 2) / aspect) * vm.radians2Degrees;
    fov = math.max(fov, forWidth);
    camera.fovRadiansY = fov.clamp(40, 82) * vm.degrees2Radians;
    camera.position = _camPos + vm.Vector3(sx, sy, 0);
    camera.target = _camTarget + vm.Vector3(sx * 0.5, sy * 0.5, 0);
  }

  // ---------- Events ----------

  /// The model a coin or power-up is drawn with.
  static String _pickupModel(Coin coin) =>
      coin.power == null ? 'pickup_coin' : _powerModel(coin.power!);

  static String _powerModel(PowerUp p) => switch (p) {
    PowerUp.magnet => 'pickup_magnet',
    PowerUp.double => 'pickup_double',
  };

  void coinCollected(Coin coin, {bool doubled = false}) {
    final n = _coinNodes.remove(coin.id);
    if (n != null) _popping.add(_PoppingCoin(n, coin.x, coin.z));
    for (var i = 0; i < _n(doubled ? 16 : 10); i++) {
      final a = _rand.nextDouble() * math.pi * 2;
      final s = 2 + _rand.nextDouble() * 4;
      sparkles.emit(
        x: ex(coin.x),
        y: 1.2,
        z: coin.z,
        vx: math.cos(a) * s,
        vy: 1 + _rand.nextDouble() * 5,
        vz: math.sin(a) * s,
        life: 0.4 + _rand.nextDouble() * 0.4,
        size: 0.5 + _rand.nextDouble() * 0.5,
        endSize: 0.1,
        r: doubled ? 0.6 : 1.6,
        g: doubled ? 1.8 : 1.2,
        b: 0.4,
        rotation: a,
        spin: 4,
        drag: 2,
        gravity: 6,
      );
    }
  }

  void powerUpCollected(Coin pickup) {
    final n = _coinNodes.remove(pickup.id);
    if (n != null) _popping.add(_PoppingCoin(n, pickup.x, pickup.z));
    _fovKick = 1.2;
    _trauma = math.min(1, _trauma + 0.25);
    for (var i = 0; i < _n(40); i++) {
      _glitter(pickup.x, 1.2, pickup.z, pickup.power!, burst: true);
    }
  }

  /// A sparkle in a power-up's colour.
  void _glitter(
    double x,
    double y,
    double z,
    PowerUp power, {
    bool burst = false,
  }) {
    final a = _rand.nextDouble() * math.pi * 2;
    final s = burst ? 3 + _rand.nextDouble() * 6 : 0.6;
    final magnet = power == PowerUp.magnet;
    sparkles.emit(
      x: ex(x) + math.cos(a) * (burst ? 0 : 1.2),
      y: y + (_rand.nextDouble() - 0.5),
      z: z + math.sin(a) * (burst ? 0 : 1.2),
      vx: math.cos(a) * s,
      vy: burst ? 2 + _rand.nextDouble() * 5 : 1.5,
      vz: math.sin(a) * s,
      life: burst ? 0.7 : 0.5,
      size: burst ? 0.8 : 0.5,
      endSize: 0.1,
      r: magnet ? 2.2 : 0.5,
      g: magnet ? 0.4 : 2.0,
      b: magnet ? 0.5 : 0.6,
      rotation: a,
      spin: 4,
      drag: 1.5,
      gravity: burst ? 5 : 0,
    );
  }

  void nearMiss(TrafficCar t) {
    _fovKick = 1;
    _trauma = math.min(1, _trauma + 0.15);
  }

  void laneChanged(int direction) {
    // Rock the body the other way, like a quick flick of the wheel.
    _rollVel += direction * 2.6;
  }

  void kerbBumped(int direction) {
    _bumpVel += direction * 9;
    _rollVel -= direction * 3;
    _trauma = math.min(1, _trauma + 0.3);
    final c = _sim!.car;
    // Sparks off the kerb.
    final rx = -c.hz, rz = c.hx;
    final px = c.x + rx * direction * 1.1, pz = c.z + rz * direction * 1.1;
    for (var i = 0; i < _n(24); i++) {
      final a = _rand.nextDouble() * math.pi * 2;
      final s = 3 + _rand.nextDouble() * 6;
      sparks.emit(
        x: ex(px),
        y: 0.3,
        z: pz,
        vx: math.cos(a) * s - ex(c.hx) * 4,
        vy: 1 + _rand.nextDouble() * 4,
        vz: math.sin(a) * s - c.hz * 4,
        life: 0.25 + _rand.nextDouble() * 0.3,
        size: 0.15,
        endSize: 0.04,
        r: 2.2,
        g: 1.4,
        b: 0.5,
        drag: 1,
        gravity: 14,
      );
    }
  }

  void crashed(CrashKind kind, TrafficCar? other) {
    final sim = _sim!;
    final c = sim.car;
    _trauma = 1;
    final pos = player.root.position;
    final yaw = yawFor(c.hx, c.hz);
    final v = vm.Vector3(ex(c.hx), 0, c.hz) * c.speed;
    final spin = vm.Vector3.zero();
    // Bounce off the other car and spin.
    final o = other;
    final away = o == null
        ? vm.Vector3(0, 0, 0)
        : (vm.Vector3(ex(c.x - o.x), 0, c.z - o.z)..normalize());
    v.setFrom(v * 0.3 + away * (6 + c.speed * 0.35));
    v.y = 4 + c.speed * 0.1;
    spin.setValues(
      (_rand.nextDouble() - 0.5) * 5,
      (_rand.nextDouble() < 0.5 ? -1 : 1) * (8 + _rand.nextDouble() * 6),
      (_rand.nextDouble() - 0.5) * 6,
    );
    final rot =
        vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw) *
        vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), -_visualRoll);
    _tumble = CrashTumble(pos.clone(), v, rot, spin, _groundAt);
    player.shadow = false;

    // Debris, sparks and a puff of smoke.
    for (var i = 0; i < _n(60); i++) {
      final a = _rand.nextDouble() * math.pi * 2;
      final s = 4 + _rand.nextDouble() * 12;
      sparks.emit(
        x: pos.x,
        y: 0.8,
        z: pos.z,
        vx: math.cos(a) * s + v.x * 0.3,
        vy: 2 + _rand.nextDouble() * 8,
        vz: math.sin(a) * s + v.z * 0.3,
        life: 0.4 + _rand.nextDouble() * 0.6,
        size: 0.18,
        endSize: 0.05,
        r: 2.2,
        g: 1.4,
        b: 0.5,
        drag: 1,
        gravity: 14,
      );
    }
    for (var i = 0; i < _n(26); i++) {
      final a = _rand.nextDouble() * math.pi * 2;
      final s = 1 + _rand.nextDouble() * 3;
      smoke.emit(
        x: pos.x + math.cos(a),
        y: 0.6,
        z: pos.z + math.sin(a),
        vx: math.cos(a) * s,
        vy: 1 + _rand.nextDouble() * 2,
        vz: math.sin(a) * s,
        life: 1.2 + _rand.nextDouble(),
        size: 1.5,
        endSize: 5,
        r: 0.75,
        g: 0.74,
        b: 0.76,
        a: 0.6,
        rotation: a,
        spin: 1,
        drag: 2,
      );
    }
    for (var i = 0; i < _n(12); i++) {
      final a = _rand.nextDouble() * math.pi * 2;
      sparkles.emit(
        x: pos.x,
        y: 1.6,
        z: pos.z,
        vx: math.cos(a) * 3,
        vy: 3 + _rand.nextDouble() * 3,
        vz: math.sin(a) * 3,
        life: 1.0,
        size: 0.9,
        endSize: 0.3,
        r: 1.8,
        g: 1.8,
        b: 1.2,
        spin: 3,
        drag: 1.5,
        gravity: 3,
      );
    }
  }

  /// Height of whatever surface is at engine (x, z): asphalt, a kerb, a
  /// sidewalk or grass.
  double _groundAt(double x, double z) {
    final sim = _sim;
    final city = _city;
    if (sim == null || city == null) return kRoadY;
    final sx = -x;
    final tile = sim.track.tileAt(sx, z);
    if (tile != null) return tile.isDrivable(sx, z) ? kRoadY : 0.0;
    final gx = (sx / kTile + 0.5).floor(), gz = (z / kTile + 0.5).floor();
    for (var dz = -1; dz <= 1; dz++) {
      for (var dx = -1; dx <= 1; dx++) {
        // Lots next to the road are paved.
        if (city.isRoad(gx + dx, gz + dz)) return 0.15;
      }
    }
    return -0.06;
  }

  // ---------- Explosion ----------

  bool _exploded = false;
  double _explosionTime = 0;
  double _burnAcc = 0;
  double _columnAcc = 0;

  bool get exploded => _exploded;

  /// Blows up the crashed car: a fireball, a shockwave, a flash of light,
  /// flying debris, and the car tossed up again as a burnt-out wreck that
  /// keeps smouldering.
  void explode() {
    final tumble = _tumble;
    if (tumble == null || _exploded) return;
    _exploded = true;
    _explosionTime = 0;
    _trauma = 1;
    _fovKick = 1.5;

    // Swap in the charred car and toss it.
    player.root.visible = false;
    _wreck.root.visible = true;
    tumble.settling = false;
    tumble.vel
      ..x *= 0.3
      ..z *= 0.3
      ..y = 7.5;
    tumble.spin.setValues(
      (_rand.nextDouble() - 0.5) * 9,
      (_rand.nextDouble() - 0.5) * 5,
      (_rand.nextDouble() - 0.5) * 9,
    );

    final p = tumble.pos;
    // White-hot core.
    for (var i = 0; i < _n(6); i++) {
      fire.emit(
        x: p.x,
        y: p.y + 1,
        z: p.z,
        vy: 1,
        life: 0.18,
        size: 5,
        endSize: 9,
        r: 1.6,
        g: 1.3,
        b: 0.8,
      );
    }
    // Fireball.
    for (var i = 0; i < _n(80); i++) {
      final a = _rand.nextDouble() * math.pi * 2;
      final up = _rand.nextDouble();
      final s = 3 + _rand.nextDouble() * 9;
      fire.emit(
        x: p.x + math.cos(a) * 0.5,
        y: p.y + 0.6,
        z: p.z + math.sin(a) * 0.5,
        vx: math.cos(a) * s * (1 - up * 0.6),
        vy: 2 + up * 9,
        vz: math.sin(a) * s * (1 - up * 0.6),
        life: 0.5 + _rand.nextDouble() * 0.6,
        size: 1.8 + _rand.nextDouble() * 1.4,
        endSize: 3.5 + _rand.nextDouble() * 2.5,
        r: 1.5,
        g: 0.32 + _rand.nextDouble() * 0.4,
        b: 0.05,
        rotation: a,
        spin: (_rand.nextDouble() - 0.5) * 3,
        drag: 3.5,
        gravity: -2,
      );
    }
    // Solid orange billows give the fireball body against a bright sky.
    for (var i = 0; i < _n(34); i++) {
      final a = _rand.nextDouble() * math.pi * 2;
      final up = _rand.nextDouble();
      final s = 2 + _rand.nextDouble() * 6;
      final hot = _rand.nextDouble();
      smoke.emit(
        x: p.x + math.cos(a) * 0.6,
        y: p.y + 0.8 + up,
        z: p.z + math.sin(a) * 0.6,
        vx: math.cos(a) * s * (1 - up * 0.5),
        vy: 2 + up * 7,
        vz: math.sin(a) * s * (1 - up * 0.5),
        life: 0.7 + _rand.nextDouble() * 0.6,
        size: 2 + _rand.nextDouble() * 1.5,
        endSize: 4.5 + _rand.nextDouble() * 2,
        r: 1.0,
        g: 0.45 + hot * 0.35,
        b: 0.08 + hot * 0.1,
        a: 0.95,
        rotation: a,
        spin: (_rand.nextDouble() - 0.5) * 2,
        drag: 3,
        gravity: -1.5,
      );
    }

    // Sparks and glowing debris.
    for (var i = 0; i < _n(90); i++) {
      final a = _rand.nextDouble() * math.pi * 2;
      final s = 6 + _rand.nextDouble() * 16;
      sparks.emit(
        x: p.x,
        y: p.y + 0.8,
        z: p.z,
        vx: math.cos(a) * s,
        vy: 4 + _rand.nextDouble() * 12,
        vz: math.sin(a) * s,
        life: 0.6 + _rand.nextDouble() * 0.9,
        size: 0.22,
        endSize: 0.08,
        r: 2.4,
        g: 1.3,
        b: 0.4,
        drag: 0.8,
        gravity: 16,
      );
    }
    for (var i = 0; i < _n(30); i++) {
      final a = _rand.nextDouble() * math.pi * 2;
      final s = 4 + _rand.nextDouble() * 9;
      smoke.emit(
        x: p.x,
        y: p.y + 0.8,
        z: p.z,
        vx: math.cos(a) * s,
        vy: 5 + _rand.nextDouble() * 9,
        vz: math.sin(a) * s,
        life: 1 + _rand.nextDouble() * 0.6,
        size: 0.35 + _rand.nextDouble() * 0.3,
        endSize: 0.3,
        r: 0.05,
        g: 0.05,
        b: 0.05,
        rotation: a,
        spin: (_rand.nextDouble() - 0.5) * 12,
        drag: 0.4,
        gravity: 18,
      );
    }
    _shockwave.visible = true;
    _blastLightNode.position = vm.Vector3(p.x, p.y + 2, p.z);
  }

  void _updateExplosion(double dt, vm.Vector3 pos) {
    _explosionTime += dt;
    final t = _explosionTime;

    // Shockwave racing out across the ground.
    final k = (t / 0.55).clamp(0.0, 1.0);
    if (k < 1) {
      final r = 1 + Curves.easeOutQuad.transform(k) * 16;
      _shockwave.localTransform = vm.Matrix4.compose(
        vm.Vector3(pos.x, kRoadY + 0.02, pos.z),
        vm.Quaternion.identity(),
        vm.Vector3(r, 1, r),
      );
      _shockwaveMaterial.baseColorFactor = vm.Vector4(
        1,
        0.85,
        0.6,
        0.65 * (1 - k),
      );
    } else {
      _shockwave.visible = false;
    }

    // Flash of light, then a flickering glow from the fire.
    final flash = 22 * math.exp(-t * 8);
    final flicker =
        6 *
        (0.8 + 0.2 * math.sin(t * 31) * math.sin(t * 17)) *
        math.exp(-t * 0.25);
    _blastLight.intensity = flash + flicker;
    _blastLightNode.position = vm.Vector3(pos.x, pos.y + 2, pos.z);

    // A column of black smoke rising behind the fireball.
    if (t > 0.18 && t < 1.2) {
      _columnAcc += dt * _n(45);
      while (_columnAcc > 1) {
        _columnAcc -= 1;
        final a = _rand.nextDouble() * math.pi * 2;
        final s = 0.5 + _rand.nextDouble() * 2.5;
        smoke.emit(
          x: pos.x + math.cos(a),
          y: pos.y + 2.5,
          z: pos.z + math.sin(a),
          vx: math.cos(a) * s,
          vy: 4 + _rand.nextDouble() * 4,
          vz: math.sin(a) * s,
          life: 2 + _rand.nextDouble() * 1.5,
          size: 2,
          endSize: 8,
          r: 0.17,
          g: 0.16,
          b: 0.16,
          a: 0.6,
          rotation: a,
          spin: (_rand.nextDouble() - 0.5),
          drag: 1.4,
        );
      }
    }

    // The wreck burns.
    _burnAcc += dt * _n(55);
    while (_burnAcc > 1) {
      _burnAcc -= 1;
      final a = _rand.nextDouble() * math.pi * 2;
      if (_rand.nextBool()) {
        fire.emit(
          x: pos.x + math.cos(a) * 0.7,
          y: pos.y + 0.8,
          z: pos.z + math.sin(a) * 0.9,
          vx: math.cos(a) * 0.4,
          vy: 2 + _rand.nextDouble() * 2,
          vz: math.sin(a) * 0.4,
          life: 0.45 + _rand.nextDouble() * 0.4,
          size: 1.4 + _rand.nextDouble() * 1.0,
          endSize: 0.3,
          r: 2.6,
          g: 0.8 + _rand.nextDouble() * 0.5,
          b: 0.12,
          rotation: a,
        );
      } else {
        smoke.emit(
          x: pos.x + math.cos(a) * 0.6,
          y: pos.y + 1.4,
          z: pos.z + math.sin(a) * 0.6,
          vx: math.cos(a) * 0.5 + 0.6,
          vy: 2.5 + _rand.nextDouble() * 1.5,
          vz: math.sin(a) * 0.5,
          life: 2.2 + _rand.nextDouble(),
          size: 1.2,
          endSize: 5.5,
          r: 0.18,
          g: 0.17,
          b: 0.17,
          a: 0.55,
          rotation: a,
          spin: 0.6,
          drag: 0.8,
        );
      }
    }
  }
}

class _PoppingCoin {
  final Node node;
  final double x, z;
  double t = 0;
  _PoppingCoin(this.node, this.x, this.z);
}
