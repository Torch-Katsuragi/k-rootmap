// 位置共有: 実Firebase RTDBに対する往復の統合テスト
//
// 実行（エミュ/実機が必要）:
//   flutter test integration_test/party_rtdb_test.dart -d <device>
//
// 検証内容: 匿名認証 → ルーム作成 → 位置publish → peersで読み戻し（サーバー時刻が
// 付与されること）→ track publish → 後片付け。セキュリティルールが期待どおり
// 書き込みを許可することも併せて確認する。
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:root_maps/firebase_options.dart';
import 'package:root_maps/models/party/peer_position.dart';
import 'package:root_maps/services/party/rtdb_peer_source.dart';
import 'package:root_maps/services/party/rtdb_room_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  });

  test('host: 作成→位置publish→読み戻し→track→後片付け', () async {
    final repo = RtdbRoomRepository();
    final uid = await repo.ensureSignedIn();
    expect(uid, isNotEmpty);

    final meta = await repo.createRoom(name: 'integ-test');
    expect(meta.roomCode.length, 8);
    expect(meta.hostUid, uid);

    final source = RtdbPeerSource(roomCode: meta.roomCode, selfUid: uid);
    source.start();

    // 読み戻しの待受をpublishより先に張る（broadcastの取りこぼし防止）
    final readback = source.peers
        .firstWhere((m) => m.containsKey(uid))
        .timeout(const Duration(seconds: 15));

    await source.publishPosition(
      const PeerPosition(
        uid: 'ignored',
        latitude: 35.681,
        longitude: 139.767,
        accuracy: 5,
        bearing: 90,
        speed: 1.2,
        serverTimeMs: 0,
      ),
    );

    final peers = await readback;
    final self = peers[uid]!;
    expect(self.latitude, closeTo(35.681, 1e-4));
    expect(self.longitude, closeTo(139.767, 1e-4));
    expect(self.serverTimeMs, greaterThan(0),
        reason: 'サーバー時刻(ServerValue.timestamp)が付与されるはず');

    // track（gap backfill）も書けること
    await source.publishTrack(encodedPolyline: '_p~iF~ps|U', fromMs: 1, toMs: 2);

    // 後片付け（順序が重要: active=trueのうちに退出 → その後host終了）
    await source.dispose();
    await repo.leaveRoom(meta.roomCode); // active===true のうちに自己削除
    await repo.endRoom(meta.roomCode); // host: active=false（purge対象化）
    await FirebaseAuth.instance.signOut();
  });
}
