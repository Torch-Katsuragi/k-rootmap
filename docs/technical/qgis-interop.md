---
title: QGIS相互運用
tags: [technical, geopackage, qgis, interop]
---

# QGIS相互運用

RootMap GIS は「ユーザーの `.gpkg` をそのまま読み書きする」ことを identity にしている
（[[../features/concept|コンセプト]]）。変換もパッケージ化も要求しないのが競合に対する差なので、
**編集して返したファイルが QGIS で普通に開けること**が要件になる。

ここは「編集中には邪魔だが QGIS 側では必要」というものの面倒を見る仕組み。
実装は `lib/models/geopackage/qgis_interop.dart`、テストは `test/qgis_interop_test.dart`。

## いつ走るか

`GeoPackageFile.dispose()` の中、**全ての書き込みが終わったあと・DBを閉じる直前**。

```
dispose()
  ├ flushChanges()              保留中の変更を書ききる
  ├ clearPendingChanges()
  ├ _finalizeForQgis()          ← ここ
  │   ├ QgisInterop.syncAllLayers()   範囲と件数を実データに合わせる
  │   └ qgisInterop.restoreTriggers() SpatiaLiteトリガーを戻す
  └ _connection.dispose()
```

> [!WARNING] トリガー復元は必ず最後
> 復元後に書き込むと、sqflite に `ST_IsEmpty` 等が無いため落ちる。
> 順序を入れ替えないこと。

## 1. SpatiaLiteトリガーの復元

QGIS/GDAL 製の GeoPackage は RTree を自動更新するトリガーを持ち、
それらは `ST_IsEmpty` / `ST_MinX` 等の **SpatiaLite 関数**を使う。
sqflite にその拡張は無いので、RootMap は書き込み前にトリガーを落とし、
rtree は `SpatialIndexManager` が自前で更新している。

> [!IMPORTANT] 落としたまま返してはいけない
> トリガーが無いまま QGIS に戻すと、**その後 QGIS で編集しても空間インデックスが
> 更新されない**。インデックスと実データがズレて、空間検索の結果が欠ける。

対処: 落とす前に `sqlite_master` の `sql` を控えておき、クローズ時に**逐語的に**戻す。

規格から生成し直さない理由は、RTreeトリガーの構成が GDAL のバージョンで違うため
（`update1`〜`update7` 等）。生成し直すと元と違うものを書き込むことになる。

⚠ アプリが強制終了した場合は控えが失われ、トリガーが落ちたまま残る。
これは対処前と同じ状態なので退行ではないが、既知の穴。

## 2. `gpkg_contents` のバウンディングボックス

QGIS はここをレイヤの範囲として使う。空だと「レイヤにズーム」が効かない。

RootMap は新規レイヤ作成時に `min_x`/`min_y`/`max_x`/`max_y` を null で入れていたため、
クローズ時に rtree から集計して埋める。

rtree が無い場合はスキップする（全件走査は重く、RootMap は rtree を自前で維持しているので通常は存在する）。

## 3. `gpkg_ogr_contents` のフィーチャ数

GDAL 拡張の件数キャッシュ。RootMap が直接 INSERT/DELETE すると実態とズレる
（GDAL 製ファイルにはこれを維持するトリガーもあるが、上記1で一緒に落ちることがある）。

存在しない GeoPackage もあるので、**無ければ何もしない**。
RootMap が勝手に作ると、逆に GDAL の前提を崩す可能性がある。

## 既にQGISに合わせてある点

- **主キーは `fid`**（QGIS/GDAL標準）。旧 RootMap 形式の `id` も読める
- 任意の EPSG コードに対応（GPKG内蔵WKTから座標系を自動検出）

## 未対応

- **`layer_styles`**（QGISのスタイル保存テーブル）。RootMap で設定した色・線幅は
  QGIS に引き継がれない。逆も同様
- `gpkg_metadata` / `gpkg_metadata_reference`

## テストの注意点

`test/qgis_interop_test.dart` は GDAL 製 GeoPackage を模したフィクスチャを作って検証する。

> [!WARNING] フィクスチャには `PRAGMA user_version = 1` が必要
> 実物の GeoPackage は `user_version=1`（GDAL製・既存ファイルで確認済み）。
> これを立てないと sqflite が「新規DB」とみなして `onCreate` を走らせ、
> 既存テーブルと衝突して `table gpkg_spatial_ref_sys already exists` で落ちる。

## 関連

- [[../features/concept|コンセプト]]
- [[testing|テスト構成]]
