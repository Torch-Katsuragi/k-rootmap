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
/// パーティ位置共有: ルームコード生成
///
/// コードは「鍵（capability）」そのもの。推測困難性のため8文字とし、
/// 紛らわしい文字（0/O/1/I/L）を除外した31種から生成する
/// （31^8 ≈ 8.5e11、失効＋App Check と併せて総当たりを実用上無効化）。
library;

import 'dart:math';

/// ルームコード生成・検証
class RoomCodeGenerator {
  /// 既定のコード長
  static const int defaultLength = 8;

  /// 使用文字集合（0 O 1 I L を除外）
  static const String alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

  final Random _random;

  /// [random] を渡さない場合は暗号論的乱数（[Random.secure]）を使う。
  RoomCodeGenerator([Random? random]) : _random = random ?? Random.secure();

  /// ルームコードを生成
  String generate([int length = defaultLength]) {
    final sb = StringBuffer();
    for (var i = 0; i < length; i++) {
      sb.write(alphabet[_random.nextInt(alphabet.length)]);
    }
    return sb.toString();
  }

  /// コードが規約（長さ・使用文字）を満たすか
  static bool isValid(String code, {int length = defaultLength}) {
    if (code.length != length) return false;
    for (final ch in code.split('')) {
      if (!alphabet.contains(ch)) return false;
    }
    return true;
  }
}
