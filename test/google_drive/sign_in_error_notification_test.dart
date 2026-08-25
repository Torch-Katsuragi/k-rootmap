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
// Googleサインイン失敗時のエラー通知テスト
// 設定系エラー（deleted_client等）が canceled コードで返っても
// silent に握りつぶさず、エラーメッセージが設定・表示されることを確認する

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart'
    as platform;

import 'package:root_maps/i18n/strings.g.dart';
import 'package:root_maps/services/google_drive/drive_auth_state.dart';
import 'package:root_maps/services/google_drive/google_drive_service.dart';
import 'package:root_maps/widgets/dialogs/drive_connect_dialog.dart';

/// GoogleSignInPlatform のフェイク
/// authenticate() で指定した GoogleSignInException を投げる
class _FakeGoogleSignInPlatform extends platform.GoogleSignInPlatform {
  /// authenticate() で投げる例外（テストごとに差し替える）
  GoogleSignInException? authenticateException;

  @override
  Future<void> init(platform.InitParameters params) async {}

  @override
  Future<platform.AuthenticationResults?>? attemptLightweightAuthentication(
    platform.AttemptLightweightAuthenticationParameters params,
  ) {
    // null = サインインイベントはストリーム経由（本テストでは発生しない）
    return null;
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<platform.AuthenticationResults> authenticate(
    platform.AuthenticateParameters params,
  ) async {
    throw authenticateException ??
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
        );
  }

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<platform.ClientAuthorizationTokenData?>
      clientAuthorizationTokensForScopes(
    platform.ClientAuthorizationTokensForScopesParameters params,
  ) async =>
          null;

  @override
  Future<platform.ServerAuthorizationTokenData?>
      serverAuthorizationTokensForScopes(
    platform.ServerAuthorizationTokensForScopesParameters params,
  ) async =>
          null;

  @override
  Future<void> signOut(platform.SignOutParams params) async {}

  @override
  Future<void> disconnect(platform.DisconnectParams params) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fakePlatform = _FakeGoogleSignInPlatform();

  setUpAll(() {
    platform.GoogleSignInPlatform.instance = fakePlatform;
  });

  group('GoogleDriveService.isUserCancellation', () {
    GoogleSignInException canceled(String? description) =>
        GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
          description: description,
        );

    test('description なしの canceled はユーザーキャンセル扱い', () {
      expect(GoogleDriveService.isUserCancellation(canceled(null)), isTrue);
    });

    test('通常のキャンセルメッセージはユーザーキャンセル扱い', () {
      expect(
        GoogleDriveService.isUserCancellation(
            canceled('activity is cancelled by the user.')),
        isTrue,
      );
    });

    test('Developer console 未設定エラーは silent にしない', () {
      expect(
        GoogleDriveService.isUserCancellation(
            canceled('[28444] Developer console is not set up correctly.')),
        isFalse,
      );
    });

    test('GMSステータスコード付きメッセージは silent にしない', () {
      expect(
        GoogleDriveService.isUserCancellation(
            canceled('16: Account reauth failed.')),
        isFalse,
      );
    });

    test('deleted_client は silent にしない', () {
      expect(
        GoogleDriveService.isUserCancellation(
            canceled('OAuth client was deleted: deleted_client')),
        isFalse,
      );
    });

    test('認証情報なし系は silent にしない', () {
      expect(
        GoogleDriveService.isUserCancellation(
            canceled('No credential available.')),
        isFalse,
      );
    });

    test('canceled 以外のコードはユーザーキャンセル扱いにしない', () {
      expect(
        GoogleDriveService.isUserCancellation(const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError,
        )),
        isFalse,
      );
    });
  });

  group('GoogleDriveService.formatSignInError', () {
    test('code と description を含む', () {
      const e = GoogleSignInException(
        code: GoogleSignInExceptionCode.providerConfigurationError,
        description: 'auth SDK unavailable',
      );
      expect(
        GoogleDriveService.formatSignInError(e),
        'providerConfigurationError: auth SDK unavailable',
      );
    });

    test('description なしは code のみ', () {
      const e = GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      );
      expect(GoogleDriveService.formatSignInError(e), 'canceled');
    });
  });

  group('GoogleDriveService.signIn', () {
    final service = GoogleDriveService();

    test('設定エラーが canceled コードで返っても errorMessage が設定される', () async {
      fakePlatform.authenticateException = const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
        description: '[28444] Developer console is not set up correctly.',
      );

      final success = await service.signIn();

      expect(success, isFalse);
      expect(service.authState.status, DriveAuthStatus.error);
      expect(service.authState.errorMessage, contains('canceled'));
      expect(service.authState.errorMessage, contains('28444'));
    });

    test('設定エラー（clientConfigurationError）で errorMessage が設定される', () async {
      fakePlatform.authenticateException = const GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
        description: 'serverClientId must be provided on Android',
      );

      final success = await service.signIn();

      expect(success, isFalse);
      expect(service.authState.status, DriveAuthStatus.error);
      expect(
        service.authState.errorMessage,
        contains('clientConfigurationError'),
      );
    });

    test('真のユーザーキャンセルは silent（errorMessage なし）', () async {
      fakePlatform.authenticateException = const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
        description: 'activity is cancelled by the user.',
      );

      final success = await service.signIn();

      expect(success, isFalse);
      expect(service.authState.status, DriveAuthStatus.unauthenticated);
      expect(service.authState.errorMessage, isNull);
    });
  });

  group('DriveConnectDialog', () {
    testWidgets('サインイン失敗時にエラーメッセージを表示する', (tester) async {
      fakePlatform.authenticateException = const GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
        description: 'serverClientId must be provided on Android',
      );

      await tester.pumpWidget(const MaterialApp(
        home: DriveConnectDialog(
          projectPath: '/tmp/project',
          projectName: 'TestProject',
        ),
      ));
      await tester.pumpAndSettle();

      // サインインステップが表示される
      expect(find.text('Sign in with Google'), findsOneWidget);

      // サインインボタンをタップ → 失敗
      await tester.tap(find.text('Sign in with Google'));
      await tester.pumpAndSettle();

      // エラーメッセージ（code/description 入り）が表示される
      final expectedMessage = t.services.signInFailed(
        error: 'clientConfigurationError: serverClientId must be provided on Android',
      );
      expect(find.text(expectedMessage), findsOneWidget);
    });
  });
}
