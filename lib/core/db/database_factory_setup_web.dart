// Copyright (C) 2024-2026 Torch-Katsuragi
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
/// web の sqflite セットアップ（sqlite3 WASM）。
///
/// > [!IMPORTANT] `web/sqlite3.wasm` と `web/sqflite_sw.js` が要る
/// > `dart run sqflite_common_ffi_web:setup` が置く。消すと web で
/// > GeoPackage が一切開けなくなる。
///
/// ⚠ ここで開くDBはブラウザ内のストレージであって、ユーザーが選んだ
/// フォルダの `.gpkg` そのものではない。元ファイルとの受け渡しは
/// `GeoPackageConnection` のチェックアウト／チェックインが行う。
library;

import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

void setupDatabaseFactory() {
  databaseFactory = databaseFactoryFfiWeb;
}
