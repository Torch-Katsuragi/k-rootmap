// K-MAPS: アプリケーション全体の定数定義
// マジックナンバーを排除し、一元管理することで保守性を向上

import 'dart:ui';

/// アプリケーション全体の定数クラス
class AppConstants {
  // プライベートコンストラクタ（インスタンス化を防止）
  AppConstants._();

  // --- UI関連定数 ---
  
  /// サイドドロワーのデフォルト幅
  static const double defaultDrawerWidth = 320.0;
  
  /// サイドドロワーの最小幅
  static const double minDrawerWidth = 200.0;
  
  /// 属性テーブルのデフォルト幅
  static const double defaultAttributeTableWidth = 400.0;
  
  /// デバウンス遅延（ミリ秒）
  static const Duration debounceDelay = Duration(milliseconds: 50);
  
  /// アニメーションのデフォルト持続時間
  static const Duration defaultAnimationDuration = Duration(milliseconds: 300);

  // --- 地図関連定数 ---
  
  /// 最大ズームレベル
  static const double maxZoom = 25.0;
  
  /// 最小ズームレベル
  static const double minZoom = 1.0;
  
  /// デフォルトズームレベル
  static const double defaultZoom = 15.0;
  
  /// 座標変化の閾値（約10m）- UI更新の判定に使用
  static const double coordinateChangeThreshold = 0.0001;

  // --- GPS関連定数 ---
  
  /// GPS追跡のデフォルト保存間隔（秒）
  static const int defaultTrackingSaveIntervalSeconds = 10;
  
  /// GPS追跡のデフォルト最小移動距離（cm）
  static const int defaultTrackingMinDistanceCm = 0;
  
  /// GPS精度表示の小数点桁数
  static const int gpsAccuracyDecimalPlaces = 1;
  
  /// GPS座標表示の小数点桁数
  static const int gpsCoordinateDecimalPlaces = 6;

  // --- 描画スタイル定数 ---
  
  /// デフォルトのポイントサイズ
  static const double defaultPointSize = 10.0;
  
  /// デフォルトのライン幅
  static const double defaultLineWidth = 2.0;
  
  /// 選択時のハイライト幅の増加量
  static const double selectionHighlightWidth = 2.0;
  
  /// ポリゴンの塗りつぶし透過度（0.0-1.0）
  static const double defaultPolygonFillOpacity = 0.3;

  // --- ファイル・DB関連定数 ---
  
  /// GeoPackageファイルの拡張子
  static const String geopackageExtension = '.gpkg';
  
  /// プロジェクトファイルの拡張子
  static const String projectExtension = '.kmaps';
  
  /// 最大同時DB接続数
  static const int maxDatabaseConnections = 5;

  // --- パフォーマンス関連定数 ---
  
  /// バッチ処理の最大サイズ
  static const int maxBatchSize = 1000;
  
  /// キャッシュの最大アイテム数
  static const int maxCacheItems = 500;
  
  /// 選択範囲計算の基準距離（ズーム16で20m）
  static const double selectionRangeBase = 20.0;
  
  /// 選択範囲計算の基準ズームレベル
  static const int selectionRangeBaseZoom = 16;
}

/// 地図関連の色定数
class MapColors {
  MapColors._();

  /// 選択時のハイライト色
  static const Color selectionHighlight = Color(0xFFFFD700); // Gold
  
  /// 現在位置マーカーの色
  static const Color currentLocation = Color(0xFF4285F4); // Google Blue
  
  /// GPS追跡ルートの色
  static const Color trackingRoute = Color(0xFF34A853); // Google Green
  
  /// エラー表示の色
  static const Color error = Color(0xFFEA4335); // Google Red
}

/// デフォルトの座標（東京駅）
class DefaultCoordinates {
  DefaultCoordinates._();

  /// デフォルトの緯度（東京駅）
  static const double latitude = 35.681236;
  
  /// デフォルトの経度（東京駅）
  static const double longitude = 139.767125;
}


