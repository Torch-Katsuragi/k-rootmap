// K-MAPS: 同期エンジン
// Google DriveとローカルファイルのPush/Pull同期を担当

import 'dart:convert';
import 'dart:io';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;

import '../../models/kmeta.dart';
import '../../utils/app_logger.dart';
import '../kmeta_service.dart';
import 'google_drive_service.dart';

/// 同期結果
class SyncResult {
  /// 成功したか
  final bool success;

  /// エラーメッセージ（失敗時）
  final String? errorMessage;

  /// アップロードしたファイル数
  final int uploadedCount;

  /// ダウンロードしたファイル数
  final int downloadedCount;

  /// スキップしたファイル数
  final int skippedCount;

  /// 削除したファイル数
  final int deletedCount;

  const SyncResult({
    required this.success,
    this.errorMessage,
    this.uploadedCount = 0,
    this.downloadedCount = 0,
    this.skippedCount = 0,
    this.deletedCount = 0,
  });

  factory SyncResult.success({
    int uploadedCount = 0,
    int downloadedCount = 0,
    int skippedCount = 0,
    int deletedCount = 0,
  }) {
    return SyncResult(
      success: true,
      uploadedCount: uploadedCount,
      downloadedCount: downloadedCount,
      skippedCount: skippedCount,
      deletedCount: deletedCount,
    );
  }

  factory SyncResult.failure(String message) {
    return SyncResult(success: false, errorMessage: message);
  }
}

/// 同期進捗情報
class SyncProgress {
  /// 現在のファイル名
  final String currentFile;

  /// 処理済みファイル数
  final int processedCount;

  /// 総ファイル数
  final int totalCount;

  /// 処理済みバイト数（null = 不明）
  final int? processedBytes;

  /// 総バイト数（null = 不明）
  final int? totalBytes;

  /// 進捗率（0.0〜1.0）
  double get progress =>
      totalCount > 0 ? processedCount / totalCount : 0.0;

  /// サイズ進捗の表示文字列（例: "12.3 MB / 45.6 MB"）
  String? get sizeProgressText {
    if (totalBytes == null || totalBytes == 0) return null;
    return '${_formatBytes(processedBytes ?? 0)} / ${_formatBytes(totalBytes!)}';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  const SyncProgress({
    required this.currentFile,
    required this.processedCount,
    required this.totalCount,
    this.processedBytes,
    this.totalBytes,
  });
}

/// ローカル同期対象ファイル
class LocalSyncFile {
  final File file;
  final String relativePath;

  const LocalSyncFile({
    required this.file,
    required this.relativePath,
  });
}

/// Drive側ファイルエントリ（相対パス付き）
class DriveFileEntry {
  final drive.File file;
  final String relativePath;

  const DriveFileEntry({
    required this.file,
    required this.relativePath,
  });
}

/// 同期エンジン
class SyncEngine {
  final GoogleDriveService _driveService;
  final KMetaService _kmetaService;

  static const int _downloadConcurrency = 5;
  static const int _uploadConcurrency = 3;

  /// 同期対象のファイルパターン
  static const List<String> syncPatterns = [
    '*.gpkg',
    '*.kmeta.json',
    '*.jpg',
    '*.jpeg',
    '*.png',
    '*.tiff',
    '*.tif',
  ];

  SyncEngine({
    GoogleDriveService? driveService,
    KMetaService? kmetaService,
  })  : _driveService = driveService ?? GoogleDriveService(),
        _kmetaService = kmetaService ?? KMetaService.instance;

  /// プロジェクトをDriveにPush（アップロード）
  /// [projectPath] ローカルプロジェクトフォルダのパス
  /// [driveFolder] DriveフォルダのIDまたはnull（新規作成）
  /// [onProgress] 進捗コールバック
  Future<SyncResult> push(
    String projectPath, {
    String? driveFolder,
    void Function(SyncProgress progress)? onProgress,
  }) async {
    if (!_driveService.isDriveApiAvailable) {
      return SyncResult.failure('Google Driveに接続されていません');
    }

    try {
      final previousMeta = await _kmetaService.getMergedMeta(projectPath);
      final previousSyncedFiles = previousMeta.sync.files;

      // プロジェクトフォルダの存在確認
      final projectDir = Directory(projectPath);
      if (!await projectDir.exists()) {
        return SyncResult.failure('プロジェクトフォルダが見つかりません');
      }

      // DriveフォルダIDを取得または作成
      String targetFolderId;
      String targetFolderName;

      if (driveFolder != null) {
        // 既存フォルダを使用
        targetFolderId = driveFolder;
        final folderInfo = await _driveService.getFolderInfo(driveFolder);
        targetFolderName = folderInfo?.name ?? 'Unknown';
      } else {
        // 新規フォルダを作成
        final projectName = p.basename(projectPath);
        final created = await _driveService.createProjectFolder(projectName);
        if (created == null) {
          return SyncResult.failure('Driveフォルダの作成に失敗しました');
        }
        targetFolderId = created.id!;
        targetFolderName = created.name!;
      }

      // 同期対象ファイルを収集
      final filesToSync = await _collectSyncFiles(projectPath);
      if (filesToSync.isEmpty) {
        return SyncResult.success(skippedCount: 0);
      }

      // 移動検出: 前回のsyncedFilesのIDがローカルの別パスにあるか確認
      int movedCount = 0;
      final movedFileIds = <String>{};
      
      // DriveFileID → 前回のパス のマップを作成
      final previousIdToPath = <String, String>{};
      for (final entry in previousSyncedFiles.entries) {
        previousIdToPath[entry.value.driveFileId] = entry.key;
      }
      
      // ローカルファイルパス → ファイル のマップを作成
      final localPathToFile = <String, LocalSyncFile>{};
      for (final localFile in filesToSync) {
        localPathToFile[localFile.relativePath] = localFile;
      }
      
      // Driveフォルダ構造を取得（移動先フォルダID解決用）
      final folderIdCache = <String, String>{};
      
      // 移動を検出して処理
      for (final entry in previousSyncedFiles.entries) {
        final previousPath = entry.key;
        final syncInfo = entry.value;
        final driveFileId = syncInfo.driveFileId;
        
        // このファイルが前回と同じパスにローカルに存在するか
        if (localPathToFile.containsKey(previousPath)) {
          continue; // 移動なし
        }
        
        // このIDのファイルがローカルの別パスにあるか探す
        // （同じファイル名を探す）
        final previousFileName = p.posix.basename(previousPath);
        String? newPath;
        LocalSyncFile? newLocalFile;
        
        for (final localFile in filesToSync) {
          if (p.basename(localFile.file.path) == previousFileName) {
            // 同名ファイルが別パスにある → 移動の可能性
            // ただし、前回のsyncedFilesにこのパスがなければ移動
            if (!previousSyncedFiles.containsKey(localFile.relativePath)) {
              newPath = localFile.relativePath;
              newLocalFile = localFile;
              break;
            }
          }
        }
        
        if (newPath != null && newLocalFile != null) {
          // 移動を検出！Drive APIで移動
          final relativeDir = p.posix.dirname(newPath);
          final newParentId = await _getDriveFolderIdForRelativeDir(
            targetFolderId,
            relativeDir,
            folderIdCache,
          );
          
          if (newParentId != null) {
            final moved = await _driveService.moveFile(
              driveFileId,
              newParentId: newParentId,
              oldParentId: syncInfo.expectedParentId,
            );
            
            if (moved) {
              movedCount++;
              movedFileIds.add(driveFileId);
              AppLogger.debug(
                '[SyncEngine] Drive上で移動: $previousPath → $newPath',
              );
            }
          }
        }
      }

      AppLogger.debug(
        '[SyncEngine] Push開始: ${filesToSync.length}ファイル → $targetFolderName (移動: $movedCount)',
      );

      // ファイルをアップロード（並列）
      int uploadedCount = 0;
      int skippedCount = 0;
      int completedCount = 0;
      final syncedFiles = <String, KMetaSyncFile>{};

      // バイト数集計用
      final totalBytes = filesToSync.fold<int>(
        0, (sum, f) => sum + f.file.lengthSync(),
      );
      int processedBytes = 0;

      // .kmeta.json と通常ファイルを分離
      final kmetaFiles = <LocalSyncFile>[];
      final normalFiles = <LocalSyncFile>[];
      for (final f in filesToSync) {
        if (p.basename(f.file.path) == kMetaFileName) {
          kmetaFiles.add(f);
        } else {
          normalFiles.add(f);
        }
      }

      // .kmeta.json を先に直列処理
      for (final localFile in kmetaFiles) {
        final file = localFile.file;
        final relativePath = localFile.relativePath;
        final relativeDir = p.posix.dirname(relativePath);
        final fileSize = file.lengthSync();

        final targetFolderForFile = await _getDriveFolderIdForRelativeDir(
          targetFolderId, relativeDir, folderIdCache,
        );
        if (targetFolderForFile == null) {
          skippedCount++;
          processedBytes += fileSize;
          continue;
        }
        final success = await _uploadKmetaFile(file, targetFolderForFile);
        if (success) {
          uploadedCount++;
          final kmetaList = await _driveService.listFiles(targetFolderForFile);
          drive.File? kmetaFile;
          for (final item in kmetaList) {
            if (item.name == kMetaFileName) { kmetaFile = item; break; }
          }
          if (kmetaFile != null) {
            syncedFiles[relativePath] = KMetaSyncFile(
              driveFileId: kmetaFile.id!,
              expectedParentId: targetFolderForFile,
              lastSyncedTime: DateTime.now(),
            );
          }
        } else {
          skippedCount++;
        }
        processedBytes += fileSize;
        completedCount++;
      }

      // フォルダIDを事前に解決（並列中のキャッシュ競合回避）
      final resolvedFolders = <int, String?>{};
      for (int i = 0; i < normalFiles.length; i++) {
        final relativeDir = p.posix.dirname(normalFiles[i].relativePath);
        resolvedFolders[i] = await _getDriveFolderIdForRelativeDir(
          targetFolderId, relativeDir, folderIdCache,
        );
      }

      onProgress?.call(SyncProgress(
        currentFile: '開始',
        processedCount: completedCount,
        totalCount: filesToSync.length,
        processedBytes: processedBytes,
        totalBytes: totalBytes,
      ));

      // 通常ファイルを並列アップロード（uploadFileByIdで検索スキップ）
      await _runParallel(
        normalFiles.asMap().entries.map((entry) => () async {
          final i = entry.key;
          final localFile = entry.value;
          final file = localFile.file;
          final fileName = p.basename(file.path);
          final relativePath = localFile.relativePath;
          final fileSize = file.lengthSync();

          final targetFolderForFile = resolvedFolders[i];
          if (targetFolderForFile == null) {
            skippedCount++;
            processedBytes += fileSize;
            completedCount++;
            return;
          }

          // previousSyncedFilesから既知のDriveファイルIDを取得
          final existingFileId =
              previousSyncedFiles[relativePath]?.driveFileId;

          final result = await _driveService.uploadFileById(
            file,
            targetFolderForFile,
            existingFileId: existingFileId,
          );
          if (result != null) {
            uploadedCount++;
            syncedFiles[relativePath] = KMetaSyncFile(
              driveFileId: result.id!,
              expectedParentId: targetFolderForFile,
              lastSyncedTime: DateTime.now(),
            );
          } else {
            skippedCount++;
          }
          processedBytes += fileSize;
          completedCount++;
          onProgress?.call(SyncProgress(
            currentFile: fileName,
            processedCount: completedCount,
            totalCount: filesToSync.length,
            processedBytes: processedBytes,
            totalBytes: totalBytes,
          ));
        }),
        maxConcurrency: _uploadConcurrency,
      );

      // ローカルにないファイルをDriveから削除（移動済みファイルは除外）
      int deletedCount = 0;
      final localFilePaths =
          filesToSync.map((f) => f.relativePath).toSet();
      final deletedFileIds = <String>{};

      // 以前の同期情報から、ローカルに存在しないものを削除
      for (final entry in previousSyncedFiles.entries) {
        if (!localFilePaths.contains(entry.key)) {
          // 移動済みファイルは削除しない
          if (movedFileIds.contains(entry.value.driveFileId)) {
            continue;
          }
          final deleted = await _driveService.deleteFile(
            entry.value.driveFileId,
          );
          if (deleted) {
            deletedCount++;
            deletedFileIds.add(entry.value.driveFileId);
            AppLogger.debug('[SyncEngine] Driveから削除（同期情報）: ${entry.key}');
          }
        }
      }

      final driveEntries =
          await _listDriveFilesRecursive(targetFolderId);

      for (final entry in driveEntries) {
        if (deletedFileIds.contains(entry.file.id)) {
          continue;
        }
        // 移動済みファイルは削除しない
        if (movedFileIds.contains(entry.file.id)) {
          continue;
        }
        final drivePath = entry.relativePath;
        // 同期対象パターンにマッチするファイルのみ削除対象
        if (!localFilePaths.contains(drivePath)) {
          final deleted = await _driveService.deleteFile(entry.file.id!);
          if (deleted) {
            deletedCount++;
            AppLogger.debug('[SyncEngine] Driveから削除: $drivePath');
          }
        }
      }

      // 最終進捗通知
      onProgress?.call(SyncProgress(
        currentFile: '完了',
        processedCount: filesToSync.length,
        totalCount: filesToSync.length,
        processedBytes: totalBytes,
        totalBytes: totalBytes,
      ));

      AppLogger.debug(
        '[SyncEngine] Push完了: $uploadedCount uploaded, $deletedCount deleted, $skippedCount skipped',
      );

      // アップロード0件で対象ファイルがあった場合はエラー
      if (uploadedCount == 0 && filesToSync.isNotEmpty) {
        return SyncResult.failure(
          'ファイルのアップロードに失敗しました（$skippedCount件スキップ）',
        );
      }

      // .kmeta.jsonの同期情報を更新（成功時のみ）
      await _kmetaService.setDriveSync(
        projectPath,
        driveId: targetFolderId,
        driveFolderName: targetFolderName,
        lastSynced: DateTime.now(),
        files: syncedFiles,
      );

      return SyncResult.success(
        uploadedCount: uploadedCount,
        skippedCount: skippedCount,
        deletedCount: deletedCount,
      );
    } catch (e, stack) {
      AppLogger.debug('[SyncEngine] Pushエラー: $e\n$stack');
      return SyncResult.failure('同期中にエラーが発生しました: $e');
    }
  }

  /// .kmeta.jsonをアップロード（deviceIdを除外）
  Future<bool> _uploadKmetaFile(File file, String targetFolderId) async {
    try {
      // ファイルを読み込み
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      // KMetaオブジェクトとして解析
      final kmeta = KMeta.fromJson(json);

      // syncフィールドをdeviceIdなしで再構築
      final syncJson = kmeta.sync.toJsonForSync();

      // 新しいJSONを構築
      final syncedJson = kmeta.toJson();
      if (syncedJson.containsKey('sync')) {
        syncedJson['sync'] = syncJson;
      }

      // 一時ファイルに書き出し（正しいファイル名で作成）
      final tempDir = Directory.systemTemp;
      final tempFile = File(p.join(tempDir.path, kMetaFileName));
      await tempFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(syncedJson),
      );

      // アップロード（正しいファイル名なので既存ファイルがあれば更新される）
      final result = await _driveService.uploadFile(tempFile, targetFolderId);

      // 一時ファイル削除
      await tempFile.delete();

      return result != null;
    } catch (e) {
      AppLogger.debug('[SyncEngine] kmeta.jsonアップロードエラー: $e');
      return false;
    }
  }

  /// 同期対象ファイルを収集
  Future<List<LocalSyncFile>> _collectSyncFiles(String projectPath) async {
    final files = <LocalSyncFile>[];
    final dir = Directory(projectPath);

    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;

      final fileName = p.basename(entity.path);
      final relativePath = _normalizeRelativePath(
        p.relative(entity.path, from: projectPath),
      );

      // 同期対象パターンにマッチするか確認
      if (_matchesSyncPattern(fileName)) {
        // .ksync-state.jsonは除外
        if (fileName == '.ksync-state.json') continue;

        files.add(LocalSyncFile(file: entity, relativePath: relativePath));
        AppLogger.debug('[SyncEngine] 同期対象: $relativePath');
      }
    }

    return files;
  }

  /// 相対パスを正規化（Drive側は / 区切り）
  String _normalizeRelativePath(String path) {
    return path.replaceAll('\\', '/');
  }

  /// 相対パスからローカルパスを生成
  String _relativePathToLocalPath(String basePath, String relativePath) {
    final segments = p.posix.split(relativePath);
    return p.joinAll([basePath, ...segments]);
  }

  /// Driveの相対フォルダパスに対応するフォルダIDを取得/作成
  Future<String?> _getDriveFolderIdForRelativeDir(
    String rootFolderId,
    String relativeDir,
    Map<String, String> cache,
  ) async {
    if (relativeDir.isEmpty || relativeDir == '.') {
      return rootFolderId;
    }

    final normalized = _normalizeRelativePath(relativeDir);
    if (cache.containsKey(normalized)) {
      return cache[normalized];
    }

    String currentId = rootFolderId;
    final segments = p.posix.split(normalized);
    String currentPath = '';

    for (final segment in segments) {
      currentPath = currentPath.isEmpty ? segment : '$currentPath/$segment';
      if (cache.containsKey(currentPath)) {
        currentId = cache[currentPath]!;
        continue;
      }

      final created = await _driveService.getOrCreateSubFolder(
        currentId,
        segment,
      );
      if (created == null || created.id == null) {
        return null;
      }
      currentId = created.id!;
      cache[currentPath] = currentId;
    }

    return currentId;
  }

  /// Driveフォルダ配下のファイル一覧とフォルダマップを一括取得
  /// 1フォルダにつきAPI 1回（listFiles）でフォルダ/ファイル両方を取得
  Future<({List<DriveFileEntry> files, Map<String, String> folderMap})>
      _listDriveFilesWithFolders(
    String rootFolderId, {
    String currentPath = '',
    Map<String, String>? folderMap,
  }) async {
    final entries = <DriveFileEntry>[];
    final map = folderMap ?? <String, String>{};

    if (currentPath.isEmpty) {
      map[rootFolderId] = '';
    }

    final allItems = await _driveService.listFiles(rootFolderId);

    // フォルダとファイルを分類
    final folders = <drive.File>[];
    for (final item in allItems) {
      if (item.mimeType == 'application/vnd.google-apps.folder') {
        folders.add(item);
      } else {
        final name = item.name ?? '';
        if (name.isEmpty) continue;
        if (!_matchesSyncPattern(name)) continue;
        final relativePath = currentPath.isEmpty ? name : '$currentPath/$name';
        entries.add(DriveFileEntry(
          file: item,
          relativePath: _normalizeRelativePath(relativePath),
        ));
      }
    }

    // サブフォルダを再帰処理
    for (final folder in folders) {
      final folderName = folder.name ?? '';
      if (folderName.isEmpty) continue;
      final nextPath =
          currentPath.isEmpty ? folderName : '$currentPath/$folderName';
      map[folder.id!] = nextPath;

      final sub = await _listDriveFilesWithFolders(
        folder.id!,
        currentPath: nextPath,
        folderMap: map,
      );
      entries.addAll(sub.files);
    }

    return (files: entries, folderMap: map);
  }

  /// Driveフォルダ配下のファイルを再帰的に取得（後方互換ラッパー）
  Future<List<DriveFileEntry>> _listDriveFilesRecursive(
    String folderId,
  ) async {
    final result = await _listDriveFilesWithFolders(folderId);
    return result.files;
  }


  /// ファイル名が同期パターンにマッチするか
  bool _matchesSyncPattern(String fileName) {
    for (final pattern in syncPatterns) {
      if (pattern.startsWith('*.')) {
        final extension = pattern.substring(1); // '*.gpkg' → '.gpkg'
        if (fileName.endsWith(extension)) return true;
      } else if (pattern == fileName) {
        return true;
      }
    }
    return false;
  }

  /// 並列数を制限して非同期タスクを実行
  static Future<List<T>> _runParallel<T>(
    Iterable<Future<T> Function()> tasks, {
    int maxConcurrency = 3,
  }) async {
    final results = <T>[];
    final active = <Future<void>>[];

    for (final task in tasks) {
      if (active.length >= maxConcurrency) {
        await Future.any(active);
      }

      final future = task().then((result) {
        results.add(result);
      });
      active.add(future);
      // ignore: unawaited_futures
      future.whenComplete(() => active.remove(future));
    }

    await Future.wait(active);
    return results;
  }

  /// DriveからプロジェクトをPull（ダウンロード）
  /// [driveFolderId] DriveフォルダID
  /// [localPath] ローカル保存先パス
  /// [onProgress] 進捗コールバック
  Future<SyncResult> pull(
    String driveFolderId,
    String localPath, {
    void Function(SyncProgress progress)? onProgress,
  }) async {
    if (!_driveService.isDriveApiAvailable) {
      return SyncResult.failure('Google Driveに接続されていません');
    }

    try {
      // ローカルフォルダを作成
      final localDir = Directory(localPath);
      if (!await localDir.exists()) {
        await localDir.create(recursive: true);
      }

      // フォルダ情報を取得
      final folderInfo = await _driveService.getFolderInfo(driveFolderId);
      if (folderInfo == null) {
        return SyncResult.failure('Driveフォルダの情報を取得できません');
      }

      // ファイル一覧を取得（再帰）
      final filesToDownload =
          await _listDriveFilesRecursive(driveFolderId);
      if (filesToDownload.isEmpty) {
        return SyncResult.success(downloadedCount: 0);
      }

      AppLogger.debug(
        '[SyncEngine] Pull開始: ${filesToDownload.length}ファイル ← ${folderInfo.name}',
      );

      // ファイルをダウンロード（並列）
      int downloadedCount = 0;
      int skippedCount = 0;
      int completedCount = 0;
      final syncedFiles = <String, KMetaSyncFile>{};

      // バイト数集計用
      final totalBytes = filesToDownload.fold<int>(
        0, (sum, e) => sum + (int.tryParse(e.file.size ?? '') ?? 0),
      );
      int processedBytes = 0;

      // ディレクトリを事前に一括作成（並列中の競合回避）
      final dirs = filesToDownload
          .map((e) => p.dirname(
              _relativePathToLocalPath(localPath, e.relativePath)))
          .toSet();
      for (final dir in dirs) {
        final d = Directory(dir);
        if (!await d.exists()) await d.create(recursive: true);
      }

      onProgress?.call(SyncProgress(
        currentFile: '開始',
        processedCount: 0,
        totalCount: filesToDownload.length,
        processedBytes: 0,
        totalBytes: totalBytes,
      ));

      await _runParallel(
        filesToDownload.map((driveEntry) => () async {
          final driveFile = driveEntry.file;
          final fileName = p.posix.basename(driveEntry.relativePath);
          final fileSize = int.tryParse(driveFile.size ?? '') ?? 0;
          final localFilePath =
              _relativePathToLocalPath(localPath, driveEntry.relativePath);

          final success = await _driveService.downloadFile(
            driveFile.id!,
            localFilePath,
          );

          if (success) {
            downloadedCount++;
            final parentId = driveFile.parents?.firstOrNull;
            syncedFiles[driveEntry.relativePath] = KMetaSyncFile(
              driveFileId: driveFile.id!,
              expectedParentId: parentId,
              lastSyncedTime: DateTime.now(),
            );
          } else {
            skippedCount++;
          }
          processedBytes += fileSize;
          completedCount++;
          onProgress?.call(SyncProgress(
            currentFile: fileName,
            processedCount: completedCount,
            totalCount: filesToDownload.length,
            processedBytes: processedBytes,
            totalBytes: totalBytes,
          ));
        }),
        maxConcurrency: _downloadConcurrency,
      );

      // Driveにないファイルをローカルから削除
      int deletedCount = 0;
      final driveFilePaths =
          filesToDownload.map((f) => f.relativePath).toSet();

      // localDirは既に上で定義済み
      if (await localDir.exists()) {
        await for (final entity in localDir.list(recursive: true)) {
          if (entity is File) {
            final localName = p.basename(entity.path);
            if (!_matchesSyncPattern(localName)) continue;
            final relativePath = _normalizeRelativePath(
              p.relative(entity.path, from: localPath),
            );
            if (!driveFilePaths.contains(relativePath)) {
              await entity.delete();
              deletedCount++;
              AppLogger.debug('[SyncEngine] ローカルから削除: $relativePath');
            }
          }
        }
      }

      // 最終進捗通知
      onProgress?.call(SyncProgress(
        currentFile: '完了',
        processedCount: filesToDownload.length,
        totalCount: filesToDownload.length,
        processedBytes: totalBytes,
        totalBytes: totalBytes,
      ));

      AppLogger.debug(
        '[SyncEngine] Pull完了: $downloadedCount downloaded, $deletedCount deleted, $skippedCount skipped',
      );

      // ダウンロード0件で対象ファイルがあった場合はエラー
      if (downloadedCount == 0 && filesToDownload.isNotEmpty) {
        return SyncResult.failure(
          'ファイルのダウンロードに失敗しました（$skippedCount件スキップ）',
        );
      }

      // .kmeta.jsonの同期情報を更新（成功時のみ）
      await _kmetaService.setDriveSync(
        localPath,
        driveId: driveFolderId,
        driveFolderName: folderInfo.name,
        lastSynced: DateTime.now(),
        files: syncedFiles,
      );

      return SyncResult.success(
        downloadedCount: downloadedCount,
        skippedCount: skippedCount,
        deletedCount: deletedCount,
      );
    } catch (e, stack) {
      AppLogger.debug('[SyncEngine] Pullエラー: $e\n$stack');
      return SyncResult.failure('ダウンロード中にエラーが発生しました: $e');
    }
  }

  /// 共有URLからプロジェクトをPull
  /// [shareUrl] Google Drive共有URL
  /// [localPath] ローカル保存先パス
  /// [onProgress] 進捗コールバック
  Future<SyncResult> pullFromUrl(
    String shareUrl,
    String localPath, {
    void Function(SyncProgress progress)? onProgress,
  }) async {
    // URLからフォルダIDを抽出
    final folderId = GoogleDriveService.extractFolderIdFromUrl(shareUrl);
    if (folderId == null) {
      return SyncResult.failure('無効な共有URLです');
    }

    return pull(folderId, localPath, onProgress: onProgress);
  }

  /// DriveフォルダをローカルにクローンFuture<bool> cloneFromDrive({
  ///   required String driveId,
  ///   required String localPath,
  ///   required String folderName,
  ///   required String driveUrl,
  ///   required bool isReadOnly,
  ///   void Function(SyncProgress progress)? onProgress,
  /// })
  /// 
  /// Drive連携フォルダとして初回クローンを実行
  /// [driveId] DriveフォルダID
  /// [localPath] ローカル保存先パス
  /// [folderName] フォルダ名
  /// [driveUrl] 元のDrive URL
  /// [isReadOnly] 読み取り専用か
  /// [onProgress] 進捗コールバック
  Future<bool> cloneFromDrive({
    required String driveId,
    required String localPath,
    required String folderName,
    required String driveUrl,
    required bool isReadOnly,
    void Function(SyncProgress progress)? onProgress,
  }) async {
    AppLogger.debug('[SyncEngine] クローン開始: $folderName ($driveId)');

    final result = await pull(
      driveId,
      localPath,
      onProgress: onProgress,
    );

    if (!result.success) {
      AppLogger.error('[SyncEngine] クローン失敗: ${result.errorMessage}');
      return false;
    }

    // クローン固有: driveUrl / isReadOnly を追加保存
    await _kmetaService.setDriveSync(
      localPath,
      driveUrl: driveUrl,
      isReadOnly: isReadOnly,
    );

    AppLogger.debug(
      '[SyncEngine] クローン完了: ${result.downloadedCount} ファイルダウンロード',
    );
    return true;
  }

  /// フォルダの同期状態をチェック
  /// ファイルID単位でDriveとローカルを比較
  Future<FolderSyncStatus> checkSyncStatus(String localPath) async {
    final detail = await checkSyncStatusDetail(localPath);
    return detail.status;
  }

  /// 同期状態の詳細を取得
  Future<FolderSyncStatusDetail> checkSyncStatusDetail(String localPath) async {
    if (!_driveService.isDriveApiAvailable) {
      return const FolderSyncStatusDetail(status: FolderSyncStatus.error);
    }

    try {
      // .kmeta.jsonからDrive情報を取得
      final meta = await _kmetaService.getMergedMeta(localPath);
      final driveId = meta.sync.driveId;
      final syncedFiles = meta.sync.files;

      if (driveId == null) {
        return const FolderSyncStatusDetail(status: FolderSyncStatus.notLinked);
      }

      // Driveフォルダ情報を取得（存在確認）
      final folderInfo = await _driveService.getFolderInfo(driveId);
      if (folderInfo == null) {
        return const FolderSyncStatusDetail(status: FolderSyncStatus.error);
      }

      // Driveのファイル一覧とフォルダマップを一括取得（API呼び出しを最小化）
      final driveData = await _listDriveFilesWithFolders(driveId);
      final driveAllEntries = driveData.files;
      final driveFolderMap = driveData.folderMap;

      // Drive fileId → DriveFileEntry のマップを構築（O(1)参照用）
      final driveIdMap = <String, DriveFileEntry>{};
      for (final entry in driveAllEntries) {
        final fileId = entry.file.id;
        if (fileId != null) driveIdMap[fileId] = entry;
      }

      // ローカルファイルを収集（再帰）
      final localDir = Directory(localPath);
      final localFiles = <String, DateTime>{};
      if (await localDir.exists()) {
        await for (final entity in localDir.list(recursive: true)) {
          final fileName = p.basename(entity.path);
          if (fileName == kMetaFileName) continue;
          if (entity is File && _matchesSyncPattern(fileName)) {
            final relativePath = _normalizeRelativePath(
              p.relative(entity.path, from: localPath),
            );
            final stat = await entity.stat();
            localFiles[relativePath] = stat.modified;
          }
        }
      }

      int localAdded = 0;
      int localDeleted = 0;
      int localModified = 0;
      int remoteAdded = 0;
      int remoteDeleted = 0;
      int remoteModified = 0;
      int remoteMoved = 0;
      final localAddedFiles = <String>[];
      final localDeletedFiles = <String>[];
      final localModifiedFiles = <String>[];
      final remoteAddedFiles = <String>[];
      final remoteDeletedFiles = <String>[];
      final remoteModifiedFiles = <String>[];
      final remoteMovedFiles = <FileChangeInfo>[];
      
      final movedFileIds = <String>{};
      final movedToPathSet = <String>{};

      // 記録済みファイルをチェック（driveIdMapからO(1)参照、API呼び出しなし）
      for (final entry in syncedFiles.entries) {
        final fileName = entry.key;
        if (p.basename(fileName) == kMetaFileName) continue;
        
        final syncInfo = entry.value;
        final lastSyncedTime = syncInfo.lastSyncedTime;
        final expectedParentId = syncInfo.expectedParentId;

        // driveIdMapから参照（getFileMetadata API呼び出し不要）
        final driveEntry = driveIdMap[syncInfo.driveFileId];

        if (driveEntry == null) {
          // Drive上に存在しない = 削除された
          remoteDeleted++;
          remoteDeletedFiles.add(fileName);
        } else {
          final driveFile = driveEntry.file;
          // 移動検出: parentsをチェック
          bool isMoved = false;
          
          if (expectedParentId != null &&
              driveFile.parents != null &&
              driveFile.parents!.isNotEmpty) {
            final currentParentId = driveFile.parents!.first;
            if (currentParentId != expectedParentId) {
              isMoved = true;
              final newParentPath = driveFolderMap[currentParentId];
              
              if (newParentPath != null) {
                final newPath = newParentPath.isEmpty
                    ? driveFile.name ?? fileName
                    : '$newParentPath/${driveFile.name ?? fileName}';
                
                final alsoModified = lastSyncedTime != null &&
                    driveFile.modifiedTime != null &&
                    driveFile.modifiedTime!.isAfter(lastSyncedTime);
                
                remoteMoved++;
                remoteMovedFiles.add(FileChangeInfo(
                  fileName: fileName,
                  type: alsoModified
                      ? FileChangeType.movedAndModified
                      : FileChangeType.moved,
                  movedFrom: fileName,
                  movedTo: newPath,
                ));
                movedFileIds.add(syncInfo.driveFileId);
                movedToPathSet.add(newPath);
              } else {
                remoteDeleted++;
                remoteDeletedFiles.add(fileName);
              }
            }
          }
          
          // 移動なしの場合の変更チェック
          if (!isMoved) {
            if (lastSyncedTime == null) {
              remoteModified++;
              remoteModifiedFiles.add(fileName);
            } else if (driveFile.modifiedTime != null &&
                driveFile.modifiedTime!.isAfter(lastSyncedTime)) {
              remoteModified++;
              remoteModifiedFiles.add(fileName);
            }
          }
        }

        // ローカル側の変更を確認
        if (movedFileIds.contains(syncInfo.driveFileId)) {
          localFiles.remove(fileName);
        } else if (localFiles.containsKey(fileName)) {
          final localModifiedTime = localFiles[fileName]!;
          if (lastSyncedTime == null) {
            localModified++;
            localModifiedFiles.add(fileName);
          } else if (localModifiedTime.isAfter(lastSyncedTime)) {
            localModified++;
            localModifiedFiles.add(fileName);
          }
          localFiles.remove(fileName);
        } else {
          localDeleted++;
          localDeletedFiles.add(fileName);
        }
      }

      // 未記録のローカルファイル = ローカル追加
      localAdded = localFiles.length;
      if (localFiles.isNotEmpty) {
        localAddedFiles.addAll(localFiles.keys);
      }

      // Driveに新規ファイルがあるか確認（driveAllEntriesを再利用、API呼び出し不要）
      for (final entry in driveAllEntries) {
        if (p.basename(entry.relativePath) == kMetaFileName) continue;
        if (movedToPathSet.contains(entry.relativePath)) continue;
        if (movedFileIds.contains(entry.file.id)) continue;
        if (!syncedFiles.containsKey(entry.relativePath)) {
          remoteAdded++;
          remoteAddedFiles.add(entry.relativePath);
        }
      }

      final hasLocalChanges =
          localAdded > 0 || localDeleted > 0 || localModified > 0;
      final hasRemoteChanges =
          remoteAdded > 0 || remoteDeleted > 0 || remoteModified > 0 || remoteMoved > 0;

      // 一度も同期していない場合
      if (syncedFiles.isEmpty && meta.sync.lastSynced == null) {
        return FolderSyncStatusDetail(
          status: FolderSyncStatus.remoteChanges,
          localAdded: localAdded,
          localDeleted: localDeleted,
          localModified: localModified,
          remoteAdded: remoteAdded,
          remoteDeleted: remoteDeleted,
          remoteModified: remoteModified,
          remoteMoved: remoteMoved,
          localAddedFiles: localAddedFiles,
          localDeletedFiles: localDeletedFiles,
          localModifiedFiles: localModifiedFiles,
          remoteAddedFiles: remoteAddedFiles,
          remoteDeletedFiles: remoteDeletedFiles,
          remoteModifiedFiles: remoteModifiedFiles,
          remoteMovedFiles: remoteMovedFiles,
        );
      }

      final status = hasLocalChanges && hasRemoteChanges
          ? FolderSyncStatus.conflict
          : hasLocalChanges
              ? FolderSyncStatus.localChanges
              : hasRemoteChanges
                  ? FolderSyncStatus.remoteChanges
                  : FolderSyncStatus.synced;

      return FolderSyncStatusDetail(
        status: status,
        localAdded: localAdded,
        localDeleted: localDeleted,
        localModified: localModified,
        remoteAdded: remoteAdded,
        remoteDeleted: remoteDeleted,
        remoteModified: remoteModified,
        remoteMoved: remoteMoved,
        localAddedFiles: localAddedFiles,
        localDeletedFiles: localDeletedFiles,
        localModifiedFiles: localModifiedFiles,
        remoteAddedFiles: remoteAddedFiles,
        remoteDeletedFiles: remoteDeletedFiles,
        remoteModifiedFiles: remoteModifiedFiles,
        remoteMovedFiles: remoteMovedFiles,
      );
    } catch (e) {
      AppLogger.error('[SyncEngine] 同期状態チェックエラー: $e');
      return const FolderSyncStatusDetail(status: FolderSyncStatus.error);
    }
  }

  /// フォルダ単位でPush
  Future<SyncResult> pushFolder(String localPath) async {
    final meta = await _kmetaService.getMergedMeta(localPath);
    final driveId = meta.sync.driveId;
    
    if (driveId == null) {
      return SyncResult.failure('Drive連携されていません');
    }

    return push(localPath, driveFolder: driveId);
  }

  /// フォルダ単位でPull
  Future<SyncResult> pullFolder(String localPath) async {
    final meta = await _kmetaService.getMergedMeta(localPath);
    final driveId = meta.sync.driveId;
    
    if (driveId == null) {
      return SyncResult.failure('Drive連携されていません');
    }

    return pull(driveId, localPath);
  }

  /// マージ用のファイルエントリ一覧を取得
  Future<List<MergeFileEntry>> getMergeEntries(String localPath) async {
    final entries = <MergeFileEntry>[];
    
    try {
      // .kmeta.jsonからDrive情報を取得
      final meta = await _kmetaService.getMergedMeta(localPath);
      final driveId = meta.sync.driveId;
      final syncedFiles = meta.sync.files;

      if (driveId == null) {
        return entries;
      }

      // Driveフォルダ情報を取得（存在確認）
      final folderInfo = await _driveService.getFolderInfo(driveId);
      if (folderInfo == null) {
        return entries;
      }

      // Driveのファイル一覧とフォルダマップを一括取得（API呼び出しを最小化）
      final driveData = await _listDriveFilesWithFolders(driveId);
      final driveAllEntries = driveData.files;
      final driveFolderMap = driveData.folderMap;

      // Drive fileId → DriveFileEntry のマップを構築（O(1)参照用）
      final driveIdMap = <String, DriveFileEntry>{};
      for (final entry in driveAllEntries) {
        final fileId = entry.file.id;
        if (fileId != null) driveIdMap[fileId] = entry;
      }

      // ローカルファイルを収集（再帰）
      final localDir = Directory(localPath);
      final localFiles = <String, DateTime>{};
      if (await localDir.exists()) {
        await for (final entity in localDir.list(recursive: true)) {
          final fileName = p.basename(entity.path);
          if (fileName == kMetaFileName) continue;
          if (entity is File && _matchesSyncPattern(fileName)) {
            final relativePath = _normalizeRelativePath(
              p.relative(entity.path, from: localPath),
            );
            final stat = await entity.stat();
            localFiles[relativePath] = stat.modified;
          }
        }
      }

      // 処理済みファイルを追跡
      final processedFiles = <String>{};
      
      final movedFileIds = <String>{};
      final movedToPathSet = <String>{};

      // 記録済みファイルをチェック（driveIdMapからO(1)参照、API呼び出しなし）
      for (final entry in syncedFiles.entries) {
        final fileName = entry.key;
        if (p.basename(fileName) == kMetaFileName) continue;
        
        final syncInfo = entry.value;
        final lastSyncedTime = syncInfo.lastSyncedTime;
        final expectedParentId = syncInfo.expectedParentId;

        // driveIdMapから参照（getFileMetadata API呼び出し不要）
        final driveEntry = driveIdMap[syncInfo.driveFileId];

        MergeChangeType localChange = MergeChangeType.none;
        MergeChangeType remoteChange = MergeChangeType.none;
        DateTime? localModTime;
        DateTime? remoteModTime = driveEntry?.file.modifiedTime;
        FileChangeInfo? moveInfo;

        // リモート変更を判定
        if (driveEntry == null) {
          remoteChange = MergeChangeType.deleted;
        } else {
          final driveFile = driveEntry.file;
          // 移動検出
          if (expectedParentId != null &&
              driveFile.parents != null &&
              driveFile.parents!.isNotEmpty) {
            final currentParentId = driveFile.parents!.first;
            if (currentParentId != expectedParentId) {
              final newParentPath = driveFolderMap[currentParentId];
              if (newParentPath != null) {
                remoteChange = MergeChangeType.moved;
                final newPath = newParentPath.isEmpty
                    ? driveFile.name ?? fileName
                    : '$newParentPath/${driveFile.name ?? fileName}';
                moveInfo = FileChangeInfo(
                  fileName: fileName,
                  type: FileChangeType.moved,
                  movedFrom: fileName,
                  movedTo: newPath,
                );
                movedFileIds.add(syncInfo.driveFileId);
                movedToPathSet.add(newPath);
              } else {
                remoteChange = MergeChangeType.deleted;
              }
            }
          }
          
          // 内容変更検出（移動がなかった場合）
          if (remoteChange == MergeChangeType.none) {
            if (lastSyncedTime != null &&
                driveFile.modifiedTime != null &&
                driveFile.modifiedTime!.isAfter(lastSyncedTime)) {
              remoteChange = MergeChangeType.modified;
            }
          }
        }

        // ローカル変更を判定
        if (movedFileIds.contains(syncInfo.driveFileId)) {
          localChange = MergeChangeType.none;
        } else if (localFiles.containsKey(fileName)) {
          localModTime = localFiles[fileName];
          if (lastSyncedTime != null && localModTime!.isAfter(lastSyncedTime)) {
            localChange = MergeChangeType.modified;
          }
          processedFiles.add(fileName);
        } else {
          localChange = MergeChangeType.deleted;
        }

        // 変更があるエントリのみ追加
        if (localChange != MergeChangeType.none || remoteChange != MergeChangeType.none) {
          entries.add(MergeFileEntry(
            relativePath: fileName,
            localChange: localChange,
            remoteChange: remoteChange,
            localModifiedTime: localModTime,
            remoteModifiedTime: remoteModTime,
            moveInfo: moveInfo,
            driveFileId: syncInfo.driveFileId,
          ));
        }
        
        localFiles.remove(fileName);
      }

      // 未記録のローカルファイル = ローカル追加
      for (final entry in localFiles.entries) {
        entries.add(MergeFileEntry(
          relativePath: entry.key,
          localChange: MergeChangeType.added,
          remoteChange: MergeChangeType.none,
          localModifiedTime: entry.value,
          remoteModifiedTime: null,
        ));
      }

      // Driveに新規ファイルがあるか確認（driveAllEntriesを再利用、API呼び出し不要）
      AppLogger.debug('[SyncEngine] getMergeEntries: Drive新規ファイル確認 (${driveAllEntries.length}件)');
      for (final driveEntry in driveAllEntries) {
        if (p.basename(driveEntry.relativePath) == kMetaFileName) continue;
        if (movedToPathSet.contains(driveEntry.relativePath)) continue;
        if (movedFileIds.contains(driveEntry.file.id)) continue;
        if (!syncedFiles.containsKey(driveEntry.relativePath)) {
          AppLogger.debug('  リモート追加検出: ${driveEntry.relativePath} (id: ${driveEntry.file.id})');
          entries.add(MergeFileEntry(
            relativePath: driveEntry.relativePath,
            localChange: MergeChangeType.none,
            remoteChange: MergeChangeType.added,
            localModifiedTime: null,
            remoteModifiedTime: driveEntry.file.modifiedTime,
            driveFileId: driveEntry.file.id,
          ));
        }
      }

      AppLogger.debug('[SyncEngine] getMergeEntries完了: ${entries.length}件のエントリ');
      return entries;
    } catch (e) {
      AppLogger.error('[SyncEngine] getMergeEntries エラー: $e');
      return entries;
    }
  }

  /// マージを実行
  Future<SyncResult> executeMerge(
    String localPath,
    List<MergeDecision> decisions,
  ) async {
    try {
      final meta = await _kmetaService.getMergedMeta(localPath);
      final driveId = meta.sync.driveId;
      final syncedFiles = Map<String, KMetaSyncFile>.from(meta.sync.files);

      if (driveId == null) {
        return SyncResult.failure('Drive連携されていません');
      }

      int uploadedCount = 0;
      int downloadedCount = 0;
      int deletedCount = 0;
      
      // フォルダIDキャッシュ
      final folderIdCache = <String, String>{};

      AppLogger.debug('[SyncEngine] executeMerge開始: ${decisions.length}件の決定');
      
      for (final decision in decisions) {
        final entry = decision.entry;
        final choice = decision.choice;
        final relativePath = entry.relativePath;
        final localFilePath = _relativePathToLocalPath(localPath, relativePath);

        AppLogger.debug('[SyncEngine] 処理: $relativePath');
        AppLogger.debug('  choice: $choice');
        AppLogger.debug('  localChange: ${entry.localChange}');
        AppLogger.debug('  remoteChange: ${entry.remoteChange}');
        AppLogger.debug('  driveFileId: ${entry.driveFileId}');

        if (choice == MergeChoice.local) {
          // ローカルを採用
          switch (entry.localChange) {
            case MergeChangeType.added:
            case MergeChangeType.modified:
              // ローカルファイルをDriveにアップロード
              final file = File(localFilePath);
              if (await file.exists()) {
                // サブフォルダ構造を維持するため、正しい親フォルダIDを取得
                final relativeDir = p.dirname(relativePath);
                String targetFolderId = driveId;
                if (relativeDir != '.' && relativeDir.isNotEmpty) {
                  final folderId = await _getDriveFolderIdForRelativeDir(
                    driveId, relativeDir, folderIdCache);
                  if (folderId != null) {
                    targetFolderId = folderId;
                  }
                }
                
                final result = await _driveService.uploadFile(file, targetFolderId);
                if (result != null) {
                  uploadedCount++;
                  syncedFiles[relativePath] = KMetaSyncFile(
                    driveFileId: result.id!,
                    expectedParentId: targetFolderId,
                    lastSyncedTime: DateTime.now(),
                  );
                }
              }
              break;
            case MergeChangeType.deleted:
              // ローカルで削除 → Driveからも削除
              if (entry.driveFileId != null) {
                await _driveService.deleteFile(entry.driveFileId!);
                syncedFiles.remove(relativePath);
                deletedCount++;
              }
              break;
            case MergeChangeType.none:
              // ローカル変更なし → リモートの変更を無視（復元）
              AppLogger.debug('  → ローカル変更なし、リモート変更を復元: ${entry.remoteChange}');
              switch (entry.remoteChange) {
                case MergeChangeType.deleted:
                  // リモートで削除されたが、ローカルを復元 → 再アップロード
                  final file = File(localFilePath);
                  if (await file.exists()) {
                    final relativeDir = p.dirname(relativePath);
                    String targetFolderId = driveId;
                    if (relativeDir != '.' && relativeDir.isNotEmpty) {
                      final folderId = await _getDriveFolderIdForRelativeDir(
                        driveId, relativeDir, folderIdCache);
                      if (folderId != null) {
                        targetFolderId = folderId;
                      }
                    }
                    
                    final result = await _driveService.uploadFile(file, targetFolderId);
                    if (result != null) {
                      uploadedCount++;
                      syncedFiles[relativePath] = KMetaSyncFile(
                        driveFileId: result.id!,
                        expectedParentId: targetFolderId,
                        lastSyncedTime: DateTime.now(),
                      );
                    }
                  }
                  break;
                case MergeChangeType.added:
                  // リモートで追加されたが、ローカル（なし）を優先 → リモートを削除
                  AppLogger.debug('  → リモート追加を削除（復元）');
                  if (entry.driveFileId != null) {
                    AppLogger.debug('    削除対象driveFileId: ${entry.driveFileId}');
                    
                    // 削除前にファイルが存在するか確認
                    final metadata = await _driveService.getFileMetadata(entry.driveFileId!);
                    if (metadata != null) {
                      AppLogger.debug('    ファイル存在確認OK: ${metadata.name}, trashed=${metadata.trashed}');
                      final deleted = await _driveService.deleteFile(entry.driveFileId!);
                      if (deleted) {
                        syncedFiles.remove(relativePath);
                        deletedCount++;
                        AppLogger.debug('    削除完了');
                      } else {
                        AppLogger.debug('    削除失敗');
                      }
                    } else {
                      AppLogger.debug('    ファイルが見つからない（getFileMetadata=null）');
                      // ファイルが見つからない場合もsyncedFilesから削除
                      syncedFiles.remove(relativePath);
                    }
                  } else {
                    AppLogger.debug('    driveFileIdがnullのためスキップ');
                  }
                  break;
                case MergeChangeType.modified:
                  // リモートで変更されたが、ローカルを優先 → ローカルをアップロード
                  final file = File(localFilePath);
                  if (await file.exists()) {
                    final relativeDir = p.dirname(relativePath);
                    String targetFolderId = driveId;
                    if (relativeDir != '.' && relativeDir.isNotEmpty) {
                      final folderId = await _getDriveFolderIdForRelativeDir(
                        driveId, relativeDir, folderIdCache);
                      if (folderId != null) {
                        targetFolderId = folderId;
                      }
                    }
                    
                    // uploadFileは同名ファイルを自動検出して更新する
                    final result = await _driveService.uploadFile(file, targetFolderId);
                    if (result != null) {
                      uploadedCount++;
                      syncedFiles[relativePath] = KMetaSyncFile(
                        driveFileId: result.id!,
                        expectedParentId: targetFolderId,
                        lastSyncedTime: DateTime.now(),
                      );
                    }
                  }
                  break;
                case MergeChangeType.moved:
                  // リモートで移動されたが、ローカル位置を優先 → 元に戻す
                  if (entry.driveFileId != null && entry.moveInfo != null) {
                    final syncedFile = syncedFiles[relativePath];
                    if (syncedFile?.expectedParentId != null) {
                      await _driveService.moveFile(
                        entry.driveFileId!,
                        newParentId: syncedFile!.expectedParentId!,
                      );
                      syncedFiles[relativePath] = syncedFile.copyWith(
                        lastSyncedTime: DateTime.now(),
                      );
                    }
                  }
                  break;
                case MergeChangeType.none:
                  // 何もしない
                  break;
              }
              break;
            case MergeChangeType.moved:
              // ローカルでは移動はないが念のため
              break;
          }
        } else {
          // リモートを採用
          switch (entry.remoteChange) {
            case MergeChangeType.added:
            case MergeChangeType.modified:
              // Driveからダウンロード
              if (entry.driveFileId != null) {
                // サブフォルダを作成
                final localFileDir = Directory(p.dirname(localFilePath));
                if (!await localFileDir.exists()) {
                  await localFileDir.create(recursive: true);
                }
                
                final success = await _driveService.downloadFile(
                  entry.driveFileId!,
                  localFilePath,
                );
                if (success) {
                  downloadedCount++;
                  // Driveメタデータから正しいparentIdを取得
                  final driveMetadata = await _driveService.getFileMetadata(entry.driveFileId!);
                  final parentId = driveMetadata?.parents.isNotEmpty == true
                      ? driveMetadata!.parents.first
                      : driveId;
                  syncedFiles[relativePath] = KMetaSyncFile(
                    driveFileId: entry.driveFileId!,
                    expectedParentId: parentId,
                    lastSyncedTime: DateTime.now(),
                  );
                }
              }
              break;
            case MergeChangeType.deleted:
              // リモートで削除 → ローカルも削除
              final file = File(localFilePath);
              if (await file.exists()) {
                await file.delete();
                syncedFiles.remove(relativePath);
                deletedCount++;
              }
              break;
            case MergeChangeType.moved:
              // リモートで移動 → ローカルも移動
              if (entry.moveInfo != null && entry.driveFileId != null) {
                final oldPath = _relativePathToLocalPath(localPath, entry.moveInfo!.movedFrom ?? relativePath);
                final newPath = _relativePathToLocalPath(localPath, entry.moveInfo!.movedTo ?? relativePath);
                final oldFile = File(oldPath);
                if (await oldFile.exists()) {
                  // 新しいディレクトリを作成
                  final newDir = Directory(p.dirname(newPath));
                  if (!await newDir.exists()) {
                    await newDir.create(recursive: true);
                  }
                  await oldFile.rename(newPath);
                  // syncedFilesを更新
                  syncedFiles.remove(entry.moveInfo!.movedFrom ?? relativePath);
                  
                  // 新しいパスでDriveメタデータを取得
                  final driveMetadata = await _driveService.getFileMetadata(entry.driveFileId!);
                  syncedFiles[entry.moveInfo!.movedTo ?? relativePath] = KMetaSyncFile(
                    driveFileId: entry.driveFileId!,
                    expectedParentId: driveMetadata?.parents.isNotEmpty == true 
                        ? driveMetadata!.parents.first 
                        : driveId,
                    lastSyncedTime: DateTime.now(),
                  );
                }
              }
              break;
            case MergeChangeType.none:
              // リモート変更なし → ローカルの変更を無視（復元）
              switch (entry.localChange) {
                case MergeChangeType.deleted:
                  // ローカルで削除されたが、リモートを復元 → 再ダウンロード
                  if (entry.driveFileId != null) {
                    // サブフォルダを作成
                    final localFileDir = Directory(p.dirname(localFilePath));
                    if (!await localFileDir.exists()) {
                      await localFileDir.create(recursive: true);
                    }
                    
                    final success = await _driveService.downloadFile(
                      entry.driveFileId!,
                      localFilePath,
                    );
                    if (success) {
                      downloadedCount++;
                      final driveMetadata = await _driveService.getFileMetadata(entry.driveFileId!);
                      final parentId = driveMetadata?.parents.isNotEmpty == true
                          ? driveMetadata!.parents.first
                          : driveId;
                      syncedFiles[relativePath] = KMetaSyncFile(
                        driveFileId: entry.driveFileId!,
                        expectedParentId: parentId,
                        lastSyncedTime: DateTime.now(),
                      );
                    }
                  }
                  break;
                case MergeChangeType.added:
                  // ローカルで追加されたが、リモート（なし）を優先 → ローカルを削除
                  final file = File(localFilePath);
                  if (await file.exists()) {
                    await file.delete();
                    syncedFiles.remove(relativePath);
                    deletedCount++;
                  }
                  break;
                case MergeChangeType.modified:
                  // ローカルで変更されたが、リモートを優先 → リモートをダウンロード
                  if (entry.driveFileId != null) {
                    final success = await _driveService.downloadFile(
                      entry.driveFileId!,
                      localFilePath,
                    );
                    if (success) {
                      downloadedCount++;
                      syncedFiles[relativePath] = KMetaSyncFile(
                        driveFileId: entry.driveFileId!,
                        expectedParentId: syncedFiles[relativePath]?.expectedParentId ?? driveId,
                        lastSyncedTime: DateTime.now(),
                      );
                    }
                  }
                  break;
                case MergeChangeType.moved:
                  // ローカルでは移動は検出しないので何もしない
                  break;
                case MergeChangeType.none:
                  // 何もしない
                  break;
              }
              break;
          }
        }
      }

      // kmetaを更新
      await _kmetaService.setDriveSync(
        localPath,
        driveId: driveId,
        driveUrl: meta.sync.driveUrl,
        isReadOnly: meta.sync.isReadOnly,
        files: syncedFiles,
      );

      AppLogger.debug(
        '[SyncEngine] Merge完了: $uploadedCount uploaded, '
        '$downloadedCount downloaded, $deletedCount deleted',
      );

      return SyncResult.success(
        uploadedCount: uploadedCount,
        downloadedCount: downloadedCount,
        deletedCount: deletedCount,
      );
    } catch (e) {
      AppLogger.error('[SyncEngine] Merge エラー: $e');
      return SyncResult.failure(e.toString());
    }
  }
}

/// フォルダの同期状態
enum FolderSyncStatus {
  /// 同期済み
  synced,
  /// ローカルに変更あり
  localChanges,
  /// Driveに変更あり
  remoteChanges,
  /// 競合あり
  conflict,
  /// Drive未連携
  notLinked,
  /// エラー
  error,
}

/// ファイル変更の種類
enum FileChangeType {
  added,
  modified,
  deleted,
  moved,
  movedAndModified,
}

/// ファイル変更情報
class FileChangeInfo {
  final String fileName;
  final FileChangeType type;
  final String? movedFrom;  // 移動元パス（moved/movedAndModifiedの場合）
  final String? movedTo;    // 移動先パス（moved/movedAndModifiedの場合）

  const FileChangeInfo({
    required this.fileName,
    required this.type,
    this.movedFrom,
    this.movedTo,
  });
}

/// 同期状態の詳細
class FolderSyncStatusDetail {
  final FolderSyncStatus status;
  final int localAdded;
  final int localDeleted;
  final int localModified;
  final int remoteAdded;
  final int remoteDeleted;
  final int remoteModified;
  final int remoteMoved;
  final List<String> localAddedFiles;
  final List<String> localDeletedFiles;
  final List<String> localModifiedFiles;
  final List<String> remoteAddedFiles;
  final List<String> remoteDeletedFiles;
  final List<String> remoteModifiedFiles;
  final List<FileChangeInfo> remoteMovedFiles;

  const FolderSyncStatusDetail({
    required this.status,
    this.localAdded = 0,
    this.localDeleted = 0,
    this.localModified = 0,
    this.remoteAdded = 0,
    this.remoteDeleted = 0,
    this.remoteModified = 0,
    this.remoteMoved = 0,
    this.localAddedFiles = const [],
    this.localDeletedFiles = const [],
    this.localModifiedFiles = const [],
    this.remoteAddedFiles = const [],
    this.remoteDeletedFiles = const [],
    this.remoteModifiedFiles = const [],
    this.remoteMovedFiles = const [],
  });

  /// 変更があるか
  bool get hasLocalChanges =>
      localAdded > 0 || localDeleted > 0 || localModified > 0;
  
  bool get hasRemoteChanges =>
      remoteAdded > 0 || remoteDeleted > 0 || remoteModified > 0 || remoteMoved > 0;
}

/// マージ用の変更タイプ
enum MergeChangeType {
  none,     // 変更なし
  added,    // 追加
  modified, // 変更
  deleted,  // 削除
  moved,    // 移動
}

/// マージの選択結果
enum MergeChoice {
  local,  // ローカルを採用
  remote, // クラウドを採用
}

/// マージ決定情報
class MergeDecision {
  final MergeFileEntry entry;
  final MergeChoice choice;

  const MergeDecision({
    required this.entry,
    required this.choice,
  });
}

/// マージ用のファイルエントリ
class MergeFileEntry {
  /// ファイルの相対パス
  final String relativePath;
  
  /// ローカル側の変更タイプ
  final MergeChangeType localChange;
  
  /// リモート側の変更タイプ
  final MergeChangeType remoteChange;
  
  /// ローカルファイルの更新日時
  final DateTime? localModifiedTime;
  
  /// リモートファイルの更新日時
  final DateTime? remoteModifiedTime;
  
  /// 移動情報（移動の場合）
  final FileChangeInfo? moveInfo;
  
  /// DriveファイルID（既存ファイルの場合）
  final String? driveFileId;

  const MergeFileEntry({
    required this.relativePath,
    required this.localChange,
    required this.remoteChange,
    this.localModifiedTime,
    this.remoteModifiedTime,
    this.moveInfo,
    this.driveFileId,
  });

  /// ローカルの方が新しいか
  bool get isLocalNewer {
    if (localModifiedTime == null) return false;
    if (remoteModifiedTime == null) return true;
    return localModifiedTime!.isAfter(remoteModifiedTime!);
  }
  
  /// 変更があるか（どちらか一方でも変更あり）
  bool get hasChanges => localChange != MergeChangeType.none || remoteChange != MergeChangeType.none;
  
  /// コンフリクト状態か（両方で変更あり）
  bool get isConflict => 
      localChange != MergeChangeType.none && 
      remoteChange != MergeChangeType.none;
}
