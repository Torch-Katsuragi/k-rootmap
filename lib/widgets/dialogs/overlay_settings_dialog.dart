// K-MAPS: オーバーレイ画像設定ダイアログ
// 変換パラメータ（位置・スケール・回転・透明度）を数値入力で設定

import 'package:flutter/material.dart';
import '../../models/nodes/overlay_image_node.dart';
import '../../models/kmeta.dart';

/// オーバーレイ画像の設定ダイアログ
/// 数値入力で精密な変換パラメータを設定できる
class OverlaySettingsDialog extends StatefulWidget {
  final OverlayImageNode node;
  final VoidCallback? onChanged;

  const OverlaySettingsDialog({
    super.key,
    required this.node,
    this.onChanged,
  });

  /// ダイアログを表示
  static Future<KMetaImageOverlay?> show(
    BuildContext context,
    OverlayImageNode node, {
    VoidCallback? onChanged,
  }) {
    return showDialog<KMetaImageOverlay>(
      context: context,
      builder: (_) => OverlaySettingsDialog(
        node: node,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<OverlaySettingsDialog> createState() => _OverlaySettingsDialogState();
}

class _OverlaySettingsDialogState extends State<OverlaySettingsDialog> {
  late TextEditingController _lngController;
  late TextEditingController _latController;
  late TextEditingController _scaleController;
  late TextEditingController _rotationController;
  late double _opacity;

  @override
  void initState() {
    super.initState();
    final p = widget.node.overlayParams;
    _lngController = TextEditingController(text: p.centerLng.toStringAsFixed(6));
    _latController = TextEditingController(text: p.centerLat.toStringAsFixed(6));
    _scaleController = TextEditingController(text: p.scale.toStringAsFixed(3));
    _rotationController = TextEditingController(text: p.rotation.toStringAsFixed(1));
    _opacity = p.opacity;
  }

  @override
  void dispose() {
    _lngController.dispose();
    _latController.dispose();
    _scaleController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('オーバーレイ設定'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latController,
                    decoration: const InputDecoration(
                      labelText: '緯度',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _lngController,
                    decoration: const InputDecoration(
                      labelText: '経度',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _scaleController,
                    decoration: const InputDecoration(
                      labelText: 'スケール (m/px)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _rotationController,
                    decoration: const InputDecoration(
                      labelText: '回転 (°)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('不透明度'),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: _opacity,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    label: '${(_opacity * 100).round()}%',
                    onChanged: (v) => setState(() => _opacity = v),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${(_opacity * 100).round()}%',
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '画像サイズ: ${widget.node.overlayParams.imageWidth} x ${widget.node.overlayParams.imageHeight}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: _onApply,
          child: const Text('適用'),
        ),
      ],
    );
  }

  void _onApply() {
    final newParams = KMetaImageOverlay(
      centerLng: double.tryParse(_lngController.text) ?? widget.node.overlayParams.centerLng,
      centerLat: double.tryParse(_latController.text) ?? widget.node.overlayParams.centerLat,
      scale: double.tryParse(_scaleController.text) ?? widget.node.overlayParams.scale,
      rotation: double.tryParse(_rotationController.text) ?? widget.node.overlayParams.rotation,
      opacity: _opacity,
      imageWidth: widget.node.overlayParams.imageWidth,
      imageHeight: widget.node.overlayParams.imageHeight,
    );

    widget.node.overlayParams = newParams;
    widget.node.saveOverlayParams();
    widget.onChanged?.call();

    Navigator.pop(context, newParams);
  }
}
