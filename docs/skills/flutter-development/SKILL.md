---
name: flutter-development
description: Flutter/Dart開発のベストプラクティスとパターン。ウィジェット設計、状態管理、非同期処理、パフォーマンス最適化に関するガイドライン。Flutterアプリの実装時に参照する。
---

# Flutter開発ガイド

## ウィジェット設計

### StatelessWidget vs StatefulWidget

```dart
// 状態を持たない場合 → StatelessWidget
class InfoCard extends StatelessWidget {
  final String title;
  const InfoCard({super.key, required this.title});
  
  @override
  Widget build(BuildContext context) => Card(child: Text(title));
}

// 内部状態が必要な場合 → StatefulWidget
class Counter extends StatefulWidget {
  const Counter({super.key});
  @override
  State<Counter> createState() => _CounterState();
}
```

### constコンストラクタ

```dart
// パフォーマンス向上のためconstを積極的に使用
const EdgeInsets.all(8.0)
const SizedBox(height: 16)
const Icon(Icons.map)
```

## 状態管理

### 推奨パターン

| 規模 | 推奨 |
|------|------|
| ローカル状態 | `setState` |
| 画面間共有 | `Provider` / `Riverpod` |
| 複雑なアプリ | `Riverpod` / `Bloc` |

### setState の適切な使用

```dart
// 最小限の更新
setState(() {
  _counter++; // 変更する状態のみ
});

// 重い処理はsetStateの外で
final result = await heavyComputation();
setState(() {
  _data = result;
});
```

## 非同期処理

### FutureBuilder

```dart
FutureBuilder<List<Item>>(
  future: _loadItems(),
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const CircularProgressIndicator();
    }
    if (snapshot.hasError) {
      return Text('エラー: ${snapshot.error}');
    }
    return ListView.builder(
      itemCount: snapshot.data!.length,
      itemBuilder: (context, index) => ItemTile(snapshot.data![index]),
    );
  },
)
```

### StreamBuilder

```dart
StreamBuilder<Position>(
  stream: _locationStream,
  builder: (context, snapshot) {
    if (!snapshot.hasData) return const Text('位置情報取得中...');
    return Text('緯度: ${snapshot.data!.latitude}');
  },
)
```

## パフォーマンス

### ビルド最適化

```dart
// 不変ウィジェットはconstで
const Divider()

// リストは itemExtent を指定
ListView.builder(
  itemExtent: 56.0, // 固定高さでパフォーマンス向上
  itemCount: items.length,
  itemBuilder: (context, index) => ItemTile(items[index]),
)

// RepaintBoundary で再描画を分離
RepaintBoundary(
  child: ExpensiveWidget(),
)
```

### メモリ管理

```dart
@override
void dispose() {
  _controller.dispose();  // コントローラーは必ず破棄
  _subscription.cancel(); // ストリーム購読もキャンセル
  super.dispose();
}
```

## よく使うウィジェット

### レイアウト

| ウィジェット | 用途 |
|--------------|------|
| `Column` | 縦方向に配置 |
| `Row` | 横方向に配置 |
| `Stack` | 重ねて配置 |
| `Expanded` | 残りスペースを埋める |
| `Flexible` | 柔軟なサイズ |
| `SizedBox` | 固定サイズ/スペーサー |

### 入力

| ウィジェット | 用途 |
|--------------|------|
| `TextField` | テキスト入力 |
| `ElevatedButton` | 主要アクション |
| `IconButton` | アイコンボタン |
| `Switch` | ON/OFF切り替え |

## ナビゲーション

### 基本的な遷移

```dart
// プッシュ
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => DetailPage()),
);

// 名前付きルート
Navigator.pushNamed(context, '/detail');

// 戻る
Navigator.pop(context);

// 結果を返す
Navigator.pop(context, result);
```

## エラーハンドリング

```dart
try {
  await riskyOperation();
} on SpecificException catch (e) {
  // 特定の例外を処理
  showSnackBar('エラー: ${e.message}');
} catch (e, stackTrace) {
  // 予期せぬエラーをログ
  debugPrint('Unexpected error: $e\n$stackTrace');
  rethrow; // 必要に応じて再スロー
}
```

## テスト

### ウィジェットテスト

```dart
testWidgets('Counter increments', (tester) async {
  await tester.pumpWidget(const MyApp());
  expect(find.text('0'), findsOneWidget);
  
  await tester.tap(find.byIcon(Icons.add));
  await tester.pump();
  
  expect(find.text('1'), findsOneWidget);
});
```

## pubspec.yaml

### 依存関係の追加

```yaml
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.0.0  # バージョン指定

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
```

### アセット登録

```yaml
flutter:
  assets:
    - assets/images/
    - assets/data/
```

## コマンド

```bash
# 依存関係取得
flutter pub get

# 分析
flutter analyze

# テスト
flutter test

# ビルド
flutter build apk
flutter build appbundle

# クリーン
flutter clean
```
