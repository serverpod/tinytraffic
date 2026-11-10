import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'look.dart';

/// A building model and the lots it takes up.
class BuildingSpec {
  final String model;

  /// Lots along the road, and lots back from it.
  final int wide, deep;

  /// Size in metres across its front and from front to back.
  final double width, depth;

  const BuildingSpec(
    this.model,
    this.width,
    this.depth, {
    this.wide = 1,
    this.deep = 1,
  });
}

/// The 3D models, loaded once and cloned for every use.
///
/// Buildings and trees also come in repainted variants, named
/// `<model>#<n>` (see [variant]); they share everything with the original
/// but the repainted materials.
class GameAssets {
  static const roads = ['road_straight', 'road_corner', 'road_crosswalk'];
  static const cars = [
    'car_sedan',
    'car_coupe',
    'car_hatchback',
    'car_suv',
    'car_pickup',
    'car_van',
    'car_wagon',
  ];

  /// Wheel radius of each car model, in metres.
  static const wheelRadius = {
    'car_sedan': 0.345,
    'car_coupe': 0.345,
    'car_hatchback': 0.356,
    'car_suv': 0.39,
    'car_pickup': 0.38,
    'car_van': 0.36,
    'car_wagon': 0.35,
    'vehicle_bus': 0.5,
  };

  /// Traffic that isn't a car the player can drive.
  static const otherVehicles = ['vehicle_bus'];

  static const trees = [
    'tree_oak',
    'tree_maple',
    'tree_maple_b',
    'tree_poplar',
  ];

  static const buildings = [
    BuildingSpec('building_cafe', 6.72, 7.5),
    BuildingSpec('building_house', 6.72, 7.55),
    BuildingSpec('building_townhouse', 6.72, 7.23),
    BuildingSpec('building_corner_shop', 6.72, 7.56),
    BuildingSpec('building_brick', 6.64, 6.82),
    BuildingSpec('building_turret', 6.72, 7.55),
    BuildingSpec('building_apartments', 6.72, 6.81),
    BuildingSpec('building_office', 7.8, 6.8),
    BuildingSpec('building_hotel', 9.88, 10.12),
    BuildingSpec('building_lofts', 9.7, 9.95),
    BuildingSpec('building_deco', 9.9, 10.6),
    BuildingSpec('building_diner', 13.1, 7.7, wide: 2),
    BuildingSpec('building_shops', 16.18, 6.81, wide: 2),
    BuildingSpec('building_cinema', 16.22, 9.86, wide: 2),
    BuildingSpec('building_skyscraper', 18.4, 14.45, wide: 2, deep: 2),
  ];

  /// Buildings that fit a single lot.
  static final small = [
    for (final b in buildings)
      if (b.wide == 1 && b.deep == 1) b,
  ];

  /// Buildings two lots wide and one deep.
  static final wide = [
    for (final b in buildings)
      if (b.wide == 2 && b.deep == 1) b,
  ];

  /// Buildings two lots wide and two deep.
  static final big = [
    for (final b in buildings)
      if (b.wide == 2 && b.deep == 2) b,
  ];

  /// Repainted variants per building and tree, besides the original.
  static const buildingVariants = 3;
  static const treeVariants = 3;

  /// The name of a repainted variant ([n] 0 is the original model).
  static String variant(String model, int n) => n == 0 ? model : '$model#$n';

  /// The variant of a tree with autumn leaves.
  static String autumn(String tree) => '$tree#a';

  static const _all = [
    ...roads,
    ...cars,
    ...otherVehicles,
    ...trees,
    'ground_sidewalk',
    'pickup_coin',
    'pickup_magnet',
    'pickup_double',
    'obstacle_barrier',
    'obstacle_cone',
  ];

  final Map<String, Node> _templates = {};

  /// One paint per colour of [carPaints], shared by every car.
  late final List<PhysicallyBasedMaterial> carPaintMaterials;

  // Lamps and windows that light up with the time of day.
  final List<PhysicallyBasedMaterial> headlights = [];
  final List<PhysicallyBasedMaterial> taillights = [];
  final List<PhysicallyBasedMaterial> indicators = [];
  final List<PhysicallyBasedMaterial> litWindows = [];
  final List<PhysicallyBasedMaterial> lamps = [];

  /// The roadworks' flashing lamps.
  final List<PhysicallyBasedMaterial> blinkLamps = [];

  /// Car and building glass, which reflect a city (see `cityReflections`).
  final List<PhysicallyBasedMaterial> carGlass = [];
  final List<PhysicallyBasedMaterial> buildingGlass = [];

  /// Loads every model, reporting progress from 0 to 1.
  Future<void> load({void Function(double progress)? onProgress}) async {
    final names = [..._all, for (final b in buildings) b.model];
    var done = 0;
    await Future.wait(
      names.map((name) async {
        _templates[name] = await loadScene('assets/models/$name.glb');
        done++;
        onProgress?.call(done / names.length);
      }),
    );
    _prepareCars();
    for (final m in _materials(_templates['obstacle_barrier']!)) {
      if (m.name == 'BlinkLamp') {
        blinkLamps.add(
          m..emissiveFactor = vm.Vector4(1.0, 0.62, 0.08, 1),
        );
      }
    }
    _prepareBuildings();
    _prepareTrees();
  }

  Node template(String name) => _templates[name]!;

  /// A fresh copy of a model. Meshes and materials are shared with the
  /// template.
  Node instance(String name) => _templates[name]!.clone();

  /// A copy of car [model] in paint [colour] (an index into [carPaints]).
  Node car(String model, int colour) => _swapped(_templates[model]!, {
    'Paint': carPaintMaterials[colour % carPaintMaterials.length],
  });

  // ---------- Materials ----------

  static Iterable<PhysicallyBasedMaterial> _materials(Node model) sync* {
    for (final n in model.meshNodes) {
      for (final p in n.mesh!.primitives) {
        final m = p.material;
        if (m is PhysicallyBasedMaterial) yield m;
      }
    }
  }

  /// A clone of [model] with the materials named in [swap] replaced.
  static Node _swapped(Node model, Map<String, Material> swap) {
    final copy = model.clone();
    for (final n in copy.meshNodes.toList()) {
      final mesh = n.mesh!;
      n.mesh = Mesh.primitives(
        primitives: [
          for (final p in mesh.primitives)
            MeshPrimitive(p.geometry, swap[p.material.name] ?? p.material),
        ],
      );
    }
    return copy;
  }

  /// A copy of [m] in another colour.
  static PhysicallyBasedMaterial _repainted(
    PhysicallyBasedMaterial m,
    vm.Vector3 colour,
  ) {
    return PhysicallyBasedMaterial()
      ..name = m.name
      ..baseColorFactor = vm.Vector4(colour.x, colour.y, colour.z, 1)
      ..metallicFactor = m.metallicFactor
      ..roughnessFactor = m.roughnessFactor;
  }

  void _prepareCars() {
    carPaintMaterials = [
      for (final c in carPaints)
        PhysicallyBasedMaterial()
          ..name = 'Paint'
          ..baseColorFactor = vm.Vector4(c.x, c.y, c.z, 1)
          ..metallicFactor = 0.25
          ..roughnessFactor = 0.35
          ..clearcoat = 1
          ..clearcoatRoughness = 0.1,
    ];
    for (final name in [...cars, ...otherVehicles]) {
      for (final m in _materials(_templates[name]!)) {
        switch (m.name) {
          case 'Window':
            // Dark tinted glass that mirrors its surroundings faintly (a
            // metal's base colour scales what it reflects).
            m
              ..baseColorFactor = vm.Vector4(0.15, 0.18, 0.22, 1)
              ..metallicFactor = 1
              ..roughnessFactor = 0.03;
            carGlass.add(m);
          case 'Headlight':
            headlights.add(m);
          case 'Taillight':
            taillights.add(m);
          case 'Indicator':
            indicators.add(m);
        }
      }
    }
  }

  void _prepareBuildings() {
    final rng = math.Random(7);
    for (final b in buildings) {
      final model = _templates[b.model]!;
      for (final m in _materials(model)) {
        switch (m.name) {
          // Unlit panes are dark mirrors; the lit ones look the same by day
          // and glow after dark.
          case 'Window':
            _darkGlass(m);
          case 'WindowLit':
            _darkGlass(m);
            litWindows.add(m);
          case 'Lamp':
            lamps.add(m);
        }
      }
      // Repaint the facades. The accent stays, so each variant keeps the
      // building's character.
      final walls = {
        for (final m in _materials(model))
          if (m.name == 'Wall' || m.name == 'WallB' || m.name == 'WallC')
            m.name: m,
      };
      for (var v = 1; v <= buildingVariants; v++) {
        final picks = [...facadePaints]..shuffle(rng);
        var i = 0;
        _templates[variant(b.model, v)] = _swapped(model, {
          for (final e in walls.entries) e.key: _repainted(e.value, picks[i++]),
        });
      }
    }
  }

  void _darkGlass(PhysicallyBasedMaterial m) {
    m
      ..baseColorFactor = vm.Vector4(0.12, 0.15, 0.19, 1)
      ..metallicFactor = 1
      ..roughnessFactor = 0.05;
    buildingGlass.add(m);
  }

  void _prepareTrees() {
    for (final t in trees) {
      final model = _templates[t]!;
      final leaves = _materials(model).firstWhere((m) => m.name == 'Leaves');
      for (var v = 1; v <= treeVariants; v++) {
        _templates[variant(t, v)] = _swapped(model, {
          'Leaves': _repainted(leaves, leafPaints[(v - 1) % leafPaints.length]),
        });
      }
      _templates[autumn(t)] = _swapped(model, {
        'Leaves': _repainted(leaves, autumnLeaves),
      });
    }
  }
}
