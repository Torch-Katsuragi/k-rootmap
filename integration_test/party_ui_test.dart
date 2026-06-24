// 位置共有UI: PartyButton → 作成ダイアログ → ルーム作成 の経路を実機で検証
//
// 実行: flutter test integration_test/party_ui_test.dart -d <device>
//
// screencap がエミュのGPUサーフェスを拾えない環境向けに、画面キャプチャに
// 頼らずウィジェットを直接駆動してUI→provider→実RTDBの配線を検証する。
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:root_maps/firebase_options.dart';
import 'package:root_maps/providers/party_providers.dart';
import 'package:root_maps/screens/map_page/widgets/party_controls.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  });

  testWidgets('PartyButton タップ→作成→セッションactive', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: Center(child: PartyButton())),
        ),
      ),
    );

    // 入口ボタンをタップ → 作成/参加ダイアログ
    await tester.tap(find.byType(PartyButton));
    await tester.pumpAndSettle();
    expect(find.text('位置共有パーティ'), findsOneWidget);

    // 表示名を入力（最初のTextFieldが名前）
    await tester.enterText(find.byType(TextField).first, 'UIテスト太郎');
    await tester.pump();

    // 新規作成（ホスト）
    await tester.tap(find.text('新規作成（ホスト）'));

    // 作成完了（ネットワーク）を待つ。pumpAndSettleはCircularProgressで
    // 終わらないので固定pumpでポーリングする。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    var active = false;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(seconds: 1));
      final s = container.read(partySessionProvider);
      if (s.active) {
        active = true;
        break;
      }
      if (s.error != null) fail('createRoom error: ${s.error}');
    }
    expect(active, isTrue, reason: 'ルーム作成でセッションがactiveになるはず');

    final state = container.read(partySessionProvider);
    expect(state.roomCode, isNotNull);
    expect(state.roomCode!.length, 8);
    expect(state.role!.name, 'host');

    // 後片付け
    await container.read(partySessionProvider.notifier).leave();
    await FirebaseAuth.instance.signOut();
  });
}
