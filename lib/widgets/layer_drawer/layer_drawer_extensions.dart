/// K-MAPS: LayerDrawer関連の拡張メソッド
library;

import 'package:path/path.dart' as p;
import '../../models/geopackage_file.dart';
import '../../utils/global_config.dart';

/// GeoPackageFileの絶対パス取得用拡張メソッド
extension GeoPackageFilePathExt on GeoPackageFile {
  /// projectRootDir + pathList で絶対パスを返す
  String? getAbsolutePath() {
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) return null;
    return p.joinAll([root, ...pathList]);
  }
}
