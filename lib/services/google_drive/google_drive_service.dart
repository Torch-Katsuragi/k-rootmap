// K-MAPS: Google Drive連携サービス
// OAuth認証とDrive API操作を担当

import 'dart:async';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

import '../../utils/app_logger.dart';
import '../../i18n/strings.g.dart';
import 'drive_auth_state.dart';

/// Driveファイルのメタデータ
class DriveFileMetadata {
  final String id;
  final String? name;
  final bool trashed;
  final DateTime? modifiedTime;
  final List<String> parents;

  const DriveFileMetadata({
    required this.id,
    this.name,
    required this.trashed,
    this.modifiedTime,
    this.parents = const [],
  });
}

/// Google Drive連携サービス
/// シングルトンパターンで実装
class GoogleDriveService {
  // シングルトン
  static final GoogleDriveService _instance = GoogleDriveService._internal();
  factory GoogleDriveService() => _instance;
  GoogleDriveService._internal();

  /// Google Sign-Inインスタンス
  GoogleSignIn? _googleSignIn;
  Completer<void>? _initCompleter;

  /// Drive APIクライアント
  drive.DriveApi? _driveApi;

  /// 認証状態
  final DriveAuthState authState = DriveAuthState();

  /// K-MAPS用Driveフォルダ名
  static const String kMapsFolderName = 'K-MAPS Projects';

  /// 必要なOAuthスコープ
  static const List<String> _scopes = [
    drive.DriveApi.driveScope, // Driveへのフルアクセス
    'email', // メールアドレス取得
  ];

  /// 初期化（二重実行防止）
  Future<void> initialize() async {
    if (_googleSignIn != null) return;

    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();
    try {
      _googleSignIn = GoogleSignIn(
        scopes: _scopes,
      );

      // 既存のサインイン状態を確認
      try {
        final account = await _googleSignIn!.signInSilently();
        if (account != null) {
          await _initializeDriveApi(account);
          authState.setAuthenticated(DriveUser.fromGoogleAccount(account));
          AppLogger.debug('[GoogleDriveService] サイレントサインイン成功: ${account.email}');
        }
      } catch (e) {
        AppLogger.debug('[GoogleDriveService] サイレントサインイン失敗: $e');
      }

      _initCompleter!.complete();
    } catch (e) {
      _googleSignIn = null;
      _initCompleter!.completeError(e);
      rethrow;
    } finally {
      _initCompleter = null;
    }
  }

  /// サインイン
  Future<bool> signIn() async {
    if (_googleSignIn == null) {
      await initialize();
    }

    authState.setAuthenticating();

    try {
      final account = await _googleSignIn!.signIn();
      if (account == null) {
        // ユーザーがキャンセル
        authState.setUnauthenticated();
        return false;
      }

      await _initializeDriveApi(account);
      authState.setAuthenticated(DriveUser.fromGoogleAccount(account));
      AppLogger.debug('[GoogleDriveService] サインイン成功: ${account.email}');
      return true;
    } catch (e) {
      AppLogger.debug('[GoogleDriveService] サインインエラー: $e');
      authState.setError(t.services.signInFailed(error: e.toString()));
      return false;
    }
  }

  /// サインアウト
  Future<void> signOut() async {
    try {
      await _googleSignIn?.signOut();
      _driveApi = null;
      authState.setUnauthenticated();
      AppLogger.debug('[GoogleDriveService] サインアウト完了');
    } catch (e) {
      AppLogger.debug('[GoogleDriveService] サインアウトエラー: $e');
    }
  }

  /// Drive APIを初期化
  Future<void> _initializeDriveApi(GoogleSignInAccount account) async {
    final httpClient = await _googleSignIn!.authenticatedClient();
    if (httpClient == null) {
      throw Exception(t.services.authClientFailed);
    }
    _driveApi = drive.DriveApi(httpClient);
  }

  /// トークンをリフレッシュしてDrive APIを再初期化
  /// トークン期限切れエラー時に呼び出す
  Future<bool> refreshToken() async {
    if (_googleSignIn == null) return false;

    try {
      // 現在のアカウントを取得
      final currentUser = _googleSignIn!.currentUser;
      if (currentUser == null) {
        // サイレントサインインを試行
        final account = await _googleSignIn!.signInSilently();
        if (account == null) return false;
        await _initializeDriveApi(account);
        AppLogger.debug('[GoogleDriveService] トークンリフレッシュ成功（サイレント）');
        return true;
      }

      // 認証トークンを再取得
      await currentUser.authentication;
      await _initializeDriveApi(currentUser);
      AppLogger.debug('[GoogleDriveService] トークンリフレッシュ成功');
      return true;
    } catch (e) {
      AppLogger.debug('[GoogleDriveService] トークンリフレッシュエラー: $e');
      return false;
    }
  }

  /// Drive APIが利用可能か確認
  bool get isDriveApiAvailable => _driveApi != null;

  /// Drive APIを取得（認証済みの場合のみ）
  drive.DriveApi? get driveApi => _driveApi;

  // ========== フォルダ操作 ==========

  /// K-MAPSルートフォルダを取得または作成
  Future<drive.File?> getOrCreateKMapsFolder() async {
    if (_driveApi == null) return null;

    try {
      // 既存のフォルダを検索
      final query =
          "name = '$kMapsFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
      final result = await _driveApi!.files.list(q: query);

      if (result.files != null && result.files!.isNotEmpty) {
        return result.files!.first;
      }

      // フォルダを新規作成
      final folder = drive.File()
        ..name = kMapsFolderName
        ..mimeType = 'application/vnd.google-apps.folder';

      final created = await _driveApi!.files.create(folder);
      AppLogger.debug('[GoogleDriveService] K-MAPSフォルダ作成: ${created.id}');
      return created;
    } catch (e) {
      AppLogger.debug('[GoogleDriveService] フォルダ取得/作成エラー: $e');
      return null;
    }
  }

  /// 指定フォルダ内のサブフォルダを取得
  Future<List<drive.File>> listFolders(String parentId) async {
    if (_driveApi == null) return [];

    try {
      final query =
          "'$parentId' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
      final result = await _driveApi!.files.list(
        q: query,
        $fields: 'files(id, name, modifiedTime)',
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      return result.files ?? [];
    } catch (e) {
      AppLogger.debug('[GoogleDriveService] フォルダ一覧取得エラー: $e');
      return [];
    }
  }

  /// 指定フォルダ内にサブフォルダを取得または作成
  Future<drive.File?> getOrCreateSubFolder(
    String parentId,
    String folderName,
  ) async {
    if (_driveApi == null) return null;

    try {
      final query =
          "name = '$folderName' and '$parentId' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
      final result = await _driveApi!.files.list(
        q: query,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        $fields: 'files(id, name)',
      );
      final existing = result.files?.isNotEmpty == true ? result.files!.first : null;
      if (existing != null) return existing;

      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parentId];

      final created = await _driveApi!.files.create(
        folder,
        supportsAllDrives: true,
      );
      AppLogger.debug('[GoogleDriveService] サブフォルダ作成: $folderName');
      return created;
    } catch (e) {
      AppLogger.debug('[GoogleDriveService] サブフォルダ作成エラー: $e');
      return null;
    }
  }

  /// 新しいプロジェクトフォルダを作成
  Future<drive.File?> createProjectFolder(
    String name, {
    String? parentId,
  }) async {
    if (_driveApi == null) return null;

    try {
      // 親フォルダが指定されていない場合はK-MAPSフォルダに作成
      final parent = parentId ?? (await getOrCreateKMapsFolder())?.id;
      if (parent == null) return null;

      final folder = drive.File()
        ..name = name
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parent];

      final created = await _driveApi!.files.create(folder);
      AppLogger.debug('[GoogleDriveService] プロジェクトフォルダ作成: ${created.id}');
      return created;
    } catch (e) {
      AppLogger.debug('[GoogleDriveService] フォルダ作成エラー: $e');
      return null;
    }
  }

  // ========== ファイル操作 ==========

  /// ファイルをアップロード
  /// [localFile] ローカルファイル
  /// [parentId] 親フォルダID
  /// [onProgress] 進捗コールバック（0.0〜1.0）
  Future<drive.File?> uploadFile(
    File localFile,
    String parentId, {
    void Function(double progress)? onProgress,
  }) async {
    if (_driveApi == null) return null;

    try {
      final fileName = localFile.uri.pathSegments.last;
      final fileSize = await localFile.length();

      // 既存ファイルを検索（同名ファイルがあれば更新）
      final existingFile = await _findFileByName(fileName, parentId);

      final media = drive.Media(
        localFile.openRead(),
        fileSize,
      );

      drive.File result;

      if (existingFile != null) {
        // 既存ファイルを更新
        result = await _driveApi!.files.update(
          drive.File(),
          existingFile.id!,
          uploadMedia: media,
          supportsAllDrives: true,
        );
        AppLogger.debug('[GoogleDriveService] ファイル更新: $fileName');
      } else {
        // 新規アップロード
        final driveFile = drive.File()
          ..name = fileName
          ..parents = [parentId];

        result = await _driveApi!.files.create(
          driveFile,
          uploadMedia: media,
          supportsAllDrives: true,
        );
        AppLogger.debug('[GoogleDriveService] ファイルアップロード: $fileName');
      }

      return result;
    } catch (e) {
      AppLogger.debug('[GoogleDriveService] アップロードエラー: $e');
      return null;
    }
  }

  /// 既知のDriveファイルIDを指定してアップロード（_findFileByName不要）
  /// [existingFileId] が指定されていれば files.update、なければ files.create
  Future<drive.File?> uploadFileById(
    File localFile,
    String parentId, {
    String? existingFileId,
  }) async {
    if (_driveApi == null) return null;

    try {
      final fileName = localFile.uri.pathSegments.last;
      final fileSize = await localFile.length();
      final media = drive.Media(localFile.openRead(), fileSize);

      if (existingFileId != null) {
        final result = await _driveApi!.files.update(
          drive.File(),
          existingFileId,
          uploadMedia: media,
          supportsAllDrives: true,
        );
        AppLogger.debug('[GoogleDriveService] ファイル更新(byId): $fileName');
        return result;
      } else {
        final driveFile = drive.File()
          ..name = fileName
          ..parents = [parentId];
        final result = await _driveApi!.files.create(
          driveFile,
          uploadMedia: media,
          supportsAllDrives: true,
        );
        AppLogger.debug('[GoogleDriveService] ファイル新規作成(byId): $fileName');
        return result;
      }
    } catch (e) {
      AppLogger.debug('[GoogleDriveService] アップロードエラー(byId): $e');
      return null;
    }
  }

  /// ファイルを削除
  /// [fileId] DriveファイルID
  /// ファイルをゴミ箱に移動（削除）
  /// 完全削除ではなくゴミ箱移動を使用（操作ミス対策 + 共有ドライブ対応）
  Future<bool> deleteFile(String fileId) async {
    if (_driveApi == null) return false;

    try {
      await _driveApi!.files.update(
        drive.File(trashed: true),
        fileId,
        supportsAllDrives: true,
      );
      AppLogger.debug('[GoogleDriveService] ファイルをゴミ箱に移動: $fileId');
      return true;
    } on drive.DetailedApiRequestError catch (e) {
      // 404は既にゴミ箱 or 削除済み
      if (e.status == 404) {
        AppLogger.debug('[GoogleDriveService] ファイル既に削除済み（404）: $fileId');
        return true;
      }
      AppLogger.debug('[GoogleDriveService] ゴミ箱移動エラー: status=${e.status}, message=${e.message}');
      return false;
    } catch (e) {
      AppLogger.debug('[GoogleDriveService] ゴミ箱移動エラー: $e');
      return false;
    }
  }

  /// ファイルを移動（親フォルダを変更）
  /// バージョン履歴を維持したまま移動
  /// [fileId] DriveファイルID
  /// [newParentId] 移動先フォルダID
  /// [oldParentId] 移動元フォルダID（省略可、省略時は現在の親から推測）
  Future<bool> moveFile(
    String fileId, {
    required String newParentId,
    String? oldParentId,
  }) async {
    if (_driveApi == null) return false;

    try {
      // 移動元が指定されていない場合は現在の親を取得
      String? removeParent = oldParentId;
      if (removeParent == null) {
        final metadata = await getFileMetadata(fileId);
        if (metadata != null && metadata.parents.isNotEmpty) {
          removeParent = metadata.parents.first;
        }
      }

      await _driveApi!.files.update(
        drive.File(),
        fileId,
        addParents: newParentId,
        removeParents: removeParent,
        supportsAllDrives: true,
      );
      
      AppLogger.debug(
        '[GoogleDriveService] ファイル移動: $fileId → $newParentId',
      );
      return true;
    } catch (e) {
      AppLogger.debug('[GoogleDriveService] ファイル移動エラー: $e');
      return false;
    }
  }

  /// ファイルメタデータを取得
  /// [fileId] DriveファイルID
  /// 戻り値: {trashed, modifiedTime, name, parents} または null（エラー/完全削除時）
  Future<DriveFileMetadata?> getFileMetadata(String fileId) async {
    if (_driveApi == null) return null;

    try {
      final file = await _driveApi!.files.get(
        fileId,
        $fields: 'id,name,trashed,modifiedTime,parents',
        supportsAllDrives: true,
      ) as drive.File;

      return DriveFileMetadata(
        id: file.id ?? fileId,
        name: file.name,
        trashed: file.trashed ?? false,
        modifiedTime: file.modifiedTime,
        parents: file.parents ?? [],
      );
    } catch (e) {
      // 404 = 完全削除済み
      AppLogger.debug('[GoogleDriveService] ファイルメタデータ取得エラー: $e');
      return null;
    }
  }

  /// ファイルをダウンロード
  /// [fileId] DriveファイルID
  /// [localPath] 保存先パス
  /// [onProgress] 進捗コールバック（0.0〜1.0）
  Future<bool> downloadFile(
    String fileId,
    String localPath, {
    void Function(double progress)? onProgress,
  }) async {
    if (_driveApi == null) return false;

    try {
      final response = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
        supportsAllDrives: true,
      );

      if (response is! drive.Media) {
        AppLogger.debug('[GoogleDriveService] ダウンロード応答が不正');
        return false;
      }

      final file = File(localPath);
      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
      }

      await sink.close();
      AppLogger.debug('[GoogleDriveService] ダウンロード完了: $localPath');
      return true;
    } catch (e) {
      AppLogger.debug('[GoogleDriveService] ダウンロードエラー: $e');
      return false;
    }
  }

  /// フォルダ内のファイル一覧を取得
  /// 共有フォルダにもアクセスするため supportsAllDrives=true を設定
  Future<List<drive.File>> listFiles(String parentId) async {
    if (_driveApi == null) return [];

    try {
      final query = "'$parentId' in parents and trashed = false";
      final result = await _driveApi!.files.list(
        q: query,
        $fields: 'files(id, name, mimeType, modifiedTime, size, parents)',
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      return result.files ?? [];
    } catch (e) {
      AppLogger.debug('[GoogleDriveService] ファイル一覧取得エラー: $e');
      return [];
    }
  }

  /// ファイル名でファイルを検索
  Future<drive.File?> _findFileByName(String name, String parentId) async {
    if (_driveApi == null) return null;

    try {
      final query =
          "name = '$name' and '$parentId' in parents and trashed = false";
      final result = await _driveApi!.files.list(
        q: query,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      return result.files?.firstOrNull;
    } catch (e) {
      return null;
    }
  }

  // ========== 共有URL操作 ==========

  /// 共有URLからフォルダIDを抽出
  /// 対応形式:
  /// - https://drive.google.com/drive/folders/{folderId}
  /// - https://drive.google.com/drive/folders/{folderId}?usp=sharing
  /// - https://drive.google.com/drive/u/0/folders/{folderId}
  /// - https://drive.google.com/open?id={folderId}
  /// - https://drive.google.com/folderview?id={folderId}
  static String? extractFolderIdFromUrl(String url) {
    try {
      // 空白をトリム
      url = url.trim();
      
      AppLogger.debug('[GoogleDriveService] URL解析: $url');
      
      final uri = Uri.parse(url);
      
      // drive.google.comドメインか確認
      if (!uri.host.contains('google.com')) {
        AppLogger.debug('[GoogleDriveService] Google Driveドメインではない: ${uri.host}');
        return null;
      }
      
      final pathSegments = uri.pathSegments;
      AppLogger.debug('[GoogleDriveService] pathSegments: $pathSegments');
      
      // パターン1: /drive/folders/{folderId} または /drive/u/0/folders/{folderId}
      final foldersIndex = pathSegments.indexOf('folders');
      if (foldersIndex != -1 && foldersIndex + 1 < pathSegments.length) {
        final folderId = pathSegments[foldersIndex + 1];
        AppLogger.debug('[GoogleDriveService] フォルダID検出 (folders): $folderId');
        return folderId;
      }
      
      // パターン2: /open?id={folderId} または /folderview?id={folderId}
      final idParam = uri.queryParameters['id'];
      if (idParam != null && idParam.isNotEmpty) {
        AppLogger.debug('[GoogleDriveService] フォルダID検出 (id param): $idParam');
        return idParam;
      }
      
      AppLogger.debug('[GoogleDriveService] フォルダIDが見つからない');
      return null;
    } catch (e) {
      AppLogger.debug('[GoogleDriveService] URL解析エラー: $e');
      return null;
    }
  }

  /// フォルダ情報を取得
  /// 共有フォルダにもアクセスするため supportsAllDrives=true を設定
  Future<drive.File?> getFolderInfo(String folderId) async {
    if (_driveApi == null) return null;

    try {
      final result = await _driveApi!.files.get(
        folderId,
        $fields: 'id, name, modifiedTime, owners, capabilities',
        supportsAllDrives: true,
      );
      return result as drive.File;
    } catch (e) {
      AppLogger.debug('[GoogleDriveService] フォルダ情報取得エラー: $e');
      return null;
    }
  }

}
