import 'package:flutter/material.dart';

/// The MedAlert logo mark: a medical cross with a magnifying glass
/// overlapping its lower-right arm. Used on the splash screen and the
/// login header so both places draw the exact same shape.
///
/// [color] is the mark's fill/stroke color (e.g. white on a brand-color
/// background). [holeColor] is painted into the ring gaps of the
/// magnifying glass so it reads as a genuine cutout -- it should match
/// whatever the mark is sitting on top of.
class MedAlertMark extends StatelessWidget {
  const MedAlertMark({
    super.key,
    required this.size,
    this.color = Colors.white,
    required this.holeColor,
  });

  final double size;
  final Color color;
  final Color holeColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MedAlertMarkPainter(color: color, holeColor: holeColor)),
    );
  }
}

class _MedAlertMarkPainter extends CustomPainter {
  _MedAlertMarkPainter({required this.color, required this.holeColor});

  final Color color;
  final Color holeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    double sx(double v) => v / 120 * w;
    double sy(double v) => v / 120 * h;

    final crossPath = Path()
      ..moveTo(sx(46), sy(8))
      ..lineTo(sx(74), sy(8))
      ..cubicTo(sx(79.5), sy(8), sx(84), sy(12.5), sx(84), sy(18))
      ..lineTo(sx(84), sy(46))
      ..lineTo(sx(112), sy(46))
      ..cubicTo(sx(117.5), sy(46), sx(122), sy(50.5), sx(122), sy(56))
      ..lineTo(sx(122), sy(64))
      ..cubicTo(sx(122), sy(69.5), sx(117.5), sy(74), sx(112), sy(74))
      ..lineTo(sx(84), sy(74))
      ..lineTo(sx(84), sy(102))
      ..cubicTo(sx(84), sy(107.5), sx(79.5), sy(112), sx(74), sy(112))
      ..lineTo(sx(46), sy(112))
      ..cubicTo(sx(40.5), sy(112), sx(36), sy(107.5), sx(36), sy(102))
      ..lineTo(sx(36), sy(74))
      ..lineTo(sx(8), sy(74))
      ..cubicTo(sx(2.5), sy(74), sx(-2), sy(69.5), sx(-2), sy(64))
      ..lineTo(sx(-2), sy(56))
      ..cubicTo(sx(-2), sy(50.5), sx(2.5), sy(46), sx(8), sy(46))
      ..lineTo(sx(36), sy(46))
      ..lineTo(sx(36), sy(18))
      ..cubicTo(sx(36), sy(12.5), sx(40.5), sy(8), sx(46), sy(8))
      ..close();

    canvas.drawPath(crossPath, Paint()..color = color);

    final glassCenter = Offset(sx(80), sy(86));
    final glassRadius = w * 0.217;
    canvas.drawCircle(
      glassCenter,
      glassRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.10
        ..color = holeColor,
    );
    canvas.drawCircle(
      glassCenter,
      glassRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.06
        ..color = color,
    );
    final handleStart = Offset(sx(98), sy(104));
    final handleEnd = Offset(sx(118), sy(124));
    canvas.drawLine(
      handleStart,
      handleEnd,
      Paint()
        ..color = holeColor
        ..strokeWidth = w * 0.10
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      handleStart,
      handleEnd,
      Paint()
        ..color = color
        ..strokeWidth = w * 0.06
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MedAlertMarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.holeColor != holeColor;
}