// K-MAPS: キーボードショートカットハンドラー
// Deleteキーなどのグローバルキーボードイベントを処理

import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'global_config.dart';

/// キーボードイベントハンドラー
/// グローバルなキーボードショートカットを管理
class KeyboardHandler {
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

    // IME関連の無効なキーイベントを無視（Windows日本語入力との互換性）
    // 無効な物理キーIDはIMEからの合成イベントで発生することがある
    final physicalKeyId = event.physicalKey.usbHidUsage;
    if (physicalKeyId > 0x100000000) {
      // 無効なキーIDは静かに無視
      return false;
    }

    AppLogger.debug('[KeyboardHandler] キー押下: ${event.logicalKey}');

    // Deleteキーまたはバックスペースキー
    // 属性テーブル編集中は無効化（GlobalConfigのフラグをチェック）
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      // 属性テーブル編集中は削除しない
      if (GlobalConfig.instance.isAttributeTableEditing) {
        AppLogger.debug('[KeyboardHandler] 属性テーブル編集中のため削除をスキップ');
        return false; // イベントを伝播させる
      }

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
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // 初期フォーカスを要求
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        // キーイベントを処理
        KeyboardHandler.handleKeyEvent(event, context, widget.mapState).then((
          handled,
        ) {
          if (handled) {
            AppLogger.debug('[KeyboardShortcutWrapper] キーイベント処理済み');
          }
        });

        // イベントを常に伝播させる（マップの操作を妨げない）
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        // タップでフォーカスを回復
        onTap: () {
          if (!_focusNode.hasFocus) {
            _focusNode.requestFocus();
          }
        },
        behavior: HitTestBehavior.translucent,
        child: widget.child,
      ),
    );
  }
}
