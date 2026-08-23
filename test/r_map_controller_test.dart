// RMapController のカメラ操作保留（attach前呼び出し）のテスト
//
// 背景:
//   地図の生成（プラットフォームビューの立ち上げ・WebView2の起動）は重く、
//   GPSの初回フィックスのほうが先に届くことがある。
//   以前は attach 前の move() が `?.` で黙って捨てられ、呼び出し側は
//   「ジャンプ済み」のフラグだけ立てていたため、
//   **起動時に現在地へ飛ばない**という不具合になっていた（Android/Windows共通）。
//
//   端末が要らないロジックなのでユニットテストで固定する。
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geobase/geobase.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' as ml;
import 'package:root_maps/core/r_map_controller.dart';

/// 呼ばれた moveCamera を記録するだけのダミー。
///
/// `ml.MapController` は abstract interface class で実装すべきメンバーが多いため、
/// 必要な moveCamera だけ実装し、残りは noSuchMethod に流す。
class _RecordingMapController implements ml.MapController {
  final List<({Geographic? center, double? zoom, double? bearing})> moves = [];

  @override
  Future<void> moveCamera({
    Geographic? center,
    double? zoom,
    double? bearing,
    double? pitch,
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    moves.add((center: center, zoom: zoom, bearing: bearing));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// StyleController のダミー。attachStyle を呼ぶためだけに使う。
class _FakeStyleController implements ml.StyleController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 地図が操作可能になるところまで進める。
///
/// 保留分が流れるのは attachStyle（onStyleLoaded）の時点。
/// onMapCreated の意味がバックエンドで違い、WebViewではその時点でまだ
/// JS側の地図が存在しないため。
void _makeReady(RMapController controller, _RecordingMapController raw) {
  controller.attach(raw);
  controller.attachStyle(_FakeStyleController());
}

void main() {
  const tokyo = LatLng(35.6812, 139.7671);
  const kitayama = LatLng(33.9707, 135.8534);

  group('RMapController のカメラ操作保留', () {
    test('attach 前の move() は false を返し、スタイル読込時に実行される', () {
      final controller = RMapController();
      expect(controller.isAttached, isFalse);

      // 地図がまだ生成されていない状態での呼び出し
      final applied = controller.move(kitayama, 16.0);
      expect(applied, isFalse, reason: 'attach前なので即時反映はされない');

      final raw = _RecordingMapController();
      expect(raw.moves, isEmpty, reason: 'attach前に下位へ流れてはいけない');

      _makeReady(controller, raw);

      expect(raw.moves, hasLength(1), reason: 'スタイル読込時に保留分が実行されるべき');
      expect(raw.moves.single.zoom, 16.0);
      expect(raw.moves.single.center?.lat, closeTo(kitayama.latitude, 1e-9));
      expect(raw.moves.single.center?.lon, closeTo(kitayama.longitude, 1e-9));
    });

    test('スタイル読込後の move() は true を返し、即座に反映される', () {
      final controller = RMapController();
      final raw = _RecordingMapController();
      _makeReady(controller, raw);

      final applied = controller.move(kitayama, 14.0);

      expect(applied, isTrue);
      expect(raw.moves, hasLength(1));
      expect(raw.moves.single.zoom, 14.0);
    });

    test('保留は最後の1件だけ実行される（カメラ操作は上書きが正しい）', () {
      final controller = RMapController();

      controller.move(tokyo, 10.0);
      controller.move(kitayama, 16.0);

      final raw = _RecordingMapController();
      _makeReady(controller, raw);

      expect(raw.moves, hasLength(1), reason: '溜め込んだぶんを全部流してはいけない');
      expect(raw.moves.single.zoom, 16.0);
      expect(raw.moves.single.center?.lat, closeTo(kitayama.latitude, 1e-9));
    });

    test('地図が使える状態なら以降の move で保留は再発しない', () {
      final controller = RMapController();
      final raw = _RecordingMapController();

      controller.move(kitayama, 16.0); // 保留
      _makeReady(controller, raw); // 実行
      controller.move(tokyo, 12.0); // 即時

      expect(raw.moves, hasLength(2));
      expect(raw.moves.last.zoom, 12.0);
    });

    test('attach 前の moveAndRotate() も保留され、bearing まで復元される', () {
      final controller = RMapController();

      final applied = controller.moveAndRotate(kitayama, 15.0, 45.0);
      expect(applied, isFalse);

      final raw = _RecordingMapController();
      _makeReady(controller, raw);

      expect(raw.moves, hasLength(1));
      expect(raw.moves.single.zoom, 15.0);
      expect(raw.moves.single.bearing, 45.0);
    });

    test('attach だけでは保留を流さない（WebViewはこの時点でJS地図が未生成）', () {
      final controller = RMapController();
      controller.move(kitayama, 16.0);

      final raw = _RecordingMapController();
      controller.attach(raw);

      expect(
        raw.moves,
        isEmpty,
        reason: 'onMapCreated の時点ではWebViewの地図がまだ無い。ここで流すと落ちる',
      );
      expect(controller.isAttached, isFalse, reason: 'スタイル未読込は「使える」ではない');

      controller.attachStyle(_FakeStyleController());

      expect(raw.moves, hasLength(1));
      expect(controller.isAttached, isTrue);
    });

    test('dispose すると保留は破棄される', () {
      final controller = RMapController();
      controller.move(kitayama, 16.0);

      controller.dispose();

      final raw = _RecordingMapController();
      _makeReady(controller, raw);

      expect(raw.moves, isEmpty, reason: 'dispose 後に古い保留が蘇ってはいけない');
    });
  });
}
