// MapLibre SymbolStyleLayer用アイコン画像のプログラム生成
// Canvas + PictureRecorder で PNG バイト列を生成し、StyleController.addImage() で登録

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// MapLibre に登録する写真マーカーアイコンを生成
class MapIconGenerator {
  MapIconGenerator._();

  static const _size = 64.0;
  static const _circleRadius = 15.0;
  static const _borderWidth = 2.0;

  /// 方向あり（くちばし付き）アイコンを生成
  static Future<Uint8List> generatePhotoMarker(Color color) async {
    return _render((canvas, size) {
      final center = Offset(size / 2, size / 2);
      _drawBeak(canvas, center, size, color);
      _drawCircleWithCamera(canvas, center, color, false);
    });
  }

  /// 方向なし（丸のみ）アイコンを生成
  static Future<Uint8List> generatePhotoMarkerNoDir(Color color) async {
    return _render((canvas, size) {
      final center = Offset(size / 2, size / 2);
      _drawCircleWithCamera(canvas, center, color, false);
    });
  }

  /// 選択版・方向あり
  static Future<Uint8List> generatePhotoMarkerSel(Color color) async {
    return _render((canvas, size) {
      final center = Offset(size / 2, size / 2);
      _drawBeak(canvas, center, size, color);
      _drawCircleWithCamera(canvas, center, color, true);
    });
  }

  /// 選択版・方向なし
  static Future<Uint8List> generatePhotoMarkerNoDirSel(Color color) async {
    return _render((canvas, size) {
      final center = Offset(size / 2, size / 2);
      _drawCircleWithCamera(canvas, center, color, true);
    });
  }

  /// Canvas描画 → PNG バイト列
  static Future<Uint8List> _render(
    void Function(Canvas canvas, double size) painter,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    painter(canvas, _size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(_size.toInt(), _size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    return byteData!.buffer.asUint8List();
  }

  /// くちばし三角形（上向き = 北向き、icon-rotateで回転）
  static void _drawBeak(
    Canvas canvas,
    Offset center,
    double size,
    Color color,
  ) {
    const halfAngle = 35 * pi / 180;
    final outerRadius = size / 2;

    // 上向き（-π/2回転）: 右向きベースを上向きに変換
    final path = Path();
    // 円の縁上の2点（上向き）
    path.moveTo(
      center.dx - _circleRadius * sin(halfAngle),
      center.dy - _circleRadius * cos(halfAngle),
    );
    // 先端（上）
    path.lineTo(center.dx, center.dy - outerRadius);
    // 反対側
    path.lineTo(
      center.dx + _circleRadius * sin(halfAngle),
      center.dy - _circleRadius * cos(halfAngle),
    );
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  /// 白背景円 + カメラアイコン
  static void _drawCircleWithCamera(
    Canvas canvas,
    Offset center,
    Color color,
    bool selected,
  ) {
    // 影
    canvas.drawCircle(
      center + const Offset(0, 1),
      _circleRadius + 1,
      Paint()
        ..color = Colors.black26
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // 白背景
    canvas.drawCircle(
      center,
      _circleRadius,
      Paint()
        ..color = selected ? Colors.yellow.shade100 : Colors.white
        ..style = PaintingStyle.fill,
    );

    // ボーダー
    canvas.drawCircle(
      center,
      _circleRadius - _borderWidth / 2,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _borderWidth,
    );

    // カメラアイコン（Material Icons フォント）
    final iconSize = selected ? 20.0 : 18.0;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.photo_camera.codePoint),
        style: TextStyle(
          fontSize: iconSize,
          fontFamily: Icons.photo_camera.fontFamily,
          package: Icons.photo_camera.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }
}
