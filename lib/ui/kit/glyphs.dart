import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../services/app_services.dart';
import 'paint_kit.dart';

/// Icons drawn in code (crisp at any size, coloured by the theme).
enum Glyph {
  home,
  gear,
  pause,
  play,
  plus,
  close,
  slotPlus,
  hint,
  swap,
  lock,
  music,
  sound,
  vibrate,
  user,
  globe,
  theme,
  help,
  info,
  shield,
  download,
  sparkle,
  arrowLeft,
  arrowRight,
  restart,
  check,
  film,
  trophy,
}

class GlyphPainter extends CustomPainter {
  GlyphPainter(this.glyph, this.color, {this.shadow});

  final Glyph glyph;
  final Color color;
  final Color? shadow;

  @override
  void paint(Canvas canvas, Size size) {
    if (shadow != null) {
      canvas.save();
      canvas.translate(0, size.width * 0.06);
      _draw(canvas, size, shadow!);
      canvas.restore();
    }
    _draw(canvas, size, color);
  }

  void _draw(Canvas canvas, Size size, Color c) {
    final w = size.width;
    Offset p(double x, double y) => Offset(x * w, y * w);
    final stroke = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = c;
    switch (glyph) {
      case Glyph.home:
        canvas.drawPath(Path()..moveTo(p(0.12, 0.5).dx, p(0.12, 0.5).dy)..lineTo(p(0.5, 0.15).dx, p(0.5, 0.15).dy)..lineTo(p(0.88, 0.5).dx, p(0.88, 0.5).dy), stroke);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(p(0.24, 0.45), p(0.76, 0.86)), Radius.circular(w * 0.06)), stroke);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(p(0.42, 0.6), p(0.58, 0.86)), Radius.circular(w * 0.04)), fill);
      case Glyph.gear:
        final center = p(0.5, 0.5);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          canvas.drawLine(center + Offset(math.cos(a), math.sin(a)) * w * 0.3, center + Offset(math.cos(a), math.sin(a)) * w * 0.44, stroke..strokeWidth = w * 0.14);
        }
        stroke.strokeWidth = w * 0.1;
        canvas.drawCircle(center, w * 0.28, stroke);
        canvas.drawCircle(center, w * 0.1, fill);
      case Glyph.pause:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(p(0.26, 0.2), p(0.42, 0.8)), Radius.circular(w * 0.05)), fill);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(p(0.58, 0.2), p(0.74, 0.8)), Radius.circular(w * 0.05)), fill);
      case Glyph.play:
        canvas.drawPath(Path()..moveTo(p(0.3, 0.18).dx, p(0.3, 0.18).dy)..lineTo(p(0.82, 0.5).dx, p(0.82, 0.5).dy)..lineTo(p(0.3, 0.82).dx, p(0.3, 0.82).dy)..close(), fill);
      case Glyph.plus:
        canvas.drawLine(p(0.5, 0.2), p(0.5, 0.8), stroke..strokeWidth = w * 0.16);
        canvas.drawLine(p(0.2, 0.5), p(0.8, 0.5), stroke);
      case Glyph.close:
        canvas.drawLine(p(0.25, 0.25), p(0.75, 0.75), stroke..strokeWidth = w * 0.13);
        canvas.drawLine(p(0.75, 0.25), p(0.25, 0.75), stroke);
      case Glyph.slotPlus:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(p(0.14, 0.14), p(0.86, 0.86)), Radius.circular(w * 0.16)), stroke);
        canvas.drawLine(p(0.5, 0.32), p(0.5, 0.68), stroke);
        canvas.drawLine(p(0.32, 0.5), p(0.68, 0.5), stroke);
      case Glyph.hint:
        canvas.drawCircle(p(0.5, 0.42), w * 0.24, stroke);
        canvas.drawLine(p(0.42, 0.72), p(0.58, 0.72), stroke);
        canvas.drawLine(p(0.44, 0.86), p(0.56, 0.86), stroke);
        canvas.drawCircle(p(0.44, 0.36), w * 0.05, fill);
      case Glyph.swap:
        canvas.drawLine(p(0.18, 0.34), p(0.78, 0.34), stroke);
        canvas.drawPath(Path()..moveTo(p(0.62, 0.18).dx, p(0.62, 0.18).dy)..lineTo(p(0.8, 0.34).dx, p(0.8, 0.34).dy)..lineTo(p(0.62, 0.5).dx, p(0.62, 0.5).dy), stroke);
        canvas.drawLine(p(0.82, 0.68), p(0.22, 0.68), stroke);
        canvas.drawPath(Path()..moveTo(p(0.38, 0.52).dx, p(0.38, 0.52).dy)..lineTo(p(0.2, 0.68).dx, p(0.2, 0.68).dy)..lineTo(p(0.38, 0.84).dx, p(0.38, 0.84).dy), stroke);
      case Glyph.lock:
        canvas.drawArc(Rect.fromPoints(p(0.3, 0.12), p(0.7, 0.62)), math.pi, math.pi, false, stroke);
        canvas.drawLine(p(0.3, 0.37), p(0.3, 0.48), stroke);
        canvas.drawLine(p(0.7, 0.37), p(0.7, 0.48), stroke);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(p(0.2, 0.46), p(0.8, 0.88)), Radius.circular(w * 0.1)), fill);
      case Glyph.music:
        canvas.drawCircle(p(0.34, 0.74), w * 0.13, fill);
        canvas.drawCircle(p(0.72, 0.64), w * 0.13, fill);
        canvas.drawLine(p(0.45, 0.74), p(0.45, 0.2), stroke);
        canvas.drawLine(p(0.83, 0.64), p(0.83, 0.12), stroke);
        canvas.drawLine(p(0.45, 0.22), p(0.83, 0.12), stroke..strokeWidth = w * 0.14);
      case Glyph.sound:
        canvas.drawPath(Path()..moveTo(p(0.14, 0.38).dx, p(0.14, 0.38).dy)..lineTo(p(0.32, 0.38).dx, p(0.32, 0.38).dy)..lineTo(p(0.52, 0.2).dx, p(0.52, 0.2).dy)..lineTo(p(0.52, 0.8).dx, p(0.52, 0.8).dy)..lineTo(p(0.32, 0.62).dx, p(0.32, 0.62).dy)..lineTo(p(0.14, 0.62).dx, p(0.14, 0.62).dy)..close(), fill);
        canvas.drawArc(Rect.fromCircle(center: p(0.52, 0.5), radius: w * 0.18), -0.9, 1.8, false, stroke);
        canvas.drawArc(Rect.fromCircle(center: p(0.52, 0.5), radius: w * 0.33), -0.9, 1.8, false, stroke);
      case Glyph.vibrate:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(p(0.34, 0.14), p(0.66, 0.86)), Radius.circular(w * 0.08)), stroke);
        canvas.drawLine(p(0.16, 0.36), p(0.16, 0.64), stroke);
        canvas.drawLine(p(0.84, 0.36), p(0.84, 0.64), stroke);
      case Glyph.user:
        canvas.drawCircle(p(0.5, 0.34), w * 0.17, fill);
        canvas.drawArc(Rect.fromPoints(p(0.18, 0.56), p(0.82, 1.1)), math.pi, math.pi, true, fill);
      case Glyph.globe:
        canvas.drawCircle(p(0.5, 0.5), w * 0.36, stroke);
        canvas.drawOval(Rect.fromPoints(p(0.33, 0.14), p(0.67, 0.86)), stroke);
        canvas.drawLine(p(0.14, 0.5), p(0.86, 0.5), stroke);
      case Glyph.theme:
        canvas.drawCircle(p(0.5, 0.5), w * 0.34, stroke);
        canvas.drawArc(Rect.fromCircle(center: p(0.5, 0.5), radius: w * 0.34), -math.pi / 2, math.pi, true, fill);
      case Glyph.help:
        canvas.drawArc(Rect.fromPoints(p(0.3, 0.14), p(0.7, 0.5)), math.pi * 1.05, math.pi * 1.25, false, stroke);
        canvas.drawLine(p(0.5, 0.5), p(0.5, 0.64), stroke);
        canvas.drawCircle(p(0.5, 0.82), w * 0.07, fill);
      case Glyph.info:
        canvas.drawCircle(p(0.5, 0.2), w * 0.08, fill);
        canvas.drawLine(p(0.5, 0.4), p(0.5, 0.84), stroke..strokeWidth = w * 0.14);
      case Glyph.shield:
        canvas.drawPath(
          Path()
            ..moveTo(p(0.5, 0.1).dx, p(0.5, 0.1).dy)
            ..lineTo(p(0.84, 0.24).dx, p(0.84, 0.24).dy)
            ..quadraticBezierTo(p(0.84, 0.72).dx, p(0.84, 0.72).dy, p(0.5, 0.9).dx, p(0.5, 0.9).dy)
            ..quadraticBezierTo(p(0.16, 0.72).dx, p(0.16, 0.72).dy, p(0.16, 0.24).dx, p(0.16, 0.24).dy)
            ..close(),
          stroke,
        );
        canvas.drawPath(Path()..moveTo(p(0.34, 0.5).dx, p(0.34, 0.5).dy)..lineTo(p(0.46, 0.62).dx, p(0.46, 0.62).dy)..lineTo(p(0.68, 0.38).dx, p(0.68, 0.38).dy), stroke);
      case Glyph.download:
        canvas.drawLine(p(0.5, 0.14), p(0.5, 0.62), stroke);
        canvas.drawPath(Path()..moveTo(p(0.3, 0.44).dx, p(0.3, 0.44).dy)..lineTo(p(0.5, 0.64).dx, p(0.5, 0.64).dy)..lineTo(p(0.7, 0.44).dx, p(0.7, 0.44).dy), stroke);
        canvas.drawLine(p(0.18, 0.84), p(0.82, 0.84), stroke);
      case Glyph.sparkle:
        canvas.drawPath(starPath(p(0.5, 0.5), w * 0.42, inner: 0.25, points: 4), fill);
      case Glyph.arrowLeft:
        canvas.drawPath(Path()..moveTo(p(0.62, 0.18).dx, p(0.62, 0.18).dy)..lineTo(p(0.3, 0.5).dx, p(0.3, 0.5).dy)..lineTo(p(0.62, 0.82).dx, p(0.62, 0.82).dy), stroke..strokeWidth = w * 0.14);
      case Glyph.arrowRight:
        canvas.drawPath(Path()..moveTo(p(0.38, 0.18).dx, p(0.38, 0.18).dy)..lineTo(p(0.7, 0.5).dx, p(0.7, 0.5).dy)..lineTo(p(0.38, 0.82).dx, p(0.38, 0.82).dy), stroke..strokeWidth = w * 0.14);
      case Glyph.restart:
        canvas.drawArc(Rect.fromCircle(center: p(0.5, 0.52), radius: w * 0.3), -math.pi * 0.35, math.pi * 1.6, false, stroke);
        canvas.drawPath(Path()..moveTo(p(0.64, 0.12).dx, p(0.64, 0.12).dy)..lineTo(p(0.78, 0.3).dx, p(0.78, 0.3).dy)..lineTo(p(0.56, 0.34).dx, p(0.56, 0.34).dy), stroke);
      case Glyph.check:
        canvas.drawPath(Path()..moveTo(p(0.2, 0.52).dx, p(0.2, 0.52).dy)..lineTo(p(0.42, 0.74).dx, p(0.42, 0.74).dy)..lineTo(p(0.8, 0.28).dx, p(0.8, 0.28).dy), stroke..strokeWidth = w * 0.14);
      case Glyph.trophy:
        canvas.drawPath(
          Path()
            ..moveTo(p(0.26, 0.16).dx, p(0.26, 0.16).dy)
            ..lineTo(p(0.74, 0.16).dx, p(0.74, 0.16).dy)
            ..lineTo(p(0.68, 0.48).dx, p(0.68, 0.48).dy)
            ..quadraticBezierTo(p(0.5, 0.66).dx, p(0.5, 0.66).dy, p(0.32, 0.48).dx, p(0.32, 0.48).dy)
            ..close(),
          fill,
        );
        canvas.drawArc(Rect.fromPoints(p(0.1, 0.2), p(0.34, 0.44)), math.pi / 2, math.pi, false, stroke);
        canvas.drawArc(Rect.fromPoints(p(0.66, 0.2), p(0.9, 0.44)), -math.pi / 2, math.pi, false, stroke);
        canvas.drawLine(p(0.5, 0.62), p(0.5, 0.78), stroke);
        canvas.drawLine(p(0.32, 0.84), p(0.68, 0.84), stroke);
      case Glyph.film:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(p(0.12, 0.22), p(0.88, 0.78)), Radius.circular(w * 0.1)), stroke);
        canvas.drawPath(Path()..moveTo(p(0.42, 0.36).dx, p(0.42, 0.36).dy)..lineTo(p(0.64, 0.5).dx, p(0.64, 0.5).dy)..lineTo(p(0.42, 0.64).dx, p(0.42, 0.64).dy)..close(), fill);
    }
  }

  @override
  bool shouldRepaint(GlyphPainter old) => old.glyph != glyph || old.color != color || old.shadow != shadow;
}

class GlyphIcon extends StatelessWidget {
  const GlyphIcon(this.glyph, {super.key, this.size = 24, this.color, this.shadow = true});

  final Glyph glyph;
  final double size;
  final Color? color;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final t = Services.of(context).theme.tokens;
    return CustomPaint(
      size: Size.square(size),
      painter: GlyphPainter(glyph, color ?? t.color('text.onStone'), shadow: shadow ? alpha(t.color('text.shadow'), 0.6) : null),
    );
  }
}
