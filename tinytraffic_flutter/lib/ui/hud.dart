import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tinytraffic_game/tinytraffic_game.dart'
    show PowerUp, kDoubleTime, kMagnetTime;

import '../game/controller.dart';
import 'kit.dart';

class Hud extends StatefulWidget {
  final GameController game;
  const Hud({super.key, required this.game});

  @override
  State<Hud> createState() => _HudState();
}

class _Popup {
  final String text;
  final Color color;
  final double born;
  final double tilt;
  _Popup(this.text, this.color, this.born, this.tilt);
}

class _HudState extends State<Hud> with TickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(days: 1),
  )..forward();
  late final AnimationController _bump = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  StreamSubscription<HudEvent>? _sub;
  final List<_Popup> _popups = [];
  final _rand = math.Random();
  int _lastScore = 0;
  double _boomAt = -10;

  double get _now => _clock.lastElapsedDuration?.inMicroseconds.toDouble() ?? 0;

  @override
  void initState() {
    super.initState();
    _sub = widget.game.hudEvents.listen(_onEvent);
  }

  void _onEvent(HudEvent e) {
    final now = _now / 1e6;
    switch (e.cue) {
      case HudCue.coin:
        _bump.forward(from: 0);
        if (e.value >= 5 && e.value % 5 == 0) {
          _add('COMBO x${e.value}!', Palette.coin, now);
        }
      case HudCue.nearMiss:
        _add('CLOSE CALL +${e.value}', Palette.mint, now);
      case HudCue.magnet:
        _add('MAGNET!', Palette.tomato, now);
      case HudCue.doubleCoins:
        _add('DOUBLE COINS!', Palette.mint, now);
      case HudCue.newBest:
        break;
      case HudCue.explosion:
        _boomAt = now;
    }
  }

  void _add(String text, Color color, double now) {
    _popups.add(_Popup(text, color, now, (_rand.nextDouble() - 0.5) * 0.25));
    if (_popups.length > 3) _popups.removeAt(0);
  }

  @override
  void dispose() {
    widget.game.world.badgeSlots.clear();
    _sub?.cancel();
    _clock.dispose();
    _bump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = unitOf(context);
    final game = widget.game;
    final tiny = isTiny(context);
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        final now = _now / 1e6;
        _popups.removeWhere((p) => now - p.born > 1.1);
        final speed = game.speedKmh;
        if (game.score != _lastScore) _lastScore = game.score;
        return Stack(
          fit: StackFit.expand,
          children: [
            // Wind streaks at speed.
            CustomPaint(
              painter: _SpeedLines(
                intensity: game.phase == GamePhase.playing
                    ? ((speed - 70) / 60).clamp(0.0, 1.0)
                    : 0,
                time: now,
              ),
            ),
            // Coins.
            Positioned(
              top: MediaQuery.paddingOf(context).top + (tiny ? 8 : 14) * u,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedBuilder(
                  animation: _bump,
                  builder: (context, child) {
                    final t = _bump.value;
                    final s = 1 + math.sin(t * math.pi) * 0.25;
                    return Transform.scale(scale: s, child: child);
                  },
                  child: StrokeText(
                    '${game.score}',
                    style: display(52 * u, color: Palette.coin),
                    stroke: Colors.black,
                    strokeWidth: 10 * u,
                    shadow: Offset(0, 5 * u),
                  ),
                ),
              ),
            ),
            // Speed.
            if (!tiny && game.phase == GamePhase.playing)
              Positioned(
                right: 18 * u,
                bottom: 18 * u + MediaQuery.paddingOf(context).bottom,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    StrokeText(
                      speed.round().toString(),
                      style: display(34 * u),
                      strokeWidth: 7 * u,
                      shadow: Offset(0, 3 * u),
                    ),
                    SizedBox(width: 4 * u),
                    StrokeText(
                      'KM/H',
                      style: display(15 * u, color: Palette.sky),
                      strokeWidth: 5 * u,
                      shadow: Offset(0, 2 * u),
                    ),
                  ],
                ),
              ),
            if (!tiny &&
                game.phase == GamePhase.playing &&
                game.world.quality.bot)
              Positioned(
                left: 16 * u,
                bottom: 18 * u + MediaQuery.paddingOf(context).bottom,
                child: Opacity(
                  opacity: 0.8,
                  child: Text(
                    'AUTOPILOT',
                    style: body(12 * u, color: Colors.white),
                  ),
                ),
              ),
            // Power-ups running: their models spin in these slots (drawn
            // by the 3D view, see [GameWorld.badgeSlots]), each in a ring
            // that runs down as it wears off.
            ..._powerUps(context, u, tiny),
            // Pop-ups.
            for (final p in _popups) _buildPopup(p, now, u),
            // Countdown.
            if (game.phase == GamePhase.countdown ||
                (game.phase == GamePhase.playing && game.phaseTime < _goTime))
              _buildCountdown(u),
            // Crash flash.
            if (game.phase == GamePhase.crashed) _CrashFlash(game: game),
            // Explosion flash.
            if (now - _boomAt < 0.3)
              ColoredBox(
                color: const Color(0xFFFFE2A8).withValues(
                  alpha: 0.5 * (1 - (now - _boomAt) / 0.3),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The running power-ups' slots, and where their models go.
  List<Widget> _powerUps(BuildContext context, double u, bool tiny) {
    final game = widget.game;
    final slots = game.world.badgeSlots..clear();
    if (game.phase != GamePhase.playing) return const [];
    final running = [
      if (game.magnetLeft > 0)
        (PowerUp.magnet, Palette.tomato, game.magnetLeft / kMagnetTime),
      if (game.doubleLeft > 0)
        (PowerUp.double, Palette.mint, game.doubleLeft / kDoubleTime),
    ];
    final view = MediaQuery.sizeOf(context);
    final size = (tiny ? 40 : 52) * u;
    final gap = 12 * u;
    final top = MediaQuery.paddingOf(context).top + (tiny ? 60 : 80) * u;
    final width = running.length * size + (running.length - 1) * gap;
    final out = <Widget>[];
    for (var i = 0; i < running.length; i++) {
      final (power, colour, left) = running[i];
      final cx = view.width / 2 - width / 2 + size / 2 + i * (size + gap);
      final cy = top + size / 2;
      // Blinks as it runs out.
      final blink = left < 0.2 && (left * 40).floor().isEven;
      if (!blink) {
        slots[power] = (
          cx / view.width * 2 - 1,
          1 - cy / view.height * 2,
          size * 0.62 / view.height,
        );
      }
      out.add(
        Positioned(
          left: cx - size / 2,
          top: top,
          width: size,
          height: size,
          child: _PowerRing(colour: colour, left: left, u: u),
        ),
      );
    }
    return out;
  }

  Widget _buildPopup(_Popup p, double now, double u) {
    final t = (now - p.born) / 1.1;
    final appear = Curves.elasticOut.transform((t * 3).clamp(0.0, 1.0));
    final fade = t > 0.7 ? 1 - (t - 0.7) / 0.3 : 1.0;
    final index = _popups.indexOf(p);
    return Align(
      alignment: Alignment(0, -0.42 + index * 0.16 - t * 0.12),
      child: Opacity(
        opacity: fade.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: p.tilt,
          child: Transform.scale(
            scale: 0.3 + appear * 0.7,
            child: StrokeText(
              p.text,
              style: display(34 * u, color: p.color),
              strokeWidth: 8 * u,
              shadow: Offset(0, 4 * u),
            ),
          ),
        ),
      ),
    );
  }

  /// The countdown's numbers, then "GO!" as the run starts. They follow
  /// the game's clock: each number pops in, holds, and fades out just as
  /// the next one comes.
  Widget _buildCountdown(double u) {
    final game = widget.game;
    final go = game.phase == GamePhase.playing;
    final double t;
    final double opacity;
    if (go) {
      t = game.phaseTime / _goTime;
      opacity = t < 0.55 ? 1 : (1 - (t - 0.55) / 0.45).clamp(0.0, 1.0);
    } else {
      t = game.phaseTime - game.phaseTime.floorToDouble();
      opacity = math.min(t / 0.06, 1) * (t < 0.8 ? 1 : (1 - t) / 0.2);
    }
    final pop = Curves.easeOutBack.transform((t / 0.35).clamp(0.0, 1.0));
    // "GO!" swells a little as it fades.
    final grow = go ? math.max(0.0, t - 0.55) * 0.5 : 0.0;
    return Center(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 2.0 - pop + grow,
          child: StrokeText(
            go ? 'GO!' : '${game.countdown}',
            style: display(110 * u, color: go ? Palette.mint : Colors.white),
            strokeWidth: 16 * u,
            shadow: Offset(0, 9 * u),
          ),
        ),
      ),
    );
  }

  /// Seconds "GO!" shows for once the run is under way.
  static const double _goTime = 0.8;
}

class _CrashFlash extends StatelessWidget {
  final GameController game;
  const _CrashFlash({required this.game});

  @override
  Widget build(BuildContext context) {
    final u = unitOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1600),
      builder: (context, t, _) {
        final flash = (1 - t * 5).clamp(0.0, 1.0);
        const word = 'CRUNCH!';
        final appear = Curves.elasticOut.transform(
          ((t - 0.05) * 2).clamp(0.0, 1.0),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.white.withValues(alpha: flash * 0.6)),
            // Up in the sky, out of the way of the wreck.
            Align(
              alignment: const Alignment(0, -0.52),
              child: Transform.rotate(
                angle: -0.12,
                child: Transform.scale(
                  scale: 0.2 + appear * 0.8,
                  child: StrokeText(
                    word,
                    style: display(78 * u, color: Palette.tomato),
                    strokeWidth: 14 * u,
                    shadow: Offset(0, 8 * u),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A ring around a power-up's spinning model that runs down as it wears
/// off.
class _PowerRing extends StatelessWidget {
  final Color colour;

  /// Fraction left, 0..1.
  final double left;
  final double u;

  const _PowerRing({required this.colour, required this.left, required this.u});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CircularProgressIndicator(
          value: 1,
          strokeWidth: 6 * u,
          color: Palette.ink.withValues(alpha: 0.55),
        ),
        Padding(
          padding: EdgeInsets.all(1.2 * u),
          child: CircularProgressIndicator(
            value: left,
            strokeWidth: 3.6 * u,
            color: colour,
            backgroundColor: Colors.transparent,
          ),
        ),
      ],
    );
  }
}

/// White streaks flying past the edges of the screen at high speed.
class _SpeedLines extends CustomPainter {
  final double intensity;
  final double time;

  _SpeedLines({required this.intensity, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final c = Offset(size.width / 2, size.height * 0.45);
    final maxR = size.longestSide * 0.75;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.5 * intensity);
    for (var i = 0; i < 36; i++) {
      final seed = i * 12.9898;
      final a = (math.sin(seed) * 43758.5453) % (math.pi * 2);
      final phase = (time * (1.4 + (i % 5) * 0.3) + i * 0.137) % 1.0;
      final r0 = maxR * (0.45 + phase * 0.6);
      final len = maxR * 0.12 * (0.5 + phase);
      final dir = Offset(math.cos(a), math.sin(a));
      paint.strokeWidth = (1.5 + phase * 3) * (size.shortestSide / 420);
      canvas.drawLine(c + dir * r0, c + dir * (r0 + len), paint);
    }
  }

  @override
  bool shouldRepaint(_SpeedLines old) => true;
}
