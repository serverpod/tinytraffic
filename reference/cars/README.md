# Cars

Seven toy-style cars modelled after the reference sheet: `car_sedan`, `car_coupe`, `car_hatchback`,
`car_suv`, `car_pickup`, `car_van`, `car_wagon` (`.glb`).

They are generated, not hand-modelled: `build_cars.py` builds every car in Blender from the
measurements in its `SPECS` list (side profiles, cabin, glass layout, lights, wheels), so change a
spec and rebuild instead of editing the GLBs.

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -P build_cars.py
```

Add car names after `--` to build only those, and `--render DIR` to also render front 3/4, side
and rear 3/4 views (top for the SUV) framed like the reference sheet; `review.jpg` shows them
next to the reference. The build prints a warning if a rounded outline folds over itself (a
profile corner tighter than the rounding); fix the spec when that happens.

## Conventions

Same as `../game-assets`: 1 unit = 1 m, +Y up, the car faces **+Z**, the pivot is the centre of
the footprint resting on `y = 0`.

- Every car is exactly **4.5 m** long, bumpers included, and 2.0 m wide (1.95 m body).
- The glTF has no extensions and no textures: positions, normals, 16-bit indices and
  metallic-roughness materials.

| Car | Height | Wheelbase | Wheel radius | Triangles | File |
| --- | --- | --- | --- | --- | --- |
| sedan | 1.58 m | 2.77 m | 0.345 m | 4,788 | 90 KB |
| coupe | 1.61 m | 2.78 m | 0.345 m | 4,496 | 81 KB |
| hatchback | 1.70 m | 2.83 m | 0.356 m | 4,602 | 84 KB |
| suv | 1.82 m | 2.79 m | 0.390 m | 5,694 | 112 KB |
| pickup | 1.74 m | 2.87 m | 0.380 m | 5,244 | 94 KB |
| van | 1.85 m | 2.85 m | 0.360 m | 4,942 | 96 KB |
| wagon | 1.63 m | 2.82 m | 0.350 m | 4,922 | 94 KB |

Triangles include all four wheels (396 each); the track is 1.59 m for all of them. The SUV's
height includes its roof rails.

## Nodes

```
car_<name>                 root; glTF extras: length, wheelRadius, wheelbase, track,
│                          paintMaterial ("Paint"), windowMaterial ("Window"),
│                          headlightMaterial, indicatorMaterial, taillightMaterial
├── body                   one mesh, one primitive per material
├── wheel_front_left       origin on the hub, axle along X (left = +X)
├── wheel_front_right
├── wheel_rear_left
└── wheel_rear_right
```

The four wheel nodes share one mesh. Because each wheel's origin is its hub, it can be posed
in place: steer by rotating the front wheels about their local Y, then spin about local X by
`distance / wheelRadius` radians (rotation order Y then X). The names contain `wheel` and
`front`, which is what `CarView` in the app looks for.

## Materials

| Material | Use |
| --- | --- |
| `Paint` | Body colour. Recolour this one per car. |
| `Window` | All glass (windscreen, side and rear windows), plain dark tint with no reflection stripes. Swap it for a transparent or reflective glass material. |
| `Bumper` | Bumpers (and the SUV's sill cladding): grey, black, chrome-grey (pickup) or dark red (wagon). |
| `Trim` | Black plastic: handles, wheel wells, roof rails, seams. |
| `Grille` | Grille. |
| `Headlight` | Front lamps (white). |
| `Indicator` | Orange front indicators beside the headlights (all but the pickup). |
| `Taillight` | Rear lamps (red). |
| `Tire`, `Rim` | Wheels. |

The lamp materials hold nothing else, so making them emissive (or swapping them for brake or
reversing lights) lights exactly the lamps. Their names are also in the root's extras; a car
without indicators has no `indicatorMaterial`.

## Viewer

`index.html` loads all seven with three.js and drives them the way a game would (paint and glass
per car, steering, wheel spin):

```bash
python3 -m http.server 8643
```

then open <http://localhost:8643/>.

## Not done yet

These aren't in `../game-assets` or the app yet. To use them there, add them to the pipeline
and note that `world.dart` repaints traffic by matching the old pack's material names
(`LightBlue`, `White`), which would become `Paint`.
