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
// Root Maps: オーバーレイ画像設定ダイアログ
// 変換パラメータ（位置・スケール・回転・透明度）を数値入力で設定

import 'package:flutter/material.dart';
import '../../i18n/strings.g.dart';
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


  @override
  void initState() {
    super.initState();
    final p = widget.node.overlayParams;
    _lngController = TextEditingController(text: p.centerLng.toStringAsFixed(6));
    _latController = TextEditingController(text: p.centerLat.toStringAsFixed(6));
    _scaleController = TextEditingController(text: p.scale.toStringAsFixed(3));
    _rotationController = TextEditingController(text: p.rotation.toStringAsFixed(1));

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
      title: Text(t.overlaySettings.title),
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
                    decoration: InputDecoration(
                      labelText: t.overlaySettings.latitude,
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
                    decoration: InputDecoration(
                      labelText: t.overlaySettings.longitude,
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
                    decoration: InputDecoration(
                      labelText: t.overlaySettings.scale,
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
                    decoration: InputDecoration(
                      labelText: t.overlaySettings.rotation,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 8),
            Text(
              t.overlaySettings.imageSize(width: '${widget.node.overlayParams.imageWidth}', height: '${widget.node.overlayParams.imageHeight}'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.common.cancel),
        ),
        FilledButton(
          onPressed: _onApply,
          child: Text(t.overlaySettings.apply),
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

      imageWidth: widget.node.overlayParams.imageWidth,
      imageHeight: widget.node.overlayParams.imageHeight,
    );

    widget.node.overlayParams = newParams;
    widget.node.saveOverlayParams();
    widget.onChanged?.call();

    Navigator.pop(context, newParams);
  }
}
