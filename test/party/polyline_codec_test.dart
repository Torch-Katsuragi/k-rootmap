// PolylineCodec のエンコード/デコード往復テスト
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:root_maps/services/party/polyline_codec.dart';

void main() {
  group('PolylineCodec', () {
    test('Google公式例と一致する', () {
      // https://developers.google.com/maps/documentation/utilities/polylinealgorithm
      final points = [
        const LatLng(38.5, -120.2),
        const LatLng(40.7, -120.95),
        const LatLng(43.252, -126.453),
      ];
      expect(PolylineCodec.encode(points), '_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    });

    test('decode は encode の逆', () {
      const expected = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
      final decoded = PolylineCodec.decode(expected);
      expect(decoded, hasLength(3));
      expect(decoded[0].latitude, closeTo(38.5, 1e-5));
      expect(decoded[0].longitude, closeTo(-120.2, 1e-5));
      expect(decoded[2].latitude, closeTo(43.252, 1e-5));
      expect(decoded[2].longitude, closeTo(-126.453, 1e-5));
    });

    test('往復で精度1e-5以内を保つ', () {
      final points = [
        const LatLng(35.681236, 139.767125), // 東京駅
        const LatLng(35.658034, 139.701636), // 渋谷駅
        const LatLng(35.689487, 139.691711), // 新宿駅
      ];
      final round = PolylineCodec.decode(PolylineCodec.encode(points));
      expect(round, hasLength(points.length));
      for (var i = 0; i < points.length; i++) {
        expect(round[i].latitude, closeTo(points[i].latitude, 1e-5));
        expect(round[i].longitude, closeTo(points[i].longitude, 1e-5));
      }
    });

    test('空リストは空文字', () {
      expect(PolylineCodec.encode([]), '');
      expect(PolylineCodec.decode(''), isEmpty);
    });
  });
}
