/// 外部機器連動ツールの抽象基底クラス
///
/// [ExternalDeviceService]と連携し、機器接続時のみツールバーに表示される
/// 地図操作ツール。各機器のツールはこのクラスを継承する。
///
/// map_page / MapToolbar はこの抽象型のみに依存し、
/// 個別機器の知識を持たない（プラグインパターン）。
library;

import 'package:flutter/widgets.dart';
import 'package:maplibre/maplibre.dart' as ml;
import '../../tools/map_tool.dart';
import 'device_service.dart';

abstract class DeviceTool extends MapTool with ChangeNotifier {
  /// このツールが使用する機器サービス
  ExternalDeviceService get service;

  /// ツールが利用可能か（機器が接続されているか）
  bool get isAvailable => service.isConnected;

  /// 地図上に描画するオーバーレイレイヤ（PolylineLayer等）
  List<ml.Layer> buildOverlayLayers();

  /// 地図上に描画するウィジェットマーカー（BP標識等）
  List<ml.Marker> buildOverlayMarkers();

  /// ステータスパネルウィジェット（機器状態・計測値表示）
  Widget buildStatusPanel(BuildContext context);

  /// 機器固有の詳細/操作画面（null なら遷移しない）
  Widget? buildDetailScreen(BuildContext context) => null;
}
