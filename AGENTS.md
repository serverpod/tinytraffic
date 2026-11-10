# Flutter & Serverpod project

This project is a Flutter app (frontend) backed by a Serverpod server (backend). Always build the app's backend with Serverpod.
Build for multiple users, use Serverpod's built-in authentication, which is already set up in `lib/server.dart`.

The user starts the server and Flutter app with `serverpod start`. There is no need to check if the server is running: make the changes and call the `serverpod` MCP tools as needed. If the server is not running, an informative error message will be received from the MCP server. Then STOP and ask the user to start it. NEVER start the server yourself. The Flutter app is started along with it, or can be launched from the MCP tool `spawn_flutter_app`.

While running, `serverpod start` watches for file changes to run incremental code generation and hot reload both the server and the Flutter app.

Calling `serverpod generate` directly is not needed, but might be useful to troubleshoot when an incremental generation fails.

ALWAYS use the MCP server instead of the command line. Use the MCP server to:

- `create_migration` and `apply_migrations` for database (after you change data models).
- `create_repair_migration` if the database has drifted out of sync with the migrations.
- `tail_server_logs` to read logs from the server.
- `tail_flutter_logs` to read the raw stdout/stderr of the Flutter app.
- `hot_reload` / `hot_restart` to reload or restart the server and the Flutter app. ALWAYS call `hot_restart` after doing changes in the Flutter app that may not work with normal hot reload (which is automatically applied).
- `spawn_flutter_app` to start a Flutter app declared under `serverpod: flutter_apps:` in the server `pubspec.yaml`.
- `get_flutter_app_dtd` (Dart tooling daemon) for connecting to the app through the `dart` MCP.

NEVER edit generated code. The server's `lib/src/generated/` directory and the whole `tinytraffic_client` package are rewritten by the code generator. Change the `.spy.yaml` models, the endpoints, or `lib/server.dart` instead.

Migrations are a narrow exception: the `migration.sql` of a generated migration MAY be edited by hand when the generated SQL would lose data — to add a data transformation, or to reach a destructive change through non-destructive steps. Never touch the other files in the migration directory, and keep the schema the SQL ends up with identical to `definition.sql` — new databases are created from that file and never run `migration.sql`.

Only when the server cannot be started at all, fall back to the CLI in the server package:

- `serverpod generate` to regenerate the client and the generated server code.
- `serverpod create-migration` after changing a model with a `table` (add `--force` for destructive changes). It only writes the migration; `serverpod start` applies pending migrations when it boots the server.

Tests need no Docker. `config/test.yaml` sets `database.dataPath`, so Serverpod starts and manages the test database (an embedded PostgreSQL) itself, and the project's `docker-compose.yaml` is not used for it. Just run `dart test` in the server package.

Checklist after doing changes, in this order:

- `dart analyze` (CLI)
- `dart format` (CLI)
- `create_migration` and `apply_migrations` (MCP - only if necessary)
- Do `serverpod` MCP `hot_restart` if required (hot reload is done automatically). Will also hot restart Flutter app
- Run tests, if applicable (`dart test` in the server package)
- Check `serverpod` MCP `tail_server_logs` and `tail_flutter_logs` for any issues.

If the user asks you to test the app:

1. Use `get_flutter_app_dtd` (`serverpod` MCP) to get the Flutter app's DTD
2. Pass the DTD to `connect_dart_tooling_daemon` (`dart` MCP) to connect to the app
3. Use `flutter_driver` (`dart` MCP) to navigate through the app

The app is launched from `tinytraffic_flutter/lib/driver.dart`, which starts the Flutter driver extension with text entry emulation turned off so the app stays usable by hand. To let the driver type, set `enableTextEntryEmulation: true` there and `hot_restart` the app.

## The app: Tiny Traffic

An arcade 3D endless lane runner on a city course with sharp corners. The road has three lanes; the
car accelerates and follows the road by itself (up on two wheels in the corners), and the player only
changes lanes: swipe left or right anywhere, tap the left or right half of the screen, the arrow
keys, or turn the digital crown (`LaneInput.crown`: every `crownStep`, 48 crown units, a fifth of a
turn, changes one lane; a full turn is 240 units). They collect coins (the score) and
dodge rows of slow traffic, buses and roadworks (barriers and big cones that stand still), and, after
half a minute or so, cars coming the other way; bumping the kerb is harmless, hitting anything ends
the run. Dodging out of a car's lane at the last moment is a close call (+2 coins), and
there are two power-ups: a magnet (pulls in the coins of every lane) and double coins.
Built with flutter_scene (3D) and played on the web first; it must also work on watch-sized screens.
It is always daytime (`TimeOfDay.day`), and it always draws with the fast graphics the watch needs
(`Quality.lite`: no bloom, vignette, glass reflections or explosion light, a third of the particles).
On the watch the renderer aims for 30 fps and keeps the render scale at 0.75 or more (aiming for 60
halved the resolution), and the camera comes in closer with the car low on the screen.

Packages:

- `tinytraffic_game/`: pure-Dart, **deterministic** simulation shared by app and server: course
  generation (`track.dart`), lanes, traffic rows, coins and power-ups (`simulation.dart`), all
  constants (`tuning.dart`), input log encoding and replay (`replay.dart`; one input per tick: -1, 0
  or 1 for a lane change), and an autopilot used for the title screen and tests. Distances run along
  the road's centre line, and the player's speed depends only on the time, so traffic rows are laid
  out knowing when the player reaches them: every row leaves a free lane the player can reach from
  any lane free in the row before (`_planRow`). On corners the lanes turn together (outer faster,
  inner slower), which squeezes the inner lane. Collisions are tested along the lanes (side by side
  by lane offset, front to back by the distance along the lane), so long vehicles bend with the road. It must give bit-identical results on the VM and on the web: never use
  `dart:math` trig/pow/exp or 32-bit multiplies in the simulation (use `det_math.dart` and `Rng`).
  Bump `kSimVersion` whenever simulation behaviour changes. `simFingerprint()` summarises a
  scripted autopilot run; the client sends it to `startRun` and the server refuses ranked runs from
  a client whose simulation differs (logged as "Client simulation differs"; the run gets a ticket but is
  quietly left out). Note that the
  `serverpod start` watcher only watches the server package, and its incremental compiler doesn't
  pick up changes to `tinytraffic_game` even on `hot_restart`: restart `serverpod start` after
  changing the simulation (the server logs "Client simulation differs" while it is out of date). `dart test` (and `dart test -p chrome -n
  golden`) checks the golden values; regenerate them deliberately when the rules change.
- `tinytraffic_server/`: anonymous device accounts (`AnonymousIdpEndpoint`) and `GameEndpoint`:
  `startRun` hands out a server-chosen seed; `submitRun` takes the full steering input log, replays it
  with the shared simulation and only accepts the replayed score (plus wall-clock, single-use and
  ownership checks). Every run's input log is stored in `game_run.inputLog` for later replays.
  Failures are never shown in the app: cheats (score/replay mismatch, too fast, bad log, someone
  else's run) shadow-ban the player (`player_stats.shadowBanned`, with `banReason`; they still see
  their own scores but nobody else's placings count them); innocent failures (simulation fingerprint
  mismatch, expired or repeated submission) just leave the run out. `PlayerStats` holds bests; placings are "top X%" of all players' bests.
  They never count through the players: `score_count` holds how many players have each best
  (those with a run who aren't shadow-banned), changed in the same transaction as every new best or
  ban (`GameEndpoint._saveStats`, an atomic upsert), so a placing sums a few rows per distinct score.
  The server rebuilds it from `player_stats` once at startup (`rebuildScoreCounts`); change
  `player_stats` by hand (lifting a ban) and the next restart puts the counts right.
- `tinytraffic_flutter/`: `lib/game/` (controller state machine, world renderer, city dressing,
  car rig, particles, audio (`audio.dart`: the browser's Web Audio API on the web, audioplayers on
  devices, with `audioplayers_watchos` and `path_provider_watchos` on the watch (flutter_soloud
  has no watch build, so it was silent there); sounds played as they are, with no pitch or speed
  changes; effects at `GameAudio.effects` of their volume under the music; it all goes quiet
  while the page or app is hidden, since mobile browsers keep a page playing in the background), lane input, `look.dart`: the daylight and paint
  palettes, `quality.dart`: the watch's lighter budget) and `lib/ui/` (toy-box sticker UI:
  title, HUD, results, info dialog; sizes scale with `unitOf(context)`). The body roll, the
  two-wheel tilt in corners and the swerve of lane changes are only drawn (`GameWorld._posePlayer`).
  Running power-ups spin in the HUD's top bar: the HUD reserves the slots (`GameWorld.badgeSlots`)
  and the 3D view draws the models there, just in front of the camera (`_poseBadges`).

Testing on the web: URL query parameters tune and debug the client, e.g. `?fps=1` (frame rate
counter), `?bot=1` (the autopilot drives; such runs are never ranked), `?scale=0.6`, `?shadows=0`
(the soft shadows under cars and trees; there is no shadow map), `?bloom=0`, `?aa=fxaa`,
`?adaptive=0` and `?car=van` (pin the player's car). The mouse wheel
stands in for a watch's digital crown (a notch is one lane change).
`dart run tool/balance.dart [sharp]` in `tinytraffic_game` prints autopilot survival stats for tuning
(`sharp`: a far-sighted driver that should get through nearly every row).
Note the debug (DDC) web build is much slower than a release build; judge performance in release.

App icon: `reference/TinyTrafficIcon.icon` (Icon Composer) is the source. Copies sit next to the
asset catalogs in `parked/ios/Runner/`, `macos/Runner/`, `watchos/Runner/` and `watchos/HostApp/`, and every
target's `ASSETCATALOG_COMPILER_APPICON_NAME` is `TinyTrafficIcon`. The web favicon and
`web/icons/Icon-*.png` are rendered from it with Xcode's `ictool` (`Icon Composer.app/Contents/
Executables/ictool <icon> --export-image ... --platform iOS`); the maskable ones are the source PNG
cropped full bleed the way `icon.json` positions its layer on the 1024 pt canvas (`scale`, and
`translation-in-points` with y pointing down: the canvas centre is the image point
(w/2 - tx/scale, h/2 - ty/scale)).

Apple Watch: built with `flutter-watchos` (`/Users/viktor/Projects/flutter-watchos`). It ships
watch-only (`WKWatchOnly`, archived from `watchos/Runner.xcodeproj` inside the `HostApp` container,
bundle ids `com.viktorious.tinytraffic` and `.watchkitapp`). flutter-watchos switches the watch app to
an iPhone companion whenever `tinytraffic_flutter/ios/` exists, so the iOS app is parked in
`parked/ios/`; move it back only to ship an iPhone app with the watch app inside it. Needs
`flutter config --enable-dart-data-assets`. `hook/build.dart` also builds flutter_scene's engine
shaders into the app's tree, and `pubspec.yaml` lists `flutter_scene_generated/metal_ios/` for
`macos` too, because the watch build filters assets as macOS. flutter-watchos only finds plugins in
a pub workspace with the local fix in `/Users/viktor/Projects/flutter-watchos/lib/watchos_plugins.dart`
(it reads the workspace root's `package_config.json`). Without it `flutter_watchos` (crown, haptics)
isn't linked and the app falls back to touch steering: check with `nm -gU build/watchos/
Release-watchos/Runner.app/Runner | grep flutter_watchos_crown`. On the watch, login tokens are stored in files (`lib/platform/`) and fonts are bundled.

Assets: models in `tinytraffic_flutter/assets/models/` are copies (built by the flutter_scene hook,
loaded with `loadScene`) of `reference/cars/`, `reference/trees/` and `reference/buildings/` (see
their READMEs for the material names the game recolours and lights), and of `reference/game-assets/`
for the roads, sidewalk, coin, power-ups and obstacles. Every model is generated by the project's own
scripts, so no third-party credit is needed. The
three-lane road tiles are generated by `reference/pipeline/roads.mjs` (`node roads.mjs`, then copy
`road_*.glb` over): one mesh each, coloured per vertex. The coin (`pickup_coin`, tinted gold
by the game), the power-ups (`pickup_magnet`, `pickup_double`), the bus (`vehicle_bus`, following the cars' node and material contract) and the
roadworks (`obstacle_barrier`, whose `BlinkLamp` material flashes, and `obstacle_cone`) come from
`reference/pipeline/props.mjs` the same way. Every run picks a car model and a paint from `carPaints`; buildings and trees come in repainted
variants (`<model>#<n>`, made in `GameAssets`), and the city planner also places the 2×1 and 2×2
buildings. `GameController.boot` warms up every shader before leaving the loading screen. Sound effects in `assets/audio/` are generated
by `tinytraffic_flutter/tool/synth_audio.dart`; the music is `reference/music/music.m4a`, shipped as
`assets/audio/music.mp3` (`ffmpeg -i music.m4a -map 0:a -map_metadata -1 -codec:a libmp3lame
-b:a 112k -ar 44100 music.mp3`: MP3 plays in every browser and on the watch).
