# AGENTS.md

## 会話ルール

- 日本語で会話・ドキュメント作成
- 質問がある場合は推測せず確認

## プロジェクト概要

Flutter製の地図アプリ（k_maps）。Windows/Android対応。

## 開発フロー

1. 作業前: `TODO.md`、`docs/` を確認
2. 実装: できるだけ計画を立ててから実装に移る
3. 作業後: `TODO.md` を更新

## 優先順位

1. バグ修正・リンターエラー
2. 既存機能の改善
3. 新機能
4. ドキュメント

## ファイル操作

- 作成: 実装に必要なファイルのみ
- 削除: 一時ファイル、テスト用ダミー
- 一時ファイル出力: `.temp/` に配置（`.gitignore` 済み）
- .md系はObsidian記法（フロントマター、`[[リンク]]`）
- commitの前にchangelogを全言語分更新

## 参照

- `TODO.md` - タスク管理
- `docs/` - 設計書・技術資料（[[docs/index|目次]]）
- `.agent/skills/` - エージェントスキル

## よく使うパターン

- UI更新: [[docs/technical/ui-layer-tree|レイヤツリー更新ガイド]] - `updateChildren()` の使い方
