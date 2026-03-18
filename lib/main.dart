import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'screens/home_screen.dart';
import 'screens/map_page/map_page.dart';
import 'core/path_resolver.dart';
import 'providers/project_providers.dart';
import 'providers/selection_providers.dart';
import 'providers/service_providers.dart';
import 'providers/drawing_provider.dart';
import 'models/nodes/feature_node.dart';
import 'services/internal_gps_location_store.dart';
import 'utils/background_save_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _setupErrorHandlers();
  _setupDebugPrintFilter();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const ProviderScope(child: KMapsApp()));
}

void _setupErrorHandlers() {
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final errorString = details.exception.toString();

    // Windows IME切り替え時のキーイベント不整合を握りつぶす
    // (デバッグモードのassertのみ発火、リリースでは無害)
    if (errorString.contains('_pressedKeys') ||
        (errorString.contains('KeyDownEvent') &&
            errorString.contains('physical key is already pressed')) ||
        (errorString.contains('KeyRepeatEvent') &&
            errorString.contains('physical key is not pressed'))) {
      if (kDebugMode) {
        AppLogger.debug('[K-MAPS] IME関連キーイベント不整合を無視');
      }
      return;
    }

    if (originalOnError != null) {
      originalOnError(details);
    } else {
      FlutterError.presentError(details);
    }
  };
}

/// Flutterエンジンが出す「Unable to parse JSON message」を抑制
void _setupDebugPrintFilter() {
  if (!kDebugMode) return;
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null &&
        (message.contains('Unable to parse JSON message') ||
            message.contains('The document is empty'))) {
      return;
    }
    original(message, wrapWidth: wrapWidth);
  };
}

class KMapsApp extends ConsumerStatefulWidget {
  const KMapsApp({super.key});

  @override
  ConsumerState<KMapsApp> createState() => _KMapsAppState();
}

class _KMapsAppState extends ConsumerState<KMapsApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupGlobalCallbacks();
    _initializeServices();
  }

  void _setupGlobalCallbacks() {
    ProjectPathResolver.instance.setRootPathGetter(
      () => ref.read(projectRootDirProvider),
    );
    GlobalPathResolver.instance.setRootPathGetter(
      () => ref.read(globalFolderPathProvider),
    );
    FeatureNode.setOnDisposeCallback((node) {
      final features = ref.read(selectedFeaturesProvider);
      if (features.contains(node)) {
        ref.read(selectedFeaturesProvider.notifier).remove(node);
      }
    });
  }

  Future<void> _initializeServices() async {
    // シングルトンサービスにRefを注入（プロバイダ初回読み込みでsetRef()が呼ばれる）
    ref.read(drawingStateProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(gpsManagerServiceProvider).initialize();
        AppLogger.debug('[K-MAPS] GPS管理サービス初期化完了（待機状態）');
      } catch (e) {
        AppLogger.debug('[K-MAPS] GPS管理サービス初期化エラー: $e');
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(baseMapServiceProvider).initialize();
        AppLogger.debug('[K-MAPS] 背景地図サービス初期化完了');
      } catch (e) {
        AppLogger.debug('[K-MAPS] 背景地図サービス初期化エラー: $e');
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.detached) {
      _cleanupOnAppExit();
    } else if (state == AppLifecycleState.paused) {
      BackgroundSaveManager.instance.flushAllChanges();
    }
  }

  Future<void> _cleanupOnAppExit() async {
    AppLogger.debug('[K-MAPS] アプリ終了クリーンアップ開始');
    try {
      await InternalGpsLocationStore().dispose();
      await BackgroundSaveManager.instance.dispose();
      ref.read(gpsManagerServiceProvider).dispose();
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
