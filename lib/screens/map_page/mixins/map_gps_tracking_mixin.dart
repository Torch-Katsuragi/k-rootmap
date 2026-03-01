// K-MAPS: GPS軌跡抽出Mixin
// GPS軌跡は常時記録されており、このmixinは軌跡抽出ダイアログを開く機能のみ提供
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../widgets/track_extraction_dialog.dart';
import '../map_page_state_base.dart';

/// GPS軌跡抽出Mixin
/// GPS軌跡は GpsHistoryRecorder により常時記録されている。
/// このmixinは軌跡抽出ダイアログを開くインターフェースを提供する。
mixin MapGpsTrackingMixin<T extends ConsumerStatefulWidget> on MapPageStateBase<T> {

  /// 軌跡抽出ダイアログを開く
  Future<void> openTrackExtractionDialog() async {
    if (!gpsHistoryRecorder.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS履歴が初期化されていません'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => TrackExtractionDialog(
        recorder: gpsHistoryRecorder,
      ),
    );

    // ダイアログで保存された場合、フィーチャを更新
    if (result == true) {
      await updateFeatures();
      triggerSetState(() {});
    }
  }

  // =============================================
  // 抽象メソッド（サブクラスで実装）
  // =============================================

  /// フィーチャデータを更新
  Future<void> updateFeatures();
}
