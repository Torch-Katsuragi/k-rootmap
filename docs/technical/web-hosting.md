---
title: web版のホスティング
tags: [technical, hosting, web]
---

# web版のホスティング

**本番URL: `https://kokage-map.sleeptree.jp`**（Firebase Hosting、サイトID `kokage-map`）。
「隠しページ」運用: **GitHubのREADMEに載せるURLと、直接共有した相手だけが入口**。
`sleeptree.jp` 本体が公開されても、当分そこからはリンクしない（2026-08-28決定）。
検索除けは `firebase.json` の `X-Robots-Tag: noindex`。

## デプロイ

```bash
flutter build web --release --dart-define=GOOGLE_WEB_CLIENT_ID=348302294570-7srd6hqqpgpvu8sqilihhvhrd1p720p7.apps.googleusercontent.com
firebase deploy --only hosting:kokage-map --project nemurigi-kobo
```

`https://kokage-map.web.app` にも同じものが出る（Firebaseの既定ドメイン）。

## 構成の在り処

| もの | 場所 |
| --- | --- |
| Hosting設定 | このリポの `firebase.json` / `.firebaserc` |
| DNS（CNAME → kokage-map.web.app） | Call-Agent リポの `infra/gcp/main.tf`（Cloud DNS `sleeptree-jp`、terraform管理） |
| カスタムドメイン登録 | firebasehosting API の customDomains（2026-08-28 作成） |
| OAuth生成元 | GCPコンソール「K-Maps Web」クライアント。`https://kokage-map.sleeptree.jp` と `http://localhost:8099`（開発） |

⚠ Call-Agent の terraform を apply するときは **-target でDNSレコードに絞る**こと。
全体 plan には call_agent VM の must be replaced が出ている（2026-08-28時点、別課題）。

⚠ Service Worker が古いビルドを配り続けることがある。デプロイ後に挙動が変わらないときは
devtools → Application → Service Workers で unregister して再読込（2026-08-28に踏んだ）。
