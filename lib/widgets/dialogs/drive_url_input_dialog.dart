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
// Root Maps: Drive URL入力ダイアログ
// Google DriveフォルダのURLを入力またはQRスキャンしてクローンする

import 'package:flutter/material.dart';
import '../../core/platform_capabilities.dart';
import 'package:flutter/services.dart';
import '../../i18n/strings.g.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/google_drive/index.dart';
import '../auth/google_sign_in_button.dart';
import '../../utils/app_logger.dart';

/// Drive URL入力ダイアログの結果
class DriveUrlInputResult {
  /// DriveフォルダID
  final String folderId;

  /// Driveフォルダ名
  final String folderName;

  /// 元のURL
  final String url;

  /// 読み取り専用か
  final bool isReadOnly;

  const DriveUrlInputResult({
    required this.folderId,
    required this.folderName,
    required this.url,
    required this.isReadOnly,
  });
}

/// Drive URL入力ダイアログ
class DriveUrlInputDialog extends StatefulWidget {
  const DriveUrlInputDialog({super.key});

  /// ダイアログを表示
  static Future<DriveUrlInputResult?> show(BuildContext context) {
    return showDialog<DriveUrlInputResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const DriveUrlInputDialog(),
    );
  }

  @override
  State<DriveUrlInputDialog> createState() => _DriveUrlInputDialogState();
}

class _DriveUrlInputDialogState extends State<DriveUrlInputDialog>
    with SingleTickerProviderStateMixin {
  final GoogleDriveService _driveService = GoogleDriveService();
  final TextEditingController _urlController = TextEditingController();

  late TabController _tabController;

  bool _isLoading = false;
  bool _isSignedIn = false;
  String? _errorMessage;
  String? _folderName;
  String? _folderId;
  bool? _isReadOnly;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _hasQrTab ? 2 : 1, vsync: this);
    // One Tap は開いた後から返ってくる。届いたらボタンを差し替える
    _driveService.authState.addListener(_onAuthChanged);
    _initializeAuth();
  }

  @override
  void dispose() {
    _driveService.authState.removeListener(_onAuthChanged);
    _tabController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    setState(() => _isSignedIn = _driveService.authState.isAuthenticated);
  }

  /// 認証状態を初期化
  Future<void> _initializeAuth() async {
    setState(() => _isLoading = true);
    try {
      await _driveService.initialize();
      _isSignedIn = _driveService.authState.isAuthenticated;
    } catch (e) {
      AppLogger.error('[DriveUrlInputDialog] 初期化エラー: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Googleサインイン
  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final success = await _driveService.signIn();
      if (success) {
        _isSignedIn = true;
      } else {
        _errorMessage = t.drive.signInFailed;
      }
    } catch (e) {
      _errorMessage = t.drive.signInError(error: e.toString());
      AppLogger.error('[DriveUrlInputDialog] サインインエラー: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// クリップボードから貼り付け
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _urlController.text = data!.text!;
      _validateUrl();
    }
  }

  /// URLを検証してフォルダ情報を取得
  Future<void> _validateUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _errorMessage = null;
        _folderName = null;
        _folderId = null;
        _isReadOnly = null;
      });
      return;
    }

    // URLからフォルダIDを抽出
    final folderId = GoogleDriveService.extractFolderIdFromUrl(url);
    if (folderId == null) {
      setState(() {
        _errorMessage = t.drive.invalidUrl;
        _folderName = null;
        _folderId = null;
        _isReadOnly = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // フォルダ情報を取得
      final folderInfo = await _driveService.getFolderInfo(folderId);
      if (folderInfo == null) {
        setState(() {
          _errorMessage = t.drive.accessDenied;
          _folderName = null;
          _folderId = null;
          _isReadOnly = null;
        });
        return;
      }

      // 権限を確認（編集可能かどうか）
      final capabilities = folderInfo.capabilities;
      final canEdit = capabilities?.canEdit ?? false;

      setState(() {
        _folderId = folderId;
        _folderName = folderInfo.name ?? 'Unknown';
        _isReadOnly = !canEdit;
        _errorMessage = null;
      });
    } catch (e) {
      AppLogger.error('[DriveUrlInputDialog] フォルダ情報取得エラー: $e');
      setState(() {
        _errorMessage = t.drive.fetchError(error: e.toString());
        _folderName = null;
        _folderId = null;
        _isReadOnly = null;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// クローン実行
  void _onClone() {
    if (_folderId == null || _folderName == null) return;

    Navigator.pop(
      context,
      DriveUrlInputResult(
        folderId: _folderId!,
        folderName: _folderName!,
        url: _urlController.text.trim(),
        isReadOnly: _isReadOnly ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.cloud, color: Colors.blue),
          SizedBox(width: 8),
          Text('Driveフォルダを追加'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // タブバー（QRスキャンはカメラのある端末だけ）
            TabBar(
              controller: _tabController,
              tabs: [
                const Tab(text: 'URL入力'),
                if (_hasQrTab) const Tab(text: 'QRスキャン'),
              ],
            ),
            const SizedBox(height: 16),

            // タブコンテンツ
            SizedBox(
              height: 250,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildUrlInputTab(),
                  if (_hasQrTab) _buildQrScanTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.common.cancel),
        ),
        TextButton(
          onPressed: _canClone() ? _onClone : null,
          child: Text(t.drive.clone),
        ),
      ],
    );
  }

  /// QRスキャンのタブを出すか
  bool get _hasQrTab => PlatformCapabilities.supportsQrScan;

  /// 未サインインのときの案内
  ///
  /// ⚠ web は「アカウントを選ぶ」と「Driveへのアクセスを許可」が別の操作で、
  /// 前者は Google が描画したボタンでしか、後者はクリックの直下でしか通らない。
  /// **どちらが要るかは状態で決まる**ので、出すボタンは常に1つに絞る。
  /// （native はアカウント選択と認可が `signIn()` 1回で済む）
  Widget _buildSignInPrompt() {
    // アカウントがまだ無い web は、Googleが描画するボタンだけが入口
    final needsAccount = !_driveService.hasAccount;
    final rendered = needsAccount ? googleRenderedSignInButton() : null;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.account_circle, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            needsAccount
                ? 'Googleアカウントにサインインしてください'
                : 'Google Driveへのアクセスを許可してください',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (rendered != null)
            SizedBox(height: 44, child: rendered)
          else
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _signIn,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(needsAccount ? 'Googleでサインイン' : 'アクセスを許可'),
            ),
        ],
      ),
    );
  }

  /// URL入力タブ
  Widget _buildUrlInputTab() {
    if (!_isSignedIn) return _buildSignInPrompt();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // URL入力フィールド
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: 'Google Drive URL',
              hintText: 'https://drive.google.com/drive/folders/...',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste),
                onPressed: _pasteFromClipboard,
                tooltip: t.drive.paste,
              ),
            ),
            onChanged: (_) => _validateUrl(),
            maxLines: 2,
          ),
          const SizedBox(height: 16),

          // ローディング
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),

          // エラーメッセージ
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // フォルダ情報
          if (_folderName != null && !_isLoading)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        t.drive.folderDetected,
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.folder,
                        color: Colors.blue.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _folderName!,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        _isReadOnly == true ? Icons.visibility : Icons.edit,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isReadOnly == true ? t.drive.readOnly : t.drive.editable,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// QRスキャンタブ
  Widget _buildQrScanTab() {
    if (!_isSignedIn) return _buildSignInPrompt();

    return Column(
      children: [
        // QRスキャナー
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: MobileScanner(
              onDetect: _onQrDetected,
            ),
          ),
        ),
        const SizedBox(height: 8),
        
        // スキャン結果
        if (_folderName != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _folderName!,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _isReadOnly == true ? t.drive.readOnly : t.drive.editable,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// QRコード検出時の処理
  void _onQrDetected(BarcodeCapture capture) {
    if (_isLoading) return;
    
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null) continue;
      
      // Google Drive URLかチェック
      if (value.contains('drive.google.com')) {
        _urlController.text = value;
        _validateUrl();
        
        // URL入力タブに切り替え（結果を見せる）
        _tabController.animateTo(0);
        break;
      }
    }
  }

  /// クローン可能か
  bool _canClone() {
    return _folderId != null && _folderName != null && !_isLoading;
  }
}
