import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/controller.dart';
import 'kit.dart';
import 'info_dialog.dart';
import 'title_screen.dart';

class ResultsOverlay extends StatelessWidget {
  final GameController game;
  const ResultsOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final u = unitOf(context);
    final tiny = isTiny(context);
    final overlay = ColoredBox(
      color: const Color(0x8814213D),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16 * u),
            child: ListenableBuilder(
              listenable: game,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Reveal(
                    delay: 0,
                    child: StrokeText(
                      game.result?.isNewBest == true || game.localNewBest
                          ? 'NEW BEST!'
                          : 'GAME OVER',
                      style: display(
                        (tiny ? 34 : 54) * u,
                        color:
                            game.result?.isNewBest == true || game.localNewBest
                            ? Palette.coin
                            : Colors.white,
                      ),
                      strokeWidth: 11 * u,
                      shadow: Offset(0, 6 * u),
                    ),
                  ),
                  SizedBox(height: 14 * u),
                  _Reveal(
                    delay: 0.15,
                    child: Sticker(
                      tilt: -0.025,
                      padding: EdgeInsets.fromLTRB(
                        22 * u,
                        16 * u,
                        22 * u,
                        18 * u,
                      ),
                      radius: 26 * u,
                      border: 4 * u,
                      depth: 7 * u,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _CountUp(score: game.score, size: tiny ? 0.7 : 1),
                          SizedBox(height: (tiny ? 8 : 2) * u),
                          Text(
                            'COINS',
                            style: display(
                              (tiny ? 24 : 17) * u,
                              color: Palette.ink.withValues(alpha: 0.6),
                            ),
                          ),
                          SizedBox(height: 12 * u),
                          _Placing(game: game),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 22 * u),
                  _Reveal(
                    delay: 0.3,
                    child: ChunkyButton(
                      label: 'AGAIN!',
                      onTap: game.play,
                      size: u * (tiny ? 1.1 : 1.05),
                      color: Palette.mint,
                      pulse: true,
                    ),
                  ),
                  if (!tiny) ...[
                    SizedBox(height: 14 * u),
                    _Reveal(
                      delay: 0.4,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RoundButton(
                            icon: Icons.home_rounded,
                            size: u,
                            onTap: game.backToTitle,
                          ),
                          SizedBox(width: 16 * u),
                          MuteButton(game: game),
                          SizedBox(width: 16 * u),
                          RoundButton(
                            icon: Icons.info_outline_rounded,
                            size: u,
                            color: Palette.coin,
                            onTap: () => showInfo(context, game),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!tiny) return overlay;
    // On a watch-sized screen the buttons are small, so tapping anywhere
    // plays again (after a moment, so a tap still in progress from the run
    // doesn't restart it straight away); only the sound toggle sits in the
    // corner (the clock has the other one).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (game.phaseTime > 0.8) game.play();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          overlay,
          // On the clock's line (the watch draws it top right, in the
          // safe area's top inset), far enough in to clear the rounded
          // corner.
          Positioned(
            left: 24,
            top: 10,
            child: MuteButton(game: game, size: 1.15),
          ),
        ],
      ),
    );
  }
}

/// Where this run places among everybody's best scores: "TOP 13% IN THE
/// WORLD", the rank, and, when an earlier run was better, that best and its
/// placing.
class _Placing extends StatelessWidget {
  final GameController game;
  const _Placing({required this.game});

  @override
  Widget build(BuildContext context) {
    final u = unitOf(context);
    final tiny = isTiny(context);
    final r = game.result;
    // Problems with ranking are never shown; there is just no placing.
    if (!game.ranked) return const SizedBox.shrink();
    if (game.submitting) {
      return SizedBox(
        width: 22 * u,
        height: 22 * u,
        child: const CircularProgressIndicator(
          strokeWidth: 3,
          color: Palette.blue,
        ),
      );
    }
    if (r == null) return const SizedBox.shrink();
    final small = body(15 * u, color: Palette.ink.withValues(alpha: 0.7));
    final best = game.summary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: BoxConstraints(maxWidth: 300 * u),
          padding: EdgeInsets.symmetric(horizontal: 14 * u, vertical: 6 * u),
          decoration: BoxDecoration(
            color: Palette.blue,
            borderRadius: BorderRadius.circular(12 * u),
            border: Border.all(color: Palette.ink, width: 3 * u),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              placingLabel(r.rank, r.topPercent, short: tiny),
              style: display((tiny ? 32 : 24) * u),
            ),
          ),
        ),
        // The watch keeps to what reads at a glance: the placing and the
        // best.
        if (!tiny) ...[
          SizedBox(height: 6 * u),
          Text(
            r.totalPlayers > 1
                ? '#${r.rank} of ${r.totalPlayers} drivers'
                : 'The first driver in town!',
            style: small,
          ),
        ],
        // A better run before this one: where that one places.
        if (r.bestScore > r.score)
          Padding(
            padding: EdgeInsets.only(top: 6 * u),
            child: tiny
                ? Text(
                    'BEST ${r.bestScore}',
                    style: display(30 * u, color: Palette.ink),
                  )
                : Text(
                    best != null &&
                            best.rank > 0 &&
                            best.bestScore == r.bestScore
                        ? 'Your best: ${r.bestScore} '
                              '(${placingLabel(best.rank, best.topPercent, short: true).toLowerCase()})'
                        : 'Your best: ${r.bestScore}',
                    style: body(15 * u),
                  ),
          ),
      ],
    );
  }
}

class _CountUp extends StatelessWidget {
  final int score;
  final double size;
  const _CountUp({required this.score, this.size = 1});

  @override
  Widget build(BuildContext context) {
    final u = unitOf(context) * size;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score.toDouble()),
      duration: Duration(milliseconds: 400 + math.min(score, 200) * 6),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StrokeText(
            '${v.round()}',
            style: display(72 * u, color: Palette.coin),
            stroke: Colors.black,
            strokeWidth: 11 * u,
            shadow: Offset(0, 6 * u),
          ),
        ],
      ),
    );
  }
}

/// Pops a child in after a delay (in seconds).
class _Reveal extends StatelessWidget {
  final double delay;
  final Widget child;
  const _Reveal({required this.delay, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 600 + (delay * 1000).round()),
      builder: (context, t, child) {
        final local = ((t * (0.6 + delay) - delay) / 0.6).clamp(0.0, 1.0);
        final s = Curves.elasticOut.transform(local);
        return Opacity(
          opacity: local.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.4 + s * 0.6, child: child),
        );
      },
      child: child,
    );
  }
}
