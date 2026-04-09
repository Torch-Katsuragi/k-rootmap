// 地図画面の左側ツールバーウィジェット
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../i18n/strings.g.dart';
import '../models/nodes/overlay_image_node.dart';
import '../providers/selection_providers.dart';
import '../providers/tool_providers.dart';
import '../providers/device_tool_providers.dart';

/// 地図画面左側のツールバー
///
/// 固定ツール（Pan, Pen, Select, GPS）に加え、
/// 接続中の外部機器ツール（[DeviceTool]）を動的に表示する。
/// OverlayImageNode選択中はOverlay Transformツールも表示する。
class MapToolbar extends ConsumerWidget {
  final VoidCallback onToolChanged;

  const MapToolbar({
    super.key,
    required this.onToolChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTool = ref.watch(currentToolProvider);
    final deviceTools = ref.watch(connectedDeviceToolsProvider);
    final selectedFeatures = ref.watch(selectedFeaturesProvider);
    final hasOverlaySelected = selectedFeatures.any((n) => n is OverlayImageNode);

    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      child: Container(
        width: 44,
        color: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _ToolButton(
              icon: Icons.pan_tool_alt,
              tooltip: t.map.toolbar.pan,
              isSelected: currentTool.name == 'Pan',
              onPressed: () {
                ref.read(currentToolProvider.notifier).set(ref.read(panToolProvider));
                onToolChanged();
              },
            ),
            const SizedBox(height: 8),
            _ToolButton(
              icon: Icons.edit,
              tooltip: t.map.toolbar.pen,
              isSelected: currentTool.name == 'Pen',
              onPressed: () {
                ref.read(currentToolProvider.notifier).set(ref.read(penToolProvider));
                onToolChanged();
              },
            ),
            const SizedBox(height: 8),
            _ToolButton(
              icon: Icons.select_all,
              tooltip: t.map.toolbar.select,
              isSelected: currentTool.name == 'Select',
              onPressed: () {
                ref.read(currentToolProvider.notifier).set(ref.read(selectToolProvider));
                onToolChanged();
              },
            ),
            const SizedBox(height: 8),
            _ToolButton(
              icon: Icons.gps_fixed,
              tooltip: t.map.toolbar.gpsTool,
              isSelected: currentTool.name == 'GPS',
              onPressed: () {
                ref.read(currentToolProvider.notifier).set(ref.read(gpsToolProvider));
                onToolChanged();
              },
            ),
            // OverlayImageNode選択中のみ表示
            if (hasOverlaySelected) ...[
              const SizedBox(height: 8),
              _ToolButton(
                icon: Icons.transform,
                tooltip: t.map.toolbar.overlayTransform,
                isSelected: currentTool.name == 'Overlay Transform',
                onPressed: () {
                  final tool = ref.read(overlayTransformToolProvider);
                  // 選択中のOverlayImageNodeをターゲットに設定
                  final overlay = selectedFeatures.whereType<OverlayImageNode>().firstOrNull;
                  tool.setTarget(overlay);
                  ref.read(currentToolProvider.notifier).set(tool);
                  onToolChanged();
                },
              ),
            ],
            // 接続中の外部機器ツールを動的に表示
            for (final dt in deviceTools) ...[
              const SizedBox(height: 8),
              _ToolButton(
                icon: dt.icon,
                tooltip: dt.name,
                isSelected: currentTool == dt,
                onPressed: () {
                  ref.read(currentToolProvider.notifier).set(dt);
                  onToolChanged();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ツールボタン（選択状態で青い円が表示される）
class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onPressed;

  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? Colors.blue : Colors.transparent,
      ),
      child: IconButton(
        icon: Icon(
          icon,
          color: isSelected ? Colors.white : Colors.black,
        ),
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: 24,
        padding: EdgeInsets.zero,
      ),
    );
  }
}
