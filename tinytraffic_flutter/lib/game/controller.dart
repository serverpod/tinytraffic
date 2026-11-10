import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import 'package:serverpod_auth_idp_flutter/serverpod_auth_idp_flutter.dart';
import 'package:tinytraffic_client/tinytraffic_client.dart';
import 'package:tinytraffic_game/tinytraffic_game.dart';

import '../client.dart';
import 'assets.dart';
import 'audio.dart';
import 'haptics.dart';
import 'input.dart';
import 'look.dart';
import 'world.dart';

enum GamePhase { loading, title, countdown, playing, crashed, results }

/// Something worth a pop-up on the HUD.
enum HudCue { coin, nearMiss, magnet, doubleCoins, newBest, explosion }

class HudEvent {
  final HudCue cue;
  final int value;
  HudEvent(this.cue, [this.value = 0]);
}

/// Runs the game: title screen, countdown, the run itself, the crash and the
/// results, and talks to the server for runs and scores.
class GameController extends ChangeNotifier {
  final GameAssets assets = GameAssets();
  late final GameWorld world = GameWorld(assets)..onLift = _lifted;
  final GameAudio audio = GameAudio();
  final GameHaptics haptics = GameHaptics();
  final LaneInput lanes = LaneInput();

  GamePhase phase = GamePhase.loading;
  double loadProgress = 0;
  String? loadError;

  GameSimulation? _sim;
  Autopilot? _autopilot;
  final List<int> _inputs = [];
  double _acc = 0;
  double _phaseTime = 0;

  /// Seconds since the current phase began.
  double get phaseTime => _phaseTime;

  /// Seconds left in the countdown (3, 2, 1, then 0 for "GO").
  int countdown = 3;

  RunTicket? _ticket;
  String _fingerprint = '';

  /// Whether the current run counts for the leaderboard.
  bool get ranked => _ticket != null;

  // ---- HUD state ----
  int get score => _sim?.score ?? 0;
  double get speedKmh => (_sim?.car.speed ?? 0) * 3.6;
  double get distance => _sim?.car.distance ?? 0;
  int combo = 0;
  double _lastCoinTime = -10;

  /// Seconds of each power-up left.
  double get magnetLeft => (_sim?.magnetTicks ?? 0) * kDt;
  double get doubleLeft => (_sim?.doubleTicks ?? 0) * kDt;
  final StreamController<HudEvent> _hud = StreamController.broadcast();
  Stream<HudEvent> get hudEvents => _hud.stream;

  // ---- Server state ----
  bool online = false;
  PlayerSummary? summary;
  RunResult? result;
  bool submitting = false;
  int localBest = 0;
  bool localNewBest = false;
  CrashKind? lastCrash;

  // ---------- Startup ----------

  Future<void> boot() async {
    try {
      await Scene.initializeStaticResources();
      await assets.load(
        onProgress: (p) {
          loadProgress = p * 0.85;
          notifyListeners();
        },
      );
      await world.setUp();
      // Proves to the server that this app plays by the same rules.
      _fingerprint = simFingerprint();
      _startAttract();
      await world.prepareReflections();
      // Compile every shader and upload every model the title screen and a
      // run need while the loading bar is still up, so the game appears
      // whole instead of piece by piece.
      await world.scene.warmUp(
        [RenderView(camera: world.camera)],
        includeOffscreen: true,
        sliceBudget: const Duration(milliseconds: 12),
      );
      loadProgress = 1;
    } catch (e, st) {
      loadError = '$e';
      debugPrint('Loading failed: $e\n$st');
      notifyListeners();
      return;
    }
    // The crown changes lanes instead of scrolling (there is nothing to
    // scroll).
    _crown = _startCrown();
    _setPhase(GamePhase.title);
    // The music loops from here on, through every run.
    unawaited(audio.init().then((_) => audio.music('music')));
    unawaited(_connect());
  }

  Future<void> _connect() async {
    try {
      await client.auth.initialize();
      if (!client.auth.isAuthenticated) {
        final auth = AnonymousAuthController(client: client);
        await auth.login();
      }
      online = client.auth.isAuthenticated;
      if (online) await refreshScores();
    } catch (e) {
      debugPrint('Offline: $e');
      online = false;
    }
    notifyListeners();
  }

  Future<void> refreshScores() async {
    try {
      summary = await client.game.getSummary();
      online = true;
      if (summary!.bestScore > localBest) localBest = summary!.bestScore;
    } catch (e) {
      debugPrint('Could not load scores: $e');
    }
    notifyListeners();
  }

  // ---------- Phases ----------

  void _setPhase(GamePhase p) {
    phase = p;
    _phaseTime = 0;
    notifyListeners();
  }

  /// Starts the autopilot demo behind the title screen. [newLook] picks
  /// another car; the demo restarting after a crash keeps it.
  void _startAttract({bool newLook = true}) {
    final sim = GameSimulation(seed: math.Random().nextInt(1 << 30));
    _sim = sim;
    _autopilot = Autopilot(whim: 1);
    if (newLook) _pickLook();
    _attach(sim);
    world.attractBlend = 1;
    _acc = 0;
  }

  final math.Random _rng = math.Random();

  // The car and paint of the next run. The title screen shows them already.
  String _car = GameAssets.cars.first;
  int _paint = 0;

  /// Picks a different car and paint for the next run. `?car=van` on the
  /// web pins the car for testing.
  void _pickLook() {
    String? param(String key) {
      try {
        return Uri.base.queryParameters[key];
      } catch (_) {
        return null;
      }
    }

    final car = param('car');
    final cars = GameAssets.cars.where((c) => c != _car).toList();
    _car = GameAssets.cars.contains('car_$car')
        ? 'car_$car'
        : cars[_rng.nextInt(cars.length)];
    _paint =
        (_paint + 1 + _rng.nextInt(carPaints.length - 1)) % carPaints.length;
  }

  void _attach(GameSimulation sim) =>
      world.attach(sim, model: _car, colour: _paint);

  /// Whether [play] is getting a run ready (it waits for the audio engine
  /// and the server's ticket).
  bool _starting = false;

  /// Starts a run (from the title or results screen). Taps while one is
  /// getting ready are ignored.
  Future<void> play() async {
    if (_starting ||
        phase == GamePhase.countdown ||
        phase == GamePhase.playing) {
      return;
    }
    _starting = true;
    try {
      await _play();
    } finally {
      _starting = false;
    }
  }

  Future<void> _play() async {
    final from = phase;
    await audio.init();
    audio.play('ui_tap', volume: 0.5);
    haptics.play(HapticCue.tap);
    _ticket = null;
    result = null;
    localNewBest = false;
    combo = 0;
    lastCrash = null;

    // Ask the server for a seed; play unranked if it doesn't answer quickly.
    var seed = math.Random().nextInt(1 << 30);
    final bot = world.quality.bot;
    if (online && !bot) {
      try {
        final t = await client.game
            .startRun(_fingerprint)
            .timeout(const Duration(seconds: 4));
        if (t.simVersion == kSimVersion) {
          _ticket = t;
          seed = t.seed;
        }
      } catch (e) {
        debugPrint('Playing unranked: $e');
      }
    }
    // Left for another screen while waiting.
    if (phase != from) return;

    final sim = GameSimulation(seed: seed);
    _sim = sim;
    _autopilot = bot ? Autopilot() : null;
    _inputs.clear();
    _acc = 0;
    // From the title screen, drive the car it shows; after a run, the one
    // picked when the results came up.
    _attach(sim);
    world.attractBlend = 0;
    lanes.reset();
    // Forget crown turns from before the run.
    _readCrown();
    countdown = 3;
    audio.play('countdown_beep', volume: 0.6);
    haptics.play(HapticCue.countdown);
    _setPhase(GamePhase.countdown);
  }

  void backToTitle() {
    audio.play('ui_tap', volume: 0.5);
    _startAttract();
    audio.music('music');
    _setPhase(GamePhase.title);
  }

  // ---------- Frame ----------

  void tick(double dt) {
    if (phase == GamePhase.loading) return;
    // Long frames (a hidden tab) slow the game down rather than skip ahead.
    dt = math.min(dt, 0.1);
    _phaseTime += dt;
    final sim = _sim!;

    switch (phase) {
      case GamePhase.title:
        world.attractBlend = math.min(1, world.attractBlend + dt);
        _stepFixed(dt, () => _autopilot!.steer(sim));
        if (sim.isOver && _phaseTime > 0) {
          _attractRestart += dt;
          if (_attractRestart > explodeAt && !world.exploded) {
            world.explode();
            audio.play('explosion', volume: 0.3);
          }
          if (_attractRestart > 3.5) {
            _attractRestart = 0;
            _startAttract(newLook: false);
            return;
          }
        }
      case GamePhase.countdown:
        final left = 3 - _phaseTime.floor();
        if (left != countdown) {
          countdown = left;
          if (left > 0) {
            audio.play('countdown_beep', volume: 0.6);
            haptics.play(HapticCue.countdown);
          } else {
            audio.play('countdown_go', volume: 0.7);
            haptics.play(HapticCue.go);
            // Swipes during the countdown don't count.
            lanes.reset();
            _setPhase(GamePhase.playing);
          }
          notifyListeners();
        }
      case GamePhase.playing:
        // On the Apple Watch the Digital Crown changes lanes.
        lanes.crown(_readCrown());
        lanes.update(dt);
        _stepFixed(dt, () {
          final pilot = _autopilot;
          final s = pilot != null ? pilot.steer(sim) : lanes.take();
          _inputs.add(s);
          return s;
        });
        audio.tyres(slide: world.slide, on: !sim.isOver);
      case GamePhase.crashed:
        // Slow motion while the car flips, then it blows up.
        if (_phaseTime >= explodeAt && !world.exploded) {
          world.explode();
          // The blast stands out over the music; other effects sit under it.
          audio.play('explosion', volume: 2);
          haptics.play(HapticCue.explosion);
          _hud.add(HudEvent(HudCue.explosion));
        }
        dt *= _phaseTime < explodeAt
            ? 0.4
            : (_phaseTime < explodeAt + 0.45 ? 0.55 : 1);
        if (_phaseTime > 3.2) {
          _setPhase(GamePhase.results);
          _pickLook();
        }
      case GamePhase.results:
      case GamePhase.loading:
        break;
    }
    world.update(dt, (_acc / kDt).clamp(0.0, 1.0));
  }

  double _attractRestart = 0;

  /// Whether the Digital Crown is available to change lanes with.
  bool _crown = false;

  /// Takes the crown as a raw input on the Apple Watch. Returns false when it
  /// is unavailable: not a watch, or a build without flutter_watchos's native
  /// code linked in (then swipes and taps still work).
  static bool _startCrown() {
    if (!FlutterWatchosPlatform.isWatch) return false;
    try {
      WatchCrown.instance.enable();
      return true;
    } catch (e) {
      debugPrint('Digital Crown unavailable, lanes change by touch only: $e');
      return false;
    }
  }

  /// Crown rotation since the last call, in flutter_watchos crown units
  /// (SwiftUI crown-rotation values in logical points, not turns; a full
  /// turn is 240).
  double _readCrown() => _crown ? WatchCrown.instance.drain() : 0;

  /// Seconds after a crash at which the car explodes.
  static const double explodeAt = 0.9;

  void _stepFixed(double dt, int Function() input) {
    final sim = _sim!;
    _acc += dt;
    var steps = 0;
    while (_acc >= kDt && steps < 8) {
      _acc -= kDt;
      steps++;
      if (sim.isOver) {
        _acc = 0;
        break;
      }
      sim.step(input());
      _handleEvents(sim);
    }
  }

  void _handleEvents(GameSimulation sim) {
    final live = phase == GamePhase.playing;
    for (final e in sim.events) {
      switch (e) {
        case CoinCollected(:final coin, :final value):
          world.coinCollected(coin, doubled: value > 1);
          if (!live) break;
          final t = sim.time;
          combo = t - _lastCoinTime < 1.2 ? combo + 1 : 1;
          _lastCoinTime = t;
          audio.play(combo >= 4 ? 'coin_combo' : 'coin', volume: 0.45);
          _hud.add(HudEvent(HudCue.coin, combo));
          haptics.play(HapticCue.coin);
        case PowerUpCollected(:final pickup, :final kind):
          world.powerUpCollected(pickup);
          if (!live) break;
          audio.play('countdown_go', volume: 0.7);
          audio.play('coin_combo', volume: 0.5);
          haptics.play(HapticCue.powerUp);
          _hud.add(
            HudEvent(
              kind == PowerUp.magnet ? HudCue.magnet : HudCue.doubleCoins,
            ),
          );
        case NearMiss(:final car, :final bonus):
          world.nearMiss(car);
          if (!live) break;
          audio.play('whoosh', volume: 0.7);
          audio.play('coin_combo', volume: 0.35);
          haptics.play(HapticCue.nearMiss);
          _hud.add(HudEvent(HudCue.nearMiss, bonus));
        case LaneChanged(:final direction):
          world.laneChanged(direction);
          if (!live) break;
          audio.play('whoosh', volume: 0.22);
          haptics.play(HapticCue.lane);
        case KerbBumped(:final direction):
          world.kerbBumped(direction);
          if (!live) break;
          audio.play('crash', volume: 0.22);
          haptics.play(HapticCue.kerb);
        case Crashed(:final kind, :final other):
          world.crashed(kind, other);
          if (!live) {
            audio.play('crash', volume: 0.25);
            break;
          }
          lastCrash = kind;
          audio.play('crash', volume: 0.9);
          haptics.play(HapticCue.crash);
          audio.tyres(slide: 0, on: false);
          _onRunOver();
      }
    }
    sim.events.clear();
    if (live) notifyListeners();
  }

  /// The car lifted onto two wheels in a corner (see [GameWorld.onLift]).
  void _lifted() {
    if (phase != GamePhase.playing) return;
    audio.play('tip_warning', volume: 0.35);
    haptics.play(HapticCue.lift);
  }

  void _onRunOver() {
    _setPhase(GamePhase.crashed);
    final sim = _sim!;
    if (sim.score > localBest) {
      localNewBest = localBest > 0 || sim.score > 0;
      localBest = sim.score;
    }
    Future.delayed(const Duration(milliseconds: 2900), () {
      audio.play(localNewBest ? 'new_record' : 'game_over', volume: 0.6);
      if (localNewBest) haptics.play(HapticCue.newBest);
    });
    unawaited(_submit());
  }

  Future<void> _submit() async {
    final ticket = _ticket;
    final sim = _sim!;
    if (ticket == null) return;
    submitting = true;
    notifyListeners();
    try {
      final log = InputLog.encode(_inputs);
      result = await client.game.submitRun(
        ticket.runId,
        ByteData.sublistView(log),
        sim.score,
      );
      if (result!.isNewBest) _hud.add(HudEvent(HudCue.newBest));
      unawaited(refreshScores());
    } catch (e) {
      // Never shown to the player; the run just isn't placed.
      debugPrint('Submit failed: $e');
    }
    submitting = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _hud.close();
    super.dispose();
  }
}
