// gps_history_gap_provider: 圏外区間の軌跡生成テスト
import 'package:flutter_test/flutter_test.dart';
import 'package:root_maps/models/gps_track.dart';
import 'package:root_maps/services/party/gps_history_gap_provider.dart';
import 'package:root_maps/services/party/polyline_codec.dart';

GpsTrackPoint _pt(double lat, double lng, DateTime t) => GpsTrackPoint(
      latitude: lat,
      longitude: lng,
      timestamp: t,
      sourceType: 'GPS',
    );

void main() {
  group('makeGapProvider', () {
    test('点列をエンコード済みポリラインに変換する', () async {
      final base = DateTime(2026, 6, 23, 12);
      final pts = [
        _pt(35.0000, 139.0000, base),
        _pt(35.0010, 139.0010, base.add(const Duration(minutes: 1))),
        _pt(35.0020, 139.0020, base.add(const Duration(minutes: 2))),
      ];
      final provider = makeGapProvider((key, start, end) async => pts);

      final from = base.millisecondsSinceEpoch;
      final to = base.add(const Duration(minutes: 3)).millisecondsSinceEpoch;
      final gap = await provider(from, to);

      expect(gap, isNotNull);
      expect(gap!.fromMs, from);
      expect(gap.toMs, to);
      final decoded = PolylineCodec.decode(gap.encodedPolyline);
      expect(decoded.length, greaterThanOrEqualTo(2));
      // 端点は保持される
      expect(decoded.first.latitude, closeTo(35.0000, 1e-4));
      expect(decoded.last.latitude, closeTo(35.0020, 1e-4));
    });

    test('点が1点以下なら null', () async {
      final base = DateTime(2026, 6, 23, 12);
      final provider = makeGapProvider(
        (key, start, end) async => [_pt(35, 139, base)],
      );
      final gap = await provider(
        base.millisecondsSinceEpoch,
        base.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      );
      expect(gap, isNull);
    });

    test('to <= from なら null（フェッチせず即返す）', () async {
      var called = false;
      final provider = makeGapProvider((key, start, end) async {
        called = true;
        return [];
      });
      final t = DateTime(2026, 6, 23, 12).millisecondsSinceEpoch;
      expect(await provider(t, t), isNull);
      expect(called, isFalse);
    });

    test('日付をまたぐ区間は両日のキーで取得する', () async {
      final queried = <String>[];
      final provider = makeGapProvider((key, start, end) async {
        queried.add(key);
        return [];
      });
      final from = DateTime(2026, 6, 23, 23, 50).millisecondsSinceEpoch;
      final to = DateTime(2026, 6, 24, 0, 10).millisecondsSinceEpoch;
      await provider(from, to);
      expect(queried, containsAll(['2026_06_23', '2026_06_24']));
    });
  });
}
