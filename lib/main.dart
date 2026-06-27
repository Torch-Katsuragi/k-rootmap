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
import 'dart:async';

import 'package:root_maps/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/party/party_firebase.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'i18n/strings.g.dart';
import 'screens/home_screen.dart';
import 'screens/map_page/map_page.dart';
import 'core/path_resolver.dart';
import 'providers/project_providers.dart';
import 'providers/ui_state_providers.dart';
import 'providers/selection_providers.dart';
import 'providers/service_providers.dart';
import 'providers/drawing_provider.dart';
import 'models/nodes/feature_node.dart';
import 'services/internal_gps_location_store.dart';
import 'utils/background_save_manager.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _setupErrorHandlers();
  _setupDebugPrintFilter();

  // Android: ナビゲーションバー（◁□○）を非表示にする（ステータスバーは維持）
  if (Platform.isAndroid) {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
    // ジェスチャーでナビバーが表示された後、自動的に再非表示にする
    SystemChrome.setSystemUIChangeCallback((systemOverlaysAreVisible) async {
      if (systemOverlaysAreVisible) {
        await Future.delayed(const Duration(seconds: 3));
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: [SystemUiOverlay.top],
        );
      }
    });
  }

  // 言語設定: 保存値があればそれを使用、なければ端末の言語設定を自動検出
  await _initLocale();

  // 位置共有(パーティ機能)用のFirebase初期化を**非ブロッキングで**温める。
  // 山岳=常時オフライン前提のため、await せず起動クリティカルパスから外す
  // （runAppをブロックしない＝オフラインでも地図画面まで確実に到達できる）。
  // 実際の完了待ちはパーティ機能の入口（createRoom/joinRoom）で行う。
  unawaited(PartyFirebase.ensureInitialized());

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(
    TranslationProvider(
      child: const ProviderScope(child: RootMapsApp()),
    ),
  );
}
/// 言語設定のSharedPreferencesキー
const kAppLocaleKey = 'app_locale';

/// 言語設定を初期化
/// 保存値がなければ端末から自動検出して初期値を設定
Future<void> _initLocale() async {
  final prefs = await SharedPreferences.getInstance();
  final savedLocale = prefs.getString(kAppLocaleKey);

  if (savedLocale != null) {
    // 保存済みの言語設定を使用
    final locale = AppLocale.values.where((l) => l.languageCode == savedLocale).firstOrNull;
    if (locale != null) {
      LocaleSettings.instance.setLocale(locale);
      return;
    }
  }

  // 保存値がない場合は端末の言語設定を自動検出して初期値に設定
  LocaleSettings.useDeviceLocaleSync();
  // 検出結果を保存（次回起動時に使用）
  await prefs.setString(kAppLocaleKey, LocaleSettings.currentLocale.languageCode);
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
        AppLogger.debug('[Root Maps] IME関連キーイベント不整合を無視');
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

class RootMapsApp extends ConsumerStatefulWidget {
  const RootMapsApp({super.key});

  @override
  ConsumerState<RootMapsApp> createState() => _RootMapsAppState();
}

class _RootMapsAppState extends ConsumerState<RootMapsApp>
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
    // UIスケールを早期に読み込み
    await ref.read(uiScaleLevelProvider.notifier).load();

    // シングルトンサービスにRefを注入（プロバイダ初回読み込みでsetRef()が呼ばれる）
    ref.read(drawingStateProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(gpsManagerServiceProvider).initialize();
        AppLogger.debug('[Root Maps] GPS管理サービス初期化完了（待機状態）');
      } catch (e) {
        AppLogger.debug('[Root Maps] GPS管理サービス初期化エラー: $e');
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(baseMapServiceProvider).initialize();
        AppLogger.debug('[Root Maps] 背景地図サービス初期化完了');
      } catch (e) {
        AppLogger.debug('[Root Maps] 背景地図サービス初期化エラー: $e');
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
    AppLogger.debug('[Root Maps] アプリ終了クリーンアップ開始');
    try {
      await InternalGpsLocationStore().dispose();
      await BackgroundSaveManager.instance.dispose();
      ref.read(gpsManagerServiceProvider).dispose();
      AppLogger.debug('[Root Maps] アプリ終了クリーンアップ完了');
    } catch (e) {
      AppLogger.debug('[Root Maps] クリーンアップエラー: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaleLevel = ref.watch(uiScaleLevelProvider);
    final scaleFactor = ref.read(uiScaleLevelProvider.notifier).scaleFactor;
    // scaleLevel を使用して依存関係を確立（watchで再構築をトリガー）
    assert(scaleLevel >= 0);

    return MaterialApp(
      title: 'RootMap GIS',
      locale: TranslationProvider.of(context).flutterLocale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      builder: (context, child) {
        if (scaleFactor == 1.0) return child!;
        final mq = MediaQuery.of(context);
        // 論理サイズを逆スケールして、Transform.scaleで拡大した時に
        // 実際の画面サイズにぴったり収まるようにする
        return MediaQuery(
          data: mq.copyWith(
            size: mq.size / scaleFactor,
            padding: mq.padding / scaleFactor,
            viewInsets: mq.viewInsets / scaleFactor,
            viewPadding: mq.viewPadding / scaleFactor,
          ),
          child: FractionallySizedBox(
            widthFactor: 1.0 / scaleFactor,
            heightFactor: 1.0 / scaleFactor,
            alignment: Alignment.topLeft,
            child: Transform.scale(
              scale: scaleFactor,
              alignment: Alignment.topLeft,
              child: child,
            ),
          ),
        );
      },
      home: const HomeScreen(),
      routes: {'/map': (context) => const RootMapsHomePage()},
    );
  }
}
