# Play Console の掲載名を Android Publisher API から読む／書く。
#
#   読む: python tool/play/listing.py
#   書く: python tool/play/listing.py --apply
#
# ⚠ --apply を付けたときだけ commit する。付けなければ edit を作って捨てるだけで、
#    公開中の掲載情報には一切触れない。
#
# ⚠ **サービスアカウントを Play Console 側に招く操作が別に要る。**
#    APIを有効にしただけでは 403 になる（2026-08-27 に踏んだ）。
#    Play Console → ユーザーと権限 → ユーザーを招待 →
#      play-console@nemurigi-kobo.iam.gserviceaccount.com
#    に、このアプリへのアクセスと「ストアの掲載情報の編集」権限を与える。
#    ここはAPIから自分自身には付けられないので、画面での操作になる。
#
# ⚠ **書き込みは通るが commit だけ 403 になる**（2026-08-28）。
#    Play では commit が「変更を公開する」操作の扱いで、
#    「ストアでの表示の管理」だけでは足りない。
#    CLIで最後まで通すには「テスト版トラックとしてのアプリのリリース」が要るが、
#    それはビルドをアップロードして配信できる権限。一度きりの変更なら画面でやる方が安い。
#    → 読み取り専用として使うのが現実的。
#
# ⚠ 掲載名の変更は Google Play の審査に入る。

import sys

from google.oauth2 import service_account
from googleapiclient.discovery import build

KEY = 'C:/Users/mtmtk/.gcp-keys/nemurigi-play-console.json'
PACKAGE = 'com.k_root.k_maps'
SCOPES = ['https://www.googleapis.com/auth/androidpublisher']

# 変更後の掲載名。⚠ Playのタイトルは30文字まで
NEW_TITLE = {'ja-JP': 'こかげマップ', 'en-US': 'Kokage Map'}

apply = '--apply' in sys.argv

creds = service_account.Credentials.from_service_account_file(KEY, scopes=SCOPES)
api = build('androidpublisher', 'v3', credentials=creds, cache_discovery=False)
edits = api.edits()

edit = edits.insert(packageName=PACKAGE, body={}).execute()
edit_id = edit['id']
print('edit id =', edit_id)

listings = edits.listings().list(packageName=PACKAGE, editId=edit_id).execute()
for l in listings.get('listings', []):
    lang = l['language']
    print('%-8s title=%r' % (lang, l.get('title')))
    if lang in NEW_TITLE and l.get('title') != NEW_TITLE[lang]:
        body = dict(l)
        body['title'] = NEW_TITLE[lang]
        if apply:
            edits.listings().update(
                packageName=PACKAGE, editId=edit_id, language=lang, body=body
            ).execute()
            print('         -> %r に更新' % NEW_TITLE[lang])
        else:
            print('         -> %r にする（--apply で実行）' % NEW_TITLE[lang])

if apply:
    edits.commit(packageName=PACKAGE, editId=edit_id).execute()
    print('commit した。Google Playの審査に入る')
else:
    edits.delete(packageName=PACKAGE, editId=edit_id).execute()
    print('edit を捨てた（掲載情報は変えていない）')
