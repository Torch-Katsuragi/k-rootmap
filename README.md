# K-MAPS

## 概要
K-MAPSはGeoPackageベースの地理情報管理・編集アプリ。

## 主な設計方針（2024-06-10以降）
- **LayerManagerは廃止**。GeoPackageFile＋ノード（GeoPackageNode/LayerNode）＋グローバル変数で全体管理。
- UIはGeoPackageNode/LayerNodeのメソッドを直接呼び、DB操作はGeoPackageFileに集約。
- 選択状態は「現在選択中のLayerNode/GeoPackageNode」への参照をグローバル変数で保持。
- 可視状態・meta.json連携はLayerTreeNodeのvisible系メソッドで一元化。
- 複数ファイル・レイヤの一元管理も、全ノードリストをグローバルで管理。
- **地図操作ツール（MapTool）を導入し、てのひら・ペン・選択などのツール切替をサポート。現在のツールはGlobalConfigで一元管理。**
- **ペン入力（スタイラス）とタップ入力（指・マウス）で挙動を分岐し、直感的な操作性を実現。**

## 主要ファイル・クラス構成
- `lib/models/geopackage_file.dart` : GeoPackageFile（GeoPackageファイル管理・DB操作ラッパ）
  - WKBエンコード・デコード処理はlib/utils/wkb_utils.dartに集約。
  - ファイルが存在しない場合、親ディレクトリが存在すればGeoPackage必須テーブル（gpkg_spatial_ref_sys, gpkg_contents, gpkg_geometry_columns）を自動作成（OGC仕様準拠、最小構成）。
- `lib/models/layer_tree_node.dart` : LayerTreeNode/GeoPackageNode/LayerNode（ツリー構造・可視状態・meta.json連携）
- `lib/utils/global_config.dart` : グローバル変数（全ノードリスト・選択中ノード等）
- `lib/widgets/layer_drawer.dart` : レイヤツリーUI（ノード参照で操作）
  - フォルダノード右側に「GeoPackage追加」ボタン（＋）を実装。押下でファイル名入力→GeoPackageファイル自動生成→ノード追加・即反映。
  - GeoPackageノード（gpkgパネル）はタップで配下レイヤリストをトグル展開可能。
- `lib/screens/map_page.dart` : 地図画面本体（ノード・グローバル変数参照で状態管理）
- `lib/tools/map_tool.dart` : 地図操作ツールの抽象基底クラス（MapTool）。
- `lib/tools/pan_tool.dart` : てのひらツール（地図パン専用）。
- `lib/tools/pen_tool.dart` : ペンツール（レイヤ描画）。
- `lib/tools/select_tool.dart` : オブジェクト選択ツール。

## クラス構成
- **GeoPackageFile**: ファイルパスのみ保持し、DB操作（レイヤ追加・削除・リネーム・フィーチャ取得等）を担う。
- **LayerTreeNode/GeoPackageNode/LayerNode**: ツリー構造・可視状態・meta.json連携・GeoPackageFile参照を持つ。
- **GlobalConfig**: 全ノードリスト・選択中ノード等のグローバル管理。

## 状態管理
- 選択状態・可視状態・ファイル/レイヤの追加削除等は、すべてノード＋グローバル変数で一元管理。
- meta.jsonのロード・保存もLayerTreeNode側で吸収。

## 主な機能
- レイヤ構造のファイルエクスプローラ風表示・操作
- GeoPackageファイル・レイヤの追加/削除/可視切り替え
- **Drawer上部に現在のノード名を青いタイトルパネルで表示（LayerDrawerTitleBarウィジェット）**
- プロジェクトフォルダ・サブフォルダ・GeoPackage・レイヤの階層構造をファイルエクスプローラ風に1階層のみリスト表示
- フォルダ/GeoPackage/レイヤの可視切り替え・リネーム・削除
- フォルダをタップでカレントディレクトリ移動
- フォルダノード右側の「GeoPackage追加」ボタン（＋）から、任意の場所に新規GeoPackageファイルを即作成・追加可能
- GeoPackageノード（gpkgパネル）はタップで配下レイヤリストをトグル展開可能
- **地図操作ツールバーで「てのひら」「ペン」「選択」などのツールを切り替え可能。**
- **ペン入力（スタイラス）とタップ入力（指・マウス）で挙動を分岐し、ペンはフリーハンド描画、タップは点追加や選択など直感的な操作性を実現。**

## 主要ファイルとクラス
- `lib/models/geopackage.dart`: Layer, GeoPackageGroup, LayerManager（meta.json連携）
- `lib/utils/meta_data.dart`: meta.json全体の読み書き・可視状態・設定管理（MetaDataクラス）
- `lib/utils/folder_tree.dart`: FolderNode（サブフォルダツリー）
- `lib/widgets/layer_drawer.dart`: レイヤ構造Drawer本体。`LayerDrawer`（StatefulWidget）、`LayerDrawerTitleBar`（タイトルパネルWidget）などを実装。
- `lib/screens/map_page.dart`: KMapsHomePage（画面本体、LayerManager/Drawer連携）
- `lib/models/folder_node.dart`: FolderNode（サブフォルダツリー）・scanProjectFolder（.gpkgファイルもchildrenにLayerTreeNode(nodeType: "gpkg")として追加する実装）
- `lib/utils/global_config.dart`: GlobalConfigクラス。プロジェクトのルートディレクトリやmeta.json（MetaDataインスタンス）、**現在のツール（currentTool: MapTool）**などのグローバル変数・設定を一元管理。
- `lib/models/layer_tree_node.dart`: フォルダ/GeoPackage/レイヤのノード構造を定義。
- `lib/models/layer.dart`: レイヤ情報のモデル。

### クラス構成
- `LayerTreeNode`：サブフォルダ・GeoPackage・レイヤ共通の抽象クラス。親・子・可視状態・パス取得・再帰可視切替などを統一インターフェースで提供。
  - **各サブクラスでbaseIcon/baseIconColorをoverrideし、UI側はnode.baseIcon/node.baseIconColorを呼ぶだけで種別ごとのアイコン描画が可能。**
- `FolderNode`/`GeoPackageGroup`/`Layer`：LayerTreeNodeを実装し、ツリー構造を再帰的に表現。
- `LayerManager`：GeoPackage/Layerの全体管理。MetaDataを持ち、可視状態や設定をmeta.jsonと同期。
- `MetaData`：meta.json全体（layerTree, general, gps, toolProperties等）を一元管理。可視状態APIもここに統合。
- `LayerDrawer`：LayerTreeNodeのchildrenを再帰的に描画する方式でUIを構築。可視状態切替も共通化。
- `GlobalConfig`: プロジェクト全体のグローバル変数・設定（ルートディレクトリパス、MetaDataインスタンス等）をシングルトンで管理。
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

## 主なクラス構成
- LayerTreeNode: レイヤツリーの基底クラス。ノード種別（folder/gpkg/layer）を持つ。
  - FolderNode: フォルダノード。childrenTypeは["folder", "gpkg"]。
  - GeoPackageNode: GeoPackageファイルノード。childrenTypeは["layer"]。
  - PointLayerNode/LineLayerNode/PolygonLayerNode: 各ジオメトリタイプのレイヤノード。

## ノード生成の流れ
- LayerTreeNode.createNodeByType(nodeType, logicalPath, parent: ...):
  logicalPathで指定されたパスの単一ノード（LayerTreeNode?）を返す（見つからなければnull）。
  nodeType="folder"の場合: 指定パスが存在すればFolderNodeを返す。
  nodeType="gpkg"の場合: 指定パスが存在すればGeoPackageNodeを返す。
  nodeType="layer"の場合: parentがGeoPackageNodeであれば、logicalPathの末尾をテーブル名としてレイヤノードを返す。