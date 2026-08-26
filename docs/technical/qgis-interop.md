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

## `.qgs`（QGISプロジェクト）の書き出し

実装は `lib/services/qgis/`、テストは `test/qgs_writer_test.dart`。
設計の背景は [[project-format-design#View の導入]]。

```
QgsProjectBuilder   ツリーを辿って QgsProject を組み立てる（DB・FSに触る）
QgsProject / QgsLayer / QgsGroup   XMLと切り離した表現
QgsWriter           XMLにする（純粋関数。DBもFSも要らないのでテストしやすい）
```

対応:

| RootMap | QGIS |
|---|---|
| dir | レイヤグループ |
| GeoPackage | レイヤグループ |
| Layer | レイヤグループ |
| **View** | **レイヤ**（`layer-tree-layer` + `maplayer`） |

View だけがレイヤになるので **1:1 対応**が成立する。View のフィルタは OGR の
データソースURIに `|subset=` として載る（QGIS が subset string を書く場所と同じ）。

出力先は `<dir>/project.qgs`。**連携dirごとに1本**置く。パスは相対
（`<Absolute type="bool">false</Absolute>`）なので、そのdirを丸ごと渡された人が
そのdirだけで開ける。

> [!IMPORTANT] レイヤIDは決定的に作る
> 生成のたびに変わると `.qgs` の差分が毎回出て、Drive同期が無駄に動く。
> View のキーをサニタイズしたものに、キーのハッシュを添えている。

> [!WARNING] QGISで実際に開けるかは未検証（2026-08-26 時点）
> 開発機にQGISが入っていないため確かめられていない。テストで見ているのは
> **XMLの形まで**（グループ構造・IDの一致・subsetの載り方・相対パス）。
>
> 確かめたら結果をここに書くこと。落ちるとしたら候補は `renderer-v2` の
> シンボルXML。スタイル未設定のレイヤにはレンダラを書かない作りなので、
> 疑わしければ一度スタイルを外して切り分けられる。

書かないもの（`QgsProject.skipped` に入り、通知に出る）:

- 画像・オーバーレイ画像（QGISのラスタレイヤには落とせるが未対応）
- プロジェクトフォルダの**外**を参照する `.gpkg`
  （渡された相手の環境には無いので、残すと「レイヤはあるが表示されない」になる）

## `.qgs` の読み込み（寛容側）

実装は `lib/services/qgis/qgs_importer.dart`、テストは `test/qgs_importer_test.dart`。

**一度読んで変換して捨てる。** `.qgs` を正典として持たない。
`<maplayer>` を1枚ずつ見て、飲めるものを View にする。

ルール:

1. **root外への参照は丸ごと捨てる。** `C:\work\data.shp` やPostGIS接続を指すレイヤは
   山の中のスマホでは開けない。残すと「レイヤはあるが表示されない」最悪の状態になる
   - ⚠ 相対パスで root 外を指すケース（`../shared/kyoyu.gpkg`）は林業では現実にありそう。
     判定は**正規化した絶対パス**で行う
2. **QGISのグループ階層は採らない。** レイヤ構造は dir 構造に置き換える
   （`.gpkg` の実在パスで既存ツリーのレイヤに突き合わせる）
3. **生き残った参照のスタイルは View として再利用する。**
   同じレイヤを指すQGISレイヤがN枚あれば **N個の View** になる。
   ここが View を入れた最大の理由で、これが無いと「1枚選んで残りを捨てる」しかなかった
4. **捨てたものは必ず報告する**（`QgsImportResult.discarded` → 通知）

> [!IMPORTANT] 取り込んだレイヤの View は丸ごと置き換える
> 何度読んでも増えないようにするため。`.qgs` に出てこなかったレイヤは触らない。

> [!NOTE] 読み取りは寛容に
> - シンボルのプロパティは QGIS 3.x の `<Option name= value=>` と、
>   それ以前の `<prop k= v=>` の**両方**を読む。他人のファイルは古い形式で来る
> - 拾うのは単一シンボルの1レイヤ目だけ。重ね合わせや分類分けの完全再現は狙わない。
>   狙うと「開けるファイルを選り好みする」方向に行く（コンセプトと逆）
> - `subset` は `|` で切らずに**最後まで丸ごと**取る（SQLの `||` で壊れるため）

読み込み口はファイル選択ダイアログではなく「**このフォルダの中の `.qgs`**」。
共有の単位が dir なので、それで足りる。複数あれば `project.qgs` を優先。

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
