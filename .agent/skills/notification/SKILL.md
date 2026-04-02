---
name: notification
description: アプリ内通知システムの使い方ガイド。通知の送信、レベル設定、UI表示を含む。「通知」「ユーザーへの通知」「処理完了の通知」等のトリガーで使用。
---

# アプリ内通知システム

## アーキテクチャ

```
AppNotification (モデル)
  └→ NotificationCenter (Riverpod プロバイダ, keepAlive)
       └→ NotificationBell (AppBar ウィジェット)
            ├─ 自動トースト (3秒, アニメーション付き)
            ├─ 未読バッジ
            └─ ドロップダウン一覧 (展開可能)
```

## 通知の送り方

### Ref がある場合（サービス層、DeviceTool 等）

```dart
import '../../models/app_notification.dart';
import '../../providers/notification_providers.dart';

ref.read(notificationCenterProvider.notifier).add(
  title: '処理が完了しました',
  detail: '詳細情報（省略可）',
  level: NotificationLevel.success,
);
```

### ConsumerWidget / ConsumerState 内

```dart
ref.read(notificationCenterProvider.notifier).add(
  title: 'エラーが発生しました',
  detail: e.toString(),
  level: NotificationLevel.error,
);
```

## 通知レベル

| レベル | 用途 | 例 |
|---|---|---|
| `info` | 情報提供（デフォルト） | 「ファイルをインポートしました」 |
| `success` | 成功報告 | 「後視補正を適用」「エクスポート完了」 |
| `warning` | 注意喚起 | 「精度が基準値以下です」 |
| `error` | エラー報告 | 「接続に失敗しました」 |

## パラメータ

```dart
void add({
  required String title,  // 通知タイトル（必須、1行）
  String? detail,         // 詳細テキスト（省略可、展開表示）
  NotificationLevel level, // デフォルト: info
})
```

- `title`: 簡潔に（トースト表示は最大2行）
- `detail`: 設定すると通知一覧で展開可能になる

## UI の挙動

1. `add()` 呼び出し → 通知リスト先頭に挿入（最大100件）
2. `NotificationBell` が変更を検知 → 自動トースト表示（3秒で消える）
3. ベルアイコンに未読数バッジ表示
4. ベルクリック → ドロップダウン一覧（既読/全既読/クリア操作可能）

## 関連ファイル

- `lib/models/app_notification.dart` - データモデル
- `lib/providers/notification_providers.dart` - NotificationCenter プロバイダ
- `lib/widgets/notification/notification_bell.dart` - ベルUI + トースト
- `lib/widgets/notification/notification_popup.dart` - ドロップダウン一覧
