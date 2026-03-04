import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/selection_providers.dart';
import '../../../providers/tool_providers.dart';
import '../../../utils/global_drawing_state.dart';
import '../../../models/nodes/layer_node.dart';
import '../../../tools/pen_tool.dart';
import '../../../tools/gps_tool.dart';

/// 描画・測量操作用のFABボタン群
class DrawingActionButtons extends ConsumerWidget {
  final VoidCallback onConfirmDrawing;
  final VoidCallback onConfirmGpsSurvey;
  final VoidCallback onTriggerSetState;
  final void Function(String message, {Color? color})? onShowSnackBar;
  final GpsTool? Function() getGpsTool;

  const DrawingActionButtons({
    super.key,
    required this.onConfirmDrawing,
    required this.onConfirmGpsSurvey,
    required this.onTriggerSetState,
    required this.getGpsTool,
    this.onShowSnackBar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedLayerNodeProvider);
    final currentTool = ref.watch(currentToolProvider);
    final drawingState = GlobalDrawingState.instance;
    final gpsTool = currentTool is GpsTool ? currentTool : null;

    final isGpsSurveyLine =
        selected is LineLayerNode &&
        gpsTool != null &&
        gpsTool.surveyLine.isNotEmpty;
    final isGpsSurveyPolygon =
        selected is PolygonLayerNode &&
        gpsTool != null &&
        gpsTool.surveyPolygon.isNotEmpty;

    final isLineDrawing =
        selected is LineLayerNode &&
        currentTool is PenTool &&
        drawingState.drawingLine.isNotEmpty;
    final isPolygonDrawing =
        selected is PolygonLayerNode &&
        currentTool is PenTool &&
        drawingState.drawingPolygon.isNotEmpty;

    if (isGpsSurveyLine || isGpsSurveyPolygon) {
      return _buildGpsSurveyButtons(gpsTool, drawingState);
    } else if (isLineDrawing || isPolygonDrawing) {
      return _buildDrawingButtons(drawingState, isLineDrawing);
    }
    return const SizedBox.shrink();
  }

  Widget _buildGpsSurveyButtons(
    GpsTool gpsTool,
    GlobalDrawingState drawingState,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'gps_undo',
          onPressed: () {
            drawingState.undo(isLine: gpsTool.surveyLine.isNotEmpty);
            onTriggerSetState();
          },
          tooltip: 'GPS測量の最後のポイントを取り消し',
          child: const Icon(Icons.undo),
        ),
        const SizedBox(width: 12),
        FloatingActionButton(
          heroTag: 'gps_cancel',
          onPressed: () async {
            await gpsTool.cancelSurveyWithGpsStop();
            onTriggerSetState();
            onShowSnackBar?.call('GPS測量をキャンセルしました', color: Colors.orange);
          },
          tooltip: 'GPS測量をキャンセル',
          child: const Icon(Icons.clear),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.extended(
          heroTag: 'gps_confirm',
          onPressed: onConfirmGpsSurvey,
          icon: const Icon(Icons.check),
          label: const Text('GPS測量確定'),
        ),
      ],
    );
  }

  Widget _buildDrawingButtons(
    GlobalDrawingState drawingState,
    bool isLineDrawing,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'undo',
          onPressed: () {
            drawingState.undo(isLine: isLineDrawing);
            onTriggerSetState();
          },
          tooltip: 'Undo',
          child: const Icon(Icons.undo),
        ),
        const SizedBox(width: 12),
        FloatingActionButton(
          heroTag: 'cancel',
          onPressed: () {
            drawingState.cancel(isLine: isLineDrawing);
            onTriggerSetState();
          },
          tooltip: 'Cancel',
          child: const Icon(Icons.clear),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.extended(
          heroTag: 'confirm',
          onPressed: onConfirmDrawing,
          icon: const Icon(Icons.check),
          label: const Text('Confirm'),
        ),
      ],
    );
  }
}
