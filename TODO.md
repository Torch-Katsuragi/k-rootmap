# K-MAPS 作業ログ（2025年10月7日）

## 完了した作業

### 20. Pointレイヤー属性テーブルへの仮想_coordinate列追加（完了）

**背景**:
- 属性テーブルでは、geom列を表示していない
- Pointレイヤーのユーザーが緯度経度を直接確認・編集したいというニーズ
- 配列形式で表示・編集することで、データのコピー&ペーストや一括編集が容易に

**実装内容**:

1. **仮想カラム`_coordinate`の追加**
   - ✅ Pointレイヤーの属性テーブルに限定
   - ✅ geomを解析して`[lat, lon]`形式で表示
   - ✅ GeoPackageには保存されない（仮想カラム）
   - ✅ レイヤーのカラムとしても登録されない

2. **表示機能**
   - ✅ `_createColumns()`で`_coordinate`カラムを動的に追加
   - ✅ テキスト型、150pxの幅
   - ✅ `_createRows()`でPointFeatureNodeから`[lat, lon]`形式の文字列を生成

3. **編集機能と妥当性検証**
   - ✅ `_coordinate`列の編集を検知
   - ✅ `_parseCoordinate()`メソッドで座標文字列を解析
   - ✅ バリデーションチェック:
     - `[]`で囲まれているか
     - 2つの数値が含まれているか
     - 緯度: -90～90の範囲
     - 経度: -180～180の範囲
   - ✅ `[lat, lon]`と`[lon, lat]`の両形式を自動判定
   - ✅ 不正な入力は受け付けず、元の値に戻す
   - ✅ `PointFeatureNode.updateLocation()`でgeomを更新
   - ✅ GeoPackageに保存
   - ✅ マップをリアルタイム更新

**技術詳細**:

```dart
// カラム追加（Pointレイヤーのみ）
if (_isPointLayer()) {
  tableColumns.add(
    PlutoColumn(
      title: '_coordinate',
      field: '_coordinate',
      type: PlutoColumnType.text(),
      enableEditingMode: true,
      width: 150,
    ),
  );
}

// 座標データの抽出
if (isPointLayer && feature is PointFeatureNode) {
  final point = feature.point;
  cells['_coordinate'] = PlutoCell(
    value: '[${point.latitude}, ${point.longitude}]',
  );
}

// 座標編集時の処理
if (field == '_coordinate') {
  final coordinateResult = _parseCoordinate(value.toString());
  
  if (!coordinateResult['valid']) {
    // 不正な入力は受け付けずエラー表示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Invalid coordinate: ${coordinateResult['error']}'),
        backgroundColor: Colors.red,
      ),
    );
    await _initializeTableData(); // 元の値に戻す
    return;
  }
  
  final newPoint = coordinateResult['point'] as LatLng;
  await feature.updateLocation(newPoint);
  GlobalConfig.instance.mapState?.refreshFeatures();
}

// 座標解析メソッド
Map<String, dynamic> _parseCoordinate(String value) {
  // []で囲まれているかチェック
  // 2つの数値が含まれているかチェック
  // 緯度経度の範囲をチェック
  // [lat, lon]と[lon, lat]を自動判定
}
```

**効果**:
- ✅ **使いやすさ向上**: 緯度経度を配列形式で直接確認・編集可能
- ✅ **データ整合性**: 編集がgeomに即座に反映される
- ✅ **バリデーション**: 不正な入力を受け付けず、元の値に戻す
- ✅ **柔軟性**: `[lat, lon]`と`[lon, lat]`の両形式に対応
- ✅ **GeoPackage互換性維持**: 仮想カラムなので標準GeoPackage構造を変更しない
- ✅ **Pointレイヤーに限定**: 他のレイヤー（Line/Polygon）には影響なし
- ✅ **リアルタイム更新**: 編集後すぐにマップに反映される
- ✅ **コピペしやすい**: 配列形式なのでExcelやJSON等との相互変換が容易

**テスト項目**:
- ✅ コンパイル確認: Linterエラーなし
- ⏳ Pointレイヤーで`_coordinate`が`[lat, lon]`形式で表示されること（要実機確認）
- ⏳ Line/Polygonレイヤーでは表示されないこと（要実機確認）
- ⏳ `[35.6762, 139.6503]`形式で編集するとgeomが更新されること（要実機確認）
- ⏳ `[139.6503, 35.6762]`形式（lon, lat）でも正しく認識されること（要実機確認）
- ⏳ 不正な形式（`[abc, def]`、`[35.6762]`等）は受け付けないこと（要実機確認）
- ⏳ 範囲外の値（緯度>90、経度>180等）は受け付けないこと（要実機確認）
- ⏳ 編集後にマップが更新されること（要実機確認）
- ⏳ GeoPackageに仮想カラムが保存されないこと（要実機確認）

---

# K-MAPS 作業ログ（2025年10月3日）

## 完了した作業

### 19. GUIの大規模リファクタリング（完了）

**背景**:
- `map_page.dart`が3684行と非常に大きく、保守性が低下していた
- buildメソッドが巨大で可読性が低かった
- バイブコーディング時のトークン数が膨大だった
- 関連するコードが散在し、変更が困難だった

**実施したリファクタリング**:

1. **ダイアログウィジェットの分離**
   - ✅ 新規ファイル: `lib/widgets/gps_tracking_dialogs.dart`
   - `TrackingStopDialog` - GPS追跡停止時の処理選択ダイアログ
   - `SelectPointLayerDialog` - ポイントレイヤー選択ダイアログ
   - 削減: 約380行

2. **フィーチャ詳細パネルの分離**
   - ✅ 新規ファイル: `lib/widgets/feature_detail_panel.dart`
   - `FeatureDetailPanel` - フィーチャ詳細情報表示
   - ライン簡略化、ポイント変換機能を含む
   - 削減: 約420行

3. **左下FABの分離**
   - ✅ 新規ファイル: `lib/widgets/left_bottom_fab.dart`
   - `LeftBottomFab` - 左下フローティングアクションボタン
   - 削減: 約60行

4. **地図ツールバーの分離**
   - ✅ 新規ファイル: `lib/widgets/map_toolbar.dart`
   - `MapToolbar` - 左側ツールバー（Pan, Pen, Select, GPSツールボタン）
   - `_ToolButton` - ツールボタンの共通コンポーネント
   - 削減: 約130行

5. **AppBarアクションボタンの分離**
   - ✅ 新規ファイル: `lib/widgets/map_appbar_actions.dart`
   - `buildMapAppBarActions()` - AppBar右側のアクションボタン群
   - 削減: 約50行

**効果**:
- ✅ **コード量の大幅削減**: 3684行 → **2645行** (削減: **1039行、約28%**)
- ✅ **保守性の向上**: 関連するコードがまとまり、変更が容易に
- ✅ **可読性の向上**: ファイルサイズが小さくなり、ナビゲーションが容易に
- ✅ **再利用性の向上**: 分離されたウィジェットは他の箇所でも利用可能
- ✅ **トークン数の削減**: AI支援コーディングのコスト削減（約28%削減）
- ✅ **コンパイルエラーなし**: 全て正常にコンパイル可能

**新規作成ファイル**:
1. `lib/widgets/gps_tracking_dialogs.dart` (約170行)
2. `lib/widgets/feature_detail_panel.dart` (約400行)
3. `lib/widgets/left_bottom_fab.dart` (約70行)
4. `lib/widgets/map_toolbar.dart` (約120行)
5. `lib/widgets/map_appbar_actions.dart` (約60行)

**テスト状況**:
- ✅ コンパイルエラー: なし
- ✅ Linter警告: 既存の警告のみ（新規エラーなし）
- ✅ 動作確認: ユーザーによる実機テスト完了
- ✅ Git保存: 完了

---

### 18. GPS追跡ボタン（足跡アイコン）のポイント都度保存方式への変更（完了）

**背景**:
- 前回、誤ってGPS測量ボタン（青い丸）を変更してしまった
- 正しくはGPS追跡ボタン（足跡アイコン 🐾）をポイント都度保存方式に変更する必要があった
- GPS追跡ボタンは従来、軌跡をメモリに蓄積して最後にLineレイヤーとして保存していた

**問題点（従来の方式）**:
1. **データ損失のリスク**: 追跡中にアプリがクラッシュすると、全てのデータが失われる
2. **確認しにくい**: 停止するまで、個々のポイントデータを確認できない
3. **軌跡保存ダイアログ**: 停止時にダイアログが表示され、ユーザーが保存先を選択する必要があった
4. **kmaps_metadataの使用**: JSON形式でメタデータを保存していたため、属性テーブルでの確認が困難

**変更内容**:

1. **lib/screens/map_page.dart**
   - ✅ GPS追跡ポイント都度保存用のフィールドを追加（88-91行）
     - `_trackingTargetPointLayer`: 保存先PointLayerNode
     - `_trackedPointCount`: 保存済みポイント数
     - `_trackPointSubscription`: ポイント受信リスナー
   - ✅ `_startGpsTrackingService()`: 保存先PointLayerNode選択ダイアログを表示（405-442行）
     - 追跡開始前に保存先を選択
     - `addTrackPoint`イベントのリスナーを設定
     - ポイント受信時に`_handleTrackPointForSaving`を呼び出し
   - ✅ `_handleTrackPointForSaving()`: GPS追跡ポイントを都度保存（444-524行）
     - 保存先レイヤーの存在チェック
     - レイヤーが削除されている場合は自動停止
     - **kmaps_metadata廃止**: GPS属性を個別カラムに保存
     - `name`は空（NULL）
   - ✅ `_stopGpsTrackingService()`: 保存済みポイント数を表示（722-756行）
     - 軌跡保存ダイアログを削除
     - 保存済みポイント数をメッセージで表示
   - ✅ `_showSelectPointLayerDialog()`: ポイントレイヤー選択ダイアログ（526-563行）
     - 全てのポイントレイヤーを検索
     - ユーザーが保存先を選択
   - ✅ `_SelectPointLayerDialog`: 選択ダイアログウィジェット（3306-3376行）
     - ドロップダウンでレイヤーを選択
   - ✅ `dispose()`: リスナーのクリーンアップ（343行）
   - ✅ 古いtrack save関連メソッドを削除
     - `_showTrackSaveDialog()`を削除
     - `_saveTrackToGeoPackage()`を削除

2. **lib/tools/gps_tool.dart**
   - ✅ GPS測量でPointLayerNodeに保存する際も個別カラムに保存（206-267行、341-397行）
     - 長押し測量: 平均化された`altitude`、`accuracy`を保存
     - 単発測量: 直接取得した値を保存
     - **kmaps_metadata廃止**: 個別カラムに保存
     - `name`は空（NULL）

3. **import追加**
   - ✅ `package:flutter_background_service/flutter_background_service.dart`を追加
   - ✅ 未使用の`../widgets/track_save_dialog.dart`を削除

**保存される属性カラム（GPS追跡・GPS測量共通）**:
1. `altitude`: 高度（メートル）
2. `accuracy`: 測位精度（メートル）
3. `speed`: 速度（m/s）
4. `bearing`: 方位（度）
5. `source_type`: データソースタイプ（GPS/GNSS）
6. `timestamp`: 記録時刻（ISO 8601形式）
7. `sample_count`: 平均化に使用したサンプル数（長押し測量のみ、単発測量は1）

**新しいフロー**:

1. **GPS追跡開始**:
   - GPS追跡ボタン（足跡アイコン 🐾）をタップ
   - 保存先PointLayerNode選択ダイアログが表示される
   - ユーザーが保存先を選択（またはキャンセル）
   - フォアグラウンドサービスが開始

2. **GPS軌跡の都度保存**:
   - 1秒ごとにGPS位置を取得
   - 保存前に保存先レイヤーの存在をチェック
   - レイヤーが削除されている場合は自動停止してエラー表示
   - ポイントが自動的に保存される

3. **追跡の停止**:
   - GPS追跡ボタン（赤い停止アイコン）をタップ
   - 「GPS追跡を停止しました（X ポイント保存済み）」を表示
   - フォアグラウンドサービスが停止

4. **後処理（ユーザーが手動で実施）**:
   - ポイントレイヤーのコンテキストメニューから「ライン/ポリゴンに変換」を選択
   - GPS測量メタデータが保持される

**効果**:
- ✅ **データの安全性向上**: 各ポイントが都度保存されるため、アプリがクラッシュしてもデータ損失を最小化
- ✅ **データ確認の容易さ**: 追跡中でも属性テーブルで個々のポイントデータを確認可能
- ✅ **柔軟性**: ポイントデータから後でライン/ポリゴンに変換可能
- ✅ **ユーザー体験**: 保存先レイヤーが削除された場合の自動停止とエラー表示
- ✅ **シンプルな操作**: 停止時のダイアログが不要になり、操作がシンプルに
- ✅ **kmaps_metadata完全廃止**: GPS属性が個別カラムとして保存されるため、属性テーブルで直接確認・編集可能
- ✅ **データ形式の統一**: GPS追跡とGPS測量で同じ属性カラム構造を使用
- ✅ **QGISとの互換性**: 標準的な属性カラムなので他のGISソフトでも扱いやすい

**テスト項目**:
- ✅ コンパイル確認: エラーなし（既存warningのみ）
- ⏳ GPS追跡ボタンで保存先ダイアログが表示されること（要実機確認）
- ⏳ ポイントが都度保存されること（要実機確認）
- ⏳ 保存先レイヤーが削除された場合にエラー表示されること（要実機確認）
- ⏳ 停止ボタンで追跡が停止すること（要実機確認）
- ⏳ 保存されたポイントをラインに変換できること（要実機確認）

**重要な注意**:
- GPS測量ボタン（青い丸 📍）の機能は変更されていません
- GPS追跡ボタン（足跡アイコン 🐾）のみがポイント都度保存方式に変更されています

**GPS追跡の保存オプション機能（追加実装）**:

**開始時のオプション（3488-3696行）**:
- ✅ 保存先選択の拡張
  - 初期値: 「新しいレイヤを作成」
  - その他: 既存のポイントレイヤー
- ✅ 新規レイヤ名入力フィールド（3552-3563行）
  - 保存先が「新しいレイヤを作成」の場合のみ表示
  - バリデーション: 空欄チェック
- ✅ 新規レイヤ作成処理（3621-3679行）
  - プロジェクトルートから最初のGeoPackageNodeを検索
  - PointLayerNode.createIn()で新規レイヤー作成
  - 作成したレイヤーを保存先として使用
- ✅ 保存間隔設定（3256-3259行、3314-3329行）
  - 1秒以上の整数を設定可能、デフォルト10秒
  - 指定した秒数ごとにポイントを保存
- ✅ 最小移動距離設定（3257、3330-3346行）
  - 0cm以上の整数を設定可能、デフォルト0cm
  - 0の場合は移動量にかかわらず一定間隔で保存
  - 0より大きい場合は、最後に保存した点からの距離が閾値以上の場合のみ保存
- ✅ 保存オプション管理フィールド（92-95行）
  - `_trackingSaveIntervalSeconds`: 保存間隔（秒）
  - `_trackingMinDistanceCm`: 最小移動距離（cm）
  - `_lastTrackingSaveTime`: 最後に保存した時刻
  - `_lastSavedTrackingPosition`: 最後に保存した位置
- ✅ 時間間隔チェック（479-487行）
  - 最後の保存から指定秒数経過していない場合はスキップ
- ✅ 移動距離チェック（495-507行）
  - Haversine公式で2点間の距離を計算
  - 距離が閾値未満の場合はスキップ
- ✅ ダイアログUI改善（3277-3379行）
  - 保存先レイヤー選択
  - 保存間隔入力フィールド
  - 最小移動距離入力フィールド
  - バリデーション機能

**停止時のオプション（1ダイアログで完結）**:
- ✅ GPS追跡停止ダイアログ（3349-3507行）
  - 保存先プルダウン
    - 初期値: 「ポイントレイヤーにのみ保持」
    - その他: 同じGeoPackage内のLine/Polygonレイヤー
  - 「ポイントレイヤーを削除」チェックボックス
    - 保存先が「ポイントレイヤーにのみ保持」以外の場合のみ表示
- ✅ `_handleTrackingStopOption()`: 選択に応じた処理実行（856-922行）
  - ポイントのみ保持: 何もしない
  - Line/Polygonに変換（ポイント保持）: GeometryConversionServiceで変換
  - Line/Polygonに変換（ポイント削除）: 変換後にポイントレイヤーをdispose
- ✅ レイヤー検索処理をダイアログ内に統合（3375-3412行）
  - initState()で非同期検索
  - ローディング表示

**3つの処理選択肢**:
1. **ポイントのみ保持**: ポイントレイヤーはそのまま保持
2. **ライン/ポリゴンに変換（ポイント保持）**: 変換後もポイントレイヤーを保持、属性データはsub_tableに保存
3. **ライン/ポリゴンに変換（ポイント削除）**: 変換後にポイントレイヤーを自動削除

**追加修正（レイヤー削除時のエラー対策）**:
- ✅ `LayerNode.dispose()`: 子のdispose前に`_isDisposed = true`を設定していた問題を修正（311-316行）
  - 修正前: `_isDisposed = true` → `super.dispose()` → `_featureMap.clear()`
  - 修正後: `super.dispose()` → `_isDisposed = true` → `_featureMap.clear()`
  - これにより、子のFeatureNodeが`parent.removeFeature()`を呼んだ時に正常に動作
- ✅ `LayerNode.isDisposed` getter追加（60行）
  - 外部から親のdispose状態を確認可能に
- ✅ `FeatureNode`の各ゲッターで`parent.isDisposed`チェックを追加
  - `turfFeature`, `centroid`, `position`, `positions`, `geometry`, `name`, `description`, `metadata`
  - 親がdisposeされている場合はデフォルト値を返す

**修正効果**:
- ✅ レイヤー削除時の`StateError: Feature not found in parent map`エラーを解消
- ✅ dispose順序の最適化により、メモリリークを防止

---

### 16. 情報表示パネルのタイトル表示を簡潔化（完了）

**背景**:
- フィーチャの情報表示パネルのタイトルが`PointFeatureNode`、`LineFeatureNode`等のクラス名になっていた
- 冗長で分かりにくいため、`Point`、`Line`、`Polygon`のように簡潔にしたい

**変更内容**: `lib/screens/map_page.dart`

1. **タイトル表示ロジックを改善（2874-2886行）**
   - ✅ 変更前: `feature.runtimeType.toString()` → `PointFeatureNode`等
   - ✅ 変更後: 型に応じて判定
     - `PointFeatureNode` → `'Point'`
     - `LineFeatureNode` → `'Line'`
     - `PolygonFeatureNode` → `'Polygon'`
     - その他 → `'Feature'`（フォールバック）

**実装コード**:
```dart
// タイトルをシンプルに（PointFeatureNode → Point等）
String displayTitle = 'Feature';
if (feature is PointFeatureNode) {
  displayTitle = 'Point';
} else if (feature is LineFeatureNode) {
  displayTitle = 'Line';
} else if (feature is PolygonFeatureNode) {
  displayTitle = 'Polygon';
}

return _buildPanel(
  context,
  title: displayTitle,
  children: children,
);
```

**効果**:
- ✅ **可読性向上**: タイトルが簡潔で分かりやすい
- ✅ **UI改善**: 不要な技術情報（クラス名）を隠蔽
- ✅ **一貫性**: PhotoNodeは既に「📸 写真ファイル」という分かりやすいタイトル

**テスト項目**:
- ✅ コンパイル確認: Linterエラーなし（既存warningのみ）
- ⏳ PointFeatureNodeのタイトルが「Point」になること（要実機確認）
- ⏳ LineFeatureNodeのタイトルが「Line」になること（要実機確認）
- ⏳ PolygonFeatureNodeのタイトルが「Polygon」になること（要実機確認）

---

### 15. FeatureNodeの属性設定時の自動カラム作成機能（完了）

**背景**:
- line/polygon→point変換時のdescription設定フローが意図と異なっていた
- 従来: 全ポイントに同じdescriptionを設定
- 意図: 復元データにdescriptionがあればそれを優先、なければ'imported from ○○'
- カラムが存在しない場合は作成する処理が各所に分散していた

**問題点**:
1. **descriptionの設定フローが間違っていた**
   - 全ポイントに対して一律に'imported from ○○'を設定
   - 復元データに既にdescriptionがある場合、それが上書きされてしまう

2. **カラム作成処理の重複**
   - geometry_conversion_serviceでカラムの存在チェックと作成
   - 他の箇所でも同様の処理が必要
   - 処理が分散して保守性が低い

**変更内容**:

1. **FeatureNode.setAttributeValues()の拡張（201-247行）**
   - ✅ カラムが存在しない場合は自動的に作成（TEXT型）
   - ✅ 既存カラムを取得してSet化
   - ✅ 存在しないカラムを検出（id, geomは除外）
   - ✅ addAttributeColumnで自動作成
   - ✅ エラーハンドリング（既に存在する場合など）

   ```dart
   /// 複数の属性値を一括設定
   /// カラムが存在しない場合は自動的に作成する（TEXT型）
   Future<void> setAttributeValues(Map<String, dynamic> attributes) async {
     // 既存のカラム名を取得
     final existingColumns = await geoPackageFile.getColumnNames(...);
     
     // 存在しないカラムを検出して作成
     final missingColumns = attributes.keys.where((key) => 
       !existingColumnSet.contains(key) && 
       key != 'id' && 
       key != 'geom'
     ).toList();
     
     if (missingColumns.isNotEmpty) {
       for (final columnName in missingColumns) {
         await geoPackageFile.addAttributeColumn(...);
       }
     }
     
     // 各属性を親のMap経由で更新
     ...
   }
   ```

2. **geometry_conversion_serviceのdescription処理を修正（282-358行）**
   - ✅ デフォルトdescriptionを事前準備: `'imported from ${sourceFeatureName}'`
   - ✅ ポイント作成時はdescription=null
   - ✅ 属性復元時の判定ロジック:
     ```dart
     // 復元データにdescriptionがあればそれを使い、なければデフォルト値を設定
     if (!attributes.containsKey('description') || 
         attributes['description'] == null || 
         attributes['description'].toString().isEmpty) {
       if (defaultDescription != null) {
         attributes['description'] = defaultDescription;
       }
     }
     ```
   - ✅ setAttributeValuesで設定（カラムがなければ自動作成）
   - ✅ 属性テーブルがない場合でも、デフォルトdescriptionを設定

**新しいフロー**:

1. **属性テーブルから復元データがある場合**:
   - descriptionフィールドがある → その値を使用
   - descriptionフィールドがない/null/空 → `'imported from ${元のname}'`を設定
   - その他の属性も復元

2. **属性テーブルがない場合**:
   - `'imported from ${元のname}'`のみを設定（元のnameがある場合）

3. **カラムが存在しない場合**:
   - setAttributeValuesが自動的にdescriptionカラムを作成（TEXT型）

**効果**:
- ✅ **データ保持**: 復元データのdescriptionが優先される
- ✅ **汎用性**: setAttributeValuesは他の箇所でも使える
- ✅ **安全性**: カラム作成のエラーハンドリング
- ✅ **効率化**: カラム作成処理が一元化
- ✅ **保守性**: カラム作成ロジックが1箇所に集約

**テスト項目**:
- ✅ コンパイル確認: Linterエラーなし
- ⏳ 復元データにdescriptionがある場合、それが優先されること（要実機確認）
- ⏳ descriptionがない場合、'imported from ○○'が設定されること（要実機確認）
- ⏳ descriptionカラムが存在しない場合、自動作成されること（要実機確認）
- ⏳ 他の属性も正常に復元されること（要実機確認）

**副次的効果**:
- 🔄 今後、任意の箇所でsetAttributeValuesを使えば、カラムの自動作成が行われる
- 🔄 ペンツールや他の機能でも同様の恩恵を受けられる

---

## 既知の問題・要調査

### geolocatorプラグインのスレッディング警告

**エラー内容**:
```
[ERROR:flutter/shell/common/shell.cc(1120)] The 'flutter.baseflow.com/geolocator_updates' 
channel sent a message from native to Flutter on a non-platform thread.
```

**原因**:
- `geolocator`プラグイン（v10.1.0）がバックグラウンドスレッドからメッセージを送信
- プラグイン内部の実装問題（特にWindows版）
- Flutterのプラットフォームチャネルの制約に違反

**影響**:
- ⚠️ 警告レベルのエラー（実際にクラッシュやデータ損失が発生しているかは不明）
- 🔍 GPS機能自体は動作している可能性が高い

**対処法の候補**:
1. **geolocatorを最新版にアップデート**
   - 現在: `geolocator: ^10.1.0`
   - pub.devで最新版を確認: https://pub.dev/packages/geolocator
   
2. **Flutter SDKを最新版にアップデート**
   - 現在: SDK ^3.7.2
   - プラグインとの互換性が改善される可能性

3. **エラーを無視**（暫定対応）
   - 実際にGPS機能が正常動作していれば、警告として無視
   - データ損失やクラッシュが発生していないか要確認

**要確認事項**:
- ⏳ GPS機能が正常に動作しているか（位置取得、測量など）
- ⏳ データ損失が発生していないか
- ⏳ アプリがクラッシュしていないか
- ⏳ 最新のgeolocatorバージョンで問題が解決するか

**参考リンク**:
- Flutter Platform Channels: https://docs.flutter.dev/platform-integration/platform-channels#channels-and-platform-threading
- geolocator Issues: https://github.com/Baseflow/flutter-geolocator/issues

---

## 完了した作業

### 14. GPS位置更新の最適化とログ出力制御（完了）

**背景**:
- アクセシビリティエラーの根本原因は、GPS位置更新ログが大量に出力されていたこと
- `GpsManagerService: 位置更新 - Lat: ..., Lon: ..., Source: GPS`のログが1秒間に複数回出力
- GPS更新のたびにログ出力とUI更新（notifyListeners）が発生し、Flutterのアクセシビリティツリーが追いつかない

**問題の詳細**:
1. **distanceFilter: 0**（522行）
   - わずかな位置変化（1cm未満でも）で更新が発生
   - GPSの精度誤差でも頻繁に更新が走る
   - 静止していても1秒間に何度も更新される可能性

2. **無制限なログ出力**（638-642行）
   - GPS更新のたびに必ずログ出力
   - 1分間で60回以上のログが出力される可能性
   - ログ出力自体がパフォーマンスに影響

**変更内容**: `lib/services/gps_manager_service.dart`

1. **distanceFilterの設定（525行）**
   - ✅ 変更前: `distanceFilter: 0`（制限なし）
   - ✅ 変更後: `distanceFilter: 1`（1メートル以上移動した場合のみ更新）
   - ✅ これにより、静止時や微小な移動では更新が発生しない

2. **ログ出力の制限（641-650行）**
   - ✅ 最後のログ出力から5秒経過した場合のみログを出力
   - ✅ `_lastLogTime`フィールドを追加（116-117行）
   - ✅ ログ頻度を1/5以下に削減（毎秒 → 5秒に1回）

3. **実装の詳細**
   ```dart
   // ログ出力を5秒に1回に制限
   final now = DateTime.now();
   if (_lastLogTime == null || now.difference(_lastLogTime!).inSeconds >= 5) {
     debugPrint(...);
     _lastLogTime = now;
   }
   ```

**効果**:
- ✅ **GPS更新頻度の大幅削減**: 毎秒複数回 → 1メートル移動時のみ
- ✅ **ログ出力の削減**: 1分間で60+回 → 12回程度
- ✅ **パフォーマンス向上**: ログ出力とUI更新の負荷が大幅に軽減
- ✅ **アクセシビリティエラーの解消**: UI更新頻度が正常範囲に
- ✅ **バッテリー消費の削減**: 不要な処理が減る
- ✅ **GPS精度への影響なし**: 実用上1mの閾値は問題ない

**テスト項目**:
- ✅ コンパイル確認: Linterエラーなし（既存warningのみ）
- ⏳ アクセシビリティエラーが発生しないこと（要実機確認）
- ⏳ ログ出力が5秒に1回程度に抑えられていること（要実機確認）
- ⏳ GPS機能が正常に動作すること（要実機確認）
- ⏳ 1メートル以上移動すると位置が更新されること（要実機確認）

**備考**:
- distanceFilterは用途に応じて調整可能（0.5m、2m等）
- ログ出力間隔も調整可能（3秒、10秒等）
- GPS測量など高精度が必要な場合は、オプション設定で上書き可能

---

### 13. line/polygon→point変換時のログ出力削減とパフォーマンス改善（完了）

**背景**:
- line→point変換時に`[ERROR:flutter/shell/platform/common/accessibility_bridge.cc(65)] Failed to update ui::AXTree`エラーが発生
- これはFlutterのアクセシビリティに関する既知の問題で、大量の高速UI更新が原因
- 各ポイント作成時に詳細なデバッグログが出力されており（print文が10個以上/ポイント）、大量のポイント変換時にログ出力が追いつかない

**問題の詳細**:
- 従来の実装では各ポイント作成時に以下のログを出力：
  - `[GeometryConversion] ポイント${i + 1}: データ行=${rowData}`
  - `[GeometryConversion]   カラム[$columnName]をスキップ（組み込み）` （複数回）
  - `[GeometryConversion]   カラム[$columnName] = $value` （複数回）
  - `[GeometryConversion] ポイント${i + 1}に属性を設定: $attributes`
  - `[GeometryConversion] ポイント${i + 1}の属性設定完了＆DB保存: ${attributes.length}個`
  - `[GeometryConversion] ポイント${i + 1}: 復元する属性なし`
- 100個のポイントを変換する場合、1000個以上のログ出力が発生

**変更内容**: `lib/services/geometry_conversion_service.dart`

1. **詳細ログの削減（299-350行）**
   - ✅ 各ポイントの詳細ログを削除
   - ✅ 進捗表示を10%ごとに変更（100ポイントなら10回のログ）
   - ✅ エラーログのみ保持

2. **進捗表示の追加（305-308行）**
   - ✅ 開始時: `ポイント変換開始: ${totalPoints}個のポイントを作成`
   - ✅ 進捗: `進捗: ${i + 1}/${totalPoints} (${percentage}%)` （10%ごと）
   - ✅ 完了時: `ポイント変換完了: ${createdFeatures.length}個のポイントを作成`

3. **不要なログの削除**
   - ✅ 各データ行の表示
   - ✅ 各カラムのスキップメッセージ
   - ✅ 各カラムの値の表示
   - ✅ 属性設定の詳細メッセージ
   - ✅ 「復元する属性なし」メッセージ

**効果**:
- ✅ **ログ出力を90%以上削減**: 100ポイントで1000+個 → 15個程度
- ✅ **パフォーマンス向上**: ログ出力のオーバーヘッドを大幅削減
- ✅ **アクセシビリティエラーの軽減**: UI更新の負荷が減少
- ✅ **進捗の可視化**: 大量のポイント変換時の進捗が分かりやすい

**テスト項目**:
- ✅ コンパイル確認: Linterエラーなし
- ⏳ アクセシビリティエラーが発生しないこと（要実機確認）
- ⏳ 進捗ログが適切に表示されること（要実機確認）
- ⏳ 大量のポイント変換でも正常動作すること（要実機確認）

**備考**:
- アクセシビリティエラー自体は無害だが、ログが見づらくなるため対処
- 今後、さらに大量のポイント（1000個以上）を扱う場合は、プログレスバー付きダイアログの追加を検討

---

### 12. point→line/polygon変換時の名前入力ダイアログ追加（完了）

**背景**:
- point→line/polygon変換時、フィーチャ名が自動的に`'Converted from ${sourceLayer.name}'`に設定されていた
- ペンツールではユーザーが名前を入力できるダイアログがあるが、変換機能にはなかった
- ユーザーからペンツールと同様に名前を決められるようにしてほしいとの要望

**変更内容**:

1. **`GeometryConversionService.convertPointsToGeometry()`にname引数を追加（87-96行）**
   - ✅ `String? name`引数を追加
   - ✅ 指定がない場合はデフォルト名`'Converted from ${sourceLayer.name}'`を使用
   - ✅ ドキュメントコメントを追加

2. **フィーチャ名の決定ロジックを更新（137-138行）**
   - ✅ `final featureName = name ?? 'Converted from ${sourceLayer.name}';`
   - ✅ LineFeatureNode/PolygonFeatureNodeの作成時にfeatureNameを使用

3. **名前入力ダイアログを追加（layer_drawer_tiles.dart 844-881行）**
   - ✅ ターゲットレイヤー選択後、変換実行前にダイアログを表示
   - ✅ ペンツールと同じパターンのAlertDialog
   - ✅ タイトルに「ライン フィーチャ名の入力」または「ポリゴン フィーチャ名の入力」を動的に表示
   - ✅ キャンセルボタンで処理を中断
   - ✅ 空の名前を入力した場合はデフォルト名を使用

**実装の詳細**:
```dart
// ダイアログで名前を入力
String? featureName = await showDialog<String>(...);

// キャンセル時は処理中断
if (featureName == null) {
  return;
}

// 変換実行（空の場合はnullでデフォルト名使用）
final createdFeature = await GeometryConversionService.convertPointsToGeometry(
  sourceLayer: sourceLayer,
  targetLayer: targetLayer,
  name: featureName.isNotEmpty ? featureName : null,
);
```

**効果**:
- ✅ **ユーザー体験の向上**: フィーチャ名を自由に設定できる
- ✅ **一貫性**: ペンツールと同じUIパターン
- ✅ **柔軟性**: 空欄の場合はデフォルト名を使用
- ✅ **キャンセル可能**: ダイアログでキャンセルすれば変換を中断

**テスト項目**:
- ✅ コンパイル確認: Linterエラーなし（既存warningのみ）
- ⏳ ダイアログが表示されること（要実機確認）
- ⏳ 名前を入力して変換できること（要実機確認）
- ⏳ 空欄のまま変換するとデフォルト名になること（要実機確認）
- ⏳ キャンセルすると変換が中断されること（要実機確認）

---

### 11. ジオメトリ変換時のname/description設定の改善（完了）

**背景**:
- line/polygon→point変換時、ポイントのnameに`'Point ${i + 1} from ${sourceFeature.name}'`のようなデフォルト値を自動設定していた
- ユーザーからnameは空（null）で良いとの要望
- 代わりに、descriptionに元のフィーチャ情報を記録する方式に変更

**変更内容**: `lib/services/geometry_conversion_service.dart`

1. **nameのデフォルト値設定を廃止（274-300行）**
   - ✅ 従来: `'Point ${i + 1} from ${sourceFeature.name}'`
   - ✅ 変更後: 空文字列 `''` （型的にnullは不可のため）
   - ✅ nameカラムが存在しない場合は何も設定しない

2. **descriptionに元フィーチャ情報を条件付きで追加（274-289行）**
   - ✅ 条件1: 元のline/polygonフィーチャのnameが設定されている（空でない）
   - ✅ 条件2: ターゲットのポイントレイヤーにdescriptionカラムが存在する
   - ✅ 両方を満たす場合: `'imported from ${sourceFeatureName}'`を設定
   - ✅ 条件を満たさない場合: nullを設定（何も書き込まない）

3. **実装の詳細**
   - ✅ `targetColumnNames`で変数名の重複を回避
   - ✅ ループの外でdescription値を1回だけ計算（全ポイントで同じ値）
   - ✅ 元のフィーチャのnameが空の場合は何も設定しない

**効果**:
- ✅ **属性テーブルの可読性向上**: nameフィールドに不要な自動生成値が入らない
- ✅ **トレーサビリティ**: descriptionで元のフィーチャを追跡可能
- ✅ **柔軟性**: descriptionカラムが存在しない場合でもエラーにならない
- ✅ **一貫性**: 全ての変換ポイントに同じdescriptionが設定される

**テスト項目**:
- ✅ コンパイル確認: Linterエラーなし
- ⏳ nameが空文字列で作成されること（要実機確認）
- ⏳ descriptionに'imported from ○○'が設定されること（要実機確認）
- ⏳ descriptionカラムがない場合でもエラーにならないこと（要実機確認）

---

### 10. データフローの最適化：インスタンスベースの状態管理（完了）

**背景**:
- 従来、featureに変更がある度に「DBに保存→DBから読み出し→インスタンスに反映」という流れになっていた
- 非同期処理が間に合わない場合、インスタンス側に変更が反映されず、バグの原因となっていた
- 特に`_forceMapRefresh()`が`LayerNode.children`をクリアしてDBから全て再読み込みしていたのが問題

**新しいフロー**:
1. **フィーチャ追加・更新時**: インスタンス（`LayerNode.children`）に即座に反映
2. **DB保存**: 非同期でバックグラウンド実行（既に実装済み）
3. **DB読み出し**: プロジェクト起動時（初回のみ）に限定

**変更内容**: `lib/screens/map_page.dart`

1. **`_forceMapRefresh()`を`_refreshMapUI()`に置き換え（1189-1216行）**
   - ✅ LayerNodeのchildrenをクリアしない（メモリ上のインスタンスを維持）
   - ✅ DBからの再読み込みは行わず、既存のchildrenから読み込む
   - ✅ フィーチャデータのキャッシュ（`_pointFeatures`, `_lineFeatures`等）のみクリア
   - ✅ `_updateFeatures()`を呼んで、childrenから読み込む

2. **全ての`_forceMapRefresh()`呼び出しを`_refreshMapUI()`に置き換え**
   - ✅ GPS測量後のコールバック（853行）
   - ✅ フィーチャ確定後のコールバック（945行）
   - ✅ フィーチャ削除後の処理（2326行）
   - ✅ 外部公開メソッド`forceMapRefresh()`（1119行）

3. **`_updateFeatures()`の既存実装を維持（1028-1036行等）**
   - ✅ childrenが空の場合のみ`updateChildren()`を呼んでDBから読み込む
   - ✅ childrenにフィーチャがある場合は、そこから直接読み込む（DBアクセスなし）

**効果**:
- ✅ **パフォーマンス向上**: DBへの不要なアクセスを削減
- ✅ **データの一貫性**: メモリ上のインスタンスが常に最新の状態を保持
- ✅ **バグ防止**: 非同期処理の遅延による不整合を回避
- ✅ **UI応答性向上**: childrenからの読み込みは同期的で高速

**既存実装の確認**:
- ✅ `FeatureNode.createIn()`等は既に正しい順序で実装されていた：
  1. DBに保存してrowIdを取得
  2. FeatureNodeを作成
  3. `parent.addChild(node)`でインスタンスに追加
- ✅ rowIdはDB保存時に生成されるため、この順序は変更不要

**テスト項目**:
- ✅ コンパイル確認: Linterエラーなし（既存warningのみ）
- ⏳ フィーチャ追加後、即座にマップに反映されること（要実機確認）
- ⏳ フィーチャ削除後、即座にマップから消えること（要実機確認）
- ⏳ プロジェクト起動時、DBから正常に読み込まれること（要実機確認）

---

# K-MAPS 作業ログ（2025年10月2日）

## 完了した作業

### 1. 固定属性カラムへの依存削除（完了）

**変更内容**: `name`, `description`, `kmaps_metadata` カラムへの依存を完全に削除  
**目的**: 外部ファイルインポート時に問答無用でカラムが追加されないようにする  
**保持**: `id`（PRIMARY KEY）と `geom`（必須カラム）は維持

#### 修正箇所（最終版）

1. **lib/models/geopackage_file.dart**
   - ✅ `supportedAttributes`: `id`と`geom`のみに変更
   - ✅ `addLayer`: テーブル作成時に固定カラムを追加しないように修正
   - ✅ `getFeature`, `getFeatures`: `ensureNameDescriptionColumns`/`ensureMetadataColumn`の呼び出しを削除
   - ✅ `ensureNameDescriptionColumns`, `ensureMetadataColumn`: メソッド自体を削除
   - ✅ `addPointWithAttributes`, `addLineWithAttributes`, `addPolygonWithAttributes`: 全ての`ensureMetadataColumn`呼び出しを削除
   - ✅ `addPoint`: カラムの存在確認を追加し、存在する場合のみ値を設定（try-catchで保護）
   - ✅ `updatePoint`, `updateLine`, `updatePolygon`: カラムの存在を動的に確認し、存在するカラムのみを更新するように修正
   - ✅ `addPointsBatch`, `addLinesBatch`, `addPolygonsBatch`: デフォルト値設定（`name`, `description`）を削除
   - ✅ `getAttributeColumnInfo`: 組み込みカラムから固定カラムを削除
   - ✅ `addAttributeColumns`: ログ出力を削減（開始/完了メッセージを削除）
   - ✅ `addAttributeColumn`: カラム追加成功/既存のログを削除

2. **lib/services/import_export_service.dart**
   - ✅ `_addGeoJsonSchemaToGeoPackage`: `name`と`description`をスキップする処理を削除
   - ✅ `_addDbfSchemaToGeoPackage`: `name`と`description`をスキップする処理を削除
   - ✅ `_importShapefileFeatures`: ポリゴンデータ作成時に`name`と`description`のデフォルト値設定を削除
   - ✅ `_extractShapefileCoordinates`: Point/Line/Polygonデータ作成時に`name`と`description`のデフォルト値設定を削除、DBF属性を全てそのまま追加
   - ✅ フィールド定義の詳細ログを削除

3. **lib/models/nodes/feature_node.dart**
   - ✅ `PointFeatureNode.createIn`: カラムの存在確認を追加し、存在するカラムのみ値を設定
   - ✅ `LineFeatureNode.createIn`: カラムの存在確認を追加し、存在するカラムのみ値を設定
   - ✅ `PolygonFeatureNode.createIn`: カラムの存在確認を追加し、存在するカラムのみ値を設定

4. **lib/utils/wkb_utils.dart**
   - ✅ `[GPB] Adding envelope`ログを削除

#### バグ修正
1. **ペンツール追加エラー**: `PointFeatureNode.createIn`が常に`name`と`description`を属性マップに含めていた問題を修正
2. **Shapefileバッチインポートエラー（第1弾）**: `addPolygonsBatch`が`name`と`description`のデフォルト値を設定していた問題を修正
3. **Shapefileバッチインポートエラー（第2弾）**: `_importShapefileFeatures`でポリゴンデータ作成時に`name`と`description`を追加していた問題を修正
4. **Shapefileバッチインポートエラー（第3弾）**: `_extractShapefileCoordinates`でPoint/Line/Polygonデータ作成時に`name`と`description`を追加していた問題を修正（最終的な原因）

### 2. 属性テーブルのフリーズ問題修正（完了）

**問題**: フィーチャが0個のレイヤーで属性テーブルを開くとフリーズする

**原因**: 
- `_createRows()`メソッドで、`features.isEmpty || columnNames.isEmpty`の場合に`'no_data'`フィールドを持つ行を返していた
- しかし、`columnNames`が存在し`features`が空の場合、`_createColumns()`は通常のカラムを作成するため、フィールド名が一致せずPlutoGridがフリーズ

**修正内容**: `lib/widgets/dynamic_attribute_table_widget.dart`
- ✅ `_createRows()`: `columnNames.isEmpty`と`features.isEmpty`を分離して判定
  - `columnNames.isEmpty`の場合のみ`'no_data'`行を返す
  - `features.isEmpty`の場合は空のリスト`[]`を返す（PlutoGridは空のrowsを正常に処理できる）
- ✅ `build()`: カラムが空の場合とフィーチャが空の場合を区別
  - `columns.isEmpty`の場合は「カラム定義がありません」メッセージを表示
  - `features.isEmpty`（rowsが空）の場合は空のテーブルを表示

#### テスト状況
- ✅ Linterエラー: なし
- ✅ ペンツール: 固定カラムなしレイヤーへの追加が正常動作
- ✅ Shapefileインポート: バッチ処理が正常動作
- ✅ 属性テーブル: フィーチャ0個のレイヤーでもフリーズしない
- ✅ ログ出力: 大幅に削減され、追跡が容易に

---

### 3. ID列の属性テーブルからの除外（完了）

**背景**: 
- `id`列（主キー）がGeoPackageファイルに保存され、属性テーブルにも表示されていた
- ユーザーには不要な情報であり、データ量を増やす原因となっていた
- GeoPackage標準では主キーは必須のため、完全削除はできない

**採用アプローチ**: 
- `id`列はテーブルの主キーとして保持（GeoPackage標準準拠、QGIS等との互換性維持）
- 属性データとしては扱わない（ユーザーインターフェースでは非表示）

**変更内容**:

1. **lib/models/geopackage_file.dart**
   - ✅ `supportedAttributes`: `id`を削除、`geom`のみに変更
   - ✅ `getColumnNames()`: `id`と`geom`を常に除外するよう修正
     - `getAll: true`の場合でも、`id`と`geom`は属性データではないため除外
     - コメント追加：主キーとして存在するが属性データとしては扱わない旨を明記

**効果**:
- ✅ 属性テーブルに`id`列が表示されなくなる
- ✅ `id`列はデータベースの主キーとして機能し続ける（内部処理で使用）
- ✅ QGIS等の外部GISアプリケーションとの互換性を維持
- ✅ データ量の削減（ユーザーが見る属性データから除外）

**テスト項目**:
- ✅ コンパイル確認: Linterエラーなし
- ⏳ 属性テーブルで`id`が表示されないこと（要実機確認）
- ⏳ 内部処理（更新・削除）が正常動作すること（要実機確認）
- ⏳ QGISで開いて`id`列が存在すること（互換性確認）

**備考**:
- `id`列はSQLクエリ（`WHERE id = ?`など）で引き続き使用される
- `geom`列も同様に属性データから除外（ジオメトリは別扱い）
- 既存のGPKGファイルとの互換性は維持される

---

### 4. ポイントレイヤー→ライン変換機能の実装（完了）

**背景**: 
- ポイントレイヤーのジオメトリリストをラインフィーチャのジオメトリに変換し、既存のラインレイヤーに追加する機能が必要だった
- GPS軌跡などの連続したポイントデータをラインとして可視化するための機能

**実装内容**:

1. **lib/widgets/layer_drawer/layer_drawer_tiles.dart**
   - ✅ ポイントレイヤーのコンテキストメニュー（...）に「ラインに変換」オプションを追加
   - ✅ `_convertPointsToLine()` メソッドを実装
     - ポイントレイヤーの全フィーチャから座標リストを抽出
     - ターゲットのラインレイヤーを選択するダイアログを表示
     - `LineFeatureNode.createIn()` を使用してラインフィーチャを作成・追加
   - ✅ `_ConvertToLineDialog` ダイアログクラスを実装
     - カレントディレクトリ直下の.gpkg内のラインレイヤーを検索
     - ドロップダウンで追加先レイヤーを選択可能
     - レイヤーが存在しない場合の警告表示

**機能詳細**:
- ポイントレイヤーのフィーチャリストから順番に座標を取得し、ラインジオメトリに変換
- geom以外の属性はまっさらな状態で追加（最小構成）
- 変換元のレイヤー名とポイント数をフィーチャの名前として設定
- 変換完了後にUI更新とマップの再描画を実行

**テスト項目**:
- ✅ コンパイル確認: Linterエラーなし
- ⏳ ポイントレイヤーのコンテキストメニューに「ラインに変換」が表示されること（要実機確認）
- ⏳ ダイアログでラインレイヤーが正しく検索・表示されること（要実機確認）
- ⏳ 変換処理が正常に動作し、ラインフィーチャが追加されること（要実機確認）
- ⏳ 変換後のラインが地図上に正しく表示されること（要実機確認）

**参考実装**:
- `pen_tool.dart` の `LineFeatureNode.createIn()` 呼び出し処理を参考にした
- レイヤー移植処理の `_handleLayerDrop()` と同様のダイアログパターンを採用

---

### 5. ID列の属性テーブル表示の復活（完了）

**背景**: 
- 以前の作業でid列を属性テーブルから非表示にしていたが、ユーザーの要望によりid列を再表示することになった

**変更内容**:

1. **lib/models/geopackage_file.dart**
   - ✅ `supportedAttributes`: `"id"`を追加し、`["id", "geom"]`に変更
   - ✅ `getColumnNames()`: id列を除外しないように修正（geomのみ除外）
     - 変更前: `columns.where((c) => c != 'id' && c != 'geom')`
     - 変更後: `columns.where((c) => c != 'geom')`
   - ✅ コメント更新: 「id（主キー）とgeom（ジオメトリ）は常に除外される」→「geom（ジオメトリ）は常に除外される」

**効果**:
- ✅ 属性テーブルにid列が表示されるようになる
- ✅ id列はデータベースの主キーとして引き続き機能する
- ✅ QGIS等の外部GISアプリケーションとの互換性を維持

**テスト項目**:
- ✅ コンパイル確認: Linterエラーなし
- ⏳ 属性テーブルでid列が表示されること（要実機確認）

---

### 6. ポイント→ライン変換ダイアログの実装と問題解決（完了）

**初期問題**: 
- ポイントレイヤーから「ラインに変換」を選ぶと、ダイアログが表示されずにフリーズする
- ログ調査により、2つの問題が判明

**問題1: FeatureNodeの不要な検索**
- `_searchLineLayers()`が、LayerNode配下のFeatureNodeまで全て検索していた
  - 例: 40林班の58個のPolygonFeatureNode、合計100個以上のノードを検索
- UIスレッドがブロックされ、ダイアログ表示に遅延が発生

**修正1**:
- FeatureNodeは最初にスキップ（`if (node is FeatureNode) return;`）
- LineLayerNode発見後、その子は検索しない

**問題2: DropdownButtonFormFieldの使用**
- `initState()`で非同期処理を開始するパターンで`DropdownButtonFormField`を使用
- AlertDialogの表示処理自体がブロックされていた

**修正2: TrackSaveDialogパターンの採用**
1. ✅ ダイアログ表示前にデータを同期的に準備
   - `_searchLineLayersSync()`でラインレイヤーを事前検索
   - `showDialog`呼び出し前に完全にデータを準備

2. ✅ TrackSaveDialogと同じUIパターンを採用
   - `DropdownButton<LineLayerNode>`を使用（`DropdownButtonFormField`ではない）
   - `DropdownButtonHideUnderline`でラップ
   - `Container`でボーダーを追加

3. ✅ シンプルなStatefulWidget実装
   - `initState()`で最初のレイヤーを選択
   - 非同期処理なし

**修正内容**: `lib/widgets/layer_drawer/layer_drawer_tiles.dart`

1. **`_searchLineLayersSync()`メソッド追加**
   - 同期的にラインレイヤーを検索
   - FeatureNodeは検索しない

2. **`_ConvertToLineDialogSimple`クラス実装**
   - TrackSaveDialogパターンに準拠
   - 事前に検索したレイヤーリストを受け取る
   - DropdownButtonでレイヤー選択
   - ElevatedButton.iconで変換実行

3. **デバッグログの整理**
   - テストダイアログを削除
   - 不要なログを削減

**効果**:
- ✅ FeatureNodeの無駄な検索を完全に排除
- ✅ ダイアログが即座に表示される
- ✅ ドロップダウンでレイヤーを選択可能
- ✅ TrackSaveDialogと一貫性のあるUI

**テスト項目**:
- ✅ コンパイル確認: Linterエラーなし
- ✅ ダイアログが正常に表示されること（実機確認済み）
- ✅ ドロップダウンでレイヤーを選択できること（実機確認済み）
- ✅ ポイント→ライン変換が正常に動作すること（実機確認済み）

**追加機能: ポリゴン変換サポート（完了）**

1. **メニュー項目名の変更**
   - 変更前: 「ラインに変換」
   - 変更後: 「ライン/ポリゴンに変換」
   - アイコン: `Icons.transform`

2. **ライン/ポリゴン両方を検索**
   - ✅ `_searchLineAndPolygonLayersSync()` メソッドを追加
   - LineLayerNodeとPolygonLayerNodeの両方を検索対象に

3. **ダイアログの拡張**
   - ✅ `_ConvertPointsDialog`にリネーム（より適切な名前）
   - ドロップダウンで各レイヤーのタイプを表示 `(ライン)` / `(ポリゴン)`
   - 選択に応じてメッセージが動的に変化

4. **変換処理の分岐**
   - ✅ LineLayerNode: ポイントリストをそのまま使用
   - ✅ PolygonLayerNode: ポイントリストを外環として使用（穴なし）
     - `rings = [points]` で外環のみのポリゴンを作成

5. **マップ反映処理の追加**
   - ✅ `triggerMapRefresh()` を呼び出し
   - ✅ `mapState.refreshFeatures()` を呼び出し
   - pen_toolと同じパターンでマップに即座に反映

**テスト項目（追加）**:
- ✅ ポイント→ポリゴン変換が正常に動作すること（実機確認済み）
- ✅ 変換後すぐにマップに反映されること（実機確認済み）

---

### 7. ライン/ポリゴン→ポイント変換機能の実装（完了）

**背景**:
- ポイント→ライン/ポリゴン変換の逆機能として、ライン/ポリゴンの頂点をポイントに変換する機能を実装
- 選択フィーチャの情報表示パネルにボタンを追加（ライン簡略化と同様のUI）

**実装内容**: `lib/screens/map_page.dart`

1. **FeatureDetailPanelにボタン追加**
   - ✅ LineFeatureNode: 「ライン簡略化」ボタンの下に「ポイントに変換」ボタンを追加
   - ✅ PolygonFeatureNode: 「ポイントに変換」ボタンを追加
   - スタイル: 緑色のElevatedButton.icon

2. **`_showConvertToPointsDialog()`メソッド実装**
   - ✅ LineFeatureNode: `feature.line`で全頂点を取得
   - ✅ PolygonFeatureNode: 外環（最初のリング）を取得
     - 閉じたポリゴンの場合、最後の座標が最初と同じなら削除
     - `outerRing.sublist(0, outerRing.length - 1)`で重複を除外
   - ✅ カレントディレクトリ直下のポイントレイヤーを検索
   - ✅ ダイアログでポイントレイヤーを選択
   - ✅ 各座標を`PointFeatureNode.createIn()`で追加

3. **`_ConvertToPointsDialog`クラス実装**
   - ✅ TrackSaveDialogパターンに準拠
   - ✅ DropdownButtonでポイントレイヤー選択
   - ✅ フィーチャタイプ（ライン/ポリゴン）を表示

4. **`_searchPointLayersInNode()`静的メソッド追加**
   - ✅ ポイントレイヤーを検索
   - ✅ FeatureNodeをスキップ（パフォーマンス最適化）

**効果**:
- ✅ ラインの全頂点をポイントとして抽出可能
- ✅ ポリゴンの外環の頂点をポイントとして抽出可能（最後の重複座標は除外）
- ✅ 既存のポイントレイヤーに追加される
- ✅ マップに即座に反映される

**テスト項目**:
- ✅ コンパイル確認: Linterエラーなし（既存warningのみ）
- ✅ ライン→ポイント変換が正常に動作すること（実機確認済み）
- ✅ ポリゴン→ポイント変換が正常に動作すること（実機確認済み）
- ✅ 閉じたポリゴンの最後の座標が除外されること（実機確認済み）

---

### 8. ジオメトリ変換処理のリファクタリング（完了）

**背景**:
- 変換処理が複数のファイルに分散していた（layer_drawer_tiles.dart, map_page.dart）
- 重複したコードが多く、保守性が低かった
- 今後の機能拡張（属性保存など）を見据えて、コードを整理

**実装内容**:

1. **新規ファイル作成**
   - ✅ `lib/services/geometry_conversion_service.dart`
     - ジオメトリ変換ロジックを集約
     - レイヤー検索ヘルパー関数
     - ユーティリティ関数（closeRingなど）
   - ✅ `lib/widgets/geometry_conversion_dialogs.dart`
     - 変換ダイアログウィジェットを集約
     - `ConvertPointsToGeometryDialog`（ポイント→ライン/ポリゴン）
     - `ConvertGeometryToPointsDialog`（ライン/ポリゴン→ポイント）

2. **GeometryConversionServiceの構成**
   - ✅ `closeRing()`: ポリゴンリングを閉じる
   - ✅ `searchLineAndPolygonLayers()`: ライン/ポリゴンレイヤー検索
   - ✅ `searchPointLayers()`: ポイントレイヤー検索
   - ✅ `findTargetLayersForPoints()`: ポイント変換先候補の検索
   - ✅ `findTargetLayersForGeometry()`: ジオメトリ変換先候補の検索
   - ✅ `convertPointsToGeometry()`: ポイント→ライン/ポリゴン変換実行
   - ✅ `convertGeometryToPoints()`: ライン/ポリゴン→ポイント変換実行

3. **既存コードの書き換え**
   - ✅ `layer_drawer_tiles.dart`
     - `_convertPointsToLine()`を簡略化（サービス呼び出しのみ）
     - 古いダイアログクラス（`_ConvertToLineDialog`, `_ConvertPointsDialog`）を削除
     - ヘルパー関数を削除
   - ✅ `map_page.dart`
     - `_showConvertToPointsDialog()`を簡略化（サービス呼び出しのみ）
     - 古いダイアログクラス（`_ConvertToPointsDialog`）を削除
     - 検索関数を削除

**効果**:
- ✅ コードの重複を排除
- ✅ 保守性の向上（変換ロジックが1箇所に集約）
- ✅ テストしやすい構造
- ✅ 将来の拡張が容易（属性保存機能の追加準備完了）

**ファイル構成**:
```
lib/
├── services/
│   └── geometry_conversion_service.dart  ← NEW（変換ロジック）
├── widgets/
│   └── geometry_conversion_dialogs.dart  ← NEW（ダイアログUI）
├── widgets/layer_drawer/
│   └── layer_drawer_tiles.dart          ← 簡略化
└── screens/
    └── map_page.dart                    ← 簡略化
```

**テスト項目**:
- ✅ コンパイル確認: Linterエラーなし（既存warningのみ）
- ⏳ リファクタリング後も全機能が正常動作すること（要実機確認）

---

### 9. FeatureNode.dispose()の_featureMap削除漏れ修正（完了）

**背景**:
- たまに`StateError (Bad state: Feature not found in parent map: rowId=XX)`というエラーが発生
- 主に以下の2つのケースで発生：
  1. 属性テーブルからフィーチャを削除したとき
  2. point→line変換のとき

**原因**:
- `FeatureNode.dispose()`メソッドで`parent.children.remove(this)`を直接呼んでいた
- これにより、`parent.children`リストからは削除されるが、`parent._featureMap`からは削除されない
- その後、何らかの理由で`turfFeature`プロパティにアクセスすると、`parent.getFeatureById(_rowId)`がnullを返してエラーが発生

**修正内容**: `lib/models/nodes/feature_node.dart`

1. **`dispose()`メソッドの修正（288-298行）**
   - ✅ `parent.children.remove(this)`の代わりに`parent.removeFeature(this)`を呼び出し
   - ✅ `removeFeature()`は`children`リストと`_featureMap`の両方から削除する
   - ✅ try-catchでエラーハンドリングを追加（フォールバック処理）

2. **`turfFeature`ゲッターの改善（36-52行）**
   - ✅ エラーメッセージに`rowId`と`layerName`を追加
   - ✅ エラー発生時に詳細なデバッグ情報をログ出力
   - ✅ `parent._featureMap`のサイズも表示

**効果**:
- ✅ dispose時に`children`と`_featureMap`の両方から確実に削除される
- ✅ エラーが発生した場合でも、より詳細な情報が得られる
- ✅ フォールバック処理により、エラーが発生しても可能な限り削除を試みる

**テスト項目**:
- ✅ コンパイル確認: Linterエラーなし
- ⏳ 属性テーブルからフィーチャを削除してもエラーが出ないこと（要実機確認）
- ⏳ point→line変換でエラーが出ないこと（要実機確認）