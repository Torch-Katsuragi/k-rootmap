---
title: Google Drive連携セットアップ
tags: [technical, google-drive, setup]
---


> [!NOTE] 2026-08-27: 同期コードを web でも動く形にした
> `lib/services/google_drive/` から `dart:io` を撤去した。API境界が
> `dart:io` の `File` を持ち回っていたので、そこから変えている:
>
> - `uploadFile(File)` → `uploadFile(String localPath)`
> - `uploadBytes(Uint8List, name, parent)` を追加（一時ファイルを作らないため。
>   web には一時ディレクトリが無い）
> - `LocalSyncFile` は `File` ではなく `path` + `size` を持つ
> - 再帰列挙は `fs.listRecursive()` / `fs.listDirectoriesRecursive()`
> - 更新日時は `fs.lastModified()`（web も `File.lastModified` で取れる）
>
> ⚠ **アップロードは中身を丸ごとメモリに載せる。**
> `openRead()` のストリームは web に無いので揃えた。
> 現場のgpkgは数十MB程度なので許容している。
>
> ⚠ **web で使うには web用のOAuthクライアントIDが要る。**
> GCPコンソールでしか発行できない。`--dart-define=GOOGLE_WEB_CLIENT_ID=...`
> で渡す。未設定の間は `PlatformCapabilities.supportsDriveSync` が
> web で false のままなので、UIも出ない。

# Google Drive連携セットアップ

Google Drive連携機能を有効にするためのセットアップ手順。

## 前提条件

- Googleアカウント（GCP利用可能なもの）
- Android端末またはエミュレータ（OAuth認証のテスト用）

---

## 1. Google Cloud Console設定

### 1.1 プロジェクト作成

1. [Google Cloud Console](https://console.cloud.google.com/) にアクセス
2. 「プロジェクトを選択」→「新しいプロジェクト」
3. プロジェクト名: `Root Maps`（任意）
4. 「作成」をクリック

### 1.2 Drive API有効化

1. 左メニュー「APIとサービス」→「ライブラリ」
2. 「Google Drive API」を検索
3. 「有効にする」をクリック

### 1.3 OAuth同意画面設定

1. 左メニュー「APIとサービス」→「OAuth同意画面」
2. ユーザータイプ: 「外部」を選択（テスト段階）
3. 必須項目を入力：
   - アプリ名: `Root Maps`
   - ユーザーサポートメール: 自分のメールアドレス（またはGoogle Group）
   - デベロッパーの連絡先: 自分のメールアドレス
4. スコープ設定で以下を追加：
   - `https://www.googleapis.com/auth/drive` （Driveへのフルアクセス）
   - `https://www.googleapis.com/auth/userinfo.email` （メールアドレス取得）

### 1.3.1 テストユーザーの追加（重要）

**アプリが「テストモード」の間は、テストユーザーに登録されたアカウントのみログイン可能。**

1. OAuth同意画面 → 「**Audience**」または「**対象**」タブ
2. 「テストユーザー」セクションで「**+ ADD USERS**」をクリック
3. ログインに使用するGoogleアカウントのメールアドレスを追加
4. 保存

> **Note**: テストユーザーは最大100人まで追加可能。本番公開前の開発・テスト段階ではこれで十分。

### 1.3.2 本番公開について

本番公開（Google審査）は**ストア公開直前**でOK。開発中はテストユーザー追加で対応。

本番公開に必要なもの（今は不要）：
- プライバシーポリシーURL（GitHub Pagesで簡易ページを作成可）
- 利用規約URL（任意）
- `drive`スコープは機密性が高いため、追加のセキュリティ審査が必要になる場合あり

### 1.4 OAuthクライアントID作成（Android）

**重要**: デバッグビルドとリリースビルドで異なるSHA-1フィンガープリントが使われるため、**両方のクライアントIDを作成**する必要がある。両方登録しておけば、GoogleがSHA-1を見て自動で正しいクライアントIDを選択する。

#### SHA-1フィンガープリントの取得

```powershell
# デバッグ用SHA-1
keytool -list -v -keystore $env:USERPROFILE\.android\debug.keystore -alias androiddebugkey -storepass android -keypass android | Select-String "SHA1"

# リリース用SHA-1（key.propertiesのパスを参照）
keytool -list -v -keystore C:\Users\kitay\Root Maps-release.keystore -alias Root Maps
```

#### デバッグ用クライアントID作成

1. 左メニュー「APIとサービス」→「認証情報」
2. 「認証情報を作成」→「OAuthクライアントID」
3. アプリケーションの種類: 「Android」
4. 名前: `Root Maps Android (Debug)`
5. パッケージ名: `com.k_root.root_maps`
6. SHA-1フィンガープリント: デバッグ用SHA-1を入力
7. 「作成」をクリック

#### リリース用クライアントID作成

1. 「認証情報を作成」→「OAuthクライアントID」
2. アプリケーションの種類: 「Android」
3. 名前: `Root Maps Android (Release)`
4. パッケージ名: `com.k_root.root_maps`
5. SHA-1フィンガープリント: リリース用SHA-1を入力
6. 「作成」をクリック

> **Note**: AndroidクライアントIDはアプリ内で直接使用しない。Google Play Servicesが自動でマッチングする。

### 1.5 OAuthクライアントID作成（Web）

google_sign_inパッケージはWebクライアントIDも必要：

1. 「認証情報を作成」→「OAuthクライアントID」
2. アプリケーションの種類: 「ウェブ アプリケーション」
3. 名前: `Root Maps Web`
4. 「作成」をクリック
5. **クライアントIDをコピー**

---

## 2. Androidプロジェクト設定

### 2.1 strings.xmlにクライアントIDを追加

`android/app/src/main/res/values/strings.xml` を作成：

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Google Sign-In用のWebクライアントID -->
    <string name="default_web_client_id">YOUR_WEB_CLIENT_ID.apps.googleusercontent.com</string>
</resources>
```

`YOUR_WEB_CLIENT_ID` を実際のWebクライアントIDに置き換え。

---

## 3. 環境変数（オプション）

機密情報を環境変数で管理する場合：

```powershell
# 開発環境用
$env:GOOGLE_WEB_CLIENT_ID = "your-web-client-id.apps.googleusercontent.com"
```

---

## 4. 動作確認

1. アプリをデバッグビルドで実行
2. Google Drive連携画面で「Sign in with Google」をタップ
3. Googleアカウント選択画面が表示されることを確認
4. 権限同意後、Drive APIが使用可能になることを確認

---

## トラブルシューティング

### 「DEVELOPER_ERROR」（ApiException: 10）が表示される

- **最もよくある原因**: デバッグ/リリース両方のAndroidクライアントIDが登録されていない
- SHA-1フィンガープリントが正しいか確認（`keytool`で再取得して比較）
- パッケージ名が`com.k_root.root_maps`と一致しているか確認
- Google Cloud Consoleで両方のクライアントIDが作成されているか確認

### 「access_denied」が表示される

- OAuth同意画面でテストユーザーに追加されているか確認
- スコープが正しく設定されているか確認

### Windows環境での認証

google_sign_inはWindowsネイティブ非対応。代替手段：
- WebViewベースのOAuth（要追加パッケージ）
- ブラウザ経由のOAuth（url_launcher使用）

---

## 関連ドキュメント

- [[google-drive]] - Google Drive連携設計書
