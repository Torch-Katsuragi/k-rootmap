// Root Maps: Driveフォルダ選択ダイアログ
// Google Driveからプロジェクトフォルダを選択してダウンロード

import 'package:flutter/material.dart';
import '../../i18n/strings.g.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../../services/google_drive/index.dart';

/// Driveフォルダ選択ダイアログの結果
class DriveFolderPickerResult {
  /// 成功したか
  final bool success;

  /// ダウンロード先のローカルパス
  final String? localPath;

  /// DriveフォルダID
  final String? folderId;

  /// フォルダ名
  final String? folderName;

  /// ダウンロードしたファイル数
  final int downloadedCount;

  /// エラーメッセージ
  final String? errorMessage;

  const DriveFolderPickerResult({
    required this.success,
    this.localPath,
    this.folderId,
    this.folderName,
    this.downloadedCount = 0,
    this.errorMessage,
  });
}

/// Driveフォルダ選択ダイアログ
class DriveFolderPicker extends StatefulWidget {
  /// ダウンロード先の親フォルダ
  final String downloadDirectory;

  const DriveFolderPicker({
    super.key,
    required this.downloadDirectory,
  });

  /// ダイアログを表示
  static Future<DriveFolderPickerResult?> show(
    BuildContext context, {
    required String downloadDirectory,
  }) {
    return showDialog<DriveFolderPickerResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => DriveFolderPicker(
        downloadDirectory: downloadDirectory,
      ),
    );
  }

  @override
  State<DriveFolderPicker> createState() => _DriveFolderPickerState();
}

class _DriveFolderPickerState extends State<DriveFolderPicker> {
  final GoogleDriveService _driveService = GoogleDriveService();
  final SyncEngine _syncEngine = SyncEngine();

  // 状態
  _DialogStep _currentStep = _DialogStep.checkAuth;
  String? _errorMessage;
  List<drive.File> _folders = [];
  drive.File? _selectedFolder;
  SyncProgress? _syncProgress;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _driveService.initialize();

    if (_driveService.authState.isAuthenticated) {
      setState(() => _currentStep = _DialogStep.loading);
      await _loadFolders();
    } else {
      setState(() => _currentStep = _DialogStep.signIn);
    }
  }

  Future<void> _loadFolders() async {
    try {
      final rootMapsFolder = await _driveService.getOrCreateRootMapsFolder();
      if (rootMapsFolder != null) {
        final folders = await _driveService.listFolders(rootMapsFolder.id!);
        setState(() {
          _folders = folders;
          _currentStep = _DialogStep.selectFolder;
        });
      } else {
        setState(() {
          _currentStep = _DialogStep.selectFolder;
          _errorMessage = 'K-RootMapフォルダにアクセスできません';
        });
      }
    } catch (e) {
      setState(() {
        _currentStep = _DialogStep.selectFolder;
        _errorMessage = t.drive.listError(error: e.toString());
      });
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _currentStep = _DialogStep.checkAuth;
      _errorMessage = null;
    });

    final success = await _driveService.signIn();

    if (success) {
      setState(() => _currentStep = _DialogStep.loading);
      await _loadFolders();
    } else {
      setState(() {
        _currentStep = _DialogStep.signIn;
        _errorMessage = _driveService.authState.errorMessage;
      });
    }
  }

  Future<void> _startDownload() async {
    if (_selectedFolder == null) return;

    setState(() {
      _currentStep = _DialogStep.downloading;
      _errorMessage = null;
    });

    final folderName = _selectedFolder!.name ?? 'Unknown';
    final localPath = '${widget.downloadDirectory}/$folderName';

    final result = await _syncEngine.pull(
      _selectedFolder!.id!,
      localPath,
      onProgress: (progress) {
        setState(() => _syncProgress = progress);
      },
    );

    if (result.success) {
      if (mounted) {
        Navigator.of(context).pop(DriveFolderPickerResult(
          success: true,
          localPath: localPath,
          folderId: _selectedFolder!.id,
          folderName: folderName,
          downloadedCount: result.downloadedCount,
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
        width: 450,
        height: 400,
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
      case _DialogStep.loading:
        return const Text('Loading...');
      case _DialogStep.selectFolder:
        return const Text('Open from Drive');
      case _DialogStep.downloading:
        return const Text('Downloading...');
    }
  }

  Widget _buildContent() {
    switch (_currentStep) {
      case _DialogStep.checkAuth:
      case _DialogStep.loading:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(t.drive.loading),
            ],
          ),
        );

      case _DialogStep.signIn:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Google Driveからプロジェクトを開くには、Googleアカウントでサインインしてください。',
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              _buildErrorMessage(),
            ],
          ],
        );

      case _DialogStep.selectFolder:
        return Column(
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
                  ],
                ),
              ),

            const Text('Root Maps Projectsフォルダ:'),
            const SizedBox(height: 8),

            // フォルダ一覧
            Expanded(
              child: _folders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder_off,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t.drive.noProjectFolders,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _folders.length,
                      itemBuilder: (context, index) {
                        final folder = _folders[index];
                        final isSelected = _selectedFolder?.id == folder.id;
                        return ListTile(
                          leading: Icon(
                            Icons.folder,
                            color: isSelected
                                ? Colors.blue
                                : Colors.amber.shade700,
                          ),
                          title: Text(folder.name ?? 'Unknown'),
                          subtitle: folder.modifiedTime != null
                              ? Text(
                                  _formatDate(folder.modifiedTime!),
                                  style: const TextStyle(fontSize: 12),
                                )
                              : null,
                          selected: isSelected,
                          selectedTileColor: Colors.blue.shade50,
                          onTap: () {
                            setState(() => _selectedFolder = folder);
                          },
                        );
                      },
                    ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              _buildErrorMessage(),
            ],
          ],
        );

      case _DialogStep.downloading:
        return Center(
          child: Column(
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
          ),
        );
    }
  }

  Widget _buildErrorMessage() {
    return Container(
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
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  List<Widget> _buildActions() {
    switch (_currentStep) {
      case _DialogStep.checkAuth:
      case _DialogStep.loading:
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
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton.icon(
            onPressed: _loadFolders,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
          ElevatedButton.icon(
            onPressed: _selectedFolder != null ? _startDownload : null,
            icon: const Icon(Icons.cloud_download),
            label: const Text('Download'),
          ),
        ];

      case _DialogStep.downloading:
        return [];
    }
  }
}

/// ダイアログのステップ
enum _DialogStep {
  checkAuth,
  signIn,
  loading,
  selectFolder,
  downloading,
}
