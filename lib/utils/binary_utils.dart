// K-MAPS: Binary Utilities
// バイト変換ヘルパー（Shapefile等のバイナリファイル処理用）
import 'dart:typed_data';
import 'package:charset/charset.dart' as charset;
import 'package:k_maps/utils/app_logger.dart';

/// バイナリ変換ユーティリティクラス
class BinaryUtils {
  /// 32bit整数をビッグエンディアンで書き込み
  static List<int> writeInt32BigEndian(int value) {
    return [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }

  /// 32bit整数をリトルエンディアンで書き込み
  static List<int> writeInt32LittleEndian(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];
  }

  /// 16bit整数をリトルエンディアンで書き込み
  static List<int> writeInt16LittleEndian(int value) {
    return [value & 0xFF, (value >> 8) & 0xFF];
  }

  /// 64bit浮動小数点をリトルエンディアンで書き込み
  static List<int> writeFloat64(double value) {
    final buffer = ByteData(8);
    buffer.setFloat64(0, value, Endian.little);
    return buffer.buffer.asUint8List().toList();
  }

  /// 32bit整数をビッグエンディアンで読み込み
  static int readInt32BigEndian(Uint8List bytes, int offset) {
    return ByteData.sublistView(bytes, offset, offset + 4)
        .getInt32(0, Endian.big);
  }

  /// 32bit整数をリトルエンディアンで読み込み
  static int readInt32LittleEndian(Uint8List bytes, int offset) {
    return ByteData.sublistView(bytes, offset, offset + 4)
        .getInt32(0, Endian.little);
  }

  /// 32bit符号なし整数をリトルエンディアンで読み込み
  static int readUint32LittleEndian(Uint8List bytes, int offset) {
    return ByteData.sublistView(bytes, offset, offset + 4)
        .getUint32(0, Endian.little);
  }

  /// 16bit符号なし整数をリトルエンディアンで読み込み
  static int readUint16LittleEndian(Uint8List bytes, int offset) {
    return ByteData.sublistView(bytes, offset, offset + 2)
        .getUint16(0, Endian.little);
  }

  /// 64bit浮動小数点をリトルエンディアンで読み込み
  static double readFloat64LittleEndian(Uint8List bytes, int offset) {
    return ByteData.sublistView(bytes, offset, offset + 8)
        .getFloat64(0, Endian.little);
  }

  /// 文字列をShift-JIS（CP932）でエンコードし、指定バイト長に調整
  /// [padWithSpace] trueの場合はスペース(0x20)でパディング、falseの場合はNULL(0x00)
  static List<int> encodeToShiftJis(
    String text,
    int byteLength, {
    bool padWithSpace = false,
  }) {
    try {
      final encoded = charset.shiftJis.encode(text);
      final padByte = padWithSpace ? 0x20 : 0x00;

      if (encoded.length >= byteLength) {
        return encoded.sublist(0, byteLength);
      } else {
        final result = List<int>.from(encoded);
        result.addAll(List.filled(byteLength - encoded.length, padByte));
        return result;
      }
    } catch (e) {
      AppLogger.debug('[BinaryUtils] Shift-JISエンコード失敗: $e');
      final padByte = padWithSpace ? 0x20 : 0x00;
      final asciiBytes =
          text.codeUnits.where((c) => c < 128).take(byteLength).toList();
      if (asciiBytes.length < byteLength) {
        asciiBytes.addAll(List.filled(byteLength - asciiBytes.length, padByte));
      }
      return asciiBytes;
    }
  }

  /// Shift-JIS（CP932）でデコード
  static String decodeFromShiftJis(List<int> bytes) {
    try {
      return charset.shiftJis.decode(bytes);
    } catch (e) {
      AppLogger.debug('[BinaryUtils] Shift-JISデコード失敗: $e');
      // フォールバック: ASCII範囲のみ
      return String.fromCharCodes(bytes.where((c) => c >= 0x20 && c < 0x7F));
    }
  }
}

/// バウンディングボックスを表すクラス
class BoundingBox {
  double minX;
  double minY;
  double maxX;
  double maxY;

  BoundingBox({
    this.minX = double.infinity,
    this.minY = double.infinity,
    this.maxX = double.negativeInfinity,
    this.maxY = double.negativeInfinity,
  });

  /// 座標を追加してバウンディングボックスを更新
  void extend(double x, double y) {
    if (x.isFinite && y.isFinite) {
      if (minX.isFinite) {
        minX = minX < x ? minX : x;
        maxX = maxX > x ? maxX : x;
      } else {
        minX = maxX = x;
      }
      if (minY.isFinite) {
        minY = minY < y ? minY : y;
        maxY = maxY > y ? maxY : y;
      } else {
        minY = maxY = y;
      }
    }
  }

  /// バウンディングボックスが有効かチェック
  bool get isValid =>
      minX.isFinite && maxX.isFinite && minY.isFinite && maxY.isFinite;

  /// 無効な場合はデフォルト値を設定
  void ensureValid() {
    if (!minX.isFinite) minX = 0.0;
    if (!maxX.isFinite) maxX = 0.0;
    if (!minY.isFinite) minY = 0.0;
    if (!maxY.isFinite) maxY = 0.0;
  }
}

