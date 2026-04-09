// K-MAPS: ダイアログヘルパークラス
// 共通のダイアログパターンを一元化して重複コードを削減

import 'package:flutter/material.dart';
import '../../i18n/strings.g.dart';

/// 共通ダイアログヘルパークラス
/// リネームダイアログ、確認ダイアログなどの汎用パターンを提供
class DialogHelpers {
  /// リネームダイアログ（共通化）
  /// 
  /// テキスト入力によるリネーム操作を行うダイアログ
  /// [context] ビルドコンテキスト
  /// [title] ダイアログタイトル
  /// [currentName] 現在の名前（初期値）
  /// [labelText] 入力フィールドのラベル（オプション）
  /// [hintText] 入力フィールドのヒントテキスト（オプション）
  /// [validator] 入力値のバリデーション関数（オプション）
  /// 戻り値: 新しい名前（キャンセル時はnull）
  static Future<String?> showRenameDialog(
    BuildContext context, {
    required String title,
    required String currentName,
    String? labelText,
    String? hintText,
    String? Function(String?)? validator,
  }) async {
    final controller = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();
    
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: labelText ?? t.common.name,
                hintText: hintText,
                border: const OutlineInputBorder(),
              ),
              validator: validator ?? (value) {
                if (value == null || value.trim().isEmpty) {
                  return t.common.nameCannotBeEmpty;
                }
                return null;
              },
              onFieldSubmitted: (value) {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(dialogContext).pop(controller.text.trim());
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: Text(t.common.cancel),
            ),
            TextButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(dialogContext).pop(controller.text.trim());
                }
              },
              child: Text(t.common.ok),
            ),
          ],
        );
      },
    );
  }

  /// 確認ダイアログ（共通化）
  /// 
  /// Yes/No形式の確認ダイアログ
  /// [context] ビルドコンテキスト
  /// [title] ダイアログタイトル
  /// [content] ダイアログ本文
  /// [confirmText] 確認ボタンのテキスト（デフォルト: 'OK'）
  /// [cancelText] キャンセルボタンのテキスト（デフォルト: 'Cancel'）
  /// [isDangerous] 危険な操作の場合は確認ボタンを赤くする
  /// 戻り値: 確認した場合はtrue、キャンセルした場合はfalse
  static Future<bool> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String content,
    String confirmText = 'OK',
    String cancelText = 'Cancel',
    bool isDangerous = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(cancelText),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: isDangerous
                  ? TextButton.styleFrom(foregroundColor: Colors.red)
                  : null,
              child: Text(confirmText),
            ),
          ],
        );
      },
    );
    
    return result ?? false;
  }

  /// 削除確認ダイアログ（危険な操作用）
  /// 
  /// 削除などの取り消し不可能な操作の確認
  /// [context] ビルドコンテキスト
  /// [itemName] 削除対象の名前
  /// [itemType] 削除対象の種類（'layer', 'feature'など）
  /// 戻り値: 削除を確認した場合はtrue
  static Future<bool> showDeleteConfirmDialog(
    BuildContext context, {
    required String itemName,
    String itemType = 'item',
  }) async {
    return showConfirmDialog(
      context,
      title: t.dialog.deleteTitle(type: itemType),
      content: t.dialog.deleteConfirm(name: itemName),
      confirmText: t.common.delete,
      isDangerous: true,
    );
  }

  /// 選択リストダイアログ（共通化）
  /// 
  /// 複数の選択肢から1つを選ぶダイアログ
  /// [context] ビルドコンテキスト
  /// [title] ダイアログタイトル
  /// [options] 選択肢のリスト
  /// [getLabel] 選択肢からラベルを取得する関数
  /// 戻り値: 選択された項目（キャンセル時はnull）
  static Future<T?> showSelectionDialog<T>(
    BuildContext context, {
    required String title,
    required List<T> options,
    required String Function(T) getLabel,
    T? selectedValue,
  }) async {
    return showDialog<T>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: Text(title),
          children: options.map((option) {
            final isSelected = option == selectedValue;
            return SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(option),
              child: Row(
                children: [
                  if (isSelected)
                    const Icon(Icons.check, color: Colors.blue, size: 20)
                  else
                    const SizedBox(width: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(getLabel(option))),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  /// ロード中ダイアログを表示
  /// 
  /// 処理中であることを示すダイアログ
  /// [context] ビルドコンテキスト
  /// [message] 表示メッセージ
  static void showLoadingDialog(
    BuildContext context, {
    String message = '',
  }) {
    final displayMessage = message.isEmpty ? t.common.processing : message;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(child: Text(displayMessage)),
            ],
          ),
        );
      },
    );
  }

  /// ロード中ダイアログを閉じる
  static void hideLoadingDialog(BuildContext context) {
    Navigator.of(context).pop();
  }
}


