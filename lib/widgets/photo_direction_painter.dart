// Root Maps: 写真撮影方向インジケーター
// 写真マーカーの円外側に方向を示すくちばし状の三角形を描画

import 'package:flutter/material.dart';
import 'dart:math';

/// 写真の撮影方向を示す三角形ポインターを描画するCustomPainter
///
/// 右方向（0ラジアン）にポインターを描画する。
/// 使用時に[Transform.rotate]で実際の撮影方向に回転させる。
class PhotoDirectionPainter extends CustomPainter {
  /// ポインターの色
  final Color color;

  /// 円マーカーの半径（この外側にポインターを描画）
  final double circleRadius;

  const PhotoDirectionPainter({
    required this.color,
    this.circleRadius = 10.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;

    // くちばし状の三角形（円の外縁から外に突き出す）
    const halfAngle = 35 * pi / 180; // 左右35度 = 70度幅のくちばし

    final path = Path();
    // 円の縁上の2点
    path.moveTo(
      center.dx + circleRadius * cos(halfAngle),
      center.dy - circleRadius * sin(halfAngle),
    );
    // 先端
    path.lineTo(center.dx + outerRadius, center.dy);
    // 反対側
    path.lineTo(
      center.dx + circleRadius * cos(halfAngle),
      center.dy + circleRadius * sin(halfAngle),
    );
    path.close();

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(covariant PhotoDirectionPainter oldDelegate) =>
      color != oldDelegate.color || circleRadius != oldDelegate.circleRadius;
}
