// K-MAPS: MapPage状態の基底mixin
// 全てのMixinが共通でアクセスする状態変数を定義
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../../models/nodes/layer_tree_node.dart';
import '../../models/nodes/layer_node.dart';
import '../../models/nodes/feature_node.dart';
import '../../models/nodes/image_node.dart';
import '../../models/gps_position_record.dart';
import '../../services/gps_manager_service.dart';
import '../../services/internal_gps_location_store.dart';
import '../../services/gps_history_recorder.dart';
import '../../interfaces/map_state_interface.dart';

/// MapPageの状態変数を定義する基底mixin
/// 各機能別Mixinはこのmixinを継承（on）して状態にアクセス
mixin MapPageStateBase<T extends StatefulWidget> on State<T>, TickerProviderStateMixin<T>
    implements IMapState {
  // =============================================
  // 地図基本状態
  // =============================================
  
  /// 地図の初期中心座標（東京駅）
  final LatLng defaultCenter = const LatLng(35.681236, 139.767125);
  
  /// 現在位置
  LatLng? currentLocation;
  
  /// 位置情報ストリームサブスクリプション（Store.positionStream購読用）
  StreamSubscription<GpsPositionRecord>? positionSubscription;
  
  /// 初回の現在位置移動フラグ
  bool movedToCurrentLocationOnce = false;
  
  /// 地図コントローラー
  final MapController mapControllerInstance = MapController();
  
  @override
  MapController get mapController => mapControllerInstance;
  
  // =============================================
  // コンパス関連
  // =============================================
  
  /// 現在のデバイス方角（度数）
  double? currentHeading;
  
  /// コンパスイベントサブスクリプション
  StreamSubscription<CompassEvent>? compassSubscription;
  
  // =============================================
  // レイヤーツリー関連
  // =============================================
  
  /// 現在選択中のノード
  LayerTreeNode? currentNode;
  
  // =============================================
  // ドロワー関連
  // =============================================
  
  /// ドロワー幅
  double drawerWidth = 320;
  
  /// ドロワー開閉状態
  bool drawerOpen = true;
  
  /// ドロワー最小幅
  final double minDrawerWidth = 200;
  
  // =============================================
  // GPS管理サービス
  // =============================================
  
  /// 統合GPS管理サービス
  final GpsManagerService gpsManager = GpsManagerService();
  
  /// 内蔵GPS位置情報ストア
  final InternalGpsLocationStore locationStore = InternalGpsLocationStore();
  
  /// GPS履歴レコーダー
  final GpsHistoryRecorder gpsHistoryRecorder = GpsHistoryRecorder();
  
  /// 現在のGPS情報
  Map<String, dynamic>? currentGpsInfo;
  
  /// GPS取得待機秒数
  int gpsWaitSeconds = 0;
  
  /// GPS待機タイマー
  Timer? gpsWaitTimer;
  
  // =============================================
  // GPS測量関連
  // =============================================
  
  /// 長押し中フラグ
  bool isLongPressing = false;
  
  /// 長押しGPSカウント
  int longPressGpsCount = 0;
  
  /// 長押しカウント更新タイマー
  Timer? longPressCountUpdateTimer;
  
  // =============================================
  // 属性テーブル関連
  // =============================================
  
  /// 属性テーブル表示フラグ
  bool showAttributeTable = false;
  
  /// 属性テーブル幅
  double attributeTableWidth = 400;
  
  /// 属性テーブル対象レイヤー
  LayerNode? attributeTableLayer;
  
  // =============================================
  // フィーチャキャッシュ
  // =============================================
  
  /// ポイントフィーチャキャッシュ
  List<PointFeatureNode> pointFeatures = [];
  
  /// ラインフィーチャキャッシュ
  List<LineFeatureNode> lineFeatures = [];
  
  /// ポリゴンフィーチャキャッシュ
  List<PolygonFeatureNode> polygonFeatures = [];
  
  /// 写真ノードキャッシュ
  List<ImageNode> photoNodes = [];
  
  // =============================================
  // IMapState実装
  // =============================================
  
  @override
  LatLng offsetToLatLng(Offset offset) {
    try {
      final camera = mapControllerInstance.camera;
      return camera.offsetToCrs(offset);
    } catch (e) {
      return mapControllerInstance.camera.center;
    }
  }
  
  @override
  Offset latLngToOffset(LatLng latlng) {
    try {
      final camera = mapControllerInstance.camera;
      return camera.latLngToScreenOffset(latlng);
    } catch (e) {
      final size = MediaQuery.of(context).size;
      return Offset(size.width / 2, size.height / 2);
    }
  }
  
  @override
  List<LatLng> closeRing(List<LatLng> pts) {
    if (pts.length < 3) return [];
    final first = pts.first;
    final last = pts.last;
    bool isClosed =
        (first.latitude == last.latitude) &&
        (first.longitude == last.longitude);
    if (!isClosed) {
      return List<LatLng>.from(pts)..add(first);
    }
    return pts;
  }
  
  // =============================================
  // 抽象メソッド（各Mixinで実装）
  // =============================================
  
  /// GPS情報更新コールバック
  void onGpsManagerUpdate();
  
  /// 背景地図サービス更新コールバック
  void onBaseMapServiceUpdate();
  
  /// レイヤスタイル変更コールバック
  void onLayerStyleChanged();
  
  /// 現在のGPS情報を更新
  void updateCurrentGpsInfo();
  
  // =============================================
  // ヘルパーメソッド
  // =============================================
  
  /// setStateのラッパー（Mixinから呼び出し用）
  void triggerSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }
}
