// 招待リンク（URL参加）の組み立て・解析テスト
import 'package:flutter_test/flutter_test.dart';
import 'package:root_maps/services/party/party_invite.dart';

void main() {
  group('buildInviteUrl', () {
    test('web版URLに room クエリを載せる', () {
      expect(
        buildInviteUrl('AB23CD45'),
        'https://kokage-map.sleeptree.jp/?room=AB23CD45',
      );
    });
  });

  group('extractRoomCode', () {
    test('生コードを受ける（小文字・空白は正規化）', () {
      expect(extractRoomCode('AB23CD45'), 'AB23CD45');
      expect(extractRoomCode('  ab23cd45 '), 'AB23CD45');
    });

    test('招待URLからコードを取り出す', () {
      expect(
        extractRoomCode('https://kokage-map.sleeptree.jp/?room=AB23CD45'),
        'AB23CD45',
      );
    });

    test('他クエリが混ざったURLでも room を拾う', () {
      expect(
        extractRoomCode('https://example.com/?x=1&room=AB23CD45&y=2'),
        'AB23CD45',
      );
    });

    test('不正な形式は null', () {
      expect(extractRoomCode(''), isNull);
      expect(extractRoomCode('SHORT'), isNull);
      // O/0/1/I/L は使用文字集合に無い
      expect(extractRoomCode('OOOOOOOO'), isNull);
      expect(extractRoomCode('https://example.com/'), isNull);
      expect(extractRoomCode('https://example.com/?room=BAD'), isNull);
    });
  });
}
