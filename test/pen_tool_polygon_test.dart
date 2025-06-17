import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/gestures.dart';
import '../lib/tools/pen_tool.dart';
import '../lib/models/layer_tree_node.dart';
import '../lib/utils/global_config.dart';
import 'dart:io';

void main() {
  group('PenTool Polygon Tap Tests', () {
    late PenTool penTool;
    late PolygonLayerNode testPolygonLayer;
    late MockMapState mockMapState;

    setUp(() async {
      // グローバル設定初期化
      GlobalConfig.instance.folderTree = FolderNode("test", visible: true);

      // テスト用ディレクトリ作成
      final testDir = Directory.systemTemp.createTempSync('pen_tool_test');
      final gpkgPath = '${testDir.path}/test.gpkg';

      try {
        // テスト用GeoPackageとポリゴンレイヤー作成
        final gpkgNode = await GeoPackageNode.createNewFile(
          gpkgPath,
          GlobalConfig.instance.folderTree!,
        );

        if (gpkgNode != null) {
          testPolygonLayer = await PolygonLayerNode.createIn(
            gpkgNode,
            'test_polygons',
          );
          GlobalConfig.instance.selectedLayerNode = testPolygonLayer;

          // PenTool初期化
          penTool = PenTool();

          // MockMapState初期化
          mockMapState = MockMapState();

          print('[TEST] Setup complete - GeoPackage: $gpkgPath');
        } else {
          throw Exception('Failed to create test GeoPackage');
        }
      } catch (e) {
        print('[TEST] Setup error: $e');
        rethrow;
      }
    });

    tearDown(() {
      // テスト用ファイルのクリーンアップ
      try {
        final testDir =
            Directory.systemTemp
                .listSync()
                .where((entity) => entity.path.contains('pen_tool_test'))
                .toList();
        for (final dir in testDir) {
          if (dir is Directory) {
            dir.deleteSync(recursive: true);
          }
        }
      } catch (e) {
        print('[TEST] Cleanup error: $e');
      }
    });

    test('Polygon drawing with taps should not freeze', () async {
      print('[TEST] Starting polygon tap test');

      // テスト用座標
      final point1 = LatLng(35.681, 139.767);
      final point2 = LatLng(35.682, 139.767);
      final point3 = LatLng(35.682, 139.768);

      // 1点目をタップ
      print('[TEST] Adding point 1: $point1');
      final tapDetails1 = TapUpDetails(
        kind: PointerDeviceKind.touch,
        localPosition: Offset(100, 100),
        globalPosition: Offset(100, 100),
      );
      mockMapState.mockLatLng = point1;

      expect(
        () => penTool.onTap(tapDetails1, mockMapState),
        isNot(throwsA(anything)),
      );
      expect(penTool.drawingPolygon.length, equals(1));
      expect(penTool.drawingPolygon.first, equals(point1));

      print('[TEST] Point 1 added successfully');

      // 2点目をタップ
      print('[TEST] Adding point 2: $point2');
      final tapDetails2 = TapUpDetails(
        kind: PointerDeviceKind.touch,
        localPosition: Offset(150, 100),
        globalPosition: Offset(150, 100),
      );
      mockMapState.mockLatLng = point2;

      expect(
        () => penTool.onTap(tapDetails2, mockMapState),
        isNot(throwsA(anything)),
      );
      expect(penTool.drawingPolygon.length, equals(2));
      expect(penTool.drawingPolygon[1], equals(point2));

      print('[TEST] Point 2 added successfully');

      // 3点目をタップ（ここでフリーズが発生する可能性）
      print('[TEST] Adding point 3: $point3');
      final tapDetails3 = TapUpDetails(
        kind: PointerDeviceKind.touch,
        localPosition: Offset(150, 150),
        globalPosition: Offset(150, 150),
      );
      mockMapState.mockLatLng = point3;

      expect(
        () => penTool.onTap(tapDetails3, mockMapState),
        isNot(throwsA(anything)),
      );
      expect(penTool.drawingPolygon.length, equals(3));
      expect(penTool.drawingPolygon[2], equals(point3));

      print('[TEST] Point 3 added successfully');

      // 描画状態の検証
      expect(penTool.drawingPolygon.isNotEmpty, isTrue);
      expect(penTool.drawingPolygon.length, equals(3));

      print('[TEST] Polygon tap test completed successfully');
    });

    test('Multiple polygon tap additions should be stable', () async {
      print('[TEST] Starting multiple polygon tap test');

      // 5点でポリゴンを作成
      final points = [
        LatLng(35.681, 139.767),
        LatLng(35.682, 139.767),
        LatLng(35.682, 139.768),
        LatLng(35.681, 139.768),
        LatLng(35.680, 139.7675),
      ];

      for (int i = 0; i < points.length; i++) {
        print('[TEST] Adding point ${i + 1}: ${points[i]}');

        final tapDetails = TapUpDetails(
          kind: PointerDeviceKind.touch,
          localPosition: Offset(100 + i * 10.0, 100 + i * 10.0),
          globalPosition: Offset(100 + i * 10.0, 100 + i * 10.0),
        );
        mockMapState.mockLatLng = points[i];

        expect(
          () => penTool.onTap(tapDetails, mockMapState),
          isNot(throwsA(anything)),
        );
        expect(penTool.drawingPolygon.length, equals(i + 1));
        expect(penTool.drawingPolygon[i], equals(points[i]));

        // UI更新処理の安定性をチェック
        expect(mockMapState.setStateCallCount, greaterThan(i));

        print('[TEST] Point ${i + 1} added successfully');
      }

      expect(penTool.drawingPolygon.length, equals(5));
      print('[TEST] Multiple polygon tap test completed successfully');
    });
  });
}

/// モックMapStateクラス（テスト用）
class MockMapState {
  LatLng? mockLatLng;
  int setStateCallCount = 0;

  LatLng offsetToLatLng(Offset offset) {
    return mockLatLng ?? LatLng(35.681236, 139.767125);
  }

  void setState(VoidCallback fn) {
    setStateCallCount++;
    print('[MOCK] setState called ($setStateCallCount)');
    fn();
  }

  void refreshFeatures() {
    print('[MOCK] refreshFeatures called');
  }

  BuildContext get context {
    // テスト用の簡易的なBuildContext
    return _MockBuildContext();
  }

  List<LatLng> closeRing(List<LatLng> points) {
    if (points.length < 3) return points;
    final first = points.first;
    final last = points.last;
    if (first.latitude != last.latitude || first.longitude != last.longitude) {
      return List<LatLng>.from(points)..add(first);
    }
    return points;
  }
}

/// モックBuildContextクラス（テスト用）
class _MockBuildContext implements BuildContext {
  @override
  bool get debugDoingBuild => false;

  @override
  InheritedWidget? dependOnInheritedElement(
    InheritedElement ancestor, {
    Object? aspect,
  }) => null;

  @override
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>({
    Object? aspect,
  }) => null;

  @override
  DiagnosticsNode describeElement(
    String name, {
    DiagnosticsTreeStyle style = DiagnosticsTreeStyle.errorProperty,
  }) {
    throw UnimplementedError();
  }

  @override
  List<DiagnosticsNode> describeMissingAncestor({
    required Type expectedAncestorType,
  }) {
    throw UnimplementedError();
  }

  @override
  DiagnosticsNode describeOwnershipChain(String name) {
    throw UnimplementedError();
  }

  @override
  DiagnosticsNode describeWidget(
    String name, {
    DiagnosticsTreeStyle style = DiagnosticsTreeStyle.errorProperty,
  }) {
    throw UnimplementedError();
  }

  @override
  void dispatchNotification(Notification notification) {}

  @override
  T? findAncestorRenderObjectOfType<T extends RenderObject>() => null;

  @override
  T? findAncestorStateOfType<T extends State<StatefulWidget>>() => null;

  @override
  T? findAncestorWidgetOfExactType<T extends Widget>() => null;

  @override
  RenderObject? findRenderObject() => null;

  @override
  T? findRootAncestorStateOfType<T extends State<StatefulWidget>>() => null;

  @override
  InheritedElement?
  getElementForInheritedWidgetOfExactType<T extends InheritedWidget>() => null;

  @override
  BuildOwner get owner => throw UnimplementedError();

  @override
  Size get size => Size.zero;

  @override
  void visitAncestorElements(bool Function(Element element) visitor) {}

  @override
  void visitChildElements(ElementVisitor visitor) {}

  @override
  Widget get widget => throw UnimplementedError();

  @override
  bool get mounted => true;
}
