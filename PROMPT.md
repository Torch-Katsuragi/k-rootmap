# PROMPT.md

**K-MAPS プロジェクト固有の開発指示書**

---

## プロジェクト概要

**K-MAPS** は「お絵描きアプリのような直感的な操作性で、誰でも気軽にGeoPackageデータを編集・作成できるモバイルアプリ」です。

### コアバリュー
- **直感的なUI/UX**: Adobe Frescoのようなツール切り替えやレイヤー操作
- **手軽さ**: 専門知識がなくても地図上にお絵描きする感覚で地理空間データを作成・編集
- **モバイルファースト**: GPS連携やタッチ操作に最適化
- **Googleエコシステム連携**: Google Driveでの同期・共有

---

## 開発指針

### 1. アーキテクチャ遵守
現在のアーキテクチャを維持し、以下のパターンを活用してください：

#### 主要クラス構成
- **GlobalConfig**: アプリケーション設定とシングルトン管理
- **GlobalDrawingState**: 描画状態の共有管理（自動保存機能含む）
- **ツール系統**: PanTool, PenTool, GpsTool, SelectTool
- **データ階層**: LayerTreeNode → FeatureNode構造
- **サービス層**: GpsManagerService, BaseMapService, ForegroundService

#### デザインパターン
- **Singleton**: GlobalConfig, GlobalDrawingState
- **Factory**: FeatureNode作成
- **Strategy**: ツール切り替え
- **Observer**: 状態変更通知

### 2. コーディング規約

#### 基本方針
- **再利用性と保守性を重視**し、デザインパターンを意識して実装
- **デバッグ出力を最適化**し、エラー原因の特定に活用
- **親切にコメント**をつけ、将来の保守性を確保
- **テストコード**を書いてログファイルに出力しながら実装を進める

#### APIの使用
- 既存のAPIで利用できるものがないかチェック
- 必要に応じて新しいAPIを追加
- 統一されたインターフェースを提供（例：`undo({required bool isLine})`）

#### エラーハンドリング
- 非同期処理での例外キャッチを徹底
- ユーザーフレンドリーなエラーメッセージ
- デバッグログの充実

### 3. 実装時の注意点

#### ジオメトリタイプ仕様
OGC Simple Features準拠で以下の3種類をサポート：
- **Point**: 点の集合
- **LineString**: 線分の集合  
- **Polygon**: ポリゴンの集合

#### 描画機能
- **フリーハンド描画**: ペン入力（スタイラス）対応
- **タップ入力**: 点追加や選択操作
- **PointerEvent.kind**でペン/タップ/マウスを判別し挙動を分岐

#### GPS機能
- 現在位置表示・追跡
- 測量点の記録（メタデータ付き）
- バックグラウンド動作対応

#### レイヤー管理
- フォルダ構造とGeoPackageファイルに連動
- 階層的なレイヤー/レイヤーグループ管理
- Adobe Frescoライクな直感的操作

---

## 技術スタック

### フロントエンド
- **Flutter (Dart)**: クロスプラットフォーム対応
- **状態管理**: Riverpod/Provider/BLoC
- **地図表示**: `flutter_map`（オフライン対応）
- **GPS**: `geolocator`, `location`

### データ管理
- **GeoPackage**: SQLiteベースの地理空間データ
- **SQLite**: `sqlite3`, `drift`ライブラリ使用
- **プロジェクト管理**: フォルダベースの階層構造

### 外部連携
- **Google Drive**: `googleapis`, `google_sign_in`
- **Git**: バージョン管理対応（将来予定）

---

## 開発フロー

### テスト駆動開発
1. **テストコードを先に作成**
2. **ログファイルに出力**してテスト実行
3. **実装を進めながらテストを確認**
4. **リファクタリングで品質向上**

### デバッグ手法
- シェル出力の読み取りが困難なため、**ログファイル出力を活用**
- エラー原因の特定に必要な情報を漏れなく記録
- デバッグ出力を段階的に最適化

### 仮想環境の使用
- 可能な限り仮想環境での開発を推奨
- 依存関係の管理を明確化

---

## プロジェクト管理

### README.mdの活用
- **メモ代わり**として使用
- **主要ファイルとクラス構成の詳細**をリアルタイムで更新
- 最新の更新履歴を継続的に記録

### 開発ステップ
現在はMVP段階を超え、フェーズ2-3の機能実装中：
- フリーハンド描画機能（完了）
- 階層的レイヤー管理（完了）
- フィーチャ追記・編集機能（完了）
- **次のステップ**: Google Drive連携の強化、計測ツール

---

## 重要なAPI・メソッド

### GlobalDrawingState主要メソッド
```dart
// 描画操作
void addLinePoint(LatLng, Map<String, dynamic>?)
void addPolygonPoint(LatLng, Map<String, dynamic>?)
void undo({required bool isLine})
void cancel({required bool isLine})

// フィーチャ確定
Future<bool> confirmCurrentFeature(...)
Future<bool> confirmLineFeature(...)
Future<bool> confirmPolygonFeature(...)

// 追記モード
void startEditingLineFeature(LineFeatureNode)
void startEditingPolygonFeature(PolygonFeatureNode)

// 自動保存
void setAutoSaveLayerNode(LayerNode?, void Function()?)
```

### FeatureNode更新API
```dart
// ジオメトリ更新
Future<bool> updateGeometry(...)
Future<bool> delete()

// ファクトリメソッド
static Future<FeatureNode> createIn(LayerNode, ...)
```

---

## 開発上の留意点

### UI/UX設計
- **モバイルファースト**：タッチ操作に最適化
- **直感的操作**：学習コストを最小化
- **ツール切り替え**：「てのひら」「ペン」「選択」の明確な区別

### パフォーマンス
- 大量の描画データでも滑らかな操作
- メモリ効率的なデータ管理
- バックグラウンド処理の適切な制御

### 拡張性
- 新しいツールやレイヤータイプの追加を容易に
- プラグイン機能の将来的な対応
- 国際化対応の準備

---

**このPROMPT.mdは、K-MAPSプロジェクトの開発効率と品質向上のための指針です。実装時は常にこの指示を参照し、プロジェクトの一貫性を保ってください。** 