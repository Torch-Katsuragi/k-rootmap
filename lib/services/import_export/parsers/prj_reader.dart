// Root Maps: PRJ Reader
// PRJファイル（座標系定義）の読み込みクラス
import 'dart:io';
import 'package:root_maps/utils/app_logger.dart';
import '../../../utils/coordinate_converter.dart';
import '../coordinate_system_manager.dart';

/// PRJファイルを読み込んで座標系情報を取得するクラス
class PrjReader {
  static final SmartCoordinateSystemManager _crsManager =
      SmartCoordinateSystemManager();

  /// PRJファイルから座標系情報を読み取り
  static Future<CoordinateSystem?> read(String prjFilePath) async {
    try {
      final prjFile = File(prjFilePath);
      if (!prjFile.existsSync()) {
        AppLogger.debug('[PrjReader] PRJファイルが見つかりません: $prjFilePath');
        return null;
      }

      final prjContent = await prjFile.readAsString();
      AppLogger.debug('[PrjReader] PRJファイル読み込み成功');
      AppLogger.debug('[PrjReader] ファイルパス: $prjFilePath');
      AppLogger.debug('[PrjReader] 文字数: ${prjContent.length}文字');

      // スマート座標系マネージャーを使用してWKTを解析
      final coordinateSystem = await _crsManager
          .parseWktToCoordinateSystem(prjContent);

      if (coordinateSystem != null) {
        _crsManager.printCoordinateSystemInfo(coordinateSystem);
        return coordinateSystem;
      } else {
        AppLogger.debug('[PrjReader] スマート座標系解析に失敗');
        return null;
      }
    } catch (e) {
      AppLogger.debug('[PrjReader] PRJファイル読み取りエラー: $e');
      return null;
    }
  }
}

