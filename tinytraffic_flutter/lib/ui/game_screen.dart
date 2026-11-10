import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';

import '../game/controller.dart';
import '../game/input.dart';
import 'hud.dart';
import 'kit.dart';
import 'results.dart';
import 'title_screen.dart';

/// The whole game: the 3D view, changing lanes by swiping or tapping
/// anywhere (or with the arrow keys), and the overlays for each phase.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final GameController game = GameController();

  @override
  void initState() {
    super.initState();
    game.addListener(_changed);
    game.boot();
  }

  GamePhase? _lastPhase;

  void _changed() {
    // Only rebuild the tree on phase changes; overlays listen themselves.
    if (game.phase != _lastPhase) {
      _lastPhase = game.phase;
      setState(() {});
    }
  }

  @override
  void dispose() {
    game.removeListener(_changed);
    game.dispose();
    super.dispose();
  }

  /// Arrow keys and A/D change lanes.
  KeyEventResult _key(KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    game.audio.unlock();
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
      game.lanes.push(-1);
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD) {
      game.lanes.push(1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.sky,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          game.lanes.layout(size.width);
          game.world.aspect = size.width / size.height;
          game.world.shortestSide = size.shortestSide;
          final phase = game.phase;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (phase != GamePhase.loading)
                Focus(
                  autofocus: true,
                  onKeyEvent: (node, e) => _key(e),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) {
                      // Browsers only let audio start from a tap.
                      game.audio.unlock();
                      game.lanes.down(
                        e.pointer,
                        e.localPosition.dx,
                        e.localPosition.dy,
                      );
                    },
                    onPointerMove: (e) => game.lanes.move(
                      e.pointer,
                      e.localPosition.dx,
                      e.localPosition.dy,
                    ),
                    onPointerUp: (e) => game.lanes.up(
                      e.pointer,
                      e.localPosition.dx,
                      e.localPosition.dy,
                    ),
                    onPointerCancel: (e) => game.lanes.cancel(e.pointer),
                    // A mouse wheel stands in for a watch's digital crown:
                    // a notch (100) is one lane change.
                    onPointerSignal: (e) {
                      if (e is PointerScrollEvent) {
                        game.lanes.crown(
                          e.scrollDelta.dy / 100 * LaneInput.crownStep,
                        );
                      }
                    },
                    child: SceneView(
                      game.world.scene,
                      camera: game.world.camera,
                      onTick: (elapsed, dt) => game.tick(dt),
                    ),
                  ),
                ),
              if (phase == GamePhase.loading) LoadingOverlay(game: game),
              if (phase == GamePhase.title) TitleOverlay(game: game),
              if (phase == GamePhase.countdown ||
                  phase == GamePhase.playing ||
                  phase == GamePhase.crashed)
                IgnorePointer(child: Hud(game: game)),
              if (phase == GamePhase.results) ResultsOverlay(game: game),
              if (game.world.quality.showFps)
                const Positioned(left: 4, bottom: 4, child: FpsCounter()),
            ],
          );
        },
      ),
    );
  }
}

class LoadingOverlay extends StatelessWidget {
  final GameController game;
  const LoadingOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final u = unitOf(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Palette.blue, Palette.sky],
        ),
      ),
      child: Center(
        child: ListenableBuilder(
          listenable: game,
          builder: (context, _) {
            if (game.loadError != null) {
              return Padding(
                padding: EdgeInsets.all(24 * u),
                child: Sticker(
                  child: Text(
                    'Could not start the engine.\n${game.loadError}',
                    style: body(16 * u),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Logo(),
                SizedBox(height: 28 * u),
                Container(
                  width: 220 * u,
                  height: 22 * u,
                  decoration: BoxDecoration(
                    color: Palette.cream,
                    borderRadius: BorderRadius.circular(12 * u),
                    border: Border.all(color: Palette.ink, width: 3.5 * u),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: game.loadProgress.clamp(0.04, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Palette.coin,
                        borderRadius: BorderRadius.circular(8 * u),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 12 * u),
                Text(
                  'Warming up the engine…',
                  style: body(15 * u, color: Palette.ink),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A small frame rate readout, shown with `?fps=1`.
class FpsCounter extends StatefulWidget {
  const FpsCounter({super.key});

  @override
  State<FpsCounter> createState() => _FpsCounterState();
}

class _FpsCounterState extends State<FpsCounter>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _frames = 0;
  Duration _last = Duration.zero;
  double _fps = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _frames++;
      final dt = elapsed - _last;
      if (dt.inMilliseconds >= 500) {
        setState(() => _fps = _frames * 1000 / dt.inMilliseconds);
        _frames = 0;
        _last = elapsed;
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      color: Colors.black54,
      child: Text(
        '${_fps.toStringAsFixed(0)} fps',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
