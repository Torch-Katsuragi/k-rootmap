// Root Maps: Drive URL入力ダイアログ
// Google DriveフォルダのURLを入力またはQRスキャンしてクローンする

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../i18n/strings.g.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/google_drive/index.dart';
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
    _tabController = TabController(length: 2, vsync: this);
    _initializeAuth();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _urlController.dispose();
    super.dispose();
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
            // タブバー
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'URL入力'),
                Tab(text: 'QRスキャン'),
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
                  _buildQrScanTab(),
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

  /// URL入力タブ
  Widget _buildUrlInputTab() {
    // 未サインインの場合
    if (!_isSignedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_circle, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Googleアカウントにサインインしてください'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _signIn,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: const Text('Googleでサインイン'),
            ),
          ],
        ),
      );
    }

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
    // PCではQRスキャン非対応
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_scanner, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'QRスキャンはスマホ専用です',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // 未サインインの場合
    if (!_isSignedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_circle, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Googleアカウントにサインインしてください'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _signIn,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: const Text('Googleでサインイン'),
            ),
          ],
        ),
      );
    }

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
