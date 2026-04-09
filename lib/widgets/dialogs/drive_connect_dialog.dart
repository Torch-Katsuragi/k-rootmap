// K-MAPS: Google Drive連携ダイアログ
// プロジェクトとDriveフォルダの連携・同期を行うダイアログ

import 'package:flutter/material.dart';
import '../../i18n/strings.g.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../../services/google_drive/index.dart';
import '../../services/kmeta_service.dart';

/// Drive連携ダイアログの結果
class DriveConnectResult {
  /// 成功したか
  final bool success;

  /// DriveフォルダID
  final String? folderId;

  /// Driveフォルダ名
  final String? folderName;

  /// アップロードしたファイル数
  final int uploadedCount;

  const DriveConnectResult({
    required this.success,
    this.folderId,
    this.folderName,
    this.uploadedCount = 0,
  });
}

/// Google Drive連携ダイアログ
/// プロジェクトをDriveに接続し、Pushする
class DriveConnectDialog extends StatefulWidget {
  /// プロジェクトフォルダのパス
  final String projectPath;

  /// プロジェクト名
  final String projectName;

  const DriveConnectDialog({
    super.key,
    required this.projectPath,
    required this.projectName,
  });

  /// ダイアログを表示
  static Future<DriveConnectResult?> show(
    BuildContext context, {
    required String projectPath,
    required String projectName,
  }) {
    return showDialog<DriveConnectResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => DriveConnectDialog(
        projectPath: projectPath,
        projectName: projectName,
      ),
    );
  }

  @override
  State<DriveConnectDialog> createState() => _DriveConnectDialogState();
}

class _DriveConnectDialogState extends State<DriveConnectDialog> {
  final GoogleDriveService _driveService = GoogleDriveService();
  final SyncEngine _syncEngine = SyncEngine();

  // 状態
  _DialogStep _currentStep = _DialogStep.checkAuth;
  String? _errorMessage;
  String? _selectedFolderId;
  bool _createNewFolder = true;
  List<drive.File> _existingFolders = [];

  // 同期進捗
  SyncProgress? _syncProgress;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _driveService.initialize();

    if (_driveService.authState.isAuthenticated) {
      setState(() => _currentStep = _DialogStep.selectFolder);
      await _loadExistingFolders();
    } else {
      setState(() => _currentStep = _DialogStep.signIn);
    }
  }

  Future<void> _loadExistingFolders() async {
    final kmapsFolder = await _driveService.getOrCreateKMapsFolder();
    if (kmapsFolder != null) {
      final folders = await _driveService.listFolders(kmapsFolder.id!);
      setState(() => _existingFolders = folders);
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _currentStep = _DialogStep.checkAuth;
      _errorMessage = null;
    });

    final success = await _driveService.signIn();

    if (success) {
      setState(() => _currentStep = _DialogStep.selectFolder);
      await _loadExistingFolders();
    } else {
      setState(() {
        _currentStep = _DialogStep.signIn;
        _errorMessage = _driveService.authState.errorMessage;
      });
    }
  }

  Future<void> _startSync() async {
    setState(() {
      _currentStep = _DialogStep.syncing;
      _errorMessage = null;
    });

    final result = await _syncEngine.push(
      widget.projectPath,
      driveFolder: _createNewFolder ? null : _selectedFolderId,
      onProgress: (progress) {
        setState(() => _syncProgress = progress);
      },
    );

    if (result.success) {
      // 同期情報を取得
      final kmeta = await KMetaService.instance.getRawMeta(widget.projectPath);
      
      if (mounted) {
        Navigator.of(context).pop(DriveConnectResult(
          success: true,
          folderId: kmeta?.sync.driveId,
          folderName: kmeta?.sync.driveFolderName ?? widget.projectName,
          uploadedCount: result.uploadedCount,
        ));
      }
    } else {
      setState(() {
        _currentStep = _DialogStep.selectFolder;
        _errorMessage = result.errorMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: _buildTitle(),
      content: SizedBox(
        width: 400,
        child: _buildContent(),
      ),
      actions: _buildActions(),
    );
  }

  Widget _buildTitle() {
    switch (_currentStep) {
      case _DialogStep.checkAuth:
        return const Text('Connecting...');
      case _DialogStep.signIn:
        return const Text('Sign in to Google');
      case _DialogStep.selectFolder:
        return const Text('Connect to Drive');
      case _DialogStep.syncing:
        return const Text('Uploading...');
    }
  }

  Widget _buildContent() {
    switch (_currentStep) {
      case _DialogStep.checkAuth:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(t.drive.checkingAuth),
          ],
        );

      case _DialogStep.signIn:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Google Driveにプロジェクトを保存するには、Googleアカウントでサインインしてください。',
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );

      case _DialogStep.selectFolder:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ユーザー情報
            if (_driveService.authState.user != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_circle, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _driveService.authState.user!.email,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await _driveService.signOut();
                        setState(() => _currentStep = _DialogStep.signIn);
                      },
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),

            // フォルダ選択
            Text(t.drive.targetFolder),
            const SizedBox(height: 8),

            // フォルダ作成オプション
            RadioGroup<bool>(
              groupValue: _createNewFolder,
              onChanged: (value) {
                setState(() {
                  _createNewFolder = value!;
                  if (_createNewFolder) _selectedFolderId = null;
                });
              },
              child: Column(
                children: [
                  RadioListTile<bool>(
                    title: Text(t.drive.newFolder(name: widget.projectName)),
                    subtitle: const Text('K-MAPS Projectsフォルダ内に作成'),
                    value: true,
                  ),

                  // 既存フォルダ選択オプション
                  if (_existingFolders.isNotEmpty)
                    RadioListTile<bool>(
                      title: Text(t.drive.selectExisting),
                      value: false,
                    ),
                ],
              ),
            ),

            if (_existingFolders.isNotEmpty) ...[
              if (!_createNewFolder)
                Container(
                  margin: const EdgeInsets.only(left: 32),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedFolderId,
                    hint: Text(t.drive.selectFolderHint),
                    items: _existingFolders.map((folder) {
                      return DropdownMenuItem<String>(
                        value: folder.id,
                        child: Text(folder.name ?? 'Unknown'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedFolderId = value;
                      });
                    },
                  ),
                ),
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );

      case _DialogStep.syncing:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: _syncProgress?.progress,
            ),
            const SizedBox(height: 16),
            Text(
              _syncProgress?.currentFile ?? 'Preparing...',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_syncProgress != null) ...[
              Text(
                '${_syncProgress!.processedCount} / ${_syncProgress!.totalCount}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_syncProgress!.sizeProgressText != null)
                Text(
                  _syncProgress!.sizeProgressText!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ],
        );
    }
  }

  List<Widget> _buildActions() {
    switch (_currentStep) {
      case _DialogStep.checkAuth:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ];

      case _DialogStep.signIn:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: _signIn,
            icon: const Icon(Icons.login),
            label: const Text('Sign in with Google'),
          ),
        ];

      case _DialogStep.selectFolder:
        final canSync = _createNewFolder || _selectedFolderId != null;
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: canSync ? _startSync : null,
            icon: const Icon(Icons.cloud_upload),
            label: const Text('Upload to Drive'),
          ),
        ];

      case _DialogStep.syncing:
        return [];
    }
  }
}

/// ダイアログのステップ
enum _DialogStep {
  checkAuth,
  signIn,
  selectFolder,
  syncing,
}
