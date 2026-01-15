// K-MAPS: フォルダ種類選択ダイアログ
// 新規フォルダ作成時に「通常フォルダ」か「Drive連携フォルダ」かを選択

import 'dart:io';
import 'package:flutter/material.dart';

/// フォルダ追加の種類
enum AddFolderType {
  /// 通常のローカルフォルダ
  local,
  /// Google Drive連携フォルダ
  drive,
}

/// フォルダ種類選択ダイアログの結果
class AddFolderTypeResult {
  final AddFolderType type;
  final String? folderName; // 通常フォルダの場合のみ

  const AddFolderTypeResult({
    required this.type,
    this.folderName,
  });
}

/// フォルダ種類選択ダイアログ
class AddFolderTypeDialog extends StatefulWidget {
  const AddFolderTypeDialog({super.key});

  /// ダイアログを表示
  /// スマホの場合のみDriveオプションを表示
  static Future<AddFolderTypeResult?> show(BuildContext context) {
    return showDialog<AddFolderTypeResult>(
      context: context,
      builder: (context) => const AddFolderTypeDialog(),
    );
  }

  @override
  State<AddFolderTypeDialog> createState() => _AddFolderTypeDialogState();
}

class _AddFolderTypeDialogState extends State<AddFolderTypeDialog> {
  final TextEditingController _nameController = TextEditingController();
  AddFolderType _selectedType = AddFolderType.local;

  /// スマホかどうか（Drive連携はスマホ限定）
  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新規フォルダ'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // フォルダ種類選択（スマホのみDriveオプション表示）
            if (_isMobile) ...[
              const Text(
                'フォルダの種類',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              _buildTypeOption(
                type: AddFolderType.local,
                icon: Icons.folder,
                iconColor: Colors.amber,
                title: '通常フォルダ',
                subtitle: 'ローカルに保存',
              ),
              const SizedBox(height: 8),
              _buildTypeOption(
                type: AddFolderType.drive,
                icon: Icons.cloud,
                iconColor: Colors.blue,
                title: 'Google Driveフォルダ',
                subtitle: '共有URLからクローン',
              ),
              const SizedBox(height: 16),
            ],

            // 通常フォルダの場合はフォルダ名入力
            if (_selectedType == AddFolderType.local) ...[
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'フォルダ名',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _onSubmit(),
              ),
            ],

            // Driveフォルダの場合は説明
            if (_selectedType == AddFolderType.drive) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '次の画面でDriveフォルダのURLを入力するか、QRコードをスキャンします。',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: _canSubmit() ? _onSubmit : null,
          child: Text(_selectedType == AddFolderType.local ? '作成' : '次へ'),
        ),
      ],
    );
  }

  /// 種類選択オプションを構築
  Widget _buildTypeOption({
    required AddFolderType type,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _selectedType == type;
    return InkWell(
      onTap: () => setState(() => _selectedType = type),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.05) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: Theme.of(context).primaryColor,
              ),
          ],
        ),
      ),
    );
  }

  /// 送信可能か
  bool _canSubmit() {
    if (_selectedType == AddFolderType.local) {
      return _nameController.text.trim().isNotEmpty;
    }
    return true; // Driveの場合は常に次へ進める
  }

  /// 送信処理
  void _onSubmit() {
    if (!_canSubmit()) return;
    
    Navigator.pop(
      context,
      AddFolderTypeResult(
        type: _selectedType,
        folderName: _selectedType == AddFolderType.local
            ? _nameController.text.trim()
            : null,
      ),
    );
  }
}
