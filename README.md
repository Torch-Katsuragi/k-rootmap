# K-MAPS

## 概要
K-MAPSはGeoPackageベースの地理情報管理・編集アプリ。

## データベース移行について（2025年対応）
**sqlite3からsqfliteへの段階的移行を実施完了**

### 移行の背景
- Flutter推奨のsqfliteパッケージを使用し、非同期処理のベストプラクティスに準拠
- データベーススキーマのバージョン管理機能を活用
- パフォーマンス向上とFlutterのライフサイクルとの統合

### 移行方針
1. **段階的移行**: 一度に大規模リファクタリングを避け、安全に移行
2. **APIの互換性維持**: 戻り値をFutureに変更するが、使用方法は最小限の変更
3. **遅延初期化**: データベース接続は必要時に自動初期化

### 移行内容（完了済み）
- `pubspec.yaml`: sqlite3依存関係をsqflite ^2.3.0、path ^1.8.3に変更
- `lib/models/geopackage_file.dart`: sqlite3→sqfliteに移行完了（503行の完全書き換え）
  - 全メソッドが`Future<T>`を返すように変更
  - 遅延データベース初期化と自動接続管理
  - OGC GeoPackage仕様準拠のスキーマ作成をonCreateコールバックで実装
  - エラーハンドリング強化（try-catch構文で包囲）
- `lib/models/layer_tree_node.dart`: 非同期対応完了
  - LayerTreeNode基底クラスの`loadNodes`、`updateChildren`、`dispose`メソッドを非同期化
  - GeoPackageNode、LayerNode、FeatureNodeクラスのすべての重要メソッドにawait対応
  - featuresプロパティを`Future<List<FeatureNode>>`に変更
- `lib/screens/map_page.dart`: UI層の非同期対応
  - フィーチャデータキャッシュ機能追加（`_pointFeatures`, `_lineFeatures`, `_polygonFeatures`）
  - 非同期データ更新メソッド`_updateFeatures()`実装
  - build メソッドでの同期処理からキャッシュベース表示に変更
  - sqlite3 import削除
- 全体的なエラーハンドリングとログ出力の改善

### 技術的な変更点
1. **データベース接続管理**:
   ```dart
   // 旧方式（sqlite3）
   final db = sql.sqlite3.open(dbPath);
   
   // 新方式（sqflite）
   final db = await openDatabase(
     dbPath,
     version: 1,
     onCreate: _createDatabase,
     onUpgrade: _upgradeDatabase,
   );
   ```

2. **メソッド呼び出し**:
   ```dart
   // 旧方式（同期処理）
   final layerNames = geoPackage.getLayerNames();
   final points = geoPackage.getPoints(tableName);
   
   // 新方式（非同期処理）
   final layerNames = await geoPackage.getLayerNames();
   final points = await geoPackage.getPoints(tableName);
   ```

3. **UI層でのフィーチャ表示**:
   ```dart
   // 旧方式（build内で直接非同期処理）
   Widget build(BuildContext context) {
     final features = layer.features; // Error: Future型
   }
   
   // 新方式（キャッシュベース）
   List<FeatureNode> _features = [];
   Future<void> _updateFeatures() async {
     final features = await layer.features;
     setState(() => _features = features);
   }
   Widget build(BuildContext context) {
     // _featuresを使用
   }
   ```

### 移行の利点
- **Flutter生態系との統合**: sqfliteはFlutter公式推奨で長期サポート保証
- **パフォーマンス向上**: Flutter SDKと最適化された連携
- **スキーマ管理**: onCreateやonUpgradeコールバックによる自動マイグレーション対応
- **エラーハンドリング**: Dartのnull安全性とasync/awaitパターンに準拠
- **将来拡張性**: Firebaseとの統合やクラウド同期への道筋確保

### 移行後の確認手順
1. **依存関係の確認**: `flutter pub get`
2. **コード解析**: `flutter analyze`
3. **ビルドテスト**: `flutter build apk --debug`
4. **実行テスト**: `flutter run`で動作確認
5. **機能テスト**: GeoPackageファイル作成・レイヤ追加・フィーチャ描画の一連のフロー確認

### 修正済みのリンターエラー
以下のリンターエラーを修正しました：
- **`lib/tools/select_tool.dart`**: `Future<List<FeatureNode>>`の非同期処理対応
  - `selectFeatureAtLatLng`メソッドを`async/await`対応
  - `onTap`と`onScaleEnd`メソッドでの`layer.features`呼び出しを非同期化
- **`lib/widgets/layer_drawer.dart`**: UI層での非同期データ処理対応
  - レイヤ作成メソッド(`createIn`)の非同期呼び出し対応
  - `AttributeTablePanel`で`FutureBuilder`を使用してcolumnsとfeaturesを適切に処理
  - 属性値表示・編集で`getAttributeValue`の非同期処理対応

これらの修正により、sqflite移行に伴うFlutter標準の非同期処理パターンに完全準拠しました。

### sqflite初期化対応（追加）
デスクトップ環境（Windows/macOS/Linux）での動作を保証するため、以下を実装：
- **`pubspec.yaml`**: `sqflite_common_ffi: ^2.3.0` パッケージを追加
- **`lib/main.dart`**: プラットフォーム別初期化処理を追加
  - `WidgetsFlutterBinding.ensureInitialized()` の呼び出し
  - デスクトップ環境での `sqfliteFfiInit()` と `databaseFactory = databaseFactoryFfi` の設定
- **`lib/models/geopackage_file.dart`**: 初期化検証の強化
  - データベース初期化前の Widget バインディング確認
  - 初期化成功ログの追加

これにより「Bad state: databaseFactory not initialized」エラーを根本的に解決しました。

### 重複読み込み問題の修正（追加）
- **基底クラス`LayerTreeNode.loadNodes`**の重複実装問題を解決
  - 基底クラスのloadNodesメソッドから.gpkgファイルスキャン処理を削除
  - 各サブクラス（FolderNode、GeoPackageNode、LayerNode）で適切に実装を分離
- **ファイルシステム同期機能の実装**
  - `addChildIfNotExists`メソッドを追加し、同名・同型ノードの重複を防止
  - `updateChildren`メソッドを改良し、既存ノードを再利用しながらファイルシステム変更を反映
  - 削除されたファイル・レイヤに対応するノードを自動削除
  - 初期化フラグ（`_initialized`）により、コンストラクタでの自動初期化は1回のみ実行
  - その後の`updateChildren`呼び出しは何度でも可能で、ファイルシステムとの同期を維持

**設計方針**：
- `updateChildren`は何度でも呼び出し可能
- ファイルシステムに新しいファイルが追加された場合：対応する新しいノードを追加
- ファイルシステムからファイルが削除された場合：対応するノードを削除
- 既存ファイルが変更されていない場合：既存ノードを再利用（パフォーマンス向上）

これにより、プロジェクト読み込み時にディレクトリ内のGeoPackageファイルが自動的に検出・読み込まれ、Drawerに表示されるようになりました。

### フィーチャ表示問題の修正（追加）
既存プロジェクトのフィーチャが地図上に表示されない問題を根本解決：

**原因の特定**：
- プロジェクト初期化時に`_updateFeatures()`メソッドが適切なタイミングで呼ばれていなかった
- フィーチャ作成後・可視状態変更後に`refreshFeatures()`が呼ばれていなかった

**修正内容**：
- **`lib/screens/map_page.dart`**: プロジェクト初期化フローの改善
  - `_initializeProjectTree()`メソッドでプロジェクトツリー構築後に`_updateFeatures()`を呼び出し
  - initStateでの重複`_updateFeatures()`呼び出しを削除（タイミング問題を解決）
  - `_updateFeatures()`メソッドに詳細なデバッグログを追加
- **`lib/tools/pen_tool.dart`**: フィーチャ作成後の表示更新
  - `onScaleEnd`メソッドでフリーハンド描画完了時に`refreshFeatures()`を呼び出し
  - `confirm`メソッドで属性入力完了時に`refreshFeatures()`を呼び出し
- **`lib/widgets/layer_drawer.dart`**: 可視状態変更時の表示更新
  - レイヤ可視状態変更時に`refreshFeatures()`を呼び出し、即座に地図表示を更新

**動作フロー**：
1. **プロジェクト読み込み時**: ツリー構築 → フィーチャ取得 → 地図表示
2. **フィーチャ作成時**: DB保存 → `refreshFeatures()` → 地図更新
3. **可視状態変更時**: 状態更新 → `refreshFeatures()` → 地図更新

これにより、既存のフィーチャが適切に地図に表示され、新規作成したフィーチャも即座に表示されるようになりました。

### Android NDKバージョン対応（追加）
AndroidプラットフォームでのビルドエラーとNDKバージョン不整合を解決：

**問題の背景**：
- プロジェクトはAndroid NDK 26.3.11579264で設定されていた
- 使用しているプラグイン（file_picker、geolocator_android、sqflite_android等）がAndroid NDK 27.0.12077973を要求

**修正内容**：
- **`android/app/build.gradle.kts`**: NDKバージョンを27.0.12077973に更新
  ```kotlin
  android {
      ndkVersion = "27.0.12077973"
      // ...
  }
  ```
- **`pubspec.yaml`**: file_pickerを6.1.1から10.1.9に更新
  - 古いfile_pickerバージョンの`PluginRegistry.Registrar`クラス未対応エラーを解決
  - 最新版では新しいFlutter embedding APIに完全対応

**対応手順**：
1. `flutter clean` でビルドキャッシュをクリア
2. `flutter pub get` で依存関係を再取得
3. Android端末での動作確認

これにより、WindowsとAndroidの両プラットフォームで一貫した動作が可能になりました。

## 主な設計方針（2024-06-10以降）
- **LayerManagerは廃止**。GeoPackageFile＋ノード（GeoPackageNode/LayerNode）＋グローバル変数で全体管理。
- UIはGeoPackageNode/LayerNodeのメソッドを直接呼び、DB操作はGeoPackageFileに集約。
- 選択状態は「現在選択中のLayerNode/GeoPackageNode」への参照をグローバル変数で保持。
- 可視状態・meta.json連携はLayerTreeNodeのvisible系メソッドで一元化。
- 複数ファイル・レイヤの一元管理も、全ノードリストをグローバルで管理。
- **地図操作ツール（MapTool）を導入し、てのひら・ペン・選択などのツール切替をサポート。現在のツールはGlobalConfigで一元管理。**
- **ペン入力（スタイラス）とタップ入力（指・マウス）で挙動を分岐し、直感的な操作性を実現。**
- **地図操作ツール（MapTool）はPanTool, PenTool, SelectToolのグローバルインスタンスをGlobalConfigで生成し、currentToolはその参照を切り替えるだけ。ツールごとに新インスタンスは生成しない。**

## 主要ファイル・クラス構成
- `lib/models/geopackage_file.dart` : GeoPackageFile（GeoPackageファイル管理・DB操作ラッパ）
  - WKBエンコード・デコード処理はlib/utils/wkb_utils.dartに集約。
  - ファイルが存在しない場合、親ディレクトリが存在すればGeoPackage必須テーブル（gpkg_spatial_ref_sys, gpkg_contents, gpkg_geometry_columns）を自動作成（OGC仕様準拠、最小構成）。
- `lib/models/layer_tree_node.dart` : LayerTreeNode/GeoPackageNode/LayerNode（ツリー構造・可視状態・meta.json連携）
  - 各ノードクラス（FolderNode, GeoPackageNode, LayerNode）に `static List<LayerTreeNode> createNodesByType(LayerTreeNode? parent)` を実装し、親ノード直下の子ノードリストを返す。
  - **2024-06-13: FeatureNode（PointFeatureNode/LineFeatureNode/PolygonFeatureNode）を追加。LayerNode配下にfeature単位でノードを生成し、属性編集・削除（dispose）・feature参照を提供。**
- `lib/utils/global_config.dart` : グローバル変数（全ノードリスト・選択中ノード等）
  - PanTool, PenTool, SelectToolのグローバルインスタンスを保持し、currentToolはその参照を切り替えるだけ。
- `lib/widgets/layer_drawer.dart` : レイヤツリーUI（ノード参照で操作）
  - フォルダノード右側に「GeoPackage追加」ボタン（＋）を実装。押下でファイル名入力→GeoPackageファイル自動生成→ノード追加・即反映。
  - GeoPackageノード（gpkgパネル）はタップで配下レイヤリストをトグル展開可能。
  - 属性テーブル（AttributeTablePanel）でgeom「選択」ボタンを押すと、そのfeatureの中心座標に地図がジャンプ。
- `lib/screens/map_page.dart` : 地図画面本体（ノード・グローバル変数参照で状態管理）
- `lib/tools/map_tool.dart` : 地図操作ツールの抽象基底クラス（MapTool）。
- `lib/tools/pan_tool.dart` : てのひらツール（地図パン専用）。
  - onScaleStart/onScaleUpdate/onScaleEndでドラッグ操作による地図パン（中心移動）を実装。
- `lib/tools/pen_tool.dart` : ペンツール（レイヤ描画）。
- `lib/tools/select_tool.dart` : オブジェクト選択ツール。
- `lib/utils/feature_calc_utils.dart`: フィーチャ（点・線・面）に関する計算ユーティリティ。重心計算、距離計算、長さ・面積計算、点とfeatureの距離、最近傍feature取得などを提供。
  - 主な関数:
    - `calcDistance(LatLng a, LatLng b)`: 2点間の距離（m）
    - `calcLineLength(List<LatLng> line)`: 線分の長さ（m）
    - `calcPolygonArea(List<LatLng> polygon)`: ポリゴンの面積（m^2, 平面近似）
    - `calcLineCentroid(List<LatLng> line)`: 線分の重心
    - `calcPolygonCentroid(List<LatLng> polygon)`: ポリゴンの重心
    - `calcPointsCentroid(List<LatLng> points)`: 点集合の重心
    - `calcPointToLineDistance(LatLng pt, List<LatLng> line)`: 点と線分の最短距離
    - `calcPointToPolygonDistance(LatLng pt, List<LatLng> polygon)`: 点とポリゴンの最短距離
    - `calcPointToFeatureDistance(LatLng pt, Object geometry, String featureType)`: 点とfeature（点・線・面）の最短距離
    - `findNearestFeature(LatLng pt, List<FeatureNode> features, String featureType)`: 点に最も近いfeatureを取得
  - すべての関数に日本語docstring・コメント付き。FeatureNode型利用のため`layer_tree_node.dart`をimport。

## クラス構成
- **GeoPackageFile**: ファイルパスのみ保持し、DB操作（レイヤ追加・削除・リネーム・フィーチャ取得等）を担う。
- **LayerTreeNode/GeoPackageNode/LayerNode**: ツリー構造・可視状態・meta.json連携・GeoPackageFile参照を持つ。
- **FeatureNode（PointFeatureNode/LineFeatureNode/PolygonFeatureNode）**: LayerNodeの子としてfeature単位で生成され、feature参照・属性編集・削除（dispose）を提供。
- **GlobalConfig**: 全ノードリスト・選択中ノード等のグローバル管理。**選択中フィーチャリスト（selectedFeatures）も追加。**

## 状態管理
- 選択状態・可視状態・ファイル/レイヤの追加削除等は、すべてノード＋グローバル変数で一元管理。
- meta.jsonのロード・保存もLayerTreeNode側で吸収。

## 主な機能
- レイヤ構造のファイルエクスプローラ風表示・操作
- GeoPackageファイル・レイヤの追加/削除/可視切り替え
- **LayerNode配下にfeature単位のノード（FeatureNode）を自動生成し、属性編集・削除・参照が可能。**
- **Drawer上部に現在のノード名を青いタイトルパネルで表示（LayerDrawerTitleBarウィジェット）**
- 属性テーブルでgeom「選択」ボタンを押すと、そのfeatureの中心座標に地図がジャンプ（地図コントローラ連携）。
- プロジェクトフォルダ・サブフォルダ・GeoPackage・レイヤの階層構造をファイルエクスプローラ風に1階層のみリスト表示
- フォルダ/GeoPackage/レイヤの可視切り替え・リネーム・削除
- フォルダをタップでカレントディレクトリ移動
- フォルダノード右側の「GeoPackage追加」ボタン（＋）から、任意の場所に新規GeoPackageファイルを即作成・追加可能
- GeoPackageノード（gpkgパネル）はタップで配下レイヤリストをトグル展開可能
- **地図操作ツールバーで「てのひら」「ペン」「選択」などのツールを切り替え可能。**
- **ペン入力（スタイラス）とタップ入力（指・マウス）で挙動を分岐し、ペンはフリーハンド描画、タップは点追加や選択など直感的な操作性を実現。**
- **地図上でポリゴン描画時、描画中・既存ポリゴンともに内部を半透明で塗りつぶし表示（isFilled: true, withOpacity指定）**
- **選択ツールでfeatureを選択すると、selectedFeaturesに格納され、地図上でハイライト表示（色・太さ等で明示）される。**

## 主要ファイルとクラス構成
- `lib/models/geopackage.dart`: Layer, GeoPackageGroup, LayerManager（meta.json連携）
- `lib/utils/meta_data.dart`: meta.json全体の読み書き・可視状態・設定管理（MetaDataクラス）
- `lib/utils/folder_tree.dart`: FolderNode（サブフォルダツリー）
- `lib/widgets/layer_drawer.dart`: レイヤツリーUI（ノード参照で操作）
- `lib/screens/map_page.dart`: KMapsHomePage（画面本体、LayerManager/Drawer連携）
- `lib/models/folder_node.dart`: FolderNode（サブフォルダツリー）・scanProjectFolder（.gpkgファイルもchildrenにLayerTreeNode(nodeType: "gpkg")として追加する実装）
- `lib/utils/global_config.dart`: GlobalConfigクラス。プロジェクトのルートディレクトリやmeta.json（MetaDataインスタンス）、**現在のツール（currentTool: MapTool）**、**選択中フィーチャリスト（selectedFeatures）**などのグローバル変数・設定を一元管理。
- `lib/models/layer_tree_node.dart`: フォルダ/GeoPackage/レイヤのノード構造を定義。
- `lib/models/layer.dart`: レイヤ情報のモデル。

### クラス構成
- `LayerTreeNode`：サブフォルダ・GeoPackage・レイヤ共通の抽象クラス。親・子・可視状態・パス取得・再帰可視切替などを統一インターフェースで提供。
  - **各サブクラスでbaseIcon/baseIconColorをoverrideし、UI側はnode.baseIcon/node.baseIconColorを呼ぶだけで種別ごとのアイコン描画が可能。**
- `FolderNode`/`GeoPackageGroup`/`Layer`：LayerTreeNodeを実装し、ツリー構造を再帰的に表現。
- `LayerManager`：GeoPackage/Layerの全体管理。MetaDataを持ち、可視状態や設定をmeta.jsonと同期。
- `MetaData`：meta.json全体（layerTree, general, gps, toolProperties等）を一元管理。可視状態APIもここに統合。
- `LayerDrawer`：LayerTreeNodeのchildrenを再帰的に描画する方式でUIを構築。可視状態切替も共通化。
- `GlobalConfig`: プロジェクト全体のグローバル変数・設定（ルートディレクトリパス、MetaDataインスタンス等）をシングルトンで管理。**選択中フィーチャリスト（selectedFeatures）も追加。**
- `LayerDrawerTitleBar` : 現在のノード名を青いパネルで表示するWidget。
- **MapTool**: 地図操作ツールの抽象基底クラス。onPointerDown/Move/Up等のイベントを持ち、ペン/タップ入力で挙動を分岐可能。
  - PanTool, PenTool, SelectToolなどを継承クラスとして実装。

## meta.json構造と拡張性
- meta.jsonはプロジェクト直下に保存。レイヤ構造は"rootNode"ノード配下で管理し、
  設定（general/gps/toolProperties等）も同階層に格納。
- 例:
```
{
  "rootNode": {...},
  "general": {...},
  "gps": {...},
  "toolProperties": {...}
}
```
- 親（フォルダ/GeoPackage）を非表示にすると、子も再帰的に非表示
- 親を再表示したとき、子は非表示前の状態（meta.jsonに記録）で復元

## 使い方
1. プロジェクトを開くとmeta.jsonが自動生成/読込され、可視状態が復元される
2. Drawerで可視/不可視を切り替えるとmeta.jsonも即時更新

---

詳細なクラス・UI・ロジックの説明は`FEATURES.md`も参照。

## 主な機能
- 地図上でGeoPackageのレイヤ（点・線・面）を編集・表示
- レイヤ・GeoPackage・フォルダの可視状態を種別アイコンのタップで切り替え可能
  - 不可視時はアイコンがグレーアウト＋斜線重ねで明示
- 属性編集・インラインリネーム・レイヤ追加/削除
- サブフォルダの可視設定を切り替えた場合、その配下のGeoPackageやレイヤにも可視設定が一括で伝播し、UI上も連動して非表示/表示が切り替わる
- **地図上でポリゴン描画時、描画中・既存ポリゴンともに内部を半透明で塗りつぶし表示（isFilled: true, withOpacity指定）**
- 地図上でfeature選択時、selectedFeaturesに格納されたfeatureが色・太さ等でハイライト表示される

## 主要ファイル
- `lib/models/geopackage.dart`: GeoPackage管理、レイヤ/GeoPackageGroup、LayerManagerを実装（meta.json連携）
- `lib/models/layer_tree_node.dart`: フォルダ・GeoPackage・レイヤの共通抽象基底クラス
- `lib/models/layer.dart`: レイヤ・フィーチャのモデル
- `lib/utils/meta_data.dart`: meta.json全体の読み書き・可視状態・設定管理を提供
- `lib/utils/folder_tree.dart`: FolderNode実装、フォルダツリー構造管理
- `lib/screens/map_page.dart`: 地図表示およびDrawer UIのメイン画面
- `lib/widgets/layer_drawer.dart`: Drawer UI実装、レイヤツリーの再帰描画と可視状態管理
- `lib/widgets/inline_edit.dart`: インライン編集UI（名前変更等の処理）

## クラス構成
- `KMapsHomePage`: 地図・レイヤ・Drawerの状態管理とUI
- `LayerManager`: レイヤ・GeoPackageの状態管理
- `LayerTreeNode`: レイヤツリー共通ノード（FolderNode/GeoPackageGroup/Layerの親）
- `FolderNode`: フォルダツリーのノード（LayerTreeNode実装）
- `GeoPackageGroup`: GeoPackageグループ（LayerTreeNode実装）
- `Layer`: レイヤ（LayerTreeNode実装）

## UI仕様
- レイヤ・GeoPackage・フォルダの可視状態は、種別アイコン（例: 点/線/面/フォルダ/ストレージ）をタップして切り替え
  - **アイコン種別・色は各ノードクラスで定義し、Drawer側はnode.baseIcon/node.baseIconColorを呼ぶだけでOK**
- 不可視時はアイコンがグレーアウトし、斜線が重なる
- 目アイコンや可視切り替えボタンは廃止
- 親（フォルダ/GeoPackage/レイヤ）を不可視にすると、子要素も一括で不可視になり、UI上も非表示になる
- フォルダノード右側の「GeoPackage追加」ボタン（＋）を押すと、ファイル名入力ダイアログが表示され、入力後すぐにGeoPackageファイルが自動生成・Drawerに即反映される
- **Drawer上部のタイトルパネル右側に「サブフォルダ追加」「GeoPackage追加」ボタンを合成アイコン（右上に緑+）で実装。buildAddIconOverlayでWidget化し再利用可。**
- 地図のパン（ドラッグ移動）は「てのひらツール」選択時のみ有効。他のツール（ペン・選択等）では明示的なメソッド呼び出しがない限りパン不可。

## meta.json全体を管理するユーティリティ
- MetaData: 可視状態（layerTree）・設定（general/gps/toolProperties等）を一元管理
- 各ノードは名前で識別し、visibleや設定値を保持
- meta.jsonはプロジェクト直下に保存
- レイヤ構造は"rootNode"ノード配下で管理、設定は同階層に格納

- `scanProjectFolder`: 指定ディレクトリ配下を再帰的に探索し、サブフォルダ・.gpkgファイルをchildrenにLayerTreeNodeとして追加する。これによりDrawerツリーUIで.gpkgファイルも正しく表示される。

## LayerDrawerのクラス構成
- `LayerDrawer`
  - `folderTree`: ルートのLayerTreeNode
  - `currentNode`: 現在のディレクトリノード（LayerTreeNode参照管理）
  - `onDirChanged`: ディレクトリ変更時のコールバック
  - `setStateCallback`: 親WidgetのsetStateラッパー
  - `editState`: 編集状態
  - `metaData`: meta.json管理
  - `_findNodeByPath`: パスから該当ノードを再帰的に取得
  - `_parentPath`: 親ディレクトリパス取得
  - `_buildNodeRow`: 1階層分のノードをリスト表示

## 変更履歴
- 2024-06-09: LayerDrawerで_findNodeByPathの代わりにLayerTreeNodeのgetNodeByPathを使用するよう修正。
- 2024-06-09: LayerDrawer/map_page.dartでカレントディレクトリ管理をパス文字列からLayerTreeNode参照に変更。
- 2024-06-09: GeoPackageGroupにgetFeatureTableNames(), getGeometryType()追加。layerノード生成部でこれらAPIを利用するようリファクタ。
- 2024-xx-xx: childrenTypeをList<Type>に変更し、型ベースでノード管理に統一
- 2024-xx-xx: LayerTreeNode.createNodesByTypeを廃止し、各継承クラスにstatic createNodesByType(parent)を分散実装
- 2024-06-09: FeatureNodeおよびサブクラスから`updateAttr`メソッドを削除。属性値の更新は`editAttribute`で一元管理。
- 2024-06-09: feature属性のDBカラムを`attr`→`name`/`description`に移行。既存レイヤにも自動追加されるよう`ensureNameDescriptionColumns`を実装。

## FolderNodeについて
- FolderNodeはlib/models/folder_node.dartで定義され、レイヤツリーのフォルダ構造を表現するクラス。
- map_page.dartでプロジェクト全体の再スキャン時などに利用。

## 主要なグローバル設定

- `GlobalConfig.instance.projectRootDir` : プロジェクトルートディレクトリのパス。プロジェクト読み込み時にhome_screen.dartでセットされ、以降はグローバル参照。
- `GlobalConfig.instance.folderTree` : プロジェクト内のフォルダ・レイヤ構造。
- `GlobalConfig.instance.currentTool` : 現在選択中の地図操作ツール（MapToolインスタンス）。

## KMapsHomePageの初期化フロー

- `defaultGpkgPath` : デフォルトのGeoPackageファイルパス
- プロジェクトルートパスはグローバル変数(GlobalConfig.instance.projectRootDir)で管理し、引数で渡さない設計に変更
- 以降、レイヤ管理やフォルダツリーの初期化にこのパスが利用される

## 主なクラスと機能

### LayerTreeNode
- レイヤツリーのノード共通基底クラス。
- name, visible, nodeType, parent, childrenなどのプロパティを持つ。
- 可視状態の再帰変更、メタデータ連携、ファイルパス取得、子ノードの動的生成などを担う。
- **getNodeByPath(List<String> pathList)**: パスリスト（ルートからのノード名リスト）を受け取り、該当する子孫ノードへの参照を返す。見つからなければnullを返す。
  - 引数: pathList (例: ["root", "folderA", "layer1"])
  - 返り値: LayerTreeNode?（該当ノード、なければnull）

### lib/models/geopackage.dart
- `GeoPackageGroup` : GeoPackageファイルを表現。レイヤ一覧（layers）を持つ。
  - `getFeatureTableNames()` : このGeoPackage内のフィーチャテーブル名一覧を返す。
  - `getGeometryType(tableName)` : 指定テーブル名のジオメトリタイプ（POINT/LINESTRING/POLYGON等）を返す。

### lib/models/layer_tree_node.dart
- `LayerTreeNode.createNodeByType(nodeType, logicalPath, parent: ...):
  logicalPathで指定されたパスの単一ノード（LayerTreeNode?）を返す（見つからなければnull）。
  nodeType="folder"の場合: 指定パスが存在すればFolderNodeを返す。
  nodeType="gpkg"の場合: 指定パスが存在すればGeoPackageNodeを返す。
  nodeType="layer"の場合: parentがGeoPackageNodeであれば、logicalPathの末尾をテーブル名としてレイヤノードを返す。

## 主要ファイル・クラス構成

- `lib/models/geopackage_file.dart` : GeoPackageFile（GeoPackageファイル管理クラス）
  - ファイルパスのみ保持し、レイヤ一覧・属性・フィーチャ情報は全てDBからリアルタイムで取得
  - レイヤ追加・削除・リネーム等の操作メソッドも集約
- `lib/models/geopackage.dart` : 旧GeoPackageGroup/Layer/LayerManager（今後はノードクラス・マネージャとして整理予定）

## GeoPackageFile設計方針

- GeoPackageFileはファイルパスのみを保持
- レイヤ一覧や属性・フィーチャ情報は全てDBからリアルタイムで取得
- レイヤ追加・削除・リネーム等の操作もGeoPackageFile経由で行う
- ツリー構造のノード（GeoPackageNode, LayerNode等）はGeoPackageFileへの参照のみを持ち、情報取得・操作はGeoPackageFileのメソッドを呼び出す
- **ファイルが存在しない場合、親ディレクトリが存在すればGeoPackage必須テーブル（gpkg_spatial_ref_sys, gpkg_contents, gpkg_geometry_columns）を自動作成（OGC仕様準拠、最小構成）する。**
- **WKBエンコード・デコード処理はlib/utils/wkb_utils.dartに集約し、GeoPackageFile等から呼び出す。**

### GeoPackageFile主要メソッド
- `getLayerNames()` : レイヤ（フィーチャテーブル）名一覧をDBから取得
- `getGeometryType(tableName)` : 指定レイヤのジオメトリタイプをDBから取得
- `getFeatures(tableName)` : 指定レイヤのフィーチャ一覧をDBから取得
- `addLayer(name, geomType)` : レイヤ追加（DBにテーブル作成）
- `removeLayer(name)` : レイヤ削除（DBからテーブル削除）
- `renameLayer(oldName, newName)` : レイヤ名リネーム（DB内のテーブル名・メタ情報も更新）

---

今後、GeoPackageNode/LayerNode等のノードクラスもGeoPackageFile参照型にリファクタリング予定。

## 更新履歴・修正メモ
- meta.json/MetaDataを全域から排除。可視状態・設定の永続化は一時的に無効化（今後再導入予定）。

## モデル構成: LayerTreeNode系

- `LayerTreeNode` (abstract)
  - レイヤツリーのノード共通基底クラス。
  - `updateChildren()` はabstractで、サブクラスでファイル構造等を参照し子ノードを生成。
  - `addChild`, `dispose`, `getPathFromRoot` などツリー操作の共通メソッドを持つ。

- `FolderNode` (LayerTreeNode継承)
  - サブフォルダ・GeoPackageファイルノードを子ノードとして持つ。
  - `updateChildren()` で直下のフォルダ・gpkgファイルを探索しノード生成。

- `GeoPackageNode` (LayerTreeNode継承)
  - 1つのGeoPackageファイルを表現。
  - `updateChildren()` で自身のGeoPackage内のレイヤ（テーブル）をLayerNodeとして生成。

- `LayerNode` (abstract, LayerTreeNode継承)
  - 1つのレイヤ（テーブル）を表現。Point/Line/Polygonのサブクラスあり。
  - 子ノードは持たない。

### ノード生成の流れ
- FolderNode: 直下のディレクトリ→FolderNode, .gpkgファイル→GeoPackageNode
- GeoPackageNode: .gpkg内のテーブル→LayerNode (Point/Line/Polygon)
- LayerNode: 子ノードなし

### 主要ファイル
- `lib/models/layer_tree_node.dart`: 上記クラス群の実装本体

## 主要ファイル・クラス構成

- `lib/models/geopackage_file.dart` : GeoPackageFile（GeoPackageファイル管理クラス）
  - ファイルパスのみ保持し、レイヤ一覧・属性・フィーチャ情報は全てDBからリアルタイムで取得
  - レイヤ追加・削除・リネーム等の操作メソッドも集約
- `lib/models/geopackage.dart` : 旧GeoPackageGroup/Layer/LayerManager（今後はノードクラス・マネージャとして整理予定）

## GeoPackageFile設計方針

- GeoPackageFileはファイルパスのみを保持
- レイヤ一覧や属性・フィーチャ情報は全てDBからリアルタイムで取得
- レイヤ追加・削除・リネーム等の操作もGeoPackageFile経由で行う
- ツリー構造のノード（GeoPackageNode, LayerNode等）はGeoPackageFileへの参照のみを持ち、情報取得・操作はGeoPackageFileのメソッドを呼び出す
- **ファイルが存在しない場合、親ディレクトリが存在すればGeoPackage必須テーブル（gpkg_spatial_ref_sys, gpkg_contents, gpkg_geometry_columns）を自動作成（OGC仕様準拠、最小構成）する。**
- **WKBエンコード・デコード処理はlib/utils/wkb_utils.dartに集約し、GeoPackageFile等から呼び出す。**

### GeoPackageFile主要メソッド
- `getLayerNames()` : レイヤ（フィーチャテーブル）名一覧をDBから取得
- `getGeometryType(tableName)` : 指定レイヤのジオメトリタイプをDBから取得
- `getFeatures(tableName)` : 指定レイヤのフィーチャ一覧をDBから取得
- `addLayer(name, geomType)` : レイヤ追加（DBにテーブル作成）
- `removeLayer(name)` : レイヤ削除（DBからテーブル削除）
- `renameLayer(oldName, newName)` : レイヤ名リネーム（DB内のテーブル名・メタ情報も更新）

---

今後、GeoPackageNode/LayerNode等のノードクラスもGeoPackageFile参照型にリファクタリング予定。

## 更新履歴・修正メモ
- meta.json/MetaDataを全域から排除。可視状態・設定の永続化は一時的に無効化（今後再導入予定）。

## 主なクラス構成
- LayerTreeNode: レイヤツリーの基底クラス。ノード種別（folder/gpkg/layer）を持つ。
  - FolderNode: フォルダノード。childrenTypeは["folder", "gpkg"]。
  - GeoPackageNode: GeoPackageファイルノード。childrenTypeは["layer"]。
  - PointLayerNode/LineLayerNode/PolygonLayerNode: 各ジオメトリタイプのレイヤノード。

## ノード生成の流れ
- 各ノードクラス（FolderNode, GeoPackageNode, LayerNode）で `static createNodesByType(parent)` を呼び出すことで、親ノード直下の子ノードリストを取得できる。
  - 例: `FolderNode.createNodesByType(parentFolderNode)`

## GeoPackageファイルのパス管理方針

- GeoPackageFile等のファイルアクセスは、必ず `GlobalConfig.instance.projectRootDir`（プロジェクトルート）とパスリスト（`List<String>`: サブディレクトリやファイル名のリスト）を組み合わせて行う。
- 例: `GeoPackageFile(['data', 'test.gpkg'])` → ルート/data/test.gpkg
- 直接パス文字列を渡す設計は禁止。
- LayerTreeNode等も同様のパスリスト方式を採用。

### 使い方例
```dart
final gpkg = GeoPackageFile(['data', 'test.gpkg']);
final layerNames = gpkg.getLayerNames();
```

- ルートディレクトリは `GlobalConfig.instance.projectRootDir` でセット・取得する。
- ファイルアクセス時は都度 `p.joinAll([GlobalConfig.instance.projectRootDir, ...pathList])` で絶対パスを生成する。

## 地図描画UIの改善

- 線・ポリゴン描画中、画面右下に「確定」「キャンセル」「1つ取り消し」ボタンが横並びで表示されるようになりました。
  - 確定: 描画を保存
  - キャンセル: 描画点列を全消去
  - 1つ取り消し: 最後の点を削除
- これにより、誤操作時のリカバリや描画のやり直しが容易になりました。

### 主要ファイル・クラス構成

- `lib/screens/map_page.dart`: 地図・編集画面本体。地図表示、描画、ツールバー、FAB群のUIロジックを担当。
  - `KMapsHomePage`: 地図画面のStatefulWidget。
  - `_KMapsHomePageState`: 地図・描画・ツール・FABの状態管理とUI構築。
- `lib/models/layer.dart` など: レイヤ・フィーチャのデータモデル。
- `lib/utils/global_config.dart`: グローバルな設定・状態管理。
- `lib/widgets/layer_drawer.dart`: レイヤ一覧・編集用Drawer。

## 主な特徴
- レイヤツリー構造を型（クラス）ベースで管理
- childrenTypeはList<Type>で、子ノードの型を明示
- ノード生成も型分岐で柔軟に拡張可能

## 変更履歴
- 2024-xx-xx: childrenTypeをList<Type>に変更し、型ベースでノード管理に統一

## 主要クラスとメソッド

### FeatureNode（抽象クラス）
- 属性値: `name`, `description`
- 属性値の取得: `getAttributeValue(attributeName)`
- 属性値の編集: `editAttribute(attributeName, newValue)`
  - DBとメンバ変数を同時に更新
- フィーチャ削除: `dispose()`
- ジオメトリ取得: `geometry`

#### PointFeatureNode, LineFeatureNode, PolygonFeatureNode
- FeatureNodeを継承し、点・線・面のジオメトリを保持
- それぞれ`geometry`で型ごとのデータを返す

## 追加機能
- てのひらツール(PanTool)で指の移動量に応じて地図をパンできるようにした

## 主要ファイル・クラス
- lib/tools/pan_tool.dart: 地図パン専用ツール。onScaleStart/onScaleUpdate/onScaleEndでパン処理を実装。
- lib/screens/map_page.dart: 地図画面本体。PanToolから呼ばれるlatLngToScreenPoint/offsetToLatLngを提供。
- MapController: flutter_mapの地図制御用コントローラ。move/latLngToScreenPoint/pointToLatLng等を利用。

## クラス構成
- PanTool(MapTool継承):
    - onScaleStart: 指位置記録
    - onScaleUpdate: 移動量から中心座標を再計算しmove
    - onScaleEnd: 状態リセット
- KMapsHomePage(State):
    - latLngToScreenPoint/offsetToLatLng: 座標変換
    - _mapController: 地図制御

## 使い方
- 左ツールバーで「てのひら」選択後、地図上でドラッグするとパン可能

## 主な機能
- 距離・長さ・面積計算
- 重心計算
- 最近傍feature検索
- degree・metre変換

## 主要ファイル
- `lib/utils/feature_calc_utils.dart`: フィーチャ計算の静的関数群
- `lib/models/layer_tree_node.dart`: FeatureNode型定義

## feature_calc_utils.dart の主なクラス・関数

### DegreeMeterConverter（degree・metre変換系）
- `metersPerDegreeLat()`
- `metersPerDegreeLng(lat)`
- `metersToDegreesLat(meters)`
- `metersToDegreesLng(meters, lat)`
- `degreesToMetersLat(degrees)`
- `degreesToMetersLng(degrees, lat)`
- `convertAreaToMeters2(area, lat)`

### GeometryCalc（距離・長さ・面積・重心計算）
- `calcDistance(a, b)`
- `calcLineLength(line)`
- `calcPolygonArea(polygon)`
- `calcLineCentroid(line)`
- `calcPolygonCentroid(polygon)`
- `calcPointsCentroid(points)`
- `calcPointToLineDistance(pt, line)`
- `calcPointToPolygonDistance(pt, polygon)`

### FeatureSearch（feature距離・最近傍feature検索）
- `calcPointToFeatureDistance(pt, geometry, featureType)`
- `findNearestFeature(pt, features, featureType)`

---
- すべてstaticメソッドとして利用可能
- 例: `GeometryCalc.calcDistance(a, b)`

## 依存
- latlong2

---

## 新機能: 左下フロートボタン
- 地図画面左下に白い丸のフロートボタンを追加。
- 押下状態（ON/OFF）は `GlobalConfig.instance.isFabActive` でグローバル管理。
- ボタンは `lib/screens/map_page.dart` の `_LeftBottomFab` ウィジェットで実装。
- 状態は今後他機能からも参照・利用可能。

### 主要ファイル・クラス
- `lib/utils/global_config.dart`: グローバル設定・状態管理クラス。`isFabActive` プロパティ追加。
- `lib/screens/map_page.dart`: 地図画面本体。左下フロートボタンのUI・状態トグル処理を実装。

## 依存パッケージ

- nmea: NMEA0183フォーマットのGPSデータをパースするために使用。
  - 追加方法: pubspec.yaml の dependencies に `nmea: ^2.0.0` を追記し、`flutter pub get` を実行。

## 主な機能（Features）
- GPSデータの取得・パース（マルチプラットフォーム対応: Android/iOS/Windows）
- NMEAセンテンスのストリーム処理
- 衛星情報の抽出（GSV文対応）
- 位置情報モデル・衛星情報モデルの提供
- 権限管理・サービス有効化確認

## 主要ファイルと内容

### lib/tools/gps_utils.dart
- GPSユーティリティークラス（GpsUtils）
  - シングルトンパターンでインスタンス化
  - プラットフォームごとに位置情報取得・ストリーム購読・NMEAパースを分岐実装
  - NMEAセンテンスのストリームを受け取り、nmeaパッケージでパース
  - GGA文から位置情報（GpsPosition）を抽出
  - GSV文から衛星情報（SatelliteInfo）を抽出
  - 権限確認・リクエスト、サービス有効化確認
- モデルクラス
  - SatelliteInfo: 衛星ID・SNR・使用中か
  - NmeaSentence: NMEA生データ保持
  - GpsPosition: 緯度・経度・高度・衛星数・HDOP

## クラス構成

- `GpsUtils`
  - `getCurrentPosition()` : 現在地取得（未実装部分あり）
  - `getPositionStream()` : 位置情報ストリーム購読
  - `getNmeaStream(Stream<String>)` : NMEAセンテンスストリーム購読
  - `getSatellitesFromNmea(Stream<String>)` : 衛星情報抽出
  - `checkAndRequestPermission()` : 権限確認・リクエスト
  - `isLocationServiceEnabled()` : サービス有効化確認
- `SatelliteInfo` : 衛星情報モデル
- `NmeaSentence` : NMEAセンテンスモデル
- `GpsPosition` : 位置情報モデル

---

nmeaパッケージの詳細: https://pub.dev/packages/nmea

## 新機能: GPS情報バー
- 地図画面（map_page.dart）のAppBar直下に、現在のGPS情報（緯度・経度・衛星数・HDOPなど）を表示するバーを追加。
- `lib/tools/gps_utils.dart` の `GpsUtils` クラスを利用し、現在地・衛星数・HDOP等をリアルタイム表示。
- テスト用途として、GPS情報の取得・表示の動作確認が可能。

## 機能一覧
- 地図表示（OpenStreetMapタイル）
- レイヤ/フィーチャ編集（点・線・ポリゴン）
- 現在位置取得・地図上への表示（青色アイコン）
- GPS情報バー（緯度・経度・衛星数・HDOP）
- カスタムDrawerによるレイヤ管理

## 主要ファイルと内容
- `lib/screens/map_page.dart`:
    - 地図・編集画面の本体。`KMapsHomePage`/`_KMapsHomePageState`で地図・UI・ツールバー・Drawer等を管理。
    - `FlutterMap`の`MarkerLayer`にて、`_currentLocation`が取得できていれば青色の`Icons.my_location`で現在位置を地図上に表示。
    - GPS情報は`GpsUtils`経由で取得し、画面上部バーに表示。
    - レイヤ・フィーチャの描画、編集、Drawer管理、ツール切替なども本ファイルで実装。
- `lib/tools/gps_utils.dart`:
    - GPS情報取得・NMEAパース・衛星情報抽出などのユーティリティ。
    - マルチプラットフォーム対応を考慮した設計。

## クラス構成（抜粋）
- `KMapsHomePage`/`_KMapsHomePageState`：地図・編集画面のStatefulWidget。地図UI・Drawer・ツールバー・GPS情報管理。
- `GpsUtils`：GPS情報取得・NMEAパース・衛星情報抽出のユーティリティクラス。
- `GpsPosition`：緯度・経度・高度・衛星数・HDOP等のGPS情報モデル。

## 現在位置アイコンの表示仕様
- `lib/screens/map_page.dart`の`FlutterMap`内`MarkerLayer`にて、
  - `_currentLocation`がnullでなければ、青色の`Icons.my_location`アイコンを現在位置に表示。
  - 既存のフィーチャマーカーと重複しないよう、リストの先頭に追加。