/// ライン/ポリゴン簡略化アクション
///
/// Douglas-Peucker 簡略化を適用する FeatureEditAction 実装。
/// LineFeatureNode と PolygonFeatureNode に対応。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/nodes/feature_node.dart';
import '../../../utils/app_logger.dart';
import '../../../providers/ui_state_providers.dart';
import '../feature_edit_action.dart';
import '../shared/simplification_controls.dart';

class SimplifyAction extends FeatureEditAction {
  @override
  String get label => '簡略化';

  @override
  IconData get icon => Icons.timeline;

  @override
  bool canApplyTo(FeatureNode feature) =>
      feature is LineFeatureNode || feature is PolygonFeatureNode;

  @override
  Widget buildControls(
    BuildContext context,
    FeatureNode feature,
    ValueNotifier<PreviewLines> previewLines,
  ) =>
      _SimplifyControls(feature: feature, previewLines: previewLines);
}

class _SimplifyControls extends ConsumerStatefulWidget {
  final FeatureNode feature;
  final ValueNotifier<PreviewLines> previewLines;

  const _SimplifyControls({
    required this.feature,
    required this.previewLines,
  });

  @override
  ConsumerState<_SimplifyControls> createState() => _SimplifyControlsState();
}

class _SimplifyControlsState extends ConsumerState<_SimplifyControls> {
  List<LatLng> _originalLine = [];
  List<LatLng> _simplified = [];
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _originalLine = _extractLine(widget.feature);
    // 初期プレビューを設定（フレーム後に通知）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.previewLines.value = PreviewLines(
        backgroundLine: _originalLine,
        foregroundLine: _originalLine,
      );
    });
  }

  List<LatLng> _extractLine(FeatureNode feature) {
    if (feature is LineFeatureNode) return feature.line;
    if (feature is PolygonFeatureNode) {
      final polygon = feature.polygon;
      return polygon.isNotEmpty ? polygon.first : [];
    }
    return [];
  }

  void _onSimplified(List<LatLng> result) {
    setState(() => _simplified = result);
    widget.previewLines.value = PreviewLines(
      backgroundLine: _originalLine,
      foregroundLine: result,
    );
  }

  Future<void> _apply() async {
    if (_simplified.length < 2) return;
    setState(() => _isApplying = true);

    try {
      bool success = false;
      if (widget.feature is LineFeatureNode) {
        success =
            await (widget.feature as LineFeatureNode).updateLine(_simplified);
      } else if (widget.feature is PolygonFeatureNode) {
        final polygon = (widget.feature as PolygonFeatureNode).polygon;
        final updated = [_simplified, ...polygon.skip(1)];
        success = await (widget.feature as PolygonFeatureNode)
            .updatePolygon(updated);
      }

      if (!success) throw Exception('ジオメトリの更新に失敗しました');

      AppLogger.debug('[SimplifyAction] 適用完了: ${widget.feature.name}');

      ref.read(featureRefreshTriggerProvider.notifier).trigger();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('簡略化が適用されました')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      AppLogger.debug('[SimplifyAction] 適用失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('簡略化の適用に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_originalLine.length < 2) {
      return const Center(child: Text('簡略化対象のデータが不足しています'));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SimplificationControls(
          originalLine: _originalLine,
          onChanged: _onSimplified,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed:
                  _isApplying || _simplified.length < 2 ? null : _apply,
              child: _isApplying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('適用'),
            ),
          ],
        ),
      ],
    );
  }
}
