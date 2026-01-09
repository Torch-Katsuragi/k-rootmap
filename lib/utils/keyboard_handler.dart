// K-MAPS: キーボードショートカットハンドラー
// Deleteキーなどのグローバルキーボードイベントを処理

import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'global_config.dart';

/// キーボードイベントハンドラー
/// グローバルなキーボードショートカットを管理
class KeyboardHandler {
  /// テキスト入力フィールドにフォーカスがあるかチェック
  /// ダイアログ内のTextField、属性テーブル編集など
  static bool _isTextInputFocused(BuildContext context) {
    // GlobalConfigのフラグをチェック（属性テーブル編集用）
    if (GlobalConfig.instance.isAttributeTableEditing) {
      return true;
    }

    // 現在のフォーカスノードをチェック
    final focusNode = FocusManager.instance.primaryFocus;
    if (focusNode == null) {
      return false;
    }

    // デバッグ名にEditableTextが含まれているかチェック（IME切り替え時にも安定）
    final debugLabel = focusNode.debugLabel ?? '';
    if (debugLabel.contains('EditableText') || debugLabel.contains('TextField')) {
      return true;
    }

    // フォーカスノードのコンテキストからEditableTextを探す
    // TextField, TextFormField, EditableText等にフォーカスがある場合はtrue
    final focusContext = focusNode.context;
    if (focusContext != null) {
      // EditableTextStateを探す（TextField内部で使用される）
      final editableText =
          focusContext.findAncestorStateOfType<EditableTextState>();
      if (editableText != null) {
        return true;
      }
      
      // 親ウィジェットツリーにTextFieldやTextFormFieldがあるか確認
      // （CapsLock押下時のフォールバック）
      bool hasTextField = false;
      focusContext.visitAncestorElements((element) {
        final widget = element.widget;
        if (widget is TextField || widget is TextFormField || widget is EditableText) {
          hasTextField = true;
          return false; // 探索終了
        }
        return true; // 探索継続
      });
      if (hasTextField) {
        return true;
      }
    }

    return false;
  }

  /// Deleteキー押下時の処理
  /// 選択されたフィーチャを削除
  static Future<void> handleDeleteKey(
    BuildContext context,
    dynamic mapState,
  ) async {
    AppLogger.debug('[KeyboardHandler] Deleteキーが押されました');

    // 選択されたフィーチャがあるかチェック
    if (GlobalConfig.instance.selectedFeatures.isEmpty) {
      AppLogger.debug('[KeyboardHandler] 削除対象のフィーチャが選択されていません');
      return;
    }

    final featureCount = GlobalConfig.instance.selectedFeatures.length;
    AppLogger.debug('[KeyboardHandler] 削除対象: $featureCount個のフィーチャ');

    try {
      // GlobalConfigの統一削除処理を使用（pen_toolと同じロジック）
      await GlobalConfig.instance.disposeSelectedFeatures(mapState: mapState);

      AppLogger.debug('[KeyboardHandler] フィーチャ削除完了: $featureCount個');

      // 成功メッセージ
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$featureCount個のフィーチャを削除しました'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      AppLogger.debug('[KeyboardHandler] フィーチャ削除エラー: $e');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('フィーチャの削除に失敗しました: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// キーイベントを処理
  /// 戻り値: trueの場合、イベントが処理された（伝播を停止）
  static Future<bool> handleKeyEvent(
    KeyEvent event,
    BuildContext context,
    dynamic mapState,
  ) async {
    // キーが押された時のみ処理（リリースイベントは無視）
    if (event is! KeyDownEvent) {
      return false;
    }

    // 修飾キー（CapsLock, Shift, Ctrl, Alt等）は無視
    // IME切り替え時にこれらのキーが押されると、フォーカス判定が不安定になるため
    final modifierKeys = {
      LogicalKeyboardKey.capsLock,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
      LogicalKeyboardKey.numLock,
      LogicalKeyboardKey.scrollLock,
      // IME関連キー
      LogicalKeyboardKey.convert,
      LogicalKeyboardKey.nonConvert,
      LogicalKeyboardKey.kanaMode,
      LogicalKeyboardKey.hiragana,
      LogicalKeyboardKey.katakana,
      LogicalKeyboardKey.hiraganaKatakana,
      LogicalKeyboardKey.zenkakuHankaku,
      LogicalKeyboardKey.hankaku,
      LogicalKeyboardKey.zenkaku,
    };
    if (modifierKeys.contains(event.logicalKey)) {
      return false;
    }

    // IME関連の無効なキーイベントを安全にフィルタリング
    // Windows日本語入力との互換性のため、以下のケースを無視:
    // 1. 無効な物理キーID（IMEからの合成イベント）
    // 2. 極端に大きいUSB HID使用コード
    try {
      final physicalKeyId = event.physicalKey.usbHidUsage;
      if (physicalKeyId > 0x100000000 || physicalKeyId == 0) {
        // 無効なキーIDは静かに無視
        return false;
      }
    } catch (e) {
      // 物理キー情報の取得に失敗した場合も無視
      return false;
    }

    // テキスト入力中は全てのショートカットを無視
    // CapsLock押下直後もEditableTextのフォーカスは維持されているはずなので、
    // この判定を先に行う
    if (_isTextInputFocused(context)) {
      return false; // イベントを伝播させる（TextFieldで処理される）
    }

    AppLogger.debug('[KeyboardHandler] キー押下: ${event.logicalKey}');

    // Deleteキーまたはバックスペースキー
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      await handleDeleteKey(context, mapState);
      return true; // イベントを処理済みとしてマーク
    }

    // 将来的な拡張用コメント
    // Ctrl+Z: Undo
    // Ctrl+Y: Redo
    // Ctrl+C: Copy
    // Ctrl+V: Paste
    // Ctrl+A: Select All
    // Esc: Cancel current operation

    return false; // イベント未処理
  }
}

/// キーボードショートカットを有効にするウィジェット
/// マップページ全体をラップして使用
/// 
/// HardwareKeyboardのハンドラーを直接使用して、
/// IME関連のキーイベント不整合問題を回避
class KeyboardShortcutWrapper extends StatefulWidget {
  final Widget child;
  final dynamic mapState;

  const KeyboardShortcutWrapper({
    super.key,
    required this.child,
    required this.mapState,
  });

  @override
  State<KeyboardShortcutWrapper> createState() =>
      _KeyboardShortcutWrapperState();
}

class _KeyboardShortcutWrapperState extends State<KeyboardShortcutWrapper> {
  /// HardwareKeyboardのハンドラー
  bool _handleKeyEvent(KeyEvent event) {
    // IME関連の無効なキーイベントを早期にフィルタリング
    // Windows日本語入力で発生する不正なキーイベントを除外
    try {
      final physicalKeyId = event.physicalKey.usbHidUsage;
      // 無効な物理キーID（0x1600000000等のIME合成イベント）
      if (physicalKeyId > 0x100000000 || physicalKeyId == 0) {
        AppLogger.debug('[K-MAPS] IME関連キーボードイベントを無視');
        return false; // イベントを伝播
      }
    } catch (e) {
      // 物理キー情報の取得に失敗した場合も無視
      return false;
    }

    // contextが利用可能な場合のみ処理
    if (!mounted) return false;

    // 非同期で処理（UIをブロックしない）
    KeyboardHandler.handleKeyEvent(event, context, widget.mapState).then((
      handled,
    ) {
      if (handled) {
        AppLogger.debug('[KeyboardShortcutWrapper] キーイベント処理済み');
      }
    }).catchError((e) {
      // エラーを静かに無視（IME関連の問題）
      AppLogger.debug('[KeyboardShortcutWrapper] キーイベント処理エラー: $e');
    });

    // イベントを常に伝播させる（他のウィジェットがキーを受け取れるように）
    return false;
  }

  @override
  void initState() {
    super.initState();
    // HardwareKeyboardにハンドラーを登録
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    // ハンドラーを解除
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
