// RoomCodeGenerator の生成・検証テスト
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:root_maps/services/party/room_code_generator.dart';

void main() {
  group('RoomCodeGenerator', () {
    test('既定で8文字を生成し、すべて許可文字', () {
      final gen = RoomCodeGenerator(Random(42));
      final code = gen.generate();
      expect(code.length, 8);
      for (final ch in code.split('')) {
        expect(RoomCodeGenerator.alphabet.contains(ch), isTrue);
      }
    });

    test('紛らわしい文字を含まない', () {
      for (final bad in ['0', '1', 'I', 'L', 'O']) {
        expect(RoomCodeGenerator.alphabet.contains(bad), isFalse,
            reason: '$bad は除外されるべき');
      }
    });

    test('長さ指定が効く', () {
      final gen = RoomCodeGenerator(Random(1));
      expect(gen.generate(6).length, 6);
    });

    test('isValid は規約準拠コードを通す', () {
      final gen = RoomCodeGenerator(Random(7));
      expect(RoomCodeGenerator.isValid(gen.generate()), isTrue);
    });

    test('isValid は不正コードを弾く', () {
      expect(RoomCodeGenerator.isValid('ABC'), isFalse, reason: '長さ不足');
      expect(RoomCodeGenerator.isValid('ABCDEFG0'), isFalse, reason: '0を含む');
      expect(RoomCodeGenerator.isValid('abcdefgh'), isFalse, reason: '小文字');
    });
  });
}
