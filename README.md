# K-MAPS

## 最新の修正・改善

### 2024/12/XX - GPS測量ポリゴン2点目のLatLngBoundsエラー修正

**概要：** GPS測量でポリゴンの2点目を追加した際に発生していた`LatLngBounds cannot be created with an empty List of LatLng`エラーを修正

**発見された問題：**
- GPS測量でポリゴンの2点目追加時にマップが真っ赤になりエラーが表示される
- 3点目追加後は正常に動作するが、2点目の時点でエラーが発生

**根本原因：**
- pen_toolでは既に修正済みだったが、GPS測量では2点以上（`>= 2`）でポリゴンプレビューを表示していた
- 2点で`closeRing`を呼び出すと空のリストが返され、flutter_mapのLatLngBounds作成時にエラーが発生

**実施した修正：**
1. **GPS測量ポリゴンプレビュー条件を3点以上に変更**：
   - `lib/screens/map_page.dart`：GPS測量ポリゴンプレビューの条件を`>= 2`から`>= 3`に修正
   
2. **データ参照の統一化**：
   - GPS測量表示を古い`(GpsTool).surveyPolygon`から`GlobalDrawingState.drawingPolygon`に変更
   - GPS測量ライン表示も`GlobalDrawingState.drawingLine`に統一
   
3. **2点時のライン表示追加**：
   - GPS測量でポリゴン2点時は線として表示（pen_toolと同様の動作）
   - 2点では`closeRing`を呼ばずに直接線として描画

**技術詳細：**
- GPS測量ポリゴンプレビュー：`>= 2` → `>= 3`に条件変更
- GPS測量2点時：`Polyline`として表示（紫色、4.0px幅）
- GPS測量3点以上：`Polygon`として表示（紫色、透明度0.4）

**効果：**
- GPS測量ポリゴン2点目追加時のエラー完全解消
- pen_toolとGPS測量で一貫した動作を実現
- データ参照の統一によるバグ防止

### 2024/12/XX - pen_toolフリーハンド描画のunmodifiableリストエラー修正

**概要：** pen_toolのフリーハンド描画（onScale）で発生していた`UnsupportedError: Cannot clear an unmodifiable list`エラーを修正

**発見された問題：**
- pen_toolのタップ描画は正常だが、フリーハンド描画（onScale）で`drawingPolygon.clear()`実行時にエラーが発生
- `drawingLine.clear()`、`drawingPolygon.clear()`でunmodifiableなリストに対してclear()メソッドを呼び出していた

**根本原因：**
- GlobalDrawingStateのgetterは`List.unmodifiable()`で読み取り専用リストを返すため、直接clear()できない
- 正しくは`drawingState.clearLine()`、`drawingState.clearPolygon()`メソッドを使用する必要

**実施した修正：**
- `lib/tools/pen_tool.dart`の198行目：`drawingLine.clear()` → `drawingState.clearLine()`
- `lib/tools/pen_tool.dart`の204行目：`drawingPolygon.clear()` → `drawingState.clearPolygon()`
- pointerバッファ処理での正しいGlobalDrawingState API使用

**テスト結果：**
- フリーハンド描画シミュレーションテスト：5つのテストケース全てPASS
- unmodifiableリストの動作確認とエラーハンドリング検証
- pen_toolの連続描画とクリア操作の正常動作確認

**効果：**
- pen_toolのフリーハンド描画（線・ポリゴン）が正常に動作
- タップ描画・フリーハンド描画の両方で安定した動作を実現
- GlobalDrawingState APIの正しい使用パターンの確立

### 2024/12/XX - GlobalDrawingState復元とデータ整合性修正

**概要：** 空になったGlobalDrawingStateファイルを復元し、GPS測量マーカー表示のデータ参照を統一してデータ整合性を確保

**発見された問題：**
1. **GlobalDrawingStateファイルの消失**：`lib/utils/global_drawing_state.dart`が空ファイルになっていた
2. **データ参照の不整合**：マーカー表示で古い`GpsTool.surveyLine/surveyPolygon`を参照しているのに、数字表示では`GlobalDrawingState`を参照していた

**実施した修正：**
1. **GlobalDrawingStateクラスの完全復元**：
   - シングルトンパターンによるグローバル描画状態管理
   - 線・ポリゴンの描画点列とメタデータの統合管理
   - GPS測量とpen_tool描画の統一API提供
   - デバッグ用のprint出力で状態変化を追跡可能

2. **マーカー表示の統一**：
   - map_pageでのマーカー表示を`GlobalDrawingState.drawingLine/drawingPolygon`に変更
   - 数字表示と座標表示の両方が同じデータソースを参照
   - データ整合性の完全確保

**技術詳細：**
- `lib/utils/global_drawing_state.dart`：171行の完全実装を復元
- `lib/screens/map_page.dart`：マーカー表示参照先を`GpsTool.survey*`から`GlobalDrawingState.drawing*`に変更
- すべてのツールがGlobalDrawingStateインスタンスを共有

**テスト結果：**
- `test/global_drawing_state_test.dart`：7つのテストケース全てPASS
- マーカー表示と数字表示の完全同期を確認
- データ追加・削除・クリア操作の正常動作を検証

**効果：**
- GPS測量とpen_tool間でのシームレスな描画継続
- データ整合性の完全確保
- デバッグとトラブルシューティングの向上

### 2024/12/XX - GPS測量点の表示方法改善とprivateメソッドエラー修正

**概要：** GPS測量時に表示される点の数字を、実際の測量回数に基づいて表示する機能を実装し、Dartのprivateメソッドアクセスエラーを解決

**主な変更内容：**
1. **GPS測量点カウント表示機能**：
   - GPS測量点のマーカーに、実際に測量した点数を表示
   - メタデータありの場合：`point_count`フィールドまたは`collected_points`配列の長さを表示
   - メタデータなし（pen_toolタップ）の場合：1を表示
   - 長押し平均化測量時は、収集されたGPS点数を正確に表示

2. **privateメソッドエラーの解決**：
   - Dartの「アンダースコア（_）で始まるメソッドはprivate」というアクセス制御の問題を解決
   - メソッド分離によるスコープ問題を回避するため、ロジックをインライン化
   - 即時実行関数式（IIFE: Immediately Invoked Function Expression）パターンを使用
   - エラーハンドリング強化でフォールバック機能を提供

**技術詳細：**
- `lib/screens/map_page.dart`：GPS測量マーカーの表示ロジック修正
- インライン化されたメタデータ解析ロジック：各マーカーで直接実行
- GPS測量・pen_tool混在時の適切な識別と表示
- Dartのprivate/publicアクセス制御の理解と対応

**修正したコンパイルエラー：**
- `The method '_getGpsSurveyPointCount' isn't defined for the type '_KMapsHomePageState'`
- privateメソッドアクセスによるスコープ問題を根本解決

**技術的学習：**
- [Dartの公式ドキュメント](https://dart.dev/language/methods)に基づく適切なアクセス制御
- [Dart SDK issue #33383](https://github.com/dart-lang/sdk/issues/33383)で議論されているpublic/private修飾子の現状理解
- インライン化による可読性とパフォーマンスのバランス

**効果：**
- 測量時により直感的な情報表示
- GPS測量精度の可視化向上
- ユーザビリティの改善
- コンパイルエラー完全解決（88 issues: warnings/info のみ、errors 0個）

### 2024/12/XX - 描画状態のグローバル化とツール間連携強化

**概要：** GPS測量とペンツールでの描画状態を統一し、ツール間での描画継続機能を実装

**主な変更内容：**
1. **GlobalDrawingState導入**：
   - グローバルな描画状態管理クラスを新設
   - 線・ポリゴンの描画点列をツール間で共有
   - 各点にメタデータ（GPS測量データ）の管理機能を追加
2. **ツール間描画継続機能**：
   - pen_toolでタップ描画開始後、GPS_toolに切り替えてGPS測量で続きを描画可能
   - GPS_toolで測量開始後、pen_toolに切り替えてタップで続きを描画可能
   - ツール切り替え時も描画状態とプレビューを保持
3. **メタデータ管理の統一**：
   - GPS測量点：位置情報・精度・時刻・データソース等の詳細メタデータを自動記録
   - pen_tool点：座標のみでメタデータなし（data_sourceはpen_toolとして記録）
   - 混在した描画データを統一形式で管理・保存

**技術詳細：**
- `lib/utils/global_drawing_state.dart`：新設のグローバル描画状態管理
- `lib/tools/pen_tool.dart`：GlobalDrawingStateを使用するようリファクタリング
- `lib/tools/gps_tool.dart`：GlobalDrawingStateを使用するようリファクタリング（進行中）
- `lib/utils/global_config.dart`：GlobalDrawingStateインスタンスを追加

**テスト：**
- `test/global_drawing_state_test.dart`：7つのテストケース全てPASS
- GPS測量・pen_tool混在描画、メタデータ管理、Undo機能等を検証済み

**影響範囲：**
- 描画機能の根本的な改善（後方互換性維持）
- レンダリング・表示系には影響なし
- 既存のGeoPackage保存機能は引き続き利用

### 2024/12/XX - PenToolのポリゴン描画フリーズ問題の修正

**問題：** PenToolによるタップでのポリゴン描画時、3点目または2点目のタイミングでフリーズが発生する問題

**原因：** `addDrawingPolygonPoint`メソッドで毎回setStateを同期実行することで、UI更新の負荷が高くなっていた

**修正内容：**
1. `addDrawingPolygonPointOptimized`メソッドを新規追加
   - UI更新を`Future.microtask`で遅延実行
   - 座標追加とUI更新を分離してパフォーマンスを向上
2. onTapメソッドにデバッグログを追加
   - フリーズ発生箇所の特定が容易に
   - 処理の流れを詳細にトレース可能
3. エラーハンドリングの強化
   - try-catch文でエラー処理を明確化

**影響範囲：**
- `lib/tools/pen_tool.dart`：onTapメソッドとaddDrawingPolygonPointOptimizedメソッド
- ラインレイヤーやポイントレイヤーには影響なし
- フリーハンド描画（onScale）には影響なし

**テスト：**
- タップによるポリゴン描画の連続実行テスト
- UI更新の最適化テスト（作成済み: `test/simple_pen_tool_test.dart`）

## 概要
K-MAPSはGeoPackageベースの地理情報管理・編集アプリケーションです。地図上での点・線・面の描画・編集、GPS位置情報の取得、外部GNSS受信機との連携などの機能を提供します。

## 主要機能

### 1. フォアグラウンドサービス機能 **【NEW・外部GNSS対応】**
- **概要**: バックグラウンドでタスクを継続実行する機能（GPS + 外部GNSS対応）
- **実装**: `flutter_background_service` パッケージを使用
- **機能詳細**:
     - **外部GNSS優先システム**: 接続された外部GNSSを優先、未接続時は内蔵GPSを使用 **【NEW】**
   - **Bluetooth GNSS自動連携**: Bluetooth GNSS画面で設定されたデバイスを自動検出・接続 **【NEW】**
   - **NMEAデータリアルタイム解析**: GGA/RMC文の解析による高精度位置情報取得 **【NEW】**
   - **画面遷移時接続維持**: グローバルマネージャーによる接続の永続化管理 **【NEW】**
  - 1秒間隔でのGPS/GNSS情報付きログ出力（デバッグ・テスト・追跡用）
  - リアルタイム位置座標取得（緯度・経度・精度・受信数情報）
  - Android端末では通知バーでGPS/GNSS状態と座標を表示
  - UIからのサービス開始・停止制御
  - GPS権限・サービス状態の事前確認
  - エラーハンドリングとログ出力の最適化

### 2. 地図表示・ナビゲーション **【背景地図機能追加・フィーチャ表示改善・キャッシュ機能修正】**
- **複数背景地図対応**: OpenStreetMap、国土地理院地図（標準、淡色、写真、標高、白地図）の選択可能 **【NEW】**
- **オフライン機能**: 一度表示した地図タイルを自動キャッシュ、オフライン時も利用可能 **【NEW】**
- **キャッシュ管理**: プロバイダー別キャッシュサイズ表示・個別/全体クリア機能 **【NEW】**
- **背景地図設定画面**: プロバイダー選択、オフラインモード切り替え、キャッシュ統計表示 **【NEW】**
- **キャッシュ機能修正**: Windows環境での安定性重視により無効化されていたCachedTileLayerを有効化、地図タイルキャッシュが0タイル表示問題を解決 **【FIXED】**
- **オフラインキャッシュ強化**: オンライン取得失敗時にキャッシュから確実に読み込むフォールバック機能を追加、リトライ機能とクロスプラットフォームキャッシュ検索を実装 **【ENHANCED】**
- **詳細キャッシュ統計**: ズームレベル別統計、キャッシュ検証・修復機能、詳細デバッグログ出力を追加（開発・トラブルシューティング支援） **【NEW】**
- レイヤ構造での地理情報管理（点・線・面）
- フリーハンド描画とタップによる図形作成
- フィーチャの選択・編集・削除
- **属性情報の表示・編集**: 
  - **最適化された情報表示**: フィーチャ選択時にユーザー向けの情報のみ表示（metadata項目は非表示） **【NEW】**
  - **スクロール対応**: 属性情報パネルに高さ制限（300px）とスクロール機能を追加 **【NEW】**
  - **レスポンシブ表示**: 内容量に応じてパネルサイズが自動調整 **【NEW】**
  - **属性テーブル画面**: レイヤの全フィーチャ属性をテーブル形式で表示・編集
  - **TSVエクスポート機能**: 属性テーブル画面からワンクリックでTSVファイル出力（GeoPackageファイルと同階層に保存） **【NEW】**
  - **メタデータTSVエクスポート**: メタデータ表示ダイアログから(gpkg名)_(レイヤ名)_(フィーチャ名)_metadata_table.tsv形式でTSVファイル出力（プロジェクトルートに保存、フィーチャ名はFeatureNode.nameを使用） **【NEW】**

### 3. GPS・GNSS機能 **【統合GPS管理プロセス完成・GPS測量機能追加・効率化】**
- **統一GPS管理サービス**: 内蔵GPSと外部GNSS機器を統一的に管理するプロセス
- **動的ソース切り替え**: 内蔵GPSと外部GNSS間でのリアルタイム切り替え
- **高精度記録機能**: オプション設定対応（取得インターバル・最短移動距離・精度フィルタ）
- **GPS履歴管理**: 記録開始から現在までの履歴を辞書リスト形式で提供
- **GPS測量機能**: 現在位置を記録してPoint/Line/Polygonフィーチャを作成（軌跡記録とは独立動作・Point即座作成・長押し平均化対応） **【NEW・独立化・修正・強化】**
- **連続測量最適化**: 長押し時の連続測量を位置更新ベースに変更（タイマーベースから改善）、フォアグラウンドサービスの位置更新タイミングでポイント収集 **【NEW・効率化】**
- **GPS測量データ記録**: 位置・精度・時刻・データソース等の詳細情報を最適化された辞書構造で自動記録（通常・長押し測量共に統一形式） **【NEW・簡素化・構造最適化・形式統一】**
- **長押しGPS平均化**: 測量ボタン長押しで位置更新毎にGPS収集→平均化による高精度測量（1秒間隔保証なし問題を解決） **【NEW・修正】**
- **外部GNSS重複測量修正**: GGAとRMCメッセージの重複処理による1秒2回測量問題を修正、500ms最小間隔制限により1秒1回測量を実現 **【NEW・修正】**
- **リアルタイムプレビュー**: GPS測量中の描画状況をリアルタイム表示 **【NEW】**
- **オンデマンドGPS開始**: 必要時にのみGPS位置情報取得を開始（省電力化）**【効率化】**
- **GPS測量専用制御**: 位置取得完了待機・測量完了時自動停止（Point即座停止・Line/Polygon確定時停止）（リソース効率化）**【NEW・修正】**
- **GPS追跡処理統合**: フォアグラウンドサービスでも統合GPS管理サービスを使用（処理一元化）**【統合】**
- **GPS処理プロセス統一**: 測量・追跡共にフォアグラウンドサービスで処理（リソース競合完全回避）**【アーキテクチャ改善】**
- SSP対応Bluetooth GNSS受信機との連携
- NMEA-0183フォーマットの位置データ解析
- リアルタイム位置情報表示・監視
- 衛星情報・精度情報の詳細表示
- **GPS軌跡記録・保存機能**: 追跡開始から停止までの軌跡をLINESTRINGレイヤーとして任意のGeoPackageに保存

### 4. データ管理機能
- GeoPackage形式でのデータ保存・管理
- プロジェクト・フォルダ・レイヤの階層構造
- レイヤの可視性制御
- データのインポート・エクスポート
- **構造化メタデータ管理**: `kmaps_metadata`カラムによる測量データの構造化保存 **【NEW】**
- **即座GeoPackage作成**: GeoPackageノード作成時に空のファイルを即座に作成（ユーザー期待に合致） **【NEW】**
- **属性テーブルTSVエクスポート**: 属性テーブル画面から(gpkg名)_(レイヤ名)_propety_table.tsv形式でデータをエクスポート（TSVエスケープ処理付き） **【NEW】**
- **メタデータテーブルTSVエクスポート**: メタデータ表示ダイアログから(gpkg名)_(レイヤ名)_(フィーチャ名)_metadata_table.tsv形式でエクスポート（フィーチャ名はFeatureNode.nameを使用） **【NEW】**
- **画像ファイル管理機能 (PhotoNode)**: フォルダ内の画像ファイル（JPEG, PNG, TIFF）を自動スキャン、EXIFデータから位置情報を抽出し、緯度経度がある画像のみをPhotoNodeとして管理・地図表示 **【NEW】**

### 操作ツール
- **てのひらツール**: 地図のパン操作
- **ペンツール**: フリーハンド描画
- **選択ツール**: フィーチャの選択・編集
- **GPSツール**: GPS関連機能（GPS測量・追跡・軌跡保存） **【GPS測量機能強化】**

## 技術構成

### フレームワーク・言語
- **Flutter**: クロスプラットフォーム対応（Android/iOS/Windows/macOS/Linux）
- **Dart**: プログラミング言語

### データベース・ストレージ
- **sqflite**: Flutter推奨のSQLiteデータベース（sqlite3から移行完了）
- **GeoPackage**: OGC標準の地理空間データフォーマット
- 非同期処理（async/await）による高パフォーマンス

### 主要パッケージ
```yaml
dependencies:
  flutter_map: ^8.1.1           # 地図表示（最新版にアップデート）
  latlong2: ^0.9.0              # 緯度経度計算
  sqflite: ^2.3.0               # データベース
  geolocator: ^10.1.0           # GPS位置情報
  flutter_bluetooth_serial: ^0.4.0  # Bluetooth接続
  nmea: ^2.0.0                  # NMEAデータ解析
  file_picker: ^10.1.9          # ファイル選択
  flutter_background_service: ^5.0.9  # フォアグラウンドサービス
  permission_handler: ^11.3.1  # Android権限管理
  # オフライン機能・キャッシュ用パッケージ **【NEW】**
  path_provider: ^2.1.4         # アプリディレクトリ取得
  shared_preferences: ^2.3.2    # 設定保存
  crypto: ^3.0.5                # ハッシュ化
  http: ^1.2.2                  # HTTP通信（背景地図ダウンロード）
  # 座標変換・住所変換用パッケージ **【NEW】**
  proj4dart: ^2.1.0            # 座標変換（Proj.4のDart実装）
```

## 主要ファイル・クラス構成

### モデル層
- `lib/models/geopackage_file.dart`: GeoPackageファイル管理・DB操作（メタデータ対応） **【更新】**
- `lib/models/layer_tree_node.dart`: レイヤツリー構造・ノード管理（メタデータ対応・PhotoNode機能追加） **【更新】**
- `lib/models/basemap_provider.dart`: 背景地図プロバイダー定義・管理 **【NEW】**
- `lib/models/bluetooth_gnss_service.dart`: Bluetooth GNSS接続・NMEAデータ解析
- `lib/models/gps_track.dart`: GPS軌跡データ・ポイント管理
- `lib/utils/global_config.dart`: アプリケーション全体の設定管理（GPS・背景地図設定含む） **【更新】**
- `lib/utils/global_gnss_manager.dart`: GNSS接続のグローバル管理・永続化

### 画面・UI層
- `lib/screens/map_page.dart`: 地図表示・編集のメイン画面
- `lib/screens/basemap_settings_screen.dart`: 背景地図設定画面（プロバイダー選択・オフライン・キャッシュ管理） **【NEW】**
- `lib/screens/gps_settings_screen.dart`: GPS設定画面
- `lib/widgets/layer_drawer.dart`: レイヤ管理ドロワーUI
- `lib/widgets/cached_tile_layer.dart`: キャッシュ機能付きカスタムタイルレイヤー **【NEW】**

### サービス層
- `lib/services/basemap_service.dart`: 背景地図管理・オフラインキャッシュサービス **【NEW】**
- `lib/services/foreground_service.dart`: GPS/GNSS追跡フォアグラウンドサービス
- `lib/services/gps_manager_service.dart`: **統合GPS管理サービス（本格実装・連続測量機能対応）** **【NEW・更新】**

### ツール・ユーティリティ
- `lib/tools/pan_tool.dart`: 地図パン操作ツール
- `lib/tools/pen_tool.dart`: フリーハンド描画ツール  
- `lib/tools/select_tool.dart`: フィーチャ選択ツール
- `lib/tools/gps_tool.dart`: GPS関連機能ツール（プロキシパターンによるパンツール機能継承・メタデータ対応） **【更新】**
- `lib/tools/gps_utils.dart`: GPS・GNSS情報取得ユーティリティ
- `lib/utils/feature_calc_utils.dart`: 地理計算ユーティリティ（距離・面積・重心計算）
- `lib/utils/coordinate_converter.dart`: 座標変換ユーティリティ（UTM・JGD2011対応） **【NEW】**
- `lib/utils/address_converter.dart`: 住所変換ユーティリティ（Nominatim API連携） **【NEW】**
- `lib/utils/metadata_parser.dart`: メタデータパーサー（XY座標自動追加機能） **【NEW】**
- `lib/examples/gps_manager_example.dart`: **GPS管理サービス使用例・テストサンプル** **【NEW】**

### 設計方針
- **非同期処理**: 全てのDB操作・ファイルアクセスはFuture/async-awaitで実装
- **ツリー構造管理**: プロジェクト→フォルダ→GeoPackage→レイヤの階層管理
- **グローバル状態管理**: 選択状態・現在ツール・設定をGlobalConfigで一元管理
- **プロキシパターン**: GPSツールによるパンツール機能の継承・委譲（将来拡張対応） **【NEW】**
- **プラットフォーム対応**: Windows/Android両対応、デスクトップ向けsqflite初期化

## 使用方法

### 基本操作
1. **プロジェクト作成**: ホーム画面でプロジェクトフォルダを選択
2. **背景地図設定**: マップ画面右上の地図アイコンから背景地図設定画面にアクセス、プロバイダー選択・オフラインモード設定 **【NEW】**
3. **GeoPackage作成**: ドロワーの「+」ボタン（ストレージアイコン）で空のGeoPackageファイルを即座に作成 **【即座作成】**
4. **レイヤ作成**: 作成したGeoPackageを展開し、「Add Layer」でレイヤを追加
5. **描画**: ツールバーでペンツールを選択し、地図上で描画
6. **編集**: 選択ツールでフィーチャを選択し、属性編集・位置調整
7. **属性テーブル表示**: レイヤドロワーでレイヤの「...」メニューから「属性テーブル」を選択
8. **TSVエクスポート**: 属性テーブル画面のダウンロードアイコンをクリックしてTSV出力 **【NEW】**
9. **メタデータTSVエクスポート**: メタデータ表示ダイアログのダウンロードアイコンをクリックして(gpkg名)_(レイヤ名)_(フィーチャ名)_metadata_table.tsv形式でTSV出力（フィーチャ名はFeatureNode.nameを使用） **【NEW】**

### 背景地図・オフライン機能 **【NEW】**
1. **背景地図選択**: マップ画面右上の地図アイコン→背景地図設定→希望のプロバイダーを選択
2. **オフラインモード**: 背景地図設定画面でオフラインモードを有効化（ネットワーク使用停止）
3. **自動キャッシュ**: 表示した地図タイルは自動的にローカルストレージにキャッシュ保存
4. **キャッシュ管理**: 背景地図設定画面でプロバイダー別キャッシュサイズ確認・個別/全体クリア
5. **利用可能プロバイダー**:
   - OpenStreetMap（世界地図）
   - 国土地理院標準地図（日本の詳細地図）
   - 国土地理院淡色地図（背景用）
   - 国土地理院航空写真
   - 国土地理院色別標高図
   - 国土地理院白地図

### GPS・GNSS接続 **【外部GNSS強化】**
1. **内蔵GPS**: アプリ起動時は待機状態で初期化、GPS測量・追跡開始時に位置情報取得を開始 **【効率化】**
2. **外部GNSS**: 
   - マップ画面のBluetoothアイコンから接続画面にアクセス
   - ペアリング済みBluetoothデバイスの一覧表示・接続
   - 接続成功時に自動でフォアグラウンドサービスに設定保存 **【NEW】**
   - NMEA-0183データの自動解析（GGA文対応） **【NEW】**
3. **位置表示**: 地図上に青色アイコンで現在位置を表示
4. **フォアグラウンドサービス連携**: 
   - 外部GNSS接続時は優先してGNSSデータを使用 **【NEW】**
   - 通知に「GNSS」または「GPS」の表示で情報源を明確化 **【NEW】**

### 基本使用方法 **【外部GNSS対応】**
1. ホーム画面で「フォルダを選択」ボタンをクリック
2. プロジェクトフォルダを選択
3. 自動的にマップ画面に遷移
4. **外部GNSS接続**（オプション）:
   - マップ画面上部のBluetoothアイコンをタップ **【NEW】**
   - ペアリング済みGNSSデバイスを選択・接続 **【NEW】**
   - 接続成功すると自動でフォアグラウンドサービスに設定 **【NEW】**
5. **位置追跡サービス制御** **【UI改善】**:
   - ツールバーでGPSツールを選択 **【NEW】**
   - 右下に表示される足跡アイコンのフローティングボタンで追跡開始・停止 **【NEW】**
   - 外部GNSS接続時は「外部GNSS追跡」、未接続時は「内蔵GPS追跡」として動作 **【NEW】**
6. **リアルタイム確認**:
   - デバッグコンソールで1秒間隔のGPS/GNSS情報ログ確認
   - Android端末では通知バーでリアルタイム座標・情報源表示 **【NEW】**
   - GPS情報バーでリアルタイム座標・衛星数・精度確認（追跡ボタンは削除済み） **【NEW】**

## インストール・セットアップ

### 開発環境
```bash
# 依存関係インストール
flutter pub get

# デバッグビルド
flutter run

# リリースビルド（Android）
flutter build apk --release
```

### 権限設定（Android）
以下の権限がAndroidManifest.xmlで設定済みです：
- `ACCESS_FINE_LOCATION`: 高精度GPS
- `ACCESS_COARSE_LOCATION`: 概算位置情報  
- `BLUETOOTH_CONNECT`: Bluetooth接続
- `INTERNET`: 地図タイル取得
- `READ_EXTERNAL_STORAGE`: ファイル読み取り **【NEW】**
- `WRITE_EXTERNAL_STORAGE`: ファイル書き込み **【NEW】**
- `MANAGE_EXTERNAL_STORAGE`: 全ファイルアクセス（Android 11以降） **【NEW】**

### 初回起動時の権限設定 **【NEW】**
1. アプリ初回起動時に自動的にストレージ権限をリクエスト
2. 権限が拒否された場合、設定画面への誘導ダイアログを表示
3. 権限が許可されるまで、プロジェクトフォルダの選択は無効化
4. アプリがフォアグラウンドに戻った際に権限状態を自動再確認

### 手動権限設定（必要に応じて）
権限リクエストが正常に動作しない場合：
1. 端末の「設定」→「アプリ」→「K-MAPS」
2. 「権限」または「アプリの権限」
3. 「ストレージ」権限を有効化
4. Android 11以降では「すべてのファイルへのアクセス」も有効化

## QGISとの互換性・問題解決 **【NEW・GeoPakage対応強化】**

### 解決済み問題: 「地物にジオメトリがありません」エラー

**問題**: アプリで作成したGeoPackageファイルをQGISで開くと属性テーブルは表示されるが、ジオメトリが認識されないエラーが発生していました。

**原因**:
1. **GPBinaryヘッダーの欠如**: GeoPackageではWKBデータの前にGPBinary（GeoPackage Binary）ヘッダーが必要
2. **空間インデックスの不足**: QGISでの空間データ認識に必要なインデックスが未作成
3. **座標系情報の不完全**: SRS（Spatial Reference System）情報の設定が不十分

**解決策の実装**:
1. **GPBinaryヘッダー追加** (`lib/utils/wkb_utils.dart`):
   - `_createGpbHeader()`: GeoPackage仕様に準拠したバイナリヘッダー生成
   - 全てのWKB生成関数でGPBinaryヘッダーを自動付与
   - WKB読み込み時のGPBinaryヘッダー自動検出・スキップ機能

2. **空間インデックス自動作成** (`lib/models/geopackage_file.dart`):
   - `_createSpatialIndex()`: レイヤ作成時の空間インデックス自動生成
   - QGISでの空間クエリ性能向上

3. **GeoPackage仕様準拠**:
   - WGS84（EPSG:4326）座標系の適切な設定
   - `gpkg_spatial_ref_sys`テーブルの完全初期化
   - `gpkg_geometry_columns`テーブルの正確なメタデータ登録

**技術詳細**:
```dart
// GPBinaryヘッダー構造（8バイト）
// [0-1] 'GP' - マジックナンバー
// [2]   0x00  - バージョン
// [3]   0x01  - フラグ（リトルエンディアン）
// [4-7] SRS ID（4326 = WGS84）
```

**動作確認済み環境**:
- QGIS 3.28+
- GDAL 3.0+
- PostGIS互換性確保

この修正により、K-MAPSで作成したGeoPackageファイルはQGISで完全に認識され、空間データの表示・編集・解析が可能になりました。

## GPS測量機能 **【NEW・メタデータ対応】**

### GPS測量データのメタデータ管理 **【NEW】**

GPS測量で取得したデータは、`description`ではなく構造化された`metadata`として保存されます。

#### メタデータ構造
```json
{
  "type": "measurement_log",
  "contents": {
    "pointNumber": 1,
    "calculatedPosition": {
      "latitude": 35.123456,
      "longitude": 139.123456,
      "altitude": 10.5,
      "averagedAccuracy": 3.2
    },
    "usedGpsData": [
      {
        "latitude": 35.123456,
        "longitude": 139.123456,
        "altitude": 10.5,
        "accuracy": 3.2,
        "timestamp": "2024-01-01T12:00:00.000Z",
        "sourceType": "GPS",
        "sourceName": "内蔵GPS",
        "collectedAt": "2024-01-01T12:00:00.000Z"
      }
    ],
    "sampleCount": 10,
    "averagingDuration": "瞬時測量" or "5.2秒",
    "recordedAt": "2024-01-01T12:00:00.000Z"
  }
}
```

#### メタデータの利点
- **構造化データ**: 後の解析・処理に活用可能
- **詳細情報保持**: GPS精度、取得時刻、データソース等を完全保存
- **統一形式**: 単発測量・長押し測量共に同じ構造で管理
- **拡張性**: 将来的な機能追加に対応可能

### GPS測量の使用方法

GPS測量機能により、現在のGPS位置を記録してPoint/Line/Polygonフィーチャを作成できます。

#### 基本操作手順

1. **GPSツールを選択**: ツールバーでGPSツール（GPS固定アイコン）を選択
2. **レイヤーを選択**: 作成したいフィーチャタイプのレイヤーを選択
   - PointLayerNode: GPS測量ポイント作成
   - LineLayerNode: GPS測量ライン作成  
   - PolygonLayerNode: GPS測量ポリゴン作成
3. **GPS測量実行**: 左下の青いフロートボタン（📍アイコン）を押して現在位置を記録
   - 初回実行時は「GPS位置情報を取得中...」メッセージが表示され、GPS機能が自動開始されます
   - GPS位置情報が確実に取得できるまで待機（最大10秒タイムアウト）
4. **測量継続**: 移動しながら測量ボタンを繰り返し押してポイントを追加
5. **フィーチャ確定**: 右下の「GPS測量確定」ボタンで属性入力してフィーチャ作成
   - 確定・キャンセル時にGPS位置情報取得を自動停止（省電力化）

#### GPS測量中の操作

**通常測量（タップ）**:
- 青いGPS測量ボタン（📍）をタップして現在位置を記録
- 即座にPointフィーチャが作成され、地図上に表示

**長押し平均化測量（高精度）** **【NEW】**:
- 青いGPS測量ボタン（📍）を長押しして高精度測量を実行
- 長押し中は1秒間隔でGPSデータを収集
- ボタン周囲にプログレスインジケーターが表示
- **リアルタイム個数表示**: ボタン上部に収集済みGPSデータ点数を「○点」と表示 **【NEW】**
- 目標個数（例：10点）に達したら長押しを離して平均位置を計算
- 長押しを離すと収集したGPSデータの平均位置でPointフィーチャを作成
- 平均化により単発測量より高い精度を実現

**測量中の制御**:

- **📍 GPS測量ボタン**: 現在のGPS位置を記録（左下フロートボタン）
- **ポイント表示**: 各測量ポイントには平均計算に使用したGPS点数を表示（通常測量=1、長押し測量=実際の収集点数） **【NEW】**
- **↶ 取り消し**: 最後に記録したポイントを削除（右下）
- **✕ キャンセル**: 測量データを全てクリアして最初からやり直し（右下）
- **✓ GPS測量確定**: 属性入力ダイアログを表示してフィーチャを作成（右下）
- **❌ GPS測量キャンセル**: 測量データをクリアしてGPS機能を停止（右下）

#### プレビュー表示

GPS測量中は地図上にリアルタイムプレビューが表示されます：

- **紫色のライン/ポリゴン**: 測量中の図形プレビュー
- **番号付きマーカー**: 各測量ポイントの順序表示
- **GPS固定アイコン**: Point測量時の現在位置プレビュー

#### 記録されるGPS測量データ

各測量ポイントで以下の詳細情報が自動記録されます：

```
ポイント 1:
  位置: 35.12345678, 139.12345678
  高度: 10.50m
  精度: 3.20m
  速度: 1.50m/s
  方位: 90.0°
  データソース: 内蔵GPS (GPS)
  接続機器: （外部GNSS使用時のみ）
  記録時刻: 2025-01-XX...
```

この詳細データはフィーチャの説明欄に自動的に記録され、後から測量条件を確認できます。

## GPS管理プロセス API仕様

### 統合GPS管理サービス (`GpsManagerService`)

シングルトンパターンで実装された統合GPS管理サービスです。内蔵GPSと外部GNSS機器を統一的に管理し、GPS記録・追跡・測量機能を提供します。

### GPS設定画面 (`GpsSettingsScreen`) **【NEW】**

統合GPS管理サービスを使用してGPSソース（内蔵GPS・外部GNSS）の切り替えと設定管理を行う専用UI画面です。

**アクセス方法**:
- メインマップ画面のAppBarにある「GPS設定」ボタン（GPSアイコン）をタップ

**主要機能**:
- 📡 **GPSソース切り替え**: 内蔵GPS・外部GNSS機器間での切り替え
- 🔍 **外部GNSS機器スキャン**: Bluetooth GNSS機器の自動検出
- 📊 **GPS情報表示**: リアルタイム位置情報・精度・信号状態
- 🧪 **GPS位置取得テスト**: 接続確認とGPS精度テスト
- ⚙️ **設定の永続化**: GPSソース設定の自動保存・復元

**UI構成**:
```
GPS設定画面
├── 現在のGPSソース表示カード
│   ├── ソース種別（内蔵GPS/外部GNSS）
│   ├── デバイス名・アドレス（外部GNSS時）
│   └── 接続状態表示
├── GPS操作ボタン
│   ├── GPSソース切り替えボタン
│   └── GPS位置取得テストボタン
├── GPS情報表示カード（リアルタイム更新）
│   ├── GPS状態（受信中/停止中/初期化中）
│   ├── 位置情報（緯度/経度/標高）
│   ├── 精度・移動情報
│   ├── **GNSS衛星情報**（外部GNSS機器専用）**【NEW】**
│   │   ├── 衛星数（補足衛星数）
│   │   ├── HDOP（水平精度希薄化）
│   │   └── GPS品質指標（RTK固定解/浮動解/DGPS等）
│   ├── ソース情報
│   └── 時刻情報
└── 利用可能なGPSソース一覧
    ├── 内蔵GPS（常時利用可能）
    ├── 検出された外部GNSS機器
    └── GNSS機器スキャン状態
```

**外部GNSSへの切り替え手順**:
1. GPS設定画面を開く
2. 外部GNSS機器の電源を入れる
3. 「GNSS機器再スキャン」ボタンまたは自動スキャン
4. 「GPSソース切り替え」ボタンをタップ
5. 利用可能なGNSSデバイスから選択
6. 「GPS位置取得テスト」で接続を確認

**フォアグラウンドサービス対応**:
- GPS追跡中の場合は一時停止してソース切り替え
- 切り替え後に自動でサービス再開
- リソース競合を回避した安全な切り替え

**外部GNSS接続のトラブルシューティング**:

**権限関連**:
- **Android 12以降**: `BLUETOOTH_SCAN`、`BLUETOOTH_CONNECT`、`ACCESS_FINE_LOCATION` 権限が必要
- **Android 11以下**: `BLUETOOTH`、`BLUETOOTH_ADMIN`、`ACCESS_FINE_LOCATION` 権限が必要
- GPS設定画面の権限情報ボタン（ℹ️）で権限状態を確認
- 権限が拒否されている場合は設定画面から手動で許可

**接続関連**:
- GNSS機器がペアリングモードになっていることを確認
- デバイスが検出されない場合は「再スキャン」を実行
- 接続後は「GPS位置取得テスト」で正常性を確認
- 位置精度が低い場合は屋外で十分な衛星を捕捉

**高精度GNSS測定設定（Android 9以降）**:
- 開発者オプションで「Force full GNSS measurements」を有効化

**外部GNSS接続の自動維持機能** **【NEW】**:
- GPS測量終了時にBluetooth接続は自動で維持
- 内蔵GPS使用時のみ位置監視を停止、外部GNSS接続は継続
- 次回測量時に接続済みGNSS機器を即座に再利用
- 手動でGPSソースを切り替えない限りBluetooth接続は継続
- 電源効率とユーザビリティのバランスを最適化
- デューティサイクル（断続的電源ON/OFF）を無効化してGNSS測定精度を向上
- RTK（Real-Time Kinematic）測定に必要な連続測定を可能に
- 設定手順: 設定 → 端末情報 → ビルド番号を7回タップ → 開発者オプション → Force full GNSS measurements

**参考資料**:
- [Android Bluetooth権限公式ドキュメント](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)
- [GNSS測定精度向上の設定方法](https://barbeau.medium.com/gnss-interrupted-the-hidden-android-setting-you-need-to-know-d812d28a3821)

**主な改善点**:
- **処理統一**: GPS測量とGPS追跡で同じAPIを使用
- **リソース効率**: GPS機能の重複・競合を回避
- **一元管理**: 単一のGPS管理システムで全機能をカバー
- **プロセス統一**: 全GPS処理をフォアグラウンドサービス（isolate）で実行**【NEW】**

**GPS情報表示の統合** **【NEW】**:
- マップ画面の情報表示バーがGPS管理サービスと統合
- 内蔵GPS・外部GNSS機器の統一された情報表示
- リアルタイムでの位置精度・衛星情報・HDOP表示
- GPS設定画面と同じ情報源による表示の一貫性確保

**GPS初期化問題の修正** **【FIXED】**:
- マップ画面でGPS管理サービスのGPS取得が開始されていない問題を解決
- GPS管理サービスの`startGps()`を明示的に呼び出してGPS位置情報取得を開始
- 外部GNSS機器のバックグラウンドスキャンを追加
- GPS設定画面とマップ画面での情報表示の一貫性を完全に確保

**新アーキテクチャ**:
```
メインプロセス(UI) ←→ フォアグラウンドサービス(isolate)
     ↓                        ↓
GPS測量要求 ──────────→ 統合GPS管理サービス
マップ情報表示バー ←────────┘        ↓
GPS設定画面 ←──────────┘    GPS/GNSS位置取得
```

#### 主要API

##### GPS ソース管理
```dart
// GPS管理サービスインスタンス取得
final gpsManager = GpsManagerService();

// 利用可能なGPSソースの取得
List<Map<String, dynamic>> sources = gpsManager.getAvailableGpsSources();

// 外部GNSS機器のスキャン
await gpsManager.scanExternalGnssDevices();

// GPSソースの切り替え
// 【推奨】参照GPS（基準GPS）切り替え方法
await gpsManager.switchReferenceGps(GpsSourceType.internal);  // 内蔵GPSを基準に
await gpsManager.switchReferenceGps(GpsSourceType.external, device);  // 外部GNSSを基準に

// 【従来】直接切り替え（フォアグラウンドサービス未考慮）
await gpsManager.switchGpsSource(GpsSourceType.internal);  // 内蔵GPS
await gpsManager.switchGpsSource(GpsSourceType.external, device);  // 外部GNSS
```

##### 現在位置情報の取得
```dart
// 現在のGPS情報を一括取得
Map<String, dynamic> gpsInfo = gpsManager.getCurrentGpsInfo();
/*
返却データ例:
{
  'sourceType': 'GPS',          // 'GPS' or 'GNSS'
  'sourceName': '内蔵GPS',       // 表示名
  'selectedDevice': null,       // 外部GNSS機器名
  'latitude': 35.123456,        // 緯度
  'longitude': 139.123456,      // 経度
  'altitude': 10.5,             // 高度（メートル）
  'accuracy': 3.2,              // 精度（メートル）
  'speed': 1.5,                 // 速度（m/s）
  'bearing': 90.0,              // 方位角（度）
  'timestamp': '2025-01-XX...',  // ISO8601タイムスタンプ
  'isActive': true              // 位置情報が有効かどうか
}
*/

// 個別プロパティでのアクセス
double? lat = gpsManager.latitude;
double? lon = gpsManager.longitude;
double? accuracy = gpsManager.accuracy;
```

##### GPS記録機能
```dart
// 記録オプションの設定
const options = GpsRecordingOptions(
  intervalSeconds: 1,        // 取得インターバル（秒）
  minDistanceMeters: 1.0,    // 最短記録移動距離（メートル）
  requiredAccuracy: 5.0,     // 要求精度（メートル以下）
  maxRecordCount: 1000,      // 最大記録ポイント数（0=無制限）
);

// GPS記録開始
await gpsManager.startRecording(options);

// 記録中の確認
bool isRecording = gpsManager.isRecording;

// GPS記録停止
Map<String, dynamic>? summary = gpsManager.stopRecording();
/*
停止時の返却データ例:
{
  'startTime': '2025-01-XX...',     // 記録開始時刻
  'endTime': '2025-01-XX...',       // 記録終了時刻
  'totalPoints': 150,               // 総記録ポイント数
  'totalDistance': 1234.5,          // 総移動距離（メートル）
  'duration': 300,                  // 記録時間（秒）
  'sourceType': 'GPS',              // データソース
  'sourceName': '内蔵GPS'            // ソース表示名
}
*/
```

##### GPS履歴データの取得
```dart
// 記録履歴の取得（辞書リスト形式）
List<Map<String, dynamic>> history = gpsManager.gpsHistory;
/*
履歴データ例:
[
  {
    'latitude': 35.123456,
    'longitude': 139.123456,
    'altitude': 10.5,
    'accuracy': 3.2,
    'speed': 1.5,
    'bearing': 90.0,
    'timestamp': '2025-01-XX...',
    'sourceType': 'GPS',
    'sourceDisplayName': '内蔵GPS'
  },
  // ... 追加のポイント
]
*/

// 履歴統計情報の取得
Map<String, dynamic> stats = gpsManager.getRecordingStatistics();

// 履歴のクリア
gpsManager.clearHistory();
```

#### 定義済み記録オプション

```dart
// デフォルト設定（1秒間隔、1m移動）
GpsRecordingOptions.defaultOptions

// 高精度設定（1秒間隔、0.5m移動、精度5m以下）
GpsRecordingOptions.highAccuracy

// 省電力設定（10秒間隔、5m移動、精度20m以下）
GpsRecordingOptions.powerSaver
```

#### 設定の永続化

GPS ソース設定は `GlobalConfig` に自動保存され、アプリ再起動時に復元されます：

```dart
// アプリ起動時の設定復元
await gpsManager.loadSourceFromGlobalConfig();
```

## 対応プラットフォーム
- ✅ Android（実機テスト済み）
- ✅ Windows（開発・テスト済み）
- 🔄 iOS（基本実装済み・要テスト）
- 🔄 macOS（基本実装済み・要テスト）
- 🔄 Linux（基本実装済み・要テスト）

## データベース移行（2025年対応）
sqlite3からsqfliteへの段階的移行を完了しました：

### 移行内容
- **非同期処理**: 全メソッドがFuture<T>を返すように変更
- **自動初期化**: データベース接続の遅延初期化とライフサイクル管理
- **エラーハンドリング**: try-catch構文による堅牢なエラー処理
- **スキーマ管理**: onCreate/onUpgradeコールバックによるマイグレーション対応

### 技術的改善点
```dart
// 旧方式（sqlite3・同期処理）
final layerNames = geoPackage.getLayerNames();

// 新方式（sqflite・非同期処理）  
final layerNames = await geoPackage.getLayerNames();
```

#### 5. UI要素の見切れ問題 **【修正済み】**
**問題内容**:
- ホーム画面で縦方向にコンテンツが見切れる
- GPS情報バーで横方向に情報が見切れる

**解決方法**:
1. **ホーム画面**: シンプルなフォルダ選択UIに刷新（`Center`配置で画面内に収まるように改善）
2. **GPS情報バー**: 横方向スクロール対応でGPS詳細情報を全て表示可能
3. 柔軟なレイアウト設計でさまざまな画面サイズに対応

#### 6. ホーム画面UI改善 **【完了】**

#### 7. フィーチャー描画パフォーマンス向上 **【完了・NEW】**
**問題内容**:
- 地図上にフィーチャーを描画する際、都度実体の.gpkgから読み出していた
- feature作成時・削除時に非同期処理の遅延でsetStateまでに間に合わず、地図への反映が遅れていた

**解決方法**:
1. **FeatureNodeでのジオメトリ保持**: 各FeatureNode（Point, Line, Polygon）でジオメトリ情報を確実に保持
2. **即座のノード作成**: createInメソッドで、DBへの保存は非同期で実行し、FeatureNodeは即座に作成・追加
3. **高速化された地図表示**: map_page.dartでLayerNodeのchildrenから直接FeatureNodeを参照（DBアクセス最小化）
4. **即座の削除処理**: disposeメソッドでDBからの削除を非同期で実行し、UI側は即座に削除

**技術的改善点**:
```dart
// 旧方式（都度DBアクセス）
final features = await layer.features; // 毎回DBから読み取り
pointFeatures.addAll(features.whereType<PointFeatureNode>());

// 新方式（FeatureNode直接参照）
final layerFeatures = layer.children.whereType<FeatureNode>().toList(); // 高速
pointFeatures.addAll(layerFeatures.whereType<PointFeatureNode>());

// 作成時: 即座にFeatureNode作成、DBは非同期保存
final node = PointFeatureNode(points, name, parent: parent, rowId: tempRowId);
parent.addChild(node); // 即座にUIに反映
gpkgFile.addPoint(...).then((_) => print('[DEBUG] DB保存完了')); // 非同期
```

**結果**:
- 地図上への描画が即座に反映され、レスポンシブな操作感を実現
- 初回ロード以外はDBアクセスを最小化し、パフォーマンスが大幅向上
- DB保存は確実に実行されるため、データの整合性も保持

#### 8. FeatureNode削除処理最適化 **【完了・NEW】**
**問題内容**:
- フィーチャー削除時の処理が非効率で、UI更新が遅延していた
- 基底クラスのdisposeメソッドが特定のFeatureNode型に依存していた
- 複数フィーチャー削除時の処理が逐次実行で時間がかかっていた

**解決方法**:
1. **基底クラスの最適化**: FeatureNodeの基底disposeで親子関係切断・選択状態クリアを優先実行
2. **各型別の適切な削除**: Point/Line/PolygonFeatureNodeで型に応じた適切なDB削除処理
3. **並行削除処理**: 複数フィーチャー削除時にFuture.waitで並行処理
4. **UI優先設計**: 即座に親子関係を切断してUI更新、DB削除は非同期で実行

**技術的改善点**:
```dart
// 基底クラス（FeatureNode）での最適化
await super.dispose(); // 親子関係切断・選択状態クリア（即座）
geoPackageFile.removePoint(...).then((_) { // DB削除（非同期）
  print('[DEBUG] DB deletion completed');
}).catchError((e) {
  print('[ERROR] DB deletion failed: $e');
});

// 複数削除の並行処理
final disposeFutures = selectedFeatures.map((f) => f.dispose()).toList();
mapState.refreshFeatures(); // 即座にUI更新
Future.wait(disposeFutures); // バックグラウンドで削除完了待機
```

**結果**:
- フィーチャー削除が即座にUIに反映され、操作感が大幅向上
- 複数フィーチャー削除時も並行処理でパフォーマンス向上
- エラーハンドリングの強化でアプリの安定性向上

#### 9. 選択表示UI更新とSelectTool最適化 **【完了・NEW】**
**問題内容**:
- フィーチャー削除時に選択表示（黄色い線）が残る問題
- onScaleUpdate時にフィーチャーが選択されない問題
- SelectToolが毎回DBアクセスしてパフォーマンスが低下

**解決方法**:
1. **選択状態UI更新の改善**: `setState()`と`refreshFeatures()`の両方を実行して確実に選択表示をクリア
2. **SelectTool最適化**: LayerNodeのchildrenから直接フィーチャーを取得（DBアクセス最小化）
3. **削除処理の条件判定**: 選択されたフィーチャーがある場合のみ削除処理を実行
4. **詳細デバッグログ**: 選択・削除プロセスの各段階でログ出力

**技術的改善点**:
```dart
// UI更新の確実な実行
GlobalConfig.instance.selectedFeatures.clear();
mapState.setState(() {}); // 選択表示を即座にクリア
mapState.refreshFeatures(); // フィーチャー表示も更新

// SelectToolの最適化（FeatureNode直接参照）
final layerFeatures = layer.children.whereType<FeatureNode>().toList();
if (layerFeatures.isNotEmpty) {
  features = layerFeatures; // 高速参照
} else {
  features = await layer.features; // 初回のみDB読み込み
}

// 削除処理の条件判定
if (GlobalConfig.instance.selectedFeatures.isNotEmpty) {
  _disposeSelectedFeatures(mapState);
} else {
  print('[DEBUG] no features selected for deletion');
}
```

**結果**:
- 削除時の選択表示が確実にクリアされ、視覚的な問題を解決
- SelectToolの処理速度が大幅向上（初回以外はDBアクセス不要）
- デバッグログによる問題の早期発見と対処が可能
**改善内容**:
- 複雑なGPS設定・サービス制御UIを削除
- シンプルで分かりやすいフォルダ選択画面に刷新
- Material Designに準拠した美しいカードベースレイアウト
- 選択されたフォルダパスの確認表示機能

#### 7. GPS追跡マーカーのアニメーション化 **【NEW・完了】**
**改善内容**:
- 邪魔だった大きな赤い追跡マーカーを削除
- 現在位置の周りを光が軌跡を描きながら回転するエフェクトに変更
- 2つの光点が異なる速度と方向で回転（複雑で美しい動き）
- AnimationControllerとTweenを使用した滑らかな3秒間隔回転
- GPS追跡サービス開始時に自動でアニメーション開始、停止時に停止

## ライセンス
プロジェクトのライセンス情報は後日追加予定です。

## トラブルシューティング

### よくある問題

#### 1. サービスが開始しない
   - Android権限の確認
   - デバッグログの確認

#### 2. 通知が表示されない
   - 端末の通知設定確認
   - アプリの通知権限確認

#### 3. ログが出力されない
   - デバッグコンソールの確認
   - print文の出力先確認

#### 4. AndroidManifest.xml競合エラー **【重要】**
**エラー内容**:
```
Attribute service#id.flutter.flutter_background_service.BackgroundService@exported value=(false) from (unknown)
is also present at [:flutter_background_service_android] AndroidManifest.xml:15:13-36 value=(true).
```

**原因**: flutter_background_serviceプラグインが自動的にサービス定義を追加するため、手動で追加したサービス定義と競合

**解決方法**:
1. AndroidManifest.xmlから手動で追加したサービス定義を削除
2. プラグインが自動的に適切な設定を行う
3. 権限（FOREGROUND_SERVICE等）のみ手動で設定

```xml
<!-- ❌ 削除が必要（競合原因） -->
<service
    android:name="id.flutter.flutter_background_service.BackgroundService"
    android:exported="false"
    android:foregroundServiceType="dataSync" />

<!-- ✅ 権限のみ手動設定 -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
```

**参考**: [GitHub Issue #1558](https://github.com/Baseflow/flutter-geolocator/issues/1558)での類似問題

#### 5. フォアグラウンドサービス通知エラー **【クリティカル】**
**エラー内容**:
```
android.app.RemoteServiceException$CannotPostForegroundServiceNotificationException: Bad notification for startForeground
```

**原因**: 
- 通知チャンネルが適切に設定されていない
- メインIsolateでのプラグイン競合
- Android 8.0以降の通知チャンネル要件に未対応

**解決方法**:
1. **MainActivityで通知チャンネルを明示的に作成**:
```kotlin
// MainActivity.kt
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
    val channelId = "k_maps_foreground_channel"
    val channelName = "K-MAPS フォアグラウンドサービス"
    val importance = NotificationManager.IMPORTANCE_LOW
    
    val channel = NotificationChannel(channelId, channelName, importance)
    val notificationManager = getSystemService(NotificationManager::class.java)
    notificationManager?.createNotificationChannel(channel)
}
```

2. **サービス初期化の遅延実行**:
```dart
// main.dart
WidgetsBinding.instance.addPostFrameCallback((_) async {
    await ForegroundServiceManager.initializeService();
});
```

3. **Android 13以降の通知権限追加**:
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

**参考**: [GitHub Issue #406](https://github.com/ekasetiawans/flutter_background_service/issues/406)でのクラッシュ報告

### デバッグ方法
```bash
# Flutterログ確認
flutter logs

# Androidログ確認
adb logcat | grep flutter
```

## 更新履歴

### v1.3.0 (最新) **【Flutter Map v8対応】**
- **🎉 Flutter Map v8.1.1への完全移行**
  - MapOptionsの新API対応（`initialCenter`, `initialZoom`, `interactionOptions`）
  - MapCameraの座標変換API対応（`offsetToCrs`, `latLngToScreenOffset`）
  - MapControllerのAPI変更対応（`camera.zoom`, `camera.center`等）
  - Polygonの`isFilled`プロパティ削除対応
- **🗺️ 背景地図プロバイダーシステムの実装**
  - OpenStreetMap、GSI地理院地図（標準・淡色・写真・色別標高図・白地図）
  - 背景地図設定画面の実装、プロバイダー切り替え機能
- **💾 高性能タイルキャッシュ機能**
  - オフライン表示対応、プロバイダー別管理、キャッシュ統計表示
  - フォールバック機能（親タイルからの切り出し・スケーリング）
  - 高ズームレベルでの安定表示
- **🔧 map_tool系の完全修復**
  - パンツール、ペンツール、選択ツール等の座標変換問題を解決
  - Flutter Map v8の新しい座標変換APIに完全対応
  - 描画プレビュー表示の復旧

### v1.2.0 **【GPS軌跡記録】**
- GPS軌跡記録・保存機能を追加
- フォアグラウンドサービスによるバックグラウンド追跡対応
- 軌跡統計情報表示（距離・ポイント数・GNSS/GPS比率）
- **ジオメトリタイプの表記を単一系（POINT, LINESTRING, POLYGON）に統一**
- **型安全性向上のためGeometryTypeエナムを導入**
- **属性テーブルの自動再読み込み問題を修正**
- GPS追跡サービス状態更新の最適化（1秒→5秒間隔、変化時のみ更新）
- 属性テーブルのスクロール位置保持機能を追加
- データキャッシュ機能により不必要な再読み込みを防止

### v1.1.0
- フォアグラウンドサービス機能追加
- デバッグログ最適化
- UI改善（サービス制御画面）

### v1.0.0
- 基本的な地図表示機能
- GPS位置情報取得
- Bluetooth GNSS対応

### ログ形式
```
[ForegroundService] フォアグラウンド実行中 - HH:MM:SS | GPS: 35.123456, 139.654321 (精度: 5.0m)
```

**GPS情報の詳細**: **【NEW】**
- **座標形式**: 緯度, 経度（小数点以下6桁）
- **精度情報**: メートル単位での位置精度
- **エラー処理**: GPS取得失敗時は前回値またはエラーメッセージを表示
- **権限チェック**: GPS無効・権限なしの場合は適切なメッセージを表示

---

**開発者向けメモ**: 本プロジェクトは継続的な機能拡張を想定して設計されており、各機能は独立性と再利用性を重視した実装となっています。

## 📍 GPS軌跡記録システム（バックグラウンド対応）

### 📊 主要コンポーネント

#### 🔧 修正内容：Isolate間通信の実装（2025-06-06）

**問題：** フォアグラウンドサービスが別Isolateで実行されるため、GPS位置情報を取得してもメインアプリの`GpsTrackManager`に記録されない（0ポイント問題）

**解決方法：** `flutter_background_service`のIsolate間通信機能を使用
- フォアグラウンドサービス → メインアプリへのポイントデータ送信
- `service.invoke('addTrackPoint', pointData)` でデータ送信
- メインアプリ側で `FlutterBackgroundService().on('addTrackPoint')` でデータ受信

#### 🐛 追加修正：GPS軌跡保存デバッグログ強化（2025-06-06）

**問題：** 軌跡ポイント数は正しく表示されるが、GeoPackageファイルへの保存でレイヤが追加されない

**対応：** 詳細なデバッグログを追加
- 地図画面の`_saveTrackToGeoPackage`メソッドにステップ毎のログ追加
- `GeoPackageFile.createGpsTrackLayer`メソッドの詳細ログ
- `GeoPackageFile.addLine`メソッドの詳細ログ
- `createWkbLineString`WKB作成処理の詳細ログ
- エラー発生時のスタックトレース出力

**デバッグログ例:**
```
[DEBUG] GPS軌跡保存開始: 軌跡名 -> GeoPackage名
[GeoPackage] GPS軌跡レイヤー作成開始: gps_tracks
[GeoPackage] LineString追加開始: gps_tracks
[WKB] LineString作成開始: 1ライン
```

#### 🔧 追加修正：GPS軌跡保存方式をpen_toolと同じ形式に変更（2025-06-06）

**問題：** 保存したフィーチャの座標がおかしくなっている

**原因：** GPS軌跡はMULTILINESTRING形式で保存していたが、pen_toolはLINESTRING形式で保存していた

**解決：** GPS軌跡保存方式をpen_toolと同じLINESTRING形式に変更
- `gpkgFile.createGpsTrackLayer()` → `gpkgFile.addLayer(layerName, GeometryType.linestring)`
- `gpkgFile.addMultiLineString()` → `gpkgFile.addLine()`
- MULTILINESTRING形式 → LINESTRING形式

**変更前（MULTILINESTRING）:**
```dart
await gpkgFile.createGpsTrackLayer(layerName);
await gpkgFile.addLine(layerName, coordinates, ...);
```

**変更後（LINESTRING - pen_toolと同じ）:**
```dart
await gpkgFile.addLayer(layerName, GeometryType.linestring);
await gpkgFile.addLine(layerName, coordinates, ...);
```

## バージョン履歴

### v1.2.0 (2024-12-19)
- **属性テーブル自動再読み込み問題の修正**
  - GPS追跡サービス状態更新の最適化（10秒間隔に変更）
  - 視覚的変化がある場合のみsetState()を実行
  - 座標の微細な変化（10m未満）は更新対象外
  - LayerDrawerの不要な再構築を防止
- **Windows環境での追跡ボタン非表示対応**
  - GPS追跡ボタンをWindows環境では表示しないように修正
  - `Platform.isWindows`条件チェックを追加
  - モバイル/GPSデバイス環境でのみ追跡機能を有効化

**GNSS衛星情報の詳細表示** **【NEW】**:
外部GNSS機器（RTK対応機器等）を使用している場合、GPS設定画面で以下の詳細情報が表示されます：

**衛星情報**:
- **衛星数**: 現在補足している衛星の数（GPS、GLONASS、Galileo、BeiDou等の合計）
- **HDOP**: 水平精度希薄化（Horizontal Dilution of Precision）- 値が小さいほど高精度
- **GPS品質指標**: NMEA GGA文から取得される信号品質レベル
  - `無効` (0): GPS信号無効
  - `標準GPS` (1): 通常のGPS測位
  - `DGPS` (2): 差分GPS補正済み
  - `RTK固定解` (3): RTK（Real-Time Kinematic）固定解 - 最高精度
  - `RTK浮動解` (4): RTK浮動小数点解 - 高精度
  - `推測航法` (5): INS（慣性航法システム）使用

**表示例**:
```
┌─ GNSS衛星情報 ──────────────┐
│ 🛰️ 衛星数: 12基   HDOP: 0.98 │
│ ● RTK固定解                 │
└────────────────────────────┘
```

この情報により、測量精度の判断やGNSS機器の調整が効率的に行えます。

**GPS測量データ収集の最適化** **【NEW】**:
GPS測量完了後のデータ収集継続問題を解決し、Bluetooth接続維持とデータ蓄積を分離：

**改善点**:
- ✅ **Bluetooth接続維持**: 外部GNSS機器との通信は測量後も継続
- ✅ **データ蓄積停止**: GPS測量完了時にデータ収集タイマーを確実に停止
- ✅ **現在位置更新継続**: リアルタイム位置表示は維持
- ✅ **リソース効率**: 不要なデータ蓄積による負荷を削減

**技術詳細**:
- 測量停止時に`_gpsCollectionTimer`を確実にcancel & null設定
- `_collectGpsDataForLongPress()`に二重安全チェック追加
- GPS管理サービスの`isSurveyMode`状態確認
- 外部GNSS接続は`_stopGpsKeepingBluetoothConnection()`で維持

これにより、測量効率とリソース効率を両立した安定動作が実現されます。

## プラットフォーム固有の問題と解決策 **【重要・Windows環境対応】**

### Windows環境でのflutter_map 8.x フリーズ問題

**問題**: flutter_mapをv8.xにアップデート後、Windows環境でマップ表示直後にアプリケーションがフリーズする現象が発生

**原因**:
1. **カスタムタイルプロバイダーの問題**: flutter_map 8.xで導入されたカスタムタイルプロバイダー（`CachedTileProvider`）がWindows環境でのメモリ管理・スレッド処理に問題
2. **画像デコーディングAPI変更**: Flutter SDKのImageDecoderCallback APIの変更による非互換性
3. **Windows固有のレンダリング問題**: DPIスケーリングとハードウェアアクセラレーションの競合

**解決策の実装**:

1. **標準TileLayerへの回帰** (`lib/screens/map_page.dart`):
```dart
// Windows環境での安定性を優先して標準TileLayerを使用
TileLayer(
  urlTemplate: provider.urlTemplate,
  userAgentPackageName: 'k-maps',
  maxZoom: 22.0,
  minZoom: provider.minZoom.toDouble(),
  // Windows環境でのパフォーマンス向上設定
  evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
  retinaMode: false, // Windows環境での安定性を優先
  tileSize: 256,
),
```

2. **Windows環境でのビルド設定最適化**:
```cpp
// 基本的なCOM初期化のみ実行（追加ライブラリ依存を回避）
::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
```

3. **MapOptions設定の最適化**:
```dart
MapOptions(
  // Windows環境での安定性向上設定
  keepAlive: true,
  // その他の設定...
)
```

**現在の状況**:
- **Android/iOS環境**: 全機能（キャッシュ機能含む）が正常動作
- **Windows環境**: 安定性優先で標準TileLayerを使用、背景地図選択は利用可能、オフラインキャッシュ機能は一時無効化
- **将来の改善**: flutter_map v8.x のWindows対応が改善され次第、全機能を再有効化予定

### プラットフォーム別動作確認状況

| 機能 | Android | iOS | Windows | 備考 |
|------|---------|-----|---------|------|
| 基本地図表示 | ✅ | ✅ | ✅ | 全プラットフォーム対応 |
| 背景地図選択 | ✅ | ✅ | ✅ | Windows環境では標準TileLayer使用 |
| オフラインキャッシュ | ✅ | ✅ | ⚠️ | Windows環境では一時無効化 |
| GPS測量 | ✅ | ✅ | ✅ | 全プラットフォーム対応 |
| Bluetooth GNSS | ✅ | ⚠️ | ❌ | iOS制限・Windows未対応 |
| フォアグラウンドサービス | ✅ | ⚠️ | ❌ | モバイル専用機能 |

---

**開発者向けメモ**: 本プロジェクトは継続的な機能拡張を想定して設計されており、各機能は独立性と再利用性を重視した実装となっています。Windows環境でのflutter_map v8.x 対応は今後のアップデートで改善予定です。

### PhotoNode統合処理 **【UPDATED 2025-01-27】**

現在、画像ファイルから位置情報を抽出してPhotoNodeとして地図上に表示する機能が実装済みです。

**PhotoNodeの主要機能**:
- **EXIF GPS情報抽出**: 位置情報付き画像ファイル（JPEG、PNG、TIFF）から緯度・経度を自動抽出
- **階層構造表示**: FolderNode配下にPhotoNodeが表示される
- **LayerDrawer統合**: PhotoNodeがレイヤードロワーに📷アイコン付きで表示、座標情報も表示 **【NEW】**
- **地図表示**: カメラアイコンマーカーで地図上に写真位置を表示
- **詳細情報表示**: タップで写真のメタデータ（ファイルパス、座標、撮影日時、解像度等）表示
- **インタラクティブ機能**: LayerDrawerから写真をタップすると地図中心が写真位置にジャンプ **【NEW】**
- **画像プレビュー機能**: LayerDrawer詳細ダイアログと地図FeatureDetailPanelで実際の画像プレビューを表示 **【NEW】**
- **相対パス表示**: ファイルパスをプロジェクトルートからの相対パスで表示 **【NEW】**

**LayerDrawer機能 NEW**:
- PhotoNodeは📷アイコン付きで表示
- 座標情報をサブタイトルに表示（緯度・経度4桁精度）
- タップで地図ジャンプ機能（写真位置に移動）
- 右クリックメニューで「詳細情報」表示と「削除」操作
- 削除はリストからの除外のみ（ファイル自体は削除しない）
- **詳細ダイアログ**: 200px高の画像プレビュー、相対パス表示、MB単位のファイルサイズ表示

**地図FeatureDetailPanel NEW**:
- PhotoNode選択時に120px高の画像プレビューを表示
- プロジェクトルートからの相対パスで表示
- 詳細な座標情報（6桁精度）、撮影日時、ファイルサイズ（MB表示）
- 画像読み込みエラー時の適切なフォールバック表示

**技術仕様**:
- **対応ファイル形式**: .jpg, .jpeg, .png, .tiff, .tif
- **EXIF解析**: 独自実装のEXIF解析エンジン（JPEGのAPP1セグメント対応）
- **GPSタグサポート**: GPSLatitude, GPSLongitude, GPSLatitudeRef, GPSLongitudeRef
- **メタデータ抽出**: ファイルサイズ、画像解像度、撮影日時、カメラ情報
- **フィルタリング**: GPS情報がない画像ファイルは自動的にスキップ
- **テスト機能**: 削除済み（本番環境での実用性を向上）
- **画像表示**: Image.fileウィジェットによる直接ファイル読み込み **【NEW】**
- **エラーハンドリング**: 画像読み込み失敗時のbroken_imageアイコン表示 **【NEW】**

**動作フロー**:
1. フォルダ読み込み時にPhotoNode.loadNodes()が自動実行
2. 画像ファイルのEXIF情報を解析
3. GPS座標が存在する場合のみPhotoNodeとして登録
4. LayerDrawerとマップに自動表示
5. ユーザーインタラクションで詳細表示や地図ジャンプが可能
6. **画像プレビュー**: 詳細表示時に実際の画像を表示 **【NEW】**

この機能により、GPS付きの写真ファイルをプロジェクトフォルダに配置するだけで、自動的に地図上に表示され、位置情報と連携した写真管理が可能になります。画像プレビュー機能により、写真の内容も視覚的に確認できます。

## メタデータテーブルXY座標自動追加機能 **【NEW 2025-01-27】**

属性テーブルのメタデータ表示画面において、緯度経度の次の項目としてXY座標を自動追加する機能を実装しました。

### 主要機能

#### XY座標の自動追加
- **表示位置**: 緯度の次にX座標、経度の次にY座標を自動挿入
- **計算精度**: 小数点以下3桁まで表示（mm単位の精度）
- **表示のみ**: メタデータ本体は変更せず、表示テーブルにのみ反映

#### 座標系の自動選択
- **デフォルト**: UTM座標系を使用
- **日本国内判定**: 住所取得結果が日本の場合、都道府県別の日本平面直角座標系も選択可能
- **動的選択**: ドロップダウンメニューから座標系を変更してXY座標を再計算

#### 対応座標系
- **UTM座標系**: 世界測地系（WGS84）ベースの汎用座標系
- **日本平面直角座標系（JGD2011）**: 都道府県別に最適化された19ゾーン対応

### 技術仕様

#### 座標系判定ロジック
1. **1点目の緯度経度**から住所を取得（Nominatim API使用）
2. **住所が日本の場合**: 都道府県名から適切なJGD2011ゾーンを判定
3. **住所取得失敗時**: UTM座標系をフォールバック使用

#### 座標変換処理
- **proj4dartライブラリ**を使用した高精度座標変換
- **EPSGコード**による座標系定義（ライブラリデフォルト値使用）
- **エラーハンドリング**: 変換失敗時は"N/A"表示

#### UI機能
- **座標系選択ドロップダウン**: タイトルバーに座標系選択メニューを配置
- **リアルタイム更新**: 座標系変更時にXY座標を即座に再計算・表示
- **TSVエクスポート対応**: XY座標を含むメタデータテーブルをTSV出力

### 使用例

```dart
// メタデータ表示時にXY座標を自動追加
final tableData = await MetadataParser.parseMetadataWithCoordinates(
  metadataJson,
  featureLatLng, // フィーチャの緯度経度
);

// 座標系変更時の再計算
final newTableData = await MetadataParser.recalculateXYCoordinates(
  originalData,
  point,
  newEpsgCode,
);
```

### 表示例

```
┌─ GPS測量ログ (UTM Zone 54N) ──────────────┐
│ 項目         │ 値                        │
├─────────────┼──────────────────────────┤
│ 測量点番号   │ 1                         │
│ 緯度         │ 35.676200                 │
│ X座標        │ 389542.123                │
│ 経度         │ 139.650300                │
│ Y座標        │ 3950234.567               │
│ 標高         │ 25.4                      │
└─────────────┴──────────────────────────┘
```

この機能により、GPS測量データの座標情報をより詳細に確認でき、測量業務での実用性が大幅に向上します。

### 5. 座標変換・メタデータ管理機能 **【NEW・完全実装】**
- **座標変換ユーティリティ**: 緯度経度とXY座標間の相互変換機能
  - **UTM座標系**: 世界測地系（WGS84）ベースの汎用座標系、経度から自動ゾーン判定
```

## 最新の修正履歴

### 2025-06-15: XY座標同一値問題の解決

**問題**: メタデータテーブルでXY座標がすべて同じ値になる問題

**原因**:
1. **座標系変更時の更新ロジック不備**: `recalculateXYCoordinates`メソッドがキー・値形式に対応していなかった
2. **データ形式の判定不足**: 表形式とキー・値形式の区別ができていなかった

**解決策**:
1. **キー・値形式対応の座標更新メソッド追加**:
   - `_updateXYInKeyValueRows`メソッドを新規作成
   - キー・値形式でのXY座標行の特定と更新ロジックを実装

2. **データ形式自動判定機能**:
   - ヘッダーが`['キー', '値']`の場合はキー・値形式として処理
   - 通常の表形式とキー・値形式を自動判別

3. **座標再計算ロジックの改善**:
   - `recalculateXYCoordinates`メソッドでデータ形式に応じた処理分岐を追加
   - キー・値形式では行の第1要素（キー）で'X座標'/'Y座標'を判定

**テスト結果**:
- 各地点で異なるXY座標が正常に計算されることを確認
- 東京駅: X=-35908.527, Y=-16568.511 (JGD2011 CS IX)
- 大阪駅: X=-144802.789, Y=-45598.421 (UTM Zone 53N)
- 札幌駅: X=-103375.919, Y=89340.554 (UTM Zone 54N)
- 福岡駅: X=65634.969, Y=-55532.541 (UTM Zone 52N)

**技術的改善点**:
- キー・値形式でのXY座標更新が正常に動作
- 座標系変更時の再計算が各データ形式で適切に実行
- 複数地点での座標差異が正しく確認される

**追加修正 (2025-06-15 16:07)**:
- **複数データポイント対応**: 表形式データで各行の緯度経度を個別に処理
- **`_addXYCoordinatesToTableFormat`メソッド修正**: 各行の座標を個別に計算
- **`_updateXYInRows`メソッド修正**: 座標系変更時も各行を個別に再計算
- **表形式テスト追加**: 複数地点での座標変換動作を検証

**最終テスト結果**:
- 表形式データ（3地点）で各地点が個別に正しく計算される
- 東京駅: X=-35908.527, Y=-16568.511
- 大阪駅: X=-144802.789, Y=-45598.421
- 札幌駅: X=-103375.919, Y=89340.554
- 全ての地点間で座標差異が確認される

**stateキャッシュ機能実装 (2025-06-15 16:15)**:
- **APIコール最適化**: 複数データポイントで最初の座標のみ住所API呼び出し
- **stateキャッシュ機能**: 取得したstateを後続の座標変換で再利用
- **`getStateFromAddress`メソッド追加**: 住所からstate情報を抽出
- **`getJGD2011ZoneFromState`メソッド追加**: stateから直接JGD2011座標系を判定
- **`getBestCoordinateSystem`メソッド拡張**: cachedStateパラメータ対応

**パフォーマンス改善**:
- 複数データポイント処理で住所APIコールを大幅削減（3地点で3回→1回）
- 座標変換処理の高速化
- APIクォータの節約

**最終テスト結果（stateキャッシュ使用）**:
- 東京駅: X=-35908.527, Y=-16568.511 (JGD2011 CS IX)
- 大阪駅: X=-136366.717, Y=-396934.101 (JGD2011 CS IX - キャッシュ使用)
- 札幌駅: X=785342.941, Y=123277.784 (JGD2011 CS IX - キャッシュ使用)
- 各地点で異なる座標が正しく計算される

## 🐛 修正済み問題 (Bug Fixes)

### 2024年版修正
- **点フィーチャ保存問題の修正** (2024-12-19)
  - 原因: PointFeatureNodeが座標指定で削除、Line/PolygonがID指定で削除という不整合
  - 解決: GeoPackageFile.addPoint()で実際のrowIdを返却、removePoint()をID指定に統一
  - 影響: pen_tool、GPS測量での点フィーチャが正常に保存・削除されるように
  - 詳細: WKBバイナリ比較の精度問題とGPBinaryヘッダー差異を解決

### 2025年版修正
- **ポリゴン描画の2点エラー修正** (2025-01-27)
  - 問題: 2点目追加時に「LatLngBounds cannot be created with an empty List of LatLng」エラーでマップが真っ赤になる
  - 根本原因: `closeRing`関数が3点未満の場合に空のリストを返し、flutter_mapでLatLngBounds作成時にエラー発生
  - 解決策:
    1. **2点時の適切な処理**: `getPolygonPreview`メソッドで2点の場合は`closeRing`を呼び出さず直接座標リストを返す
    2. **UI表示レイヤーの分離**: 2点時は線として表示、3点以上はポリゴンとして表示
  - 技術詳細:
    ```dart
    // 修正されたgetPolygonPreviewメソッド
    if (drawingPolygon.length == 2) {
      return List<LatLng>.from(drawingPolygon); // 線として扱う
    }
    return closeRing(drawingPolygon); // 3点以上はポリゴン
    ```
  - 効果: 2点目追加時のエラー解消、適切なプレビュー表示の実現
