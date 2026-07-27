import 'dart:math';

import 'package:flutter/material.dart';

/// Custom sun rings painter for animated background
class SunRingsPainterV3 extends CustomPainter {
  final double progress;
  SunRingsPainterV3(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final sunPaint = Paint()
      ..color = Colors.amber.withOpacity(0.6)
      ..style = PaintingStyle.fill;
    final pulseRadius = 50 + 2 * sin(progress * pi * 2);
    canvas.drawCircle(center, pulseRadius, sunPaint);

    final ringPaint = Paint()
      ..color = Colors.amber.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (int i = 1; i <= 3; i++) {
      final radius = 70.0 + i * 20.0;
      canvas.drawCircle(center, radius, ringPaint);
    }

    final raysPaint = Paint()
      ..color = Colors.amber.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 20; i++) {
      final angle = (progress / 2) * 2 * pi + (pi / 10) * i;
      final offset = Offset(
        center.dx + 80 * cos(angle),
        center.dy + 80 * sin(angle),
      );
      canvas.drawCircle(offset, 3, raysPaint);
    }
  }

  @override
  bool shouldRepaint(covariant SunRingsPainterV3 oldDelegate) => true;
}

/// Background shapes painter for animated background
class BackgroundShapesPainter extends CustomPainter {
  final double progress;
  BackgroundShapesPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.fill;

    final offset1 = 20 * sin(progress * pi * 2);
    final scale1 = 1 + 0.05 * sin(progress * pi * 2);

    canvas.save();
    canvas.translate(offset1, 0);
    canvas.scale(scale1);
    final shape1 = Path()
      ..moveTo(0, size.height * 0.2)
      ..lineTo(size.width * 0.3, size.height * 0.15)
      ..lineTo(size.width * 0.2, 0)
      ..close();
    canvas.drawPath(shape1, paint);
    canvas.restore();

    final offset2 = 30 * cos(progress * pi * 2);
    final scale2 = 1 + 0.03 * cos(progress * pi * 2);

    canvas.save();
    canvas.translate(-offset2, 0);
    canvas.scale(scale2);
    final shape2 = Path()
      ..moveTo(size.width, size.height * 0.3)
      ..lineTo(size.width * 0.7, size.height * 0.4)
      ..lineTo(size.width, size.height * 0.5)
      ..close();
    canvas.drawPath(shape2, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BackgroundShapesPainter oldDelegate) => true;
}
