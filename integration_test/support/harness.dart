/// 統合テストをWindows/Androidの両方で走らせるための共通ヘルパ。
///
/// Windows版の復活作業では「Windowsを直したらAndroidが壊れた」という事故が
/// 最大のリスクになる。そのため統合テストは原則として **同じテストを両方の
/// プラットフォームで走らせる**。プラットフォーム固有の前提が揃っていない
/// 項目だけを、ここで明示的に宣言してスキップする（暗黙に落とさない）。
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';

/// 現在のプラットフォーム名（テスト出力のラベル用）
///
/// ⚠ `Platform` は web では**呼んだ瞬間に** `UnsupportedError` を投げるので、
/// 必ず `kIsWeb` を先に見ること（`lib/core/platform_capabilities.dart` と同じ規約）。
String get platformName {
  if (kIsWeb) return 'web';
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  return 'unknown';
}

/// Firebase の設定が存在するプラットフォームか。
///
/// `lib/firebase_options.dart` は android / ios ぶんしか生成されておらず、
/// それ以外では `DefaultFirebaseOptions.currentPlatform` が UnsupportedError を投げる。
/// Windows/web対応時に `flutterfire configure` へ足したら、ここを更新する。
bool get hasFirebaseConfig => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// maplibre のプラットフォーム実装が存在するか。
///
/// maplibre 0.3.5 が endorse しているのは android / ios / web。
/// Windows/macOS は maplibre_webview を直接依存に入れて opt-in する
/// （2026-08-21 に再導入。案Bの再評価中）。
bool get hasMapBackend =>
    kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isWindows;

/// スキップ理由つきの `skip` 値を作る。
///
/// `testWidgets(..., skip: skipUnless(hasMapBackend, '地図バックエンド未実装'))`
/// のように使う。false（＝スキップしない）か、理由文字列を返す。
Object? skipUnless(bool supported, String reason) =>
    supported ? false : '[$platformName] $reason';

/// [condition] が真になるまで pump を繰り返す。
///
/// `pumpAndSettle` はプラットフォームビュー（地図）や常時アニメーションが
/// あると永久に settle しないため、地図まわりでは常にこちらを使う。
///
/// [timeout] 内に真にならなければ [reason] を添えて失敗する。
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  Duration step = const Duration(milliseconds: 100),
  String reason = 'condition never became true',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await tester.pump(step);
  }
  fail('[$platformName] pumpUntil timeout (${timeout.inSeconds}s): $reason');
}
