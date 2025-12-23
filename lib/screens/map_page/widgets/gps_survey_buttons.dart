// K-MAPS: GPS測量ボタンウィジェット
// GPS測量と追跡のためのボタン群
import 'dart:io';
import 'package:flutter/material.dart';

/// GPS測量ボタンウィジェット
/// GPS測量ボタン（長押し対応）とGPS追跡ボタンを含む
class GpsSurveyButtons extends StatelessWidget {
  /// 長押し中フラグ
  final bool isLongPressing;
  
  /// 長押しGPSカウント
  final int longPressGpsCount;
  
  /// GPS追跡サービス実行中フラグ
  final bool isGpsTrackingServiceRunning;
  
  /// GPS測量タップコールバック
  final VoidCallback onRecordGpsPosition;
  
  /// GPS長押し測量開始コールバック
  final VoidCallback onStartLongPressGpsSurvey;
  
  /// GPS長押し測量停止コールバック
  final VoidCallback onStopLongPressGpsSurvey;
  
  /// GPS追跡開始コールバック
  final VoidCallback onStartGpsTracking;
  
  /// GPS追跡停止コールバック
  final VoidCallback onStopGpsTracking;

  const GpsSurveyButtons({
    super.key,
    required this.isLongPressing,
    required this.longPressGpsCount,
    required this.isGpsTrackingServiceRunning,
    required this.onRecordGpsPosition,
    required this.onStartLongPressGpsSurvey,
    required this.onStopLongPressGpsSurvey,
    required this.onStartGpsTracking,
    required this.onStopGpsTracking,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // GPS測量ボタン（長押し対応）
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 長押し中のデータ個数表示
              if (isLongPressing)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4.0,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '$longPressGpsCount点',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              // GPS測量ボタン
              GestureDetector(
                onTap: onRecordGpsPosition,
                onLongPress: onStartLongPressGpsSurvey,
                onLongPressEnd: (_) => onStopLongPressGpsSurvey(),
                child: Container(
                  width: 56.0,
                  height: 56.0,
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8.0,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 長押し進行状況を示すプログレスインジケーター
                      if (isLongPressing)
                        SizedBox(
                          width: 56.0,
                          height: 56.0,
                          child: CircularProgressIndicator(
                            strokeWidth: 3.0,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            backgroundColor: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                      // メインアイコン
                      const Icon(
                        Icons.add_location,
                        size: 28,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // GPS追跡ボタン（Windows以外の環境でのみ表示）
        if (!Platform.isWindows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FloatingActionButton(
              heroTag: 'gps_tracking_left',
              onPressed: isGpsTrackingServiceRunning
                  ? onStopGpsTracking
                  : onStartGpsTracking,
              backgroundColor: isGpsTrackingServiceRunning
                  ? Colors.red
                  : Colors.green,
              foregroundColor: Colors.white,
              tooltip: isGpsTrackingServiceRunning
                  ? 'GPS追跡停止'
                  : 'GPS追跡開始',
              child: Icon(
                isGpsTrackingServiceRunning
                    ? Icons.stop
                    : Icons.pets,
                size: 28,
              ),
            ),
          ),
      ],
    );
  }
}

