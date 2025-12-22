/// K-MAPS: 地図状態の抽象インターフェース
/// MapToolやその他のクラスで型安全にMapPageStateにアクセスするためのインターフェース
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

/// 地図状態の抽象インターフェース
/// 
/// [MapTool]やウィジェットからMapPageのStateに型安全にアクセスするために使用。
/// これにより、dynamic型を排除し、IDE補完とコンパイル時型チェックを有効化。
abstract class IMapState {
  /// 画面座標を地図座標（緯度経度）に変換
  LatLng offsetToLatLng(Offset offset);

  /// 地図座標（緯度経度）を画面座標に変換
  Offset latLngToOffset(LatLng latlng);

  /// UIの再描画をトリガー
  void setState(VoidCallback fn);

  /// フィーチャキャッシュを更新し、地図を再描画
  void refreshFeatures();

  /// マップの強制更新処理（レイヤ削除時などに使用）
  void forceMapRefresh();

  /// このStateに関連付けられたBuildContext
  BuildContext get context;

  /// ポリゴンのリングを閉じる（始点と終点を一致させる）
  List<LatLng> closeRing(List<LatLng> points);

  /// FlutterMapのMapController
  MapController get mapController;

  /// StateがWidgetツリーにマウントされているか
  bool get mounted;
}


