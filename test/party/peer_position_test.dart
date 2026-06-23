// PeerPosition のシリアライズと鮮度判定テスト
import 'package:flutter_test/flutter_test.dart';
import 'package:root_maps/models/party/peer_position.dart';

void main() {
  group('PeerPosition', () {
    test('fromMap が値を正しくパースする', () {
      final p = PeerPosition.fromMap('uidA', {
        'lat': 35.1,
        'lng': 139.2,
        'alt': 100.0,
        'acc': 5.0,
        'bearing': 180.0,
        'speed': 1.5,
        'ts': 1000,
        'battery': 80,
        'connected': true,
      });
      expect(p.uid, 'uidA');
      expect(p.latitude, 35.1);
      expect(p.longitude, 139.2);
      expect(p.altitude, 100.0);
      expect(p.serverTimeMs, 1000);
      expect(p.battery, 80);
      expect(p.connected, true);
    });

    test('fromMap は欠損フィールドに寛容', () {
      final p = PeerPosition.fromMap('uidB', {'lat': 1.0, 'lng': 2.0});
      expect(p.altitude, isNull);
      expect(p.accuracy, isNull);
      expect(p.battery, isNull);
      expect(p.serverTimeMs, 0);
      expect(p.connected, true); // 既定
    });

    test('toLiveMap は ts を含めず connected を含む', () {
      const p = PeerPosition(
        uid: 'x',
        latitude: 10,
        longitude: 20,
        serverTimeMs: 999,
        connected: true,
      );
      final m = p.toLiveMap();
      expect(m.containsKey('ts'), isFalse, reason: 'tsは送信側がServerValueで付与');
      expect(m['lat'], 10);
      expect(m['lng'], 20);
      expect(m['connected'], true);
      expect(m.containsKey('alt'), isFalse, reason: 'nullは載せない');
    });

    group('freshnessAt', () {
      const base = 1000000;
      PeerPosition at(int ts, {bool connected = true}) => PeerPosition(
        uid: 'u',
        latitude: 0,
        longitude: 0,
        serverTimeMs: ts,
        connected: connected,
      );

      test('30秒未満かつ接続中は fresh', () {
        expect(at(base).freshnessAt(base + 10000), PeerFreshness.fresh);
      });

      test('30秒以上15分未満は stale', () {
        expect(at(base).freshnessAt(base + 60000), PeerFreshness.stale);
      });

      test('15分以上は lost', () {
        expect(
          at(base).freshnessAt(base + 16 * 60 * 1000),
          PeerFreshness.lost,
        );
      });

      test('接続断は経過時間が短くても stale', () {
        expect(
          at(base, connected: false).freshnessAt(base + 5000),
          PeerFreshness.stale,
        );
      });

      test('接続断でも15分超なら lost', () {
        expect(
          at(base, connected: false).freshnessAt(base + 20 * 60 * 1000),
          PeerFreshness.lost,
        );
      });
    });

    test('ageAt は負値を0にクランプ', () {
      const p = PeerPosition(uid: 'u', latitude: 0, longitude: 0, serverTimeMs: 5000);
      expect(p.ageAt(4000), Duration.zero);
    });
  });
}
