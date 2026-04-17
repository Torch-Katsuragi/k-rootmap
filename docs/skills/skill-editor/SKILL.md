---
name: skill-editor
description: >
  Agent Skill（SKILL.md）の作成・編集・設計を行う。
  スキルの新規作成、既存スキルの改善、スキル統合、構造設計を扱う。
  「スキルを作って」「スキルを編集して」「スキル構造を見直して」等のトリガーで使用。
---

# Skill Editor

Agent Skill の作成・編集ガイド。このスキル自体が設計原則の実例になっている。

## 設計原則

### 1. コンテキストウィンドウ経済学

スキルの description は全リクエストで常時ロードされる（1スキル ≈ 50-80トークン）。
関連する機能を別々のスキルに分けると、使わないときもトークンを消費し続ける。

- 関連機能は1スキルに統合する（例: Gmail + Calendar → `google-workspace`）
- 独立した機能は分離する（例: PDF変換と会計処理は別スキル）
- 判断基準: 「同時に使われることが多いか？」

### 2. Progressive Disclosure（段階的開示）

情報を3層に分け、必要な時だけロードする:

| 層 | 内容 | ロードタイミング | コスト |
|----|------|------------------|--------|
| Discovery | `name` + `description`（frontmatter） | 常時 | ~50-80トークン/スキル |
| Activation | SKILL.md 本文 | descriptionがマッチした時 | ~500-2000トークン |
| Execution | `references/` 内のファイル | 実行時に必要な箇所だけ | 可変 |

### 3. Sub-Skill パターン

- SKILL.md は500行以下を維持する
- 500行を超えたら `references/` に分割する
- 分割してもスキル登録は1つのまま（references はスキル数にカウントされない）
- references のネストは1階層まで（SKILL.md → references/x.md。references 間の相互参照は避ける）

## ディレクトリ構成

```
skill-name/
├── SKILL.md              ← 必須。エントリポイント
├── references/           ← 任意。詳細ドキュメント（実行時にオンデマンド読み込み）
│   ├── topic-a.md
│   └── topic-b.md
├── scripts/              ← 任意。エージェントが実行するスクリプト
│   └── helper.ps1
└── assets/               ← 任意。テンプレート・設定ファイル
```

## SKILL.md の書き方

詳細は `references/authoring-guide.md` を参照。以下は要点のみ。

### Frontmatter（必須）

```yaml
---
name: skill-name          # フォルダ名と一致。小文字・ハイフン・数字のみ
description: >            # 何をするか + いつ使うか。三人称で記述
  ○○を行うスキル。△△のときに使用。
  「トリガーフレーズ」等で起動。
---
```

- description は Discovery 層で常時ロードされる唯一の情報
- 「何ができるか」と「いつ使うか」の両方を含める
- 自然言語のトリガーフレーズを含めると発見精度が上がる

### 本文の構成

1. 概要（1-2行）
2. 重要な設定・認証情報
3. よく使う操作の要約
4. references へのルーティング（「詳細は `references/xxx.md` を参照」）
5. 運用ルール・制約

### 書かなくていいこと

エージェントは十分に賢い。以下は省略してよい:

- 一般常識や基本概念の説明
- ライブラリの公式ドキュメントの転写
- 「こうしてください」の冗長な言い換え

問いかけ: 「このパラグラフはトークンコストに見合うか？」

## スキル統合の判断フロー

既存スキルに機能を追加するか、新スキルを作るかの判断:

1. 既存スキルと同じサービス/ドメインか？ → Yes: 統合を検討
2. 同時に使われることが多いか？ → Yes: 統合
3. 統合後500行を超えるか？ → references/ で分割すれば1スキルのまま維持可能
4. 完全に独立した機能か？ → 新スキルとして作成

## オプションフィールド

```yaml
upstream:                          # 参考にした外部スキルのURL
  - https://github.com/...
compatibility: Python 3.10+, gws CLI  # 環境要件
disable-model-invocation: true     # /skill-name でのみ起動（危険な操作向け）
metadata:
  category: workflow               # 分類タグ
```

## チェックリスト

スキル作成・編集後の確認事項:

- [ ] description に「何を」と「いつ」の両方が含まれている
- [ ] description は三人称で書かれている
- [ ] SKILL.md は500行以下
- [ ] references のネストは1階層
- [ ] 不要な説明・冗長な記述がない
- [ ] 関連する既存スキルとの重複がない
- [ ] スクリプトがある場合、実行環境の要件が明記されている

## リファレンス

- `references/authoring-guide.md` — description の書き方、パターン集、アンチパターン
