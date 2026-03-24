/// フォルダパスの検証ユーティリティ
library;

import 'package:path/path.dart' as p;

/// 2つのパスに含有関係（片方が片方のサブディレクトリ）があるかを判定
///
/// Windows: 大文字小文字を無視して正規化比較
/// Returns: 含有関係がある場合は警告メッセージ、なければnull
String? checkContainmentRelation(String path1, String path2) {
  final norm1 = p.normalize(path1).toLowerCase();
  final norm2 = p.normalize(path2).toLowerCase();
  if (norm1 == norm2) {
    return 'Global folder and project folder point to the same directory.';
  }
  final sep = p.separator;
  if (norm1.startsWith('$norm2$sep')) {
    return 'Global folder is inside the project folder.\n'
        'This may cause unexpected behavior.';
  }
  if (norm2.startsWith('$norm1$sep')) {
    return 'Project folder is inside the global folder.\n'
        'This may cause unexpected behavior.';
  }
  return null;
}
