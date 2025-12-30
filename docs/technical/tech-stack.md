---
title: 技術スタック
tags: [technical, stack, flutter]
---

# 技術スタック

## フロントエンド

- **Flutter (Dart)**
  - クロスプラットフォーム対応 (iOS, Android)
  - 豊富なUIライブラリと描画API

## 状態管理

- Riverpod, Provider, BLoC/Cubitなど (Flutterでの標準的な選択肢)

## GeoPackage操作ライブラリ (Dart)

- `geopackage_dart`: (もし存在すれば。なければSQLiteライブラリとGeoPackage仕様に基づき自作または既存のものを探す)
- `sqlite3` / `drift`: GeoPackageの実体はSQLiteデータベースなので、これらのライブラリで直接操作も可能。

## 地図表示

- `flutter_map`: 高いカスタマイズ性を持つ地図ライブラリ。オフライン対応や多様なタイルソース利用に適している。

## GPS

- `geolocator`, `location` などのFlutterプラグイン。

## Google Drive連携

- `googleapis` パッケージ (Google Drive API v3)
- `google_sign_in` プラグイン

## バックエンド (オプション)

- もし高度な共有機能やユーザー管理が必要な場合は、Firebase (Firestore, Authentication, Storage) などを検討。

## 地図操作ツール管理

- MapTool抽象クラス＋個別ツールクラス（PanTool, PenTool, SelectTool等）＋GlobalConfigで一元管理。

## 入力デバイス判別

- PointerEventのkindプロパティでペン/タップ/マウスを判別し、ツールごとに挙動を分岐。

---

# フリーハンド描画の実装詳細

フリーハンドでの線・領域描画は、以下のFlutter技術要素を組み合わせて実装する。

## ジェスチャー検出 (`GestureDetector`)

- `onPanStart`: 描画開始点を記録。
- `onPanUpdate`: ドラッグ中の座標を連続的に記録。
- `onPanEnd`: 描画終了処理、ジオメトリ確定。

## 描画処理 (`CustomPaint` と `CustomPainter`)

- 記録された座標リストに基づき、Canvasオブジェクトに線（Path）を描画する。
- `onPanUpdate`の度に`setState`を呼び出し、リアルタイムに描画を更新する。

## 座標管理

- 描画中の座標は一時的なリスト（例: `List<Offset>`）に保持する。
- 地図のズームレベルや表示範囲の変更に対応するため、画面座標と地理座標（緯度経度）の相互変換が必要 (`flutter_map`の機能を利用)。

## 線の平滑化 (オプション)

- より自然な曲線にするため、記録した座標点間にベジェ曲線やスプライン補間を適用することを検討。
- Flutterの`Path`オブジェクトはベジェ曲線描画メソッド（`quadraticBezierTo`, `cubicTo`）を持つ。

## GeoPackageへの保存

- 描画完了後、得られた地理座標のリストをLineStringまたはPolygonのジオメトリデータ（WKT: Well-Known Text や WKB: Well-Known Binary形式）に変換。
- 変換したジオメトリデータを、属性情報と共にGeoPackageの該当レイヤーにフィーチャとして保存する。

## 領域の描画

- 線の描画と同様の仕組みで境界線をフリーハンドで描画。
- 描画完了時にパスが閉じていなければ自動的に閉じるか、ユーザーに促す。
- 閉じたパスからPolygonジオメトリを生成する。

## 関連ドキュメント

- [[../features/drawing-editing]] - 描画・編集機能
- [[import-export]] - Import/Exportアーキテクチャ

