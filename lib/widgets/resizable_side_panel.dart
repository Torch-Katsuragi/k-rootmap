/// K-MAPS: リサイズ可能なサイドパネルウィジェット
/// LayerDrawerや属性テーブルなどで再利用できる汎用的なサイドパネル
library;

import 'package:flutter/material.dart';

/// リサイズ可能なサイドパネルウィジェット
class ResizableSidePanel extends StatefulWidget {
  /// パネルの子ウィジェット
  final Widget child;

  /// パネルの初期幅
  final double initialWidth;

  /// パネルの最小幅
  final double minWidth;

  /// パネルの最大幅（画面幅の比率で指定、0.0-1.0）
  final double maxWidthRatio;

  /// パネルの初期開閉状態
  final bool initiallyOpen;

  /// パネルの開閉状態変更コールバック
  final void Function(bool isOpen)? onOpenChanged;

  /// パネル幅変更コールバック
  final void Function(double width)? onWidthChanged;

  /// パネルの背景色
  final Color backgroundColor;

  /// ドラッグハンドルの色
  final Color handleColor;

  const ResizableSidePanel({
    super.key,
    required this.child,
    this.initialWidth = 320,
    this.minWidth = 200,
    this.maxWidthRatio = 0.67,
    this.initiallyOpen = true,
    this.onOpenChanged,
    this.onWidthChanged,
    this.backgroundColor = Colors.white,
    this.handleColor = Colors.black12,
  });

  @override
  State<ResizableSidePanel> createState() => _ResizableSidePanelState();
}

class _ResizableSidePanelState extends State<ResizableSidePanel> {
  late double _panelWidth;
  late bool _isOpen;

  @override
  void initState() {
    super.initState();
    _panelWidth = widget.initialWidth;
    _isOpen = widget.initiallyOpen;
  }

  /// パネルを開く
  void openPanel() {
    if (!_isOpen) {
      setState(() {
        _isOpen = true;
        _panelWidth = widget.initialWidth;
      });
      widget.onOpenChanged?.call(true);
      widget.onWidthChanged?.call(_panelWidth);
    }
  }

  /// パネルを閉じる
  void closePanel() {
    if (_isOpen) {
      setState(() {
        _isOpen = false;
      });
      widget.onOpenChanged?.call(false);
    }
  }

  /// パネルの開閉を切り替え
  void togglePanel() {
    if (_isOpen) {
      closePanel();
    } else {
      openPanel();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOpen) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth * widget.maxWidthRatio;

    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: _panelWidth.clamp(widget.minWidth, maxWidth),
      child: Material(
        elevation: 0,
        color: Colors.transparent,
        child: Row(
          children: [
            // Left drag handle (resizable)
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _panelWidth -= details.delta.dx;
                  if (_panelWidth < widget.minWidth) {
                    _isOpen = false;
                    widget.onOpenChanged?.call(false);
                  } else if (_panelWidth > maxWidth) {
                    _panelWidth = maxWidth;
                  } else {
                    widget.onWidthChanged?.call(_panelWidth);
                  }
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: Container(
                  width: 28,
                  color: widget.handleColor,
                  child: const Center(
                    child: VerticalDivider(width: 2, thickness: 2),
                  ),
                ),
              ),
            ),
            // Panel content
            Expanded(
              child: Container(
                color: widget.backgroundColor,
                child: widget.child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ResizableSidePanelの制御クラス
class ResizableSidePanelController {
  _ResizableSidePanelState? _state;

  void _attach(_ResizableSidePanelState state) {
    _state = state;
  }

  void _detach() {
    _state = null;
  }

  /// パネルを開く
  void openPanel() {
    _state?.openPanel();
  }

  /// パネルを閉じる
  void closePanel() {
    _state?.closePanel();
  }

  /// パネルの開閉を切り替え
  void togglePanel() {
    _state?.togglePanel();
  }

  /// パネルが開いているかどうか
  bool get isOpen => _state?._isOpen ?? false;

  /// 現在のパネル幅
  double get width => _state?._panelWidth ?? 0;
}

/// ResizableSidePanelにコントローラー機能を追加したバージョン
class ControlledResizableSidePanel extends StatefulWidget {
  /// パネルの子ウィジェット
  final Widget child;

  /// パネルの初期幅
  final double initialWidth;

  /// パネルの最小幅
  final double minWidth;

  /// パネルの最大幅（画面幅の比率で指定、0.0-1.0）
  final double maxWidthRatio;

  /// パネルの初期開閉状態
  final bool initiallyOpen;

  /// パネルの開閉状態変更コールバック
  final void Function(bool isOpen)? onOpenChanged;

  /// パネル幅変更コールバック
  final void Function(double width)? onWidthChanged;

  /// パネルの背景色
  final Color backgroundColor;

  /// ドラッグハンドルの色
  final Color handleColor;

  /// パネルコントローラー
  final ResizableSidePanelController? controller;

  const ControlledResizableSidePanel({
    super.key,
    required this.child,
    this.initialWidth = 320,
    this.minWidth = 200,
    this.maxWidthRatio = 0.67,
    this.initiallyOpen = true,
    this.onOpenChanged,
    this.onWidthChanged,
    this.backgroundColor = Colors.white,
    this.handleColor = Colors.black12,
    this.controller,
  });

  @override
  State<ControlledResizableSidePanel> createState() =>
      _ControlledResizableSidePanelState();
}

class _ControlledResizableSidePanelState
    extends State<ControlledResizableSidePanel> {
  late double _panelWidth;
  late bool _isOpen;

  @override
  void initState() {
    super.initState();
    _panelWidth = widget.initialWidth;
    _isOpen = widget.initiallyOpen;
    widget.controller?._attach(this as _ResizableSidePanelState);
  }

  @override
  void dispose() {
    widget.controller?._detach();
    super.dispose();
  }

  /// パネルを開く
  void openPanel() {
    if (!_isOpen) {
      setState(() {
        _isOpen = true;
        _panelWidth = widget.initialWidth;
      });
      widget.onOpenChanged?.call(true);
      widget.onWidthChanged?.call(_panelWidth);
    }
  }

  /// パネルを閉じる
  void closePanel() {
    if (_isOpen) {
      setState(() {
        _isOpen = false;
      });
      widget.onOpenChanged?.call(false);
    }
  }

  /// パネルの開閉を切り替え
  void togglePanel() {
    if (_isOpen) {
      closePanel();
    } else {
      openPanel();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOpen) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth * widget.maxWidthRatio;

    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: _panelWidth.clamp(widget.minWidth, maxWidth),
      child: Material(
        elevation: 0,
        color: Colors.transparent,
        child: Row(
          children: [
            // Left drag handle (resizable)
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _panelWidth -= details.delta.dx;
                  if (_panelWidth < widget.minWidth) {
                    _isOpen = false;
                    widget.onOpenChanged?.call(false);
                  } else if (_panelWidth > maxWidth) {
                    _panelWidth = maxWidth;
                  } else {
                    widget.onWidthChanged?.call(_panelWidth);
                  }
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: Container(
                  width: 28,
                  color: widget.handleColor,
                  child: const Center(
                    child: VerticalDivider(width: 2, thickness: 2),
                  ),
                ),
              ),
            ),
            // Panel content
            Expanded(
              child: Container(
                color: widget.backgroundColor,
                child: widget.child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
