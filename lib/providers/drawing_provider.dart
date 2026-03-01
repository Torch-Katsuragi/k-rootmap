import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../utils/global_drawing_state.dart';

part 'drawing_provider.g.dart';

@Riverpod(keepAlive: true)
GlobalDrawingState drawingState(Ref ref) {
  final instance = GlobalDrawingState.instance;
  instance.setRef(ref);
  return instance;
}
