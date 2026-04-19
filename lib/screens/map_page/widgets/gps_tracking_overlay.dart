// Copyright (C) 2024-2026 Torch-Katsuragi
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
// Root Maps: GPS追跡アニメーションオーバーレイ
// GPS追跡中に表示される回転する光エフェクト
import 'dart:math';
import 'package:flutter/material.dart';

/// GPS追跡アニメーションオーバーレイ
/// 現在位置の周りに回転する光エフェクトを表示
class GpsTrackingOverlay extends StatelessWidget {
  /// アニメーション値（回転角度）
  final Animation<double> rotationAnimation;
  
  /// 画面上の位置（中心座標）
  final Offset screenPosition;

  const GpsTrackingOverlay({
    super.key,
    required this.rotationAnimation,
    required this.screenPosition,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: rotationAnimation,
      builder: (context, child) {
        return Positioned(
          left: screenPosition.dx - 40,
          top: screenPosition.dy - 40,
          child: SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              children: [
                // 外側の薄い円（軌跡）
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                  ),
                ),
                // 回転する光点
                Positioned(
                  left: 40 + 30 * cos(rotationAnimation.value) - 4,
                  top: 40 + 30 * sin(rotationAnimation.value) - 4,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withValues(alpha: 0.8),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
                // 内側の小さな回転光点（逆回転）
                Positioned(
                  left: 40 + 20 * cos(-rotationAnimation.value * 1.5) - 3,
                  top: 40 + 20 * sin(-rotationAnimation.value * 1.5) - 3,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withValues(alpha: 0.6),
                          blurRadius: 3,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

