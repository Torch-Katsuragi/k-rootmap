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
/// TruPulse計測データモデル
class TruPulseMeasurement {
  /// 水平距離 (m)
  final double hd;

  /// 斜距離 (m)
  final double sd;

  /// 鉛直距離 (m)
  final double vd;

  /// 方位角 (degrees, 磁北基準)
  final double az;

  /// 傾斜角 (degrees)
  final double inc;

  /// 計測時刻
  final DateTime timestamp;

  const TruPulseMeasurement({
    required this.hd,
    required this.sd,
    required this.vd,
    required this.az,
    required this.inc,
    required this.timestamp,
  });

  @override
  String toString() =>
      'TruPulse(HD:${hd.toStringAsFixed(1)}m AZ:${az.toStringAsFixed(1)}° '
      'INC:${inc.toStringAsFixed(1)}° SD:${sd.toStringAsFixed(1)}m)';
}
