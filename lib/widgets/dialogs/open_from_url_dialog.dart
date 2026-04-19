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
// Root Maps: URLからプロジェクトを開くダイアログ
// Google Driveの共有URLを入力してプロジェクトをダウンロード

import 'package:flutter/material.dart';
import '../../i18n/strings.g.dart';

import '../../services/google_drive/index.dart';

/// URLからプロジェクトを開くダイアログの結果
class OpenFromUrlResult {
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

  const OpenFromUrlResult({
    required this.success,
    this.localPath,
    this.folderId,
    this.folderName,
    this.downloadedCount = 0,
    this.errorMessage,
  });
}

/// URLからプロジェクトを開くダイアログ
class OpenFromUrlDialog extends StatefulWidget {
  /// ダウンロード先の親フォルダ
  final String downloadDirectory;

  const OpenFromUrlDialog({
    super.key,
    required this.downloadDirectory,
  });

  /// ダイアログを表示
  static Future<OpenFromUrlResult?> show(
    BuildContext context, {
    required String downloadDirectory,
  }) {
    return showDialog<OpenFromUrlResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => OpenFromUrlDialog(
        downloadDirectory: downloadDirectory,
      ),
    );
  }

  @override
  State<OpenFromUrlDialog> createState() => _OpenFromUrlDialogState();
}

class _OpenFromUrlDialogState extends State<OpenFromUrlDialog> {
  final GoogleDriveService _driveService = GoogleDriveService();
  final SyncEngine _syncEngine = SyncEngine();
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();

  // 状態
  _DialogStep _currentStep = _DialogStep.checkAuth;
  String? _errorMessage;
  String? _folderId;
  String? _folderName;
  SyncProgress? _syncProgress;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _driveService.initialize();

    if (_driveService.authState.isAuthenticated) {
      setState(() => _currentStep = _DialogStep.inputUrl);
      _urlFocusNode.requestFocus();
    } else {
      setState(() => _currentStep = _DialogStep.signIn);
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _currentStep = _DialogStep.checkAuth;
      _errorMessage = null;
    });

    final success = await _driveService.signIn();

    if (success) {
      setState(() => _currentStep = _DialogStep.inputUrl);
      _urlFocusNode.requestFocus();
    } else {
      setState(() {
        _currentStep = _DialogStep.signIn;
        _errorMessage = _driveService.authState.errorMessage;
      });
    }
  }

  Future<void> _validateAndFetch() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _errorMessage = 'URLを入力してください');
      return;
    }

    // URLからフォルダIDを抽出
    final folderId = GoogleDriveService.extractFolderIdFromUrl(url);
    if (folderId == null) {
      setState(() => _errorMessage = t.drive.invalidUrl);
      return;
    }

    setState(() {
      _currentStep = _DialogStep.fetching;
      _errorMessage = null;
    });

    // フォルダ情報を取得
    final folderInfo = await _driveService.getFolderInfo(folderId);
    if (folderInfo == null) {
      setState(() {
        _currentStep = _DialogStep.inputUrl;
        _errorMessage = t.drive.accessDenied;
      });
      return;
    }

    setState(() {
      _folderId = folderId;
      _folderName = folderInfo.name;
      _currentStep = _DialogStep.confirm;
    });
  }

  Future<void> _startDownload() async {
    if (_folderId == null || _folderName == null) return;

    setState(() {
      _currentStep = _DialogStep.downloading;
      _errorMessage = null;
    });

    final localPath = '${widget.downloadDirectory}/$_folderName';

    final result = await _syncEngine.pull(
      _folderId!,
      localPath,
      onProgress: (progress) {
        setState(() => _syncProgress = progress);
      },
    );

    if (result.success) {
      if (mounted) {
        Navigator.of(context).pop(OpenFromUrlResult(
          success: true,
          localPath: localPath,
          folderId: _folderId,
          folderName: _folderName,
          downloadedCount: result.downloadedCount,
        ));
      }
    } else {
      setState(() {
        _currentStep = _DialogStep.confirm;
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
      case _DialogStep.inputUrl:
        return const Text('Open from URL');
      case _DialogStep.fetching:
        return const Text('Checking...');
      case _DialogStep.confirm:
        return const Text('Confirm Download');
      case _DialogStep.downloading:
        return const Text('Downloading...');
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
              'Google Driveからプロジェクトを開くには、Googleアカウントでサインインしてください。',
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              _buildErrorMessage(),
            ],
          ],
        );

      case _DialogStep.inputUrl:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Google Driveの共有URLを貼り付けてください:',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              focusNode: _urlFocusNode,
              decoration: const InputDecoration(
                labelText: 'Google Drive URL',
                hintText: 'https://drive.google.com/drive/folders/...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              onSubmitted: (_) => _validateAndFetch(),
            ),
            const SizedBox(height: 8),
            Text(
              '例: https://drive.google.com/drive/folders/1abc...xyz',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              _buildErrorMessage(),
            ],
          ],
        );

      case _DialogStep.fetching:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(t.drive.fetchingInfo),
          ],
        );

      case _DialogStep.confirm:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder, color: Colors.blue.shade700, size: 40),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _folderName ?? 'Unknown',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Google Drive',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              t.drive.saveTo(path: '${widget.downloadDirectory}/$_folderName'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              _buildErrorMessage(),
            ],
          ],
        );

      case _DialogStep.downloading:
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

  List<Widget> _buildActions() {
    switch (_currentStep) {
      case _DialogStep.checkAuth:
      case _DialogStep.fetching:
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

      case _DialogStep.inputUrl:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: _validateAndFetch,
            icon: const Icon(Icons.search),
            label: const Text('Check'),
          ),
        ];

      case _DialogStep.confirm:
        return [
          TextButton(
            onPressed: () {
              setState(() => _currentStep = _DialogStep.inputUrl);
            },
            child: const Text('Back'),
          ),
          ElevatedButton.icon(
            onPressed: _startDownload,
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
  inputUrl,
  fetching,
  confirm,
  downloading,
}
