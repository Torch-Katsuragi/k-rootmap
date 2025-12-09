import 'package:flutter/material.dart';
import 'dart:math';

/// コンパス方向を示す扇形を描画するCustomPainter
class CompassFanPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.lightBlue.withValues(alpha: 0.3)
          ..style = PaintingStyle.fill;

    final strokePaint =
        Paint()
          ..color = Colors.lightBlue.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 扇形の角度（60度の扇形）
    const sweepAngle = 60 * pi / 180; // 60度をラジアンに変換
    const startAngle = -sweepAngle / 2; // 中心から左右30度ずつ

    // 扇形のパスを作成
    final path = Path();
    path.moveTo(center.dx, center.dy); // 中心から開始
    path.arcTo(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
    );
    path.close();

    // 扇形を描画
    canvas.drawPath(path, paint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
