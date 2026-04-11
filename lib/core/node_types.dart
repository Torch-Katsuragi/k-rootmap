// Root Maps: ノードタイプの型安全な定義
// 文字列による管理をenumに置き換え、型安全性と拡張性を向上

/// レイヤツリーノードの種別を表すenum
/// 
/// 各ノードタイプは以下のカテゴリに分類される：
/// - コンテナ系: folder, geopackage
/// - データ系: layer, feature
/// - メディア系: image
enum NodeType {
  /// フォルダノード（ファイルシステムのディレクトリに対応）
  folder('folder'),
  
  /// GeoPackageノード（.gpkgファイルに対応）
  geopackage('gpkg'),
  
  /// レイヤノード（GeoPackage内のフィーチャテーブルに対応）
  layer('layer'),
  
  /// フィーチャノード（レイヤ内の個別フィーチャに対応）
  feature('feature'),
  
  /// 画像ノード（位置情報付き画像ファイルに対応）
  image('image');

  /// 文字列表現（後方互換性のため）
  final String value;
  
  const NodeType(this.value);
  
  /// 文字列からNodeTypeへの変換
  /// 不明な値の場合はnullを返す
  static NodeType? fromString(String value) {
    // 後方互換性: "photo" は "image" として扱う
    if (value == 'photo') {
      return NodeType.image;
    }
    
    for (final type in NodeType.values) {
      if (type.value == value) {
        return type;
      }
    }
    return null;
  }
  
  /// 文字列からNodeTypeへの変換（例外を投げるバージョン）
  static NodeType fromStringOrThrow(String value) {
    final type = fromString(value);
    if (type == null) {
      throw ArgumentError('Unknown NodeType: $value');
    }
    return type;
  }
  
  /// このノードタイプがコンテナ（子を持てる）かどうか
  bool get isContainer => this == folder || this == geopackage || this == layer;
  
  /// このノードタイプがリーフ（子を持たない）かどうか
  bool get isLeaf => !isContainer;
  
  /// このノードタイプがファイルシステムに対応するかどうか
  bool get hasFileSystemPath => this == folder || this == geopackage || this == image;
  
  /// 表示用の名前（日本語）
  String get displayName {
    switch (this) {
      case NodeType.folder:
        return 'フォルダ';
      case NodeType.geopackage:
        return 'GeoPackage';
      case NodeType.layer:
        return 'レイヤ';
      case NodeType.feature:
        return 'フィーチャ';
      case NodeType.image:
        return '画像';
    }
  }
  
  @override
  String toString() => value;
}
