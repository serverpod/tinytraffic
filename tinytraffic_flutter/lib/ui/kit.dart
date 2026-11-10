import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The Tiny Traffic look: toy-box stickers with thick navy outlines and hard
/// shadows, candy colours, chunky type.
abstract final class Palette {
  static const ink = Color(0xFF14213D);
  static const blue = Color(0xFF1E6BFF);
  static const sky = Color(0xFF8FD3FF);
  static const coin = Color(0xFFFFC93C);
  static const coinDeep = Color(0xFFE59400);
  static const tomato = Color(0xFFFF4D4D);
  static const mint = Color(0xFF2EE6A6);
  static const cream = Color(0xFFFFF8E7);
  static const grape = Color(0xFF8B5CF6);
}

/// Size unit: 1 on a phone, smaller on a watch, larger on a big screen.
double unitOf(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return (size.shortestSide / 420).clamp(0.42, 1.5);
}

bool isTiny(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide < 260;

TextStyle display(double size, {Color color = Colors.white}) =>
    GoogleFonts.lilitaOne(fontSize: size, color: color, height: 1.0);

TextStyle body(
  double size, {
  Color color = Palette.ink,
  FontWeight weight = FontWeight.w800,
}) => GoogleFonts.nunito(
  fontSize: size,
  color: color,
  fontWeight: weight,
  height: 1.15,
);

/// Text with a thick outline and a hard drop shadow, like a sticker.
class StrokeText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Color stroke;
  final double strokeWidth;
  final Offset shadow;
  final TextAlign align;

  const StrokeText(
    this.text, {
    super.key,
    required this.style,
    this.stroke = Palette.ink,
    this.strokeWidth = 6,
    this.shadow = const Offset(0, 4),
    this.align = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    final outline = style.copyWith(
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = stroke,
      color: null,
    );
    return Stack(
      children: [
        Transform.translate(
          offset: shadow,
          child: Text(text, style: outline, textAlign: align),
        ),
        Text(text, style: outline, textAlign: align),
        Text(text, style: style, textAlign: align),
      ],
    );
  }
}

/// A rounded panel with a thick outline and a hard offset shadow.
class Sticker extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;
  final double tilt;
  final EdgeInsetsGeometry padding;
  final double border;
  final double depth;

  const Sticker({
    super.key,
    required this.child,
    this.color = Palette.cream,
    this.radius = 22,
    this.tilt = 0,
    this.padding = const EdgeInsets.all(16),
    this.border = 4,
    this.depth = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tilt,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Palette.ink, width: border),
          boxShadow: [
            BoxShadow(color: Palette.ink, offset: Offset(0, depth)),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// A big squishy button that sinks when pressed.
class ChunkyButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final Color textColor;
  final double size;
  final IconData? icon;
  final bool pulse;

  const ChunkyButton({
    super.key,
    required this.label,
    required this.onTap,
    this.color = Palette.coin,
    this.textColor = Palette.ink,
    this.size = 1,
    this.icon,
    this.pulse = false,
  });

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton>
    with SingleTickerProviderStateMixin {
  bool _down = false;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _pulse.repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final depth = 7.0 * s;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = _pulse.value;
          final scale = widget.pulse
              ? 1 + math.sin(t * math.pi * 2) * 0.035
              : 1.0;
          return Transform.scale(scale: scale, child: child);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          margin: EdgeInsets.only(
            top: _down ? depth * 0.8 : 0,
            bottom: _down ? 0 : depth * 0.8,
          ),
          padding: EdgeInsets.symmetric(horizontal: 26 * s, vertical: 13 * s),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(20 * s),
            border: Border.all(color: Palette.ink, width: 4 * s),
            boxShadow: [
              BoxShadow(
                color: Palette.ink,
                offset: Offset(0, _down ? 1 : depth),
              ),
            ],
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(widget.color, Colors.white, 0.35)!,
                widget.color,
              ],
              stops: const [0, 0.55],
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: widget.textColor, size: 30 * s),
                SizedBox(width: 8 * s),
              ],
              Text(
                widget.label,
                style: display(30 * s, color: widget.textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small round icon button in the same style.
class RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color color;

  const RoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 1,
    this.color = Palette.cream,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48 * size,
        height: 48 * size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Palette.ink, width: 3.5 * size),
          boxShadow: [
            BoxShadow(color: Palette.ink, offset: Offset(0, 4 * size)),
          ],
        ),
        child: Icon(icon, color: Palette.ink, size: 26 * size),
      ),
    );
  }
}
