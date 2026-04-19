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
/// メタデータパース結果
class MetadataTableData {
  /// テーブルのヘッダー（列名）
  final List<String> headers;

  /// テーブルのデータ行（各行は各列の値のリスト）
  final List<List<String>> rows;

  /// メタデータタイプ
  final String type;

  /// 表示用タイトル
  final String title;

  /// 座標系選択肢（EPSGコード -> 座標系名のマップ）
  final Map<String, String>? coordinateSystemOptions;

  /// 現在選択されている座標系のEPSGコード
  final String? selectedCoordinateSystem;

  const MetadataTableData({
    required this.headers,
    required this.rows,
    required this.type,
    required this.title,
    this.coordinateSystemOptions,
    this.selectedCoordinateSystem,
  });

  /// 座標系を変更した新しいMetadataTableDataを作成
  MetadataTableData copyWithCoordinateSystem(String newEpsgCode) {
    return MetadataTableData(
      headers: headers,
      rows: rows,
      type: type,
      title: title,
      coordinateSystemOptions: coordinateSystemOptions,
      selectedCoordinateSystem: newEpsgCode,
    );
  }
}
