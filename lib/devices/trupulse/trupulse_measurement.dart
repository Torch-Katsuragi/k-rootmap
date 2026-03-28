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
