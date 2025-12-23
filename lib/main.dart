// K-MAPS: エントリーポイント
// 本ファイルはアプリ起動・ルーティングのみを担当
import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'screens/home_screen.dart';
import 'screens/map_page/map_page.dart';
import 'services/foreground_service.dart';
import 'services/gps_manager_service.dart';
import 'services/basemap_service.dart';
import 'utils/background_save_manager.dart';

void main() async {
  // sqflite使用前に必須の初期化処理
  WidgetsFlutterBinding.ensureInitialized();

  // Windows IME関連のキーボードエラーを無視するワークアラウンド
  // Flutter既知の問題: IME使用時に不正なKeyDownEventが発生することがある
  _setupErrorHandlers();

  // デスクトップ環境での sqflite_common_ffi 初期化
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
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

/// エラーハンドラーの設定
/// Windows IME関連のキーボードエラーなど、既知の非致命的エラーを無視
void _setupErrorHandlers() {
  // 元のエラーハンドラーを保存
  final originalOnError = FlutterError.onError;

  FlutterError.onError = (FlutterErrorDetails details) {
    // IME関連のキーボードエラーを無視
    // "A KeyDownEvent is dispatched, but the state shows that the physical key is already pressed"
    final errorString = details.exception.toString();
    if (errorString.contains('KeyDownEvent') &&
        errorString.contains('physical key is already pressed')) {
      // このエラーは静かに無視（デバッグログのみ）
      if (kDebugMode) {
        AppLogger.debug('[K-MAPS] IME関連キーボードイベントを無視');
      }
      return;
    }

    // その他のエラーは通常通り処理
    if (originalOnError != null) {
      originalOnError(details);
    } else {
      FlutterError.presentError(details);
    }
  };
}

/// アプリのルートウィジェット（ライフサイクル監視付き）
class KMapsApp extends StatefulWidget {
  const KMapsApp({super.key});

  @override
  State<KMapsApp> createState() => _KMapsAppState();
}

class _KMapsAppState extends State<KMapsApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// アプリライフサイクル変更時の処理
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.detached) {
      // アプリ終了時のクリーンアップ
      _cleanupOnAppExit();
    } else if (state == AppLifecycleState.paused) {
      // バックグラウンドに移行時：保留中の変更を保存
      BackgroundSaveManager.instance.flushAllChanges();
    }
  }

  /// アプリ終了時のクリーンアップ処理
  Future<void> _cleanupOnAppExit() async {
    AppLogger.debug('[K-MAPS] アプリ終了クリーンアップ開始');
    try {
      // フォアグラウンドサービスを停止
      await ForegroundServiceManager().dispose();

      // 保留中の変更を保存しタイマーをクリーンアップ
      await BackgroundSaveManager.instance.dispose();

      // GPS管理サービスのクリーンアップ
      GpsManagerService().dispose();

      AppLogger.debug('[K-MAPS] アプリ終了クリーンアップ完了');
    } catch (e) {
      AppLogger.debug('[K-MAPS] クリーンアップエラー: $e');
    }
  }

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


