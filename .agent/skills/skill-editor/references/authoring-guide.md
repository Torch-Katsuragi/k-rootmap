# スキル作成 詳細ガイド

## Description の書き方

### 構造

良い description は4つの要素を含む:

1. **何をするか**（1文）: コア機能の説明
2. **いつ使うか**: ユーザーの意図とのマッチング条件
3. **トリガーフレーズ**: ユーザーが実際に使う自然言語
4. **能動的トリガー**（任意）: エージェントが自発的に適用する条件

```yaml
# 良い例
description: >
  Google Workspace (Gmail/Calendar) を gws CLI で操作する。
  メール送信・検索・下書き、カレンダー予定の確認・登録を扱う。
  「メールを確認して」「メールを送って」「下書きを作成して」
  「カレンダーを確認して」「予定を登録して」等のトリガーで使用。

# 悪い例
description: "メール関連の処理を行う"
# → 曖昧すぎてマッチしない

description: "I can help you manage emails"
# → 一人称は不可。三人称で書く
```

### 三人称ルール

description はシステムプロンプトに注入される。三人称で記述する:

- OK: 「PDFファイルを処理し、テキストを抽出する」
- NG: 「PDFファイルの処理を手伝います」
- NG: 「このスキルを使ってPDFを処理できます」

### トークン予算

description 全体で50-80トークンが目安。長すぎると Discovery 層のコストが増える。
100トークンを超える場合は削れる箇所がないか見直す。

## パターン集

### テンプレートパターン

出力形式が決まっている場合:

```markdown
## 報告書テンプレート

\`\`\`markdown
# [タイトル]

## 概要
[1段落]

## 所見
- 項目1
- 項目2

## 推奨事項
1. アクション1
2. アクション2
\`\`\`
```

### ワークフローパターン

複数ステップの手順:

```markdown
## 処理フロー

1. 入力ファイルを検証する
2. `scripts/process.py` で変換する
3. 出力を検証する（失敗時はステップ2に戻る）
4. 結果を報告する
```

### 条件分岐パターン

状況に応じた判断:

```markdown
## 対応方法の選択

**新規作成の場合** → 「作成ワークフロー」へ
**既存編集の場合** → 「編集ワークフロー」へ
```

### ルーティングパターン（階層型スキル向け）

SKILL.md で概要を示し、詳細は references に委譲:

```markdown
## サービス別リファレンス

| サービス | 参照先 |
|----------|--------|
| Gmail | `references/gmail.md` |
| Calendar | `references/calendar.md` |
```

## アンチパターン

### 1. 選択肢の羅列

```markdown
# NG
"pypdf, pdfplumber, PyMuPDF のいずれかを使用..."

# OK — デフォルトを1つ決め、例外だけ書く
"pdfplumber を使用する。スキャン済みPDFのOCRには pdf2image + pytesseract。"
```

### 2. 一般知識の転写

エージェントが既に知っていることを書かない。

```markdown
# NG（トークンの無駄）
"PDF (Portable Document Format) はAdobe社が開発した文書形式で..."

# OK（エージェントが知らない固有情報だけ書く）
"pdfplumber で表抽出する際は `extract_tables()` の `table_settings` で罫線検出閾値を調整する"
```

### 3. Windows 固有パスのハードコード

```markdown
# NG
scripts\helper.py
C:\Users\kitay\scripts\helper.py

# OK
scripts/helper.py
$env:USERPROFILE\.venvs\tool-name
```

### 4. 用語のブレ

1つの概念に1つの用語を統一する:

- OK: 常に「エンドポイント」（「URL」「ルート」「パス」を混在させない）
- OK: 常に「フィールド」（「ボックス」「項目」「コントロール」を混在させない）

### 5. 曖昧なスキル名

```
# NG
helper, utils, tools, misc

# OK
pdf-processor, code-review, google-workspace
```

## スクリプトの設計指針

スキルにスクリプトを含める場合:

- 生成コードよりも事前作成スクリプトを優先する（信頼性・トークン節約・一貫性）
- スクリプトは `scripts/` 内に配置する
- SKILL.md にはスクリプトの呼び出し方法と引数だけ書く（コード全体は書かない）
- 実行環境の要件を明記する（Python バージョン、必要パッケージ等）
- venv の作成場所は `$env:USERPROFILE\.venvs\` 配下（AGENTS.md 準拠）

## upstream フィールド

外部スキルを参考にした場合、frontmatter に出典を記録する:

```yaml
upstream:
  - https://github.com/org/repo/tree/main/skills/skill-name
  - https://example.com/original-skill
```

将来のアップデート追従や、ライセンス確認に役立つ。

## 参考資料

- [Agent Skills: Progressive Disclosure as a System Design Pattern](https://www.newsletter.swirlai.com/p/agent-skills-progressive-disclosure) — 3層アーキテクチャの理論的背景
- [How Cursor Finds Skills](https://agenticthinking.ai/blog/skill-discovery/) — Discovery メカニズムの詳細
- [Agent Skills 公式ドキュメント](https://www.cursor.com/docs/context/skills) — Cursor 公式仕様
- [Agent Skills 仕様](https://agentskills.io/) — オープンスタンダード仕様
