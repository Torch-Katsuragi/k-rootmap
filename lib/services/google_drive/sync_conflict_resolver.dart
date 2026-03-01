// K-MAPS: 同期コンフリクト解決
// 同期状態チェック、マージエントリ取得、マージ実行を担当

import 'dart:io';
import 'package:path/path.dart' as p;

import '../../models/kmeta.dart';
import '../../utils/app_logger.dart';
import '../kmeta_service.dart';
import 'google_drive_service.dart';
import 'sync_engine.dart';
import 'sync_file_operations.dart';

/// コンフリクト解決ハンドラー
class SyncConflictResolver {
  final GoogleDriveService _driveService;
  final KMetaService _kmetaService;
  final SyncFileOperations _fileOps;

  SyncConflictResolver({
    required GoogleDriveService driveService,
    required KMetaService kmetaService,
    required SyncFileOperations fileOps,
  })  : _driveService = driveService,
        _kmetaService = kmetaService,
        _fileOps = fileOps;

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
      final meta = await _kmetaService.getMergedMeta(localPath);
      final driveId = meta.sync.driveId;
      final syncedFiles = meta.sync.files;

      if (driveId == null) {
        return const FolderSyncStatusDetail(status: FolderSyncStatus.notLinked);
      }

      final folderInfo = await _driveService.getFolderInfo(driveId);
      if (folderInfo == null) {
        return const FolderSyncStatusDetail(status: FolderSyncStatus.error);
      }

      final driveData = await _fileOps.listDriveFilesWithFolders(driveId);
      final driveAllEntries = driveData.files;
      final driveFolderMap = driveData.folderMap;

      final driveIdMap = <String, DriveFileEntry>{};
      for (final entry in driveAllEntries) {
        final fileId = entry.file.id;
        if (fileId != null) driveIdMap[fileId] = entry;
      }

      final localDir = Directory(localPath);
      final localFiles = <String, DateTime>{};
      if (await localDir.exists()) {
        await for (final entity in localDir.list(recursive: true)) {
          final fileName = p.basename(entity.path);
          if (fileName == kMetaFileName) continue;
          if (entity is File && _fileOps.matchesSyncPattern(fileName)) {
            final relativePath = _fileOps.normalizeRelativePath(
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

      for (final entry in syncedFiles.entries) {
        final fileName = entry.key;
        if (p.basename(fileName) == kMetaFileName) continue;

        final syncInfo = entry.value;
        final lastSyncedTime = syncInfo.lastSyncedTime;
        final expectedParentId = syncInfo.expectedParentId;

        final driveEntry = driveIdMap[syncInfo.driveFileId];

        if (driveEntry == null) {
          remoteDeleted++;
          remoteDeletedFiles.add(fileName);
        } else {
          final driveFile = driveEntry.file;
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

      localAdded = localFiles.length;
      if (localFiles.isNotEmpty) {
        localAddedFiles.addAll(localFiles.keys);
      }

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

  /// マージ用のファイルエントリ一覧を取得
  Future<List<MergeFileEntry>> getMergeEntries(String localPath) async {
    final entries = <MergeFileEntry>[];

    try {
      final meta = await _kmetaService.getMergedMeta(localPath);
      final driveId = meta.sync.driveId;
      final syncedFiles = meta.sync.files;

      if (driveId == null) {
        return entries;
      }

      final localFilesFuture = _fileOps.scanLocalFiles(localPath);
      final folderInfo = await _driveService.getFolderInfo(driveId);
      if (folderInfo == null) {
        return entries;
      }

      final driveData = await _fileOps.listDriveFilesWithFolders(driveId);
      final driveAllEntries = driveData.files;
      final driveFolderMap = driveData.folderMap;

      final driveIdMap = <String, DriveFileEntry>{};
      for (final entry in driveAllEntries) {
        final fileId = entry.file.id;
        if (fileId != null) driveIdMap[fileId] = entry;
      }

      final localFiles = await localFilesFuture;

      final processedFiles = <String>{};

      final movedFileIds = <String>{};
      final movedToPathSet = <String>{};

      for (final entry in syncedFiles.entries) {
        final fileName = entry.key;
        if (p.basename(fileName) == kMetaFileName) continue;

        final syncInfo = entry.value;
        final lastSyncedTime = syncInfo.lastSyncedTime;
        final expectedParentId = syncInfo.expectedParentId;

        final driveEntry = driveIdMap[syncInfo.driveFileId];

        MergeChangeType localChange = MergeChangeType.none;
        MergeChangeType remoteChange = MergeChangeType.none;
        DateTime? localModTime;
        DateTime? remoteModTime = driveEntry?.file.modifiedTime;
        FileChangeInfo? moveInfo;

        if (driveEntry == null) {
          remoteChange = MergeChangeType.deleted;
        } else {
          final driveFile = driveEntry.file;
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

          if (remoteChange == MergeChangeType.none) {
            if (lastSyncedTime != null &&
                driveFile.modifiedTime != null &&
                driveFile.modifiedTime!.isAfter(lastSyncedTime)) {
              remoteChange = MergeChangeType.modified;
            }
          }
        }

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

      for (final entry in localFiles.entries) {
        entries.add(MergeFileEntry(
          relativePath: entry.key,
          localChange: MergeChangeType.added,
          remoteChange: MergeChangeType.none,
          localModifiedTime: entry.value,
          remoteModifiedTime: null,
        ));
      }

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

      final folderIdCache = <String, String>{};

      AppLogger.debug('[SyncEngine] executeMerge開始: ${decisions.length}件の決定');

      for (final decision in decisions) {
        final entry = decision.entry;
        final choice = decision.choice;
        final relativePath = entry.relativePath;
        final localFilePath = _fileOps.relativePathToLocalPath(localPath, relativePath);

        AppLogger.debug('[SyncEngine] 処理: $relativePath');
        AppLogger.debug('  choice: $choice');
        AppLogger.debug('  localChange: ${entry.localChange}');
        AppLogger.debug('  remoteChange: ${entry.remoteChange}');
        AppLogger.debug('  driveFileId: ${entry.driveFileId}');

        if (choice == MergeChoice.local) {
          switch (entry.localChange) {
            case MergeChangeType.added:
            case MergeChangeType.modified:
              final file = File(localFilePath);
              if (await file.exists()) {
                final relativeDir = p.dirname(relativePath);
                String targetFolderId = driveId;
                if (relativeDir != '.' && relativeDir.isNotEmpty) {
                  final folderId = await _fileOps.getDriveFolderIdForRelativeDir(
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
              if (entry.driveFileId != null) {
                await _driveService.deleteFile(entry.driveFileId!);
                syncedFiles.remove(relativePath);
                deletedCount++;
              }
              break;
            case MergeChangeType.none:
              AppLogger.debug('  → ローカル変更なし、リモート変更を復元: ${entry.remoteChange}');
              switch (entry.remoteChange) {
                case MergeChangeType.deleted:
                  final file = File(localFilePath);
                  if (await file.exists()) {
                    final relativeDir = p.dirname(relativePath);
                    String targetFolderId = driveId;
                    if (relativeDir != '.' && relativeDir.isNotEmpty) {
                      final folderId = await _fileOps.getDriveFolderIdForRelativeDir(
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
                  AppLogger.debug('  → リモート追加を削除（復元）');
                  if (entry.driveFileId != null) {
                    AppLogger.debug('    削除対象driveFileId: ${entry.driveFileId}');

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
                      syncedFiles.remove(relativePath);
                    }
                  } else {
                    AppLogger.debug('    driveFileIdがnullのためスキップ');
                  }
                  break;
                case MergeChangeType.modified:
                  final file = File(localFilePath);
                  if (await file.exists()) {
                    final relativeDir = p.dirname(relativePath);
                    String targetFolderId = driveId;
                    if (relativeDir != '.' && relativeDir.isNotEmpty) {
                      final folderId = await _fileOps.getDriveFolderIdForRelativeDir(
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
                case MergeChangeType.moved:
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
                  break;
              }
              break;
            case MergeChangeType.moved:
              break;
          }
        } else {
          // リモートを採用
          switch (entry.remoteChange) {
            case MergeChangeType.added:
            case MergeChangeType.modified:
              if (entry.driveFileId != null) {
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
            case MergeChangeType.deleted:
              final file = File(localFilePath);
              if (await file.exists()) {
                await file.delete();
                syncedFiles.remove(relativePath);
                deletedCount++;
              }
              break;
            case MergeChangeType.moved:
              if (entry.moveInfo != null && entry.driveFileId != null) {
                final oldPath = _fileOps.relativePathToLocalPath(localPath, entry.moveInfo!.movedFrom ?? relativePath);
                final newPath = _fileOps.relativePathToLocalPath(localPath, entry.moveInfo!.movedTo ?? relativePath);
                final oldFile = File(oldPath);
                if (await oldFile.exists()) {
                  final newDir = Directory(p.dirname(newPath));
                  if (!await newDir.exists()) {
                    await newDir.create(recursive: true);
                  }
                  await oldFile.rename(newPath);
                  syncedFiles.remove(entry.moveInfo!.movedFrom ?? relativePath);

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
              switch (entry.localChange) {
                case MergeChangeType.deleted:
                  if (entry.driveFileId != null) {
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
                  final file = File(localFilePath);
                  if (await file.exists()) {
                    await file.delete();
                    syncedFiles.remove(relativePath);
                    deletedCount++;
                  }
                  break;
                case MergeChangeType.modified:
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
                  break;
                case MergeChangeType.none:
                  break;
              }
              break;
          }
        }
      }

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
