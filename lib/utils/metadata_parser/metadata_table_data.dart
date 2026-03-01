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
