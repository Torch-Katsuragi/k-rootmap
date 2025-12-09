// K-MAPS: エントリーポイント
// 本ファイルはアプリ起動・ルーティングのみを担当
import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'screens/home_screen.dart';
import 'screens/map_page.dart';
import 'services/foreground_service.dart';
import 'services/gps_manager_service.dart';
import 'services/basemap_service.dart'; // 追加

void main() async {
  // sqflite使用前に必須の初期化処理
  WidgetsFlutterBinding.ensureInitialized();

  // デスクトップ環境での sqflite_common_ffi 初期化
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // sqflite_common_ffi を初期化
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // GPS管理サービスの初期化（待機状態）
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await GpsManagerService().initialize();
      AppLogger.debug('[K-MAPS] GPS管理サービス初期化完了（待機状態）');
    } catch (e) {
      AppLogger.debug('[K-MAPS] GPS管理サービス初期化エラー: $e');
    }
  });

  // 背景地図サービスの初期化
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await BaseMapService().initialize();
      AppLogger.debug('[K-MAPS] 背景地図サービス初期化完了');
    } catch (e) {
      AppLogger.debug('[K-MAPS] 背景地図サービス初期化エラー: $e');
    }
  });

  // フォアグラウンドサービスの初期化（遅延実行に変更）
  // アプリ起動後に初期化してメインIsolate競合を回避
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await ForegroundServiceManager.initializeService();
      AppLogger.debug('[K-MAPS] フォアグラウンドサービス初期化完了');
    } catch (e) {
      AppLogger.debug('[K-MAPS] フォアグラウンドサービス初期化エラー: $e');
    }
  });

  runApp(const KMapsApp());
}

class KMapsApp extends StatelessWidget {
  const KMapsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'K-MAPS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      routes: {'/map': (context) => const KMapsHomePage()},
    );
  }
}


