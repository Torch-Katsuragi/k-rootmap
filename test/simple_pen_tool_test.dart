import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/gestures.dart';
import '../lib/tools/pen_tool.dart';
import '../lib/models/layer_tree_node.dart';
import '../lib/utils/global_config.dart';

void main() {
  group('PenTool Simple Tests', () {
    late PenTool penTool;

    setUp(() {
      // 基本的な初期化
      GlobalConfig.instance.folderTree = FolderNode("test", visible: true);
      penTool = PenTool();
    });

    test('PolygonLayerNode mock test', () {
      // Mock PolygonLayerNode作成
      final mockPolygonLayer = MockPolygonLayerNode('test_polygon');
      GlobalConfig.instance.selectedLayerNode = mockPolygonLayer;

      // MockMapState作成
      final mockMapState = SimpleMockMapState();

      // 3点でポリゴンを描画
      final points = [
        LatLng(35.681, 139.767),
        LatLng(35.682, 139.767),
        LatLng(35.682, 139.768),
      ];

      print('[TEST] Starting polygon tap simulation');

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

        print(
          '[TEST] Point ${i + 1} added successfully. Total points: ${penTool.drawingPolygon.length}',
        );
      }

      expect(penTool.drawingPolygon.length, equals(3));
      print('[TEST] Polygon tap simulation completed successfully');
    });

    test('UI update optimization test', () async {
      // Mock PolygonLayerNode作成
      final mockPolygonLayer = MockPolygonLayerNode('test_polygon');
      GlobalConfig.instance.selectedLayerNode = mockPolygonLayer;

      // MockMapState作成
      final mockMapState = SimpleMockMapState();

      // タップ処理を複数回実行してフリーズしないか確認
      final point = LatLng(35.681, 139.767);

      for (int i = 0; i < 5; i++) {
        print('[TEST] Rapid tap test - iteration ${i + 1}');

        final tapDetails = TapUpDetails(
          kind: PointerDeviceKind.touch,
          localPosition: Offset(100, 100),
          globalPosition: Offset(100, 100),
        );
        mockMapState.mockLatLng = point;

        final stopwatch = Stopwatch()..start();
        penTool.onTap(tapDetails, mockMapState);
        stopwatch.stop();

        print(
          '[TEST] Tap ${i + 1} completed in ${stopwatch.elapsedMilliseconds}ms',
        );

        // 各タップの処理が1秒以内に完了することを確認
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));

        // UI更新の完了を待つ
        await Future.delayed(Duration(milliseconds: 10));
      }

      expect(penTool.drawingPolygon.length, equals(5));
      print('[TEST] Rapid tap test completed successfully');
    });
  });
}

/// Mock PolygonLayerNode
class MockPolygonLayerNode extends LayerTreeNode {
  MockPolygonLayerNode(String name) : super(name, nodeType: 'layer');

  @override
  IconData get baseIcon => Icons.layers;

  @override
  Color get baseIconColor => Colors.green;

  @override
  bool isVisibleRecursive() => true;
}

/// 簡易MockMapState
class SimpleMockMapState {
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
    return SimpleMockBuildContext();
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

/// 簡易MockBuildContext
class SimpleMockBuildContext implements BuildContext {
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

  @override
  T? getInheritedWidgetOfExactType<T extends InheritedWidget>() => null;
}
