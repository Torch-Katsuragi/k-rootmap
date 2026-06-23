// PartyConnectionMonitor の接続ステートマシンテスト
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:root_maps/services/party/party_connection_monitor.dart';

/// 手動で発火できるフェイクTimer（cancelを尊重する）
class _FakeTimer implements Timer {
  final void Function() callback;
  bool _active = true;
  _FakeTimer(this.callback);
  void fire() {
    if (_active) callback();
  }

  @override
  void cancel() => _active = false;
  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
}

void main() {
  group('PartyConnectionMonitor', () {
    late StreamController<bool> ifCtrl;
    late StreamController<bool> srvCtrl;
    late int onlineCalls;
    late int offlineCalls;
    late int recoveredCount;
    late _FakeTimer? lastTimer;
    late PartyConnectionMonitor monitor;

    setUp(() {
      ifCtrl = StreamController<bool>.broadcast();
      srvCtrl = StreamController<bool>.broadcast();
      onlineCalls = 0;
      offlineCalls = 0;
      recoveredCount = 0;
      lastTimer = null;
      monitor = PartyConnectionMonitor(
        hasInterface: ifCtrl.stream,
        serverConnected: srvCtrl.stream,
        requestOnline: () async => onlineCalls++,
        requestOffline: () async => offlineCalls++,
        timerFactory: (d, cb) {
          lastTimer = _FakeTimer(cb);
          return lastTimer!;
        },
      );
      monitor.onRecovered.listen((_) => recoveredCount++);
      monitor.start();
    });

    tearDown(() async {
      await ifCtrl.close();
      await srvCtrl.close();
      await monitor.dispose();
    });

    test('初期状態は offline', () {
      expect(monitor.state, PartyConnectionState.offline);
    });

    test('インターフェイス復帰で connecting + requestOnline', () async {
      ifCtrl.add(true);
      await pumpEventQueue();
      expect(monitor.state, PartyConnectionState.connecting);
      expect(onlineCalls, 1);
    });

    test('サーバー接続で online + recovered 通知', () async {
      ifCtrl.add(true);
      srvCtrl.add(true);
      await pumpEventQueue();
      expect(monitor.state, PartyConnectionState.online);
      expect(recoveredCount, 1);
    });

    test('サーバー断で connecting に戻り、再接続で recovered 再通知', () async {
      ifCtrl.add(true);
      srvCtrl.add(true);
      await pumpEventQueue();
      srvCtrl.add(false);
      await pumpEventQueue();
      expect(monitor.state, PartyConnectionState.connecting);
      expect(recoveredCount, 1);
      srvCtrl.add(true);
      await pumpEventQueue();
      expect(monitor.state, PartyConnectionState.online);
      expect(recoveredCount, 2);
    });

    test('インターフェイス継続喪失で goOffline（ほっとく）', () async {
      ifCtrl.add(true);
      srvCtrl.add(true);
      await pumpEventQueue();
      ifCtrl.add(false);
      await pumpEventQueue();
      expect(offlineCalls, 0, reason: 'デバウンス中はまだ');
      lastTimer!.fire(); // 継続喪失タイマ発火
      await pumpEventQueue();
      expect(offlineCalls, 1);
      expect(monitor.state, PartyConnectionState.offline);
    });

    test('瞬断（タイマ発火前に復帰）は goOffline しない', () async {
      ifCtrl.add(true);
      srvCtrl.add(true);
      await pumpEventQueue();
      ifCtrl.add(false);
      await pumpEventQueue();
      ifCtrl.add(true); // すぐ復帰
      await pumpEventQueue();
      lastTimer!.fire(); // キャンセル済みなので無効
      await pumpEventQueue();
      expect(offlineCalls, 0);
      expect(onlineCalls, 1, reason: '既にSDKオンラインなので再要求しない');
      expect(monitor.state, PartyConnectionState.online);
    });
  });
}
