# TODO List

## 完了済み

- [x] READMEの整理（更新履歴の削除と機能概要の統合）
- [x] 背景地図の機能改善
  - [x] 一括ダウンロード機能（範囲・ズーム指定）の実装
  - [x] ダウンロードの並列処理化（4スレッド）と進捗バー表示
  - [x] オフライン時のフォールバック処理の最適化（親タイル拡大表示の高速化）
  - [x] ネットワーク接続状態検知による無駄なリクエスト抑制（圏外対策）
  - [x] 航空写真（JPEG）タイルのダウンロード対応
- [x] 設定画面のUI統一（共通ウィジェットテンプレート作成）
- [x] 不要な型チェック・キャストの削除
  - [x] map_page.dart
  - [x] feature_converter.dart
  - [x] import_export_service.dart
- [x] 非推奨APIの更新（一部）
  - [x] withOpacity → withValues()
  - [x] onPopInvoked → onPopInvokedWithResult

## コード品質改善

### 優先度：高（安全性・正確性）

- [x] BuildContextの非同期使用問題の修正
  - [x] gps_settings_screen.dart
  - [x] map_page.dart
  - [x] layer_drawer.dart
  - [x] layer_drawer_tiles.dart
  - [x] dynamic_attribute_table_widget.dart
  - [x] camera_screen.dart
  - [x] dialog_manager.dart（元々修正済み）
  - [x] gps_tracking_dialogs.dart（元々修正済み）
  - [x] metadata_table_dialog.dart
  - [x] gps_manager_example.dart

### 優先度：中（非推奨API・未使用コード）

- [ ] 非推奨APIの更新（残り）
  - [ ] DropdownButtonFormField value → initialValue
  - [ ] Radio groupValue/onChanged → RadioGroup
- [ ] 未使用importの削除（主要ファイル）

### 優先度：低（スタイル改善）

- [ ] print()をロギングフレームワークに置換
- [ ] その他のスタイル問題修正

## 機能改善

- [ ] フィードバックフォームにバージョン情報を事前入力
  - Google FormsのURLパラメータを使用して、アプリバージョンを埋め込む
  - フォームを開いたときにバージョン情報が入力済みの状態で表示される
