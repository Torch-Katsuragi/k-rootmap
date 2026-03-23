// 左下フローティングアクションボタンウィジェット
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/tool_providers.dart';
import '../providers/ui_state_providers.dart';
import '../tools/pen_tool.dart';

/// 左下に表示される白い円形のフローティングボタン
class LeftBottomFab extends ConsumerWidget {
  const LeftBottomFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = ref.watch(isFabActiveProvider);
    final currentTool = ref.watch(currentToolProvider);
    
    Widget centerIcon;
    switch (currentTool.runtimeType) {
      case PenTool _:
        centerIcon = Icon(
          Icons.auto_fix_normal,
          color: isActive ? Colors.white : Colors.grey,
          size: 32,
        );
        break;
      default:
        centerIcon = Icon(
          Icons.circle,
          color: isActive ? Colors.white : Colors.grey,
          size: 32,
        );
        break;
    }
    
    return GestureDetector(
      onTap: () {
        ref.read(isFabActiveProvider.notifier).set(!isActive);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: isActive ? Colors.blue : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: isActive ? Colors.blueAccent : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: centerIcon,
      ),
    );
  }
}
