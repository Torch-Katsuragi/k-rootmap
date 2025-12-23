// K-MAPS: GPS測量Mixin
// GPS測量（単一点記録、長押し測量）関連の機能を提供
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/global_config.dart';
import '../../../utils/global_drawing_state.dart';
import '../../../tools/gps_tool.dart';
import '../map_page_state_base.dart';

/// GPS測量Mixin
/// 単一点GPS測量と長押し測量機能を提供
mixin MapGpsSurveyMixin<T extends StatefulWidget> on MapPageStateBase<T> {
  
  // =============================================
  // GPS測量（単一点記録）
  // =============================================
  
  /// GPS測量（現在位置を記録）
  Future<void> recordGpsPosition() async {
    try {
      final currentTool = GlobalConfig.instance.currentTool;
      if (currentTool is! GpsTool) {
        AppLogger.debug('[MapGpsSurveyMixin] GPS測量: 現在のツールがGpsToolではありません');
        return;
      }
      
      final selected = GlobalConfig.instance.selectedLayerNode;
      if (selected == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('レイヤーが選択されていません'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      
      if (!selected.isVisibleRecursive()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('このレイヤは不可視のため編集できません'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      
      // GPS位置情報取得開始のスナックバーを表示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS位置情報を取得中...'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 1),
          ),
        );
      }
      
      // GPS位置を記録
      final success = await currentTool.recordCurrentGpsPosition();
      if (success) {
        triggerSetState(() {}); // プレビュー更新
        
        if (mounted) {
          final totalPoints =
              GlobalConfig.instance.drawingState.drawingLine.length +
              GlobalConfig.instance.drawingState.drawingPolygon.length;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('GPS位置を記録しました ($totalPointsポイント目)'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPS位置情報が取得できません。位置情報の許可と設定を確認してください。'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.debug('[MapGpsSurveyMixin] GPS測量エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPS測量エラー: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  // =============================================
  // GPS長押し測量
  // =============================================
  
  /// GPS長押し測量開始
  Future<void> startLongPressGpsSurvey() async {
    try {
      final currentTool = GlobalConfig.instance.currentTool;
      if (currentTool is! GpsTool) {
        AppLogger.debug('[MapGpsSurveyMixin] GPS長押し測量: 現在のツールがGpsToolではありません');
        return;
      }
      
      triggerSetState(() {
        isLongPressing = true;
        longPressGpsCount = 0;
      });
      
      AppLogger.debug('[MapGpsSurveyMixin] GPS長押し測量開始');
      currentTool.startLongPressGpsSurvey();
      
      // 長押し中の個数更新タイマーを開始（0.5秒間隔で更新）
      longPressCountUpdateTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (timer) {
          final newCount = currentTool.longPressGpsCount;
          if (longPressGpsCount != newCount) {
            triggerSetState(() {
              longPressGpsCount = newCount;
            });
          }
        },
      );
      
      // 長押し中のフィードバック用のスナックバーを表示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS長押し測量中... 離すと平均位置を記録します'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      AppLogger.debug('[MapGpsSurveyMixin] GPS長押し測量開始エラー: $e');
      longPressCountUpdateTimer?.cancel();
      longPressCountUpdateTimer = null;
      triggerSetState(() {
        isLongPressing = false;
        longPressGpsCount = 0;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS長押し測量開始エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// GPS長押し測量停止と平均化処理
  Future<void> stopLongPressGpsSurvey() async {
    try {
      final currentTool = GlobalConfig.instance.currentTool;
      if (currentTool is! GpsTool) {
        AppLogger.debug('[MapGpsSurveyMixin] GPS長押し測量停止: 現在のツールがGpsToolではありません');
        return;
      }
      
      AppLogger.debug('[MapGpsSurveyMixin] GPS長押し測量停止 - 平均化処理開始');
      final success = await currentTool.stopLongPressGpsSurvey();
      
      if (!success) {
        throw Exception('GPS長押し測量データが不十分です');
      }
      
      triggerSetState(() {
        isLongPressing = false;
        longPressGpsCount = 0;
      });
      
      // 長押しカウンタータイマーを停止
      longPressCountUpdateTimer?.cancel();
      longPressCountUpdateTimer = null;
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS長押し測量完了 - 平均位置でポイントを作成しました'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      AppLogger.debug('[MapGpsSurveyMixin] GPS長押し測量停止エラー: $e');
      longPressCountUpdateTimer?.cancel();
      longPressCountUpdateTimer = null;
      triggerSetState(() {
        isLongPressing = false;
        longPressGpsCount = 0;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS長押し測量エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // =============================================
  // GPS測量確定処理
  // =============================================
  
  /// GPS測量確定処理
  Future<void> onConfirmGpsSurvey() async {
    try {
      final currentTool = GlobalConfig.instance.currentTool;
      if (currentTool is! GpsTool) return;
      
      final selected = GlobalConfig.instance.selectedLayerNode;
      if (selected == null) return;
      
      // 属性入力ダイアログを表示
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) {
          String name = '';
          String description = '';
          return AlertDialog(
            title: const Text('GPS測量フィーチャの属性入力'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '名前'),
                  onChanged: (v) => name = v,
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(labelText: '説明（任意）'),
                  maxLines: 3,
                  onChanged: (v) => description = v,
                ),
                const SizedBox(height: 12),
                Text(
                  'GPS測量データ（${GlobalConfig.instance.drawingState.drawingLine.length + GlobalConfig.instance.drawingState.drawingPolygon.length}ポイント）が自動的に記録されます',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('キャンセル'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, {
                  'name': name,
                  'description': description,
                }),
                child: const Text('作成'),
              ),
            ],
          );
        },
      );
      
      if (result == null) return;
      
      // GlobalDrawingStateの統一確定処理を使用
      final drawingState = GlobalDrawingState.instance;
      
      // GPS測量データを追加メタデータとして準備
      final surveyGpsData = drawingState.isLineDrawing
          ? drawingState.getLineWithMetadata()
          : drawingState.getPolygonWithMetadata();
      final additionalMetadata = {
        'type': 'measurement_log',
        'contents': List<Map<String, dynamic>>.from(
          surveyGpsData.map((e) => Map<String, dynamic>.from(e)),
        ),
      };
      
      final success = await drawingState.confirmCurrentFeature(
        layerNode: selected,
        name: result['name']?.isNotEmpty == true ? result['name']! : 'GPS測量フィーチャ',
        description: result['description'] ?? '',
        closeRing: closeRing,
        additionalMetadata: additionalMetadata,
        refreshCallback: () {
          refreshMapUI();
        },
      );
      
      // GPS測量成功時はGPS停止
      if (success) {
        await gpsManager.stopGpsSurvey();
        await updateFeatures();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPS測量フィーチャを作成しました'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPS測量フィーチャの作成に失敗しました'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.debug('[MapGpsSurveyMixin] GPS測量確定エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS測量確定エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // =============================================
  // 抽象メソッド（サブクラスで実装）
  // =============================================
  
  /// フィーチャデータを更新
  Future<void> updateFeatures();
  
  /// マップUIを更新
  void refreshMapUI();
}

