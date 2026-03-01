/// K-MAPS: LayerDrawer関連の拡張メソッド
library;

import 'package:path/path.dart' as p;
import '../../models/geopackage/geopackage_file.dart';

/// GeoPackageFileの絶対パス取得用拡張メソッド
extension GeoPackageFilePathExt on GeoPackageFile {
  String? getAbsolutePathFromRoot(String? projectRootDir) {
    if (projectRootDir == null) return null;
    return p.joinAll([projectRootDir, ...pathList]);
  }
}
