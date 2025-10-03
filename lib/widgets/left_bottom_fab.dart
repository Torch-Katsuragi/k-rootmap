// 左下フローティングアクションボタンウィジェット
import 'package:flutter/material.dart';
import '../utils/global_config.dart';
import '../tools/pen_tool.dart';

/// 左下に表示される白い円形のフローティングボタン
/// 押下状態はGlobalConfigで管理
class LeftBottomFab extends StatefulWidget {
  const LeftBottomFab({super.key});
  
  @override
  State<LeftBottomFab> createState() => _LeftBottomFabState();
}

class _LeftBottomFabState extends State<LeftBottomFab> {
  @override
  Widget build(BuildContext context) {
    final isActive = GlobalConfig.instance.isFabActive;
    final currentTool = GlobalConfig.instance.currentTool;
    
    // 現在のツールに応じてアイコンを変更
    Widget centerIcon;
    switch (currentTool.runtimeType) {
      case PenTool:
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
        setState(() {
          GlobalConfig.instance.isFabActive = !isActive;
        });
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
              color: Colors.black.withOpacity(0.2),
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

