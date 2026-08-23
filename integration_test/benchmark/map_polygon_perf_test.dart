// ポリゴン負荷時の地図バックエンド性能（Windows / Android 共通）
//
// 実行:
//   flutter test integration_test/benchmark/map_polygon_perf_test.dart -d windows
//   flutter test integration_test/benchmark/map_polygon_perf_test.dart -d <android device>
//
// 目的:
//   森林簿の実運用規模（数千ポリゴン）を載せた状態で操作できるかを見る。
//   map_perf_test.dart は空スタイル + ポイントなので、ここが測れていなかった。
//
//   特に WebView バックエンド（Windows）は GeoJSON を**文字列として JSブリッジ経由**で
//   渡すため、頂点数がそのまま転送コストになる。ネイティブ（Android）との差が
//   出るならここに出る、という想定で測る。
//
//   合否は判定しない。数字を出すだけ。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' as ml;
import 'package:root_maps/core/r_map_controller.dart';
import 'package:root_maps/widgets/map/r_map_widget.dart';

import '../support/harness.dart';

const kCenter = LatLng(33.9707, 135.8534);
const kZoom = 13.0;
const kMapSize = Size(800, 600);

/// 測る規模。3000が松本さんの想定する実運用規模。
const kPolygonCounts = [500, 1500, 3000];

/// 1ポリゴンあたりの頂点数。林小班の輪郭を想定してやや多めに取る。
const kVerticesPerPolygon = 40;

final _report = <String, String>{};

/// [count] 個のポリゴンを持つGeoJSONを組み立てる。
///
/// 北山村付近に格子状に並べ、各ポリゴンは [kVerticesPerPolygon] 頂点の
/// 円形ポリゴン（林小班の輪郭を粗く模したもの）。
String _buildPolygonGeoJson(int count) {
  final buf = StringBuffer('{"type":"FeatureCollection","features":[');
  for (var i = 0; i < count; i++) {
    if (i > 0) buf.write(',');
    final cx = 135.78 + (i % 60) * 0.002;
    final cy = 33.92 + (i ~/ 60) * 0.002;
    const r = 0.0008;

    buf.write(
      '{"type":"Feature","properties":{"id":$i,"name":"林小班$i"},'
      '"geometry":{"type":"Polygon","coordinates":[[',
    );
    for (var v = 0; v <= kVerticesPerPolygon; v++) {
      if (v > 0) buf.write(',');
      // 円周上に頂点を置く（最後は始点に戻して閉じる）
      final t = (v % kVerticesPerPolygon) / kVerticesPerPolygon * 6.283185307;
      // dart:math を使わずに済ませるため、粗い多角形近似で十分
      final dx = r * _cos(t);
      final dy = r * _sin(t);
      buf.write(
        '[${(cx + dx).toStringAsFixed(7)},'
        '${(cy + dy).toStringAsFixed(7)}]',
      );
    }
    buf.write(']]}}');
  }
  buf.write(']}');
  return buf.toString();
}

// テイラー展開の打ち切りで十分（形が閉じたポリゴンになればよい）
double _cos(double x) {
  final t = x % 6.283185307;
  final u = t > 3.141592653 ? t - 6.283185307 : t;
  final u2 = u * u;
  return 1 - u2 / 2 + u2 * u2 / 24 - u2 * u2 * u2 / 720;
}

double _sin(double x) {
  final t = x % 6.283185307;
  final u = t > 3.141592653 ? t - 6.283185307 : t;
  final u2 = u * u;
  return u * (1 - u2 / 6 + u2 * u2 / 120 - u2 * u2 * u2 / 5040);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('ポリゴン負荷 [$platformName]', () {
    late RMapController controller;
    late ml.StyleController style;

    Future<void> pumpMap(WidgetTester tester) async {
      var styleLoaded = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: kMapSize.width,
                height: kMapSize.height,
                child: RMapWidget(
                  options: ml.MapOptions(
                    initStyle: kEmptyMapStyle,
                    initCenter: ml.Geographic(
                      lon: kCenter.longitude,
                      lat: kCenter.latitude,
                    ),
                    initZoom: kZoom,
                  ),
                  onMapCreated: (c) => controller = c,
                  onStyleLoaded: (c, s) {
                    controller = c;
                    style = s;
                    styleLoaded = true;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await pumpUntil(
        tester,
        () => styleLoaded,
        timeout: const Duration(seconds: 60),
        step: const Duration(milliseconds: 16),
        reason: 'onStyleLoaded が発火しない',
      );
    }

    for (final count in kPolygonCounts) {
      testWidgets('$count ポリゴン', (tester) async {
        await pumpMap(tester);

        final sourceId = 'poly-src-$count';
        final fillId = 'poly-fill-$count';
        final lineId = 'poly-line-$count';

        // --- 生成（Dart側のコスト。バックエンドとは無関係だが分離して見る）
        final swBuild = Stopwatch()..start();
        final geoJson = _buildPolygonGeoJson(count);
        swBuild.stop();
        final payloadKb = (geoJson.length / 1024).round();

        // --- 追加（ソース + 塗り + 輪郭。実際のレイヤ構成に合わせる）
        final swAdd = Stopwatch()..start();
        await style.addSource(ml.GeoJsonSource(id: sourceId, data: geoJson));
        await style.addLayer(ml.FillStyleLayer(id: fillId, sourceId: sourceId));
        await style.addLayer(ml.LineStyleLayer(id: lineId, sourceId: sourceId));
        await tester.pump(const Duration(milliseconds: 16));
        swAdd.stop();

        // --- 更新（属性編集後の再描画に相当。実運用で一番よく走る）
        final swUpdate = Stopwatch()..start();
        await style.updateGeoJsonSource(id: sourceId, data: geoJson);
        await tester.pump(const Duration(milliseconds: 16));
        swUpdate.stop();

        // --- 表示したままカメラを動かしたときの反映遅延
        final samples = <int>[];
        for (var i = 0; i < 10; i++) {
          final target = LatLng(
            kCenter.latitude + i * 2e-4,
            kCenter.longitude + i * 2e-4,
          );
          final sw = Stopwatch()..start();
          controller.move(target, kZoom);
          await pumpUntil(
            tester,
            () =>
                (controller.camera.center.latitude - target.latitude).abs() <
                1e-5,
            timeout: const Duration(seconds: 10),
            step: const Duration(milliseconds: 4),
            reason: 'move() が反映されない',
          );
          sw.stop();
          samples.add(sw.elapsedMilliseconds);
        }
        samples.sort();

        // --- 負荷下での座標変換（ペン描画のコストに相当）
        final swProject = Stopwatch()..start();
        for (var i = 0; i < 1000; i++) {
          controller.toScreenLocation(
            LatLng(kCenter.latitude + i * 1e-5, kCenter.longitude + i * 1e-5),
          );
        }
        swProject.stop();

        _report['${count}poly_payload'] = '${payloadKb}KB';
        _report['${count}poly_build'] = '${swBuild.elapsedMilliseconds}ms';
        _report['${count}poly_add'] = '${swAdd.elapsedMilliseconds}ms';
        _report['${count}poly_update'] = '${swUpdate.elapsedMilliseconds}ms';
        _report['${count}poly_move_median'] =
            '${samples[samples.length ~/ 2]}ms';
        _report['${count}poly_move_max'] = '${samples.last}ms';
        _report['${count}poly_project1000'] =
            '${swProject.elapsedMicroseconds ~/ 1000}ms';

        // 後片付け
        await style.removeLayer(lineId);
        await style.removeLayer(fillId);
        await style.removeSource(sourceId);
      });
    }

    tearDownAll(() {
      // ignore: avoid_print
      print('');
      // ignore: avoid_print
      print(
        '===== ポリゴン負荷 [$platformName] '
        '($kVerticesPerPolygon 頂点/ポリゴン) =====',
      );
      for (final e in _report.entries) {
        // ignore: avoid_print
        print('${e.key.padRight(26)} ${e.value}');
      }
      // ignore: avoid_print
      print('==================================================');
    });
  }, skip: skipUnless(hasMapBackend, '地図バックエンド未実装'));
}
