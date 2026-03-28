/// 接続済み外部機器ツールの集約プロバイダー
///
/// MapToolbar / map_page はこのプロバイダーのみを参照し、
/// 個別デバイスの知識を持たない。
/// 新しい機器を追加する場合、このファイルに1行追加するだけでよい。
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../devices/base/device_tool.dart';
import '../devices/trupulse/trupulse_providers.dart';

part 'device_tool_providers.g.dart';

/// DeviceTool のオーバーレイ再描画トリガー
///
/// featureRefreshTriggerProvider と同パターン。
/// DeviceTool 内部状態が変わった際に trigger() を呼び、
/// map_page 側の ref.listen で triggerSetState を発火する。
@Riverpod(keepAlive: true)
class DeviceToolOverlayRefresh extends _$DeviceToolOverlayRefresh {
  @override
  int build() => 0;

  void trigger() => state++;
}

/// 接続済みで利用可能なDeviceToolのリストを返す
///
/// 各サービスの ChangeNotifier を addListener で購読し、
/// isConnected 変更時にプロバイダを再評価する。
@riverpod
List<DeviceTool> connectedDeviceTools(Ref ref) {
  final trupulseService = ref.watch(trupulseServiceProvider);
  final trupulseTool = ref.watch(trupulseToolProvider);

  // Bridge: ChangeNotifier → Riverpod
  void onServiceChange() => ref.invalidateSelf();
  trupulseService.addListener(onServiceChange);
  ref.onDispose(() => trupulseService.removeListener(onServiceChange));

  return [
    if (trupulseTool.isAvailable) trupulseTool,
    // 将来のデバイス: ここにサービス購読 + 条件行を追加するだけ
  ];
}
