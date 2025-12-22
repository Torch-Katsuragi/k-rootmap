// K-MAPS: フィーチャキャッシュ管理mixin
// map_page.dartからフィーチャキャッシュ機能を分離して保守性を向上
// 
// TODO: map_page.dartへの統合時に完全実装する
// このファイルは将来のリファクタリング用のプレースホルダーです

import 'package:flutter/material.dart';
import '../../models/nodes/feature_node.dart';
import '../../models/nodes/image_node.dart';

/// フィーチャキャッシュに必要な状態へのアクセスを提供するインターフェース
/// map_page.dartへの統合時にこのインターフェースを実装
mixin MapFeatureCacheState {
  // キャッシュリスト
  List<PointFeatureNode> get pointFeatures;
  set pointFeatures(List<PointFeatureNode> value);
  List<LineFeatureNode> get lineFeatures;
  set lineFeatures(List<LineFeatureNode> value);
  List<PolygonFeatureNode> get polygonFeatures;
  set polygonFeatures(List<PolygonFeatureNode> value);
  List<ImageNode> get photoNodes;
  set photoNodes(List<ImageNode> value);
  
  /// triggerSetState代理メソッド
  void triggerSetState(VoidCallback fn);
  
  /// mountedプロパティ
  bool get mounted;
}

/// フィーチャキャッシュ管理mixin
/// 地図表示用のフィーチャキャッシュを効率的に管理
/// 
/// 使用方法（将来の統合時）:
/// ```dart
/// class _MapPageState extends State<MapPage>
///     with MapFeatureCacheState, MapFeatureCacheMixin {
///   // ...
/// }
/// ```
mixin MapFeatureCacheMixin on MapFeatureCacheState {
  /// フィーチャキャッシュを更新してUIを再描画
  /// 
  /// 実装はmap_page.dart統合時に完了
  void refreshFeaturesCache() {
    // updateFeatures()を呼び出す
  }

  /// マップUIを強制リフレッシュ
  void forceRefreshMapUI() {
    // フィーチャキャッシュをクリアして再取得
    pointFeatures = [];
    lineFeatures = [];
    polygonFeatures = [];
    photoNodes = [];

    if (mounted) {
      triggerSetState(() {});
    }
  }
}


