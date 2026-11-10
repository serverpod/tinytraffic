import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/controller.dart';
import 'kit.dart';
import 'info_dialog.dart';

/// The wobbly game logo.
class Logo extends StatefulWidget {
  final double scale;
  const Logo({super.key, this.scale = 1});

  @override
  State<Logo> createState() => _LogoState();
}

class _LogoState extends State<Logo> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = unitOf(context) * widget.scale;
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final a = _t.value * math.pi * 2;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: -0.07 + math.sin(a * 2) * 0.03,
              child: StrokeText(
                'TINY',
                style: display(58 * u, color: Palette.coin),
                strokeWidth: 12 * u,
                shadow: Offset(0, 7 * u),
              ),
            ),
            Transform.translate(
              offset: Offset(0, -6 * u),
              child: Transform.rotate(
                angle: 0.04 + math.sin(a * 2 + 1.3) * 0.035,
                child: StrokeText(
                  'TRAFFIC',
                  style: display(76 * u, color: Colors.white),
                  strokeWidth: 14 * u,
                  shadow: Offset(0, 8 * u),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class TitleOverlay extends StatelessWidget {
  final GameController game;
  const TitleOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final u = unitOf(context);
    final tiny = isTiny(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: game.play,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Soften the top and bottom so the text reads over the city.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66000E33),
                  Color(0x00000E33),
                  Color(0x00000E33),
                  Color(0x88000E33),
                ],
                stops: [0, 0.35, 0.6, 1],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                SizedBox(height: (tiny ? 10 : 36) * u),
                Logo(scale: tiny ? 0.8 : 1),
                SizedBox(height: 14 * u),
                ListenableBuilder(
                  listenable: game,
                  builder: (context, _) => _BestChip(game: game),
                ),
                const Spacer(),
                if (!tiny) const _SteerHint(),
                SizedBox(height: 18 * u),
                ChunkyButton(
                  label: 'DRIVE!',
                  onTap: game.play,
                  size: u * (tiny ? 1.25 : 1.1),
                  pulse: true,
                ),
                // On the watch the car sits low on the screen: keep the
                // button up in the middle, clear of it.
                if (tiny) const Spacer(flex: 2) else SizedBox(height: 34 * u),
              ],
            ),
          ),
          if (!tiny)
            Positioned(
              right: 16 * u,
              top: 16 * u + MediaQuery.paddingOf(context).top,
              child: Column(
                children: [
                  RoundButton(
                    icon: Icons.info_outline_rounded,
                    size: u,
                    color: Palette.coin,
                    onTap: () => showInfo(context, game),
                  ),
                  SizedBox(height: 12 * u),
                  MuteButton(game: game),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Turns sound and music off and on.
class MuteButton extends StatefulWidget {
  final GameController game;

  /// Scale of the button (1 is the usual size).
  final double size;
  const MuteButton({super.key, required this.game, this.size = 1});

  @override
  State<MuteButton> createState() => _MuteButtonState();
}

class _MuteButtonState extends State<MuteButton> {
  @override
  Widget build(BuildContext context) {
    final audio = widget.game.audio;
    return RoundButton(
      icon: audio.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
      size: unitOf(context) * widget.size,
      onTap: () async {
        await audio.init();
        audio.setMuted(!audio.muted);
        if (!audio.muted) audio.music('music');
        setState(() {});
      },
    );
  }
}

class _BestChip extends StatelessWidget {
  final GameController game;
  const _BestChip({required this.game});

  @override
  Widget build(BuildContext context) {
    final u = unitOf(context);
    final s = game.summary;
    final best = game.localBest;
    if (best == 0 && (s == null || s.totalRuns == 0)) {
      return const SizedBox.shrink();
    }
    return Sticker(
      tilt: -0.03,
      padding: EdgeInsets.symmetric(horizontal: 14 * u, vertical: 6 * u),
      radius: 14 * u,
      border: 3 * u,
      depth: 4 * u,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('BEST', style: display(18 * u, color: Palette.ink)),
          SizedBox(width: 8 * u),
          StrokeText(
            '$best',
            style: display(26 * u, color: Palette.coin),
            stroke: Colors.black,
            strokeWidth: 6 * u,
            shadow: Offset(0, 2 * u),
          ),
          if (s != null && s.rank > 0) ...[
            SizedBox(width: 10 * u),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8 * u, vertical: 3 * u),
              decoration: BoxDecoration(
                color: Palette.blue,
                borderRadius: BorderRadius.circular(8 * u),
              ),
              child: Text(
                placingLabel(s.rank, s.topPercent, short: isTiny(context)),
                style: display(15 * u),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String formatPercent(double p) {
  if (p >= 10) return '${p.round()}%';
  if (p >= 1) return '${p.toStringAsFixed(1).replaceAll('.0', '')}%';
  return '${p.toStringAsFixed(1)}%';
}

/// Where a score places among every player's best: "TOP 13% IN THE WORLD",
/// or just "TOP 13%" when [short].
String placingLabel(int rank, double topPercent, {bool short = false}) {
  final place = rank == 1 ? 'NO. 1' : 'TOP ${formatPercent(topPercent)}';
  return short ? place : '$place IN THE WORLD';
}

/// A finger hopping between three lanes.
class _SteerHint extends StatefulWidget {
  const _SteerHint();

  @override
  State<_SteerHint> createState() => _SteerHintState();
}

class _SteerHintState extends State<_SteerHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  /// Middle, right, middle, left: a quick swipe to each, then a pause.
  static double _lane(double t) {
    const stops = [0.0, 1.0, 0.0, -1.0];
    final f = t * stops.length;
    final i = f.floor() % stops.length;
    final from = stops[(i + stops.length - 1) % stops.length];
    final k = Curves.easeOutBack.transform(((f - f.floor()) * 3.5).clamp(0, 1));
    return from + (stops[i] - from) * k;
  }

  @override
  Widget build(BuildContext context) {
    final u = unitOf(context);
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final x = _lane(_t.value);
        return Column(
          children: [
            SizedBox(
              width: 180 * u,
              height: 54 * u,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.translate(
                    offset: Offset(x * 52 * u, 0),
                    child: Transform.rotate(
                      angle: x * 0.2,
                      child: Icon(
                        Icons.touch_app_rounded,
                        size: 46 * u,
                        color: Colors.white,
                        shadows: const [
                          Shadow(color: Palette.ink, offset: Offset(0, 3)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            StrokeText(
              'SWIPE TO CHANGE LANES',
              style: display(20 * u),
              strokeWidth: 5 * u,
              shadow: Offset(0, 3 * u),
            ),
          ],
        );
      },
    );
  }
}
