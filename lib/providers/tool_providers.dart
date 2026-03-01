import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../tools/map_tool.dart';
import '../tools/pan_tool.dart';
import '../tools/pen_tool.dart';
import '../tools/select_tool.dart';
import '../tools/gps_tool.dart';

part 'tool_providers.g.dart';

@Riverpod(keepAlive: true)
PanTool panTool(Ref ref) => PanTool(ref);

@Riverpod(keepAlive: true)
PenTool penTool(Ref ref) => PenTool(ref);

@Riverpod(keepAlive: true)
SelectTool selectTool(Ref ref) => SelectTool(ref);

@Riverpod(keepAlive: true)
GpsTool gpsTool(Ref ref) => GpsTool(ref);

@Riverpod(keepAlive: true)
class CurrentTool extends _$CurrentTool {
  @override
  MapTool build() => ref.read(panToolProvider);

  void set(MapTool tool) => state = tool;
}
