/// ライン切り取りアクション
///
/// 頂点インデックスの範囲を指定してラインを切り取る FeatureEditAction 実装。
/// LineFeatureNode のみ対応。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/app_notification.dart';
import '../../../models/nodes/feature_node.dart';
import '../../../providers/notification_providers.dart';
import '../../../providers/ui_state_providers.dart';
import '../../../utils/app_logger.dart';
import '../feature_edit_action.dart';
import '../shared/sub_table_helper.dart';

class TrimAction extends FeatureEditAction {
  @override
  String get label => '切り取り';

  @override
  IconData get icon => Icons.content_cut;

  @override
  bool canApplyTo(FeatureNode feature) => feature is LineFeatureNode;

  @override
  Widget buildControls(
    BuildContext context,
    FeatureNode feature,
    ValueNotifier<PreviewLines> previewLines,
  ) =>
      _TrimControls(
        feature: feature as LineFeatureNode,
        previewLines: previewLines,
      );
}

class _TrimControls extends ConsumerStatefulWidget {
  final LineFeatureNode feature;
  final ValueNotifier<PreviewLines> previewLines;

  const _TrimControls({
    required this.feature,
    required this.previewLines,
  });

  @override
  ConsumerState<_TrimControls> createState() => _TrimControlsState();
}

class _TrimControlsState extends ConsumerState<_TrimControls> {
  late List<LatLng> _fullLine;
  late RangeValues _range;
  List<LatLng> _trimmedLine = [];
  bool _isApplying = false;
  String? _originalSubTableJson;

  @override
  void initState() {
    super.initState();
    _fullLine = widget.feature.line;
    _range = RangeValues(0, (_fullLine.length - 1).toDouble());
    _updateTrimmed();
    _loadSubTable();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyPreview();
    });
  }

  Future<void> _loadSubTable() async {
    _originalSubTableJson = await SubTableHelper.getSubTableJson(
      widget.feature,
    );
  }

  void _updateTrimmed() {
    final start = _range.start.round();
    final end = _range.end.round();
    _trimmedLine = _fullLine.sublist(
      start.clamp(0, _fullLine.length - 1),
      (end + 1).clamp(0, _fullLine.length),
    );
  }

  void _notifyPreview() {
    widget.previewLines.value = PreviewLines(
      backgroundLine: _fullLine,
      foregroundLine: _trimmedLine,
    );
  }

  Future<void> _apply() async {
    if (_trimmedLine.length < 2) return;
    setState(() => _isApplying = true);

    try {
      final success = await widget.feature.updateLine(_trimmedLine);
      if (!success) throw Exception('ジオメトリの更新に失敗しました');

      // sub_tableもトリム範囲に合わせて更新
      if (_originalSubTableJson != null) {
        final start = _range.start.round();
        final end = _range.end.round();
        final trimmedSubTable = SubTableHelper.trimSubTable(
          _originalSubTableJson!,
          start,
          end,
        );
        if (trimmedSubTable != null) {
          await SubTableHelper.setSubTableJson(
            widget.feature,
            trimmedSubTable,
          );
        }
      }

      AppLogger.debug('[TrimAction] 適用完了: ${widget.feature.name}');

      ref.read(featureRefreshTriggerProvider.notifier).trigger();

      if (mounted) {
        ref.read(notificationCenterProvider.notifier).add(
          title: '切り取りが適用されました',
          level: NotificationLevel.success,
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      AppLogger.debug('[TrimAction] 適用失敗: $e');
      if (mounted) {
        ref.read(notificationCenterProvider.notifier).add(
          title: '切り取りの適用に失敗しました: $e',
          level: NotificationLevel.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_fullLine.length < 3) {
      return const Center(child: Text('切り取りには3点以上必要です'));
    }

    final maxIdx = (_fullLine.length - 1).toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '開始: ${_range.start.round()}',
              style: const TextStyle(fontSize: 12),
            ),
            const Spacer(),
            Text(
              '終了: ${_range.end.round()}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        RangeSlider(
          values: _range,
          min: 0,
          max: maxIdx,
          divisions: _fullLine.length > 1 ? _fullLine.length - 1 : 1,
          onChanged: (values) => setState(() => _range = values),
          onChangeEnd: (_) {
            _updateTrimmed();
            _notifyPreview();
            setState(() {});
          },
        ),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '選択: ${_trimmedLine.length}点 / 全体: ${_fullLine.length}点',
            style: const TextStyle(fontSize: 12),
          ),
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
                  _isApplying || _trimmedLine.length < 2 ? null : _apply,
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
