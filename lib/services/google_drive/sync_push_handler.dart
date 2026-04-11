// Root Maps: 同期Pushハンドラー
// ローカル→Google DriveへのPush（アップロード）処理を担当

import 'dart:convert';
import 'dart:io';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;

import '../../models/kmeta.dart';
import '../../utils/app_logger.dart';
import '../../i18n/strings.g.dart';
import '../kmeta_service.dart';
import 'google_drive_service.dart';
import 'sync_engine.dart';
import 'sync_file_operations.dart';

/// Push（アップロード）処理ハンドラー
class SyncPushHandler {
  final GoogleDriveService _driveService;
  final KMetaService _kmetaService;
  final SyncFileOperations _fileOps;

  static const int _uploadConcurrency = 3;

  SyncPushHandler({
    required GoogleDriveService driveService,
    required KMetaService kmetaService,
    required SyncFileOperations fileOps,
  })  : _driveService = driveService,
        _kmetaService = kmetaService,
        _fileOps = fileOps;

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
      return SyncResult.failure(t.drive.driveNotConnected);
    }

    try {
      final previousMeta = await _kmetaService.getMergedMeta(projectPath);
      final previousSyncedFiles = previousMeta.sync.files;

      final projectDir = Directory(projectPath);
      if (!await projectDir.exists()) {
        return SyncResult.failure(t.services.projectNotFound);
      }

      String targetFolderId;
      String targetFolderName;

      if (driveFolder != null) {
        targetFolderId = driveFolder;
        final folderInfo = await _driveService.getFolderInfo(driveFolder);
        targetFolderName = folderInfo?.name ?? 'Unknown';
      } else {
        final projectName = p.basename(projectPath);
        final created = await _driveService.createProjectFolder(projectName);
        if (created == null) {
          return SyncResult.failure(t.drive.driveFolderCreateFailed);
        }
        targetFolderId = created.id!;
        targetFolderName = created.name!;
      }

      final filesToSync = await _fileOps.collectSyncFiles(projectPath);
      if (filesToSync.isEmpty) {
        return SyncResult.success(skippedCount: 0);
      }

      final folderIdCache = <String, String>{};

      // Drive上の現在のファイル配置を取得し、ID↔パスの突合で移動を検出
      int movedCount = 0;
      final movedFileIds = <String>{};

      final driveEntries =
          await _fileOps.listDriveFilesRecursive(targetFolderId);
      final driveIdToEntry = <String, DriveFileEntry>{};
      for (final e in driveEntries) {
        if (e.file.id != null) driveIdToEntry[e.file.id!] = e;
      }

      for (final entry in previousSyncedFiles.entries) {
        final syncedPath = entry.key;
        if (p.basename(syncedPath) == kMetaFileName) continue;
        final driveFileId = entry.value.driveFileId;
        final driveEntry = driveIdToEntry[driveFileId];
        if (driveEntry == null) continue;
        if (driveEntry.relativePath == syncedPath) continue;

        // syncedFilesのパスとDrive上のパスが異なる → ローカルで移動された
        final relativeDir = p.posix.dirname(syncedPath);
        final newParentId = await _fileOps.getDriveFolderIdForRelativeDir(
          targetFolderId, relativeDir, folderIdCache,
        );
        if (newParentId != null) {
          final oldParentId = driveEntry.file.parents?.firstOrNull;
          final moved = await _driveService.moveFile(
            driveFileId,
            newParentId: newParentId,
            oldParentId: oldParentId,
          );
          if (moved) {
            movedCount++;
            movedFileIds.add(driveFileId);
            AppLogger.debug(
              '[SyncEngine] Drive上で移動: ${driveEntry.relativePath} → $syncedPath',
            );
          }
        }
      }

      AppLogger.debug(
        '[SyncEngine] Push開始: ${filesToSync.length}ファイル → $targetFolderName (移動: $movedCount)',
      );

      int uploadedCount = 0;
      int skippedCount = 0;
      int completedCount = 0;
      final syncedFiles = <String, KMetaSyncFile>{};

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

        final targetFolderForFile = await _fileOps.getDriveFolderIdForRelativeDir(
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
        resolvedFolders[i] = await _fileOps.getDriveFolderIdForRelativeDir(
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

      // 通常ファイルを並列アップロード
      await SyncFileOperations.runParallel(
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

      for (final entry in previousSyncedFiles.entries) {
        if (!localFilePaths.contains(entry.key)) {
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

      final currentDriveEntries =
          await _fileOps.listDriveFilesRecursive(targetFolderId);

      for (final entry in currentDriveEntries) {
        if (deletedFileIds.contains(entry.file.id)) {
          continue;
        }
        if (movedFileIds.contains(entry.file.id)) {
          continue;
        }
        final drivePath = entry.relativePath;
        if (!localFilePaths.contains(drivePath)) {
          final deleted = await _driveService.deleteFile(entry.file.id!);
          if (deleted) {
            deletedCount++;
            AppLogger.debug('[SyncEngine] Driveから削除: $drivePath');
          }
        }
      }

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

      if (uploadedCount == 0 && filesToSync.isNotEmpty) {
        return SyncResult.failure(
          t.services.uploadFailed(count: skippedCount.toString()),
        );
      }

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
      return SyncResult.failure(t.services.syncError(error: e.toString()));
    }
  }

  /// フォルダ単位でPush
  Future<SyncResult> pushFolder(String localPath) async {
    final meta = await _kmetaService.getMergedMeta(localPath);
    final driveId = meta.sync.driveId;

    if (driveId == null) {
      return SyncResult.failure(t.drive.driveNotLinked);
    }

    return push(localPath, driveFolder: driveId);
  }

  /// .kmeta.jsonをアップロード（deviceIdを除外）
  Future<bool> _uploadKmetaFile(File file, String targetFolderId) async {
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      final kmeta = KMeta.fromJson(json);
      final syncJson = kmeta.sync.toJsonForSync();

      final syncedJson = kmeta.toJson();
      if (syncedJson.containsKey('sync')) {
        syncedJson['sync'] = syncJson;
      }

      final tempDir = Directory.systemTemp;
      final tempFile = File(p.join(tempDir.path, kMetaFileName));
      await tempFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(syncedJson),
      );

      final result = await _driveService.uploadFile(tempFile, targetFolderId);

      await tempFile.delete();

      return result != null;
    } catch (e) {
      AppLogger.debug('[SyncEngine] kmeta.jsonアップロードエラー: $e');
      return false;
    }
  }
}
