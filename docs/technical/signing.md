---
title: Android署名鍵の管理
tags: [technical, android, signing]
---

# Android署名鍵の管理

## 保管場所

署名鍵（keystore）は開発者の個人Google Drive内で保管している。

- **場所**: `マイドライブ/matsumoto_personal/事業/google play console/`
- **ファイル**: `k-maps-release.keystore`
- **ヒント**: 同ディレクトリの `KEYSTORE_HINT.txt` を参照

プロジェクトリポジトリには鍵・パスワード情報を一切含めない。

## リリースビルド手順

1. Google Driveから `k-maps-release.keystore` を取得
2. `android/key.properties` を作成:

```properties
storePassword=<パスワード>
keyPassword=<パスワード>
keyAlias=k-maps
storeFile=<keystoreの絶対パス>
```

3. `flutter build appbundle --release` を実行
4. ビルド後、`key.properties` はローカルに残しても良い（`.gitignore` 済み）

## Google Play アップロード鍵

- 2026/03/12にアップロード鍵を `k-maps-release.keystore` にリセット済み
- 同じkeystoreで複数アプリの署名が可能
