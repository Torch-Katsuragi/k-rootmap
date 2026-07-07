#!/usr/bin/env node
// 位置共有パーティ: 偽装ピア（テスト用クライアント）
//
// 2台目の端末/エミュを用意せずに、RTDB と直接やり取りする「動くピア」を作る。
// 匿名サインイン → ルーム参加(or作成) → live/{uid} に移動する位置を publish。
// 実機アプリ側の地図に、このピアのマーカーが動いて見える。
//
// 依存なし（Node 18+ の global fetch を使用）。
//
// 使い方:
//   node tool/party_fake_peer.js join <ROOMCODE> [name] [centerLat] [centerLng]
//   node tool/party_fake_peer.js create [name]        # 自分でルームを作ってホストになる
//
// 例（実機が作ったルーム ABCD2345 に、端末のGPS(33.931,135.963)付近で参加）:
//   node tool/party_fake_peer.js join ABCD2345 Fake太郎 33.9312 135.9633
//
// Ctrl+C で live/members を掃除して退出する。

const API_KEY = 'AIzaSyABBbUulD2cEbVT7cHfRCDLk_R5QBocxDA'; // android client key（機密ではない）
const DB = 'https://k-rootmap-default-rtdb.asia-southeast1.firebasedatabase.app';
const SERVER_TS = { '.sv': 'timestamp' };
const CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ'; // 0/O/1/I/L を除外（RoomCodeGeneratorと一致）

const args = process.argv.slice(2);
const mode = args[0];

function die(msg) {
  console.error('ERROR:', msg);
  process.exit(1);
}

async function anonSignIn() {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ returnSecureToken: true }),
    },
  );
  const json = await res.json();
  if (!res.ok) die(`匿名サインイン失敗: ${JSON.stringify(json)}`);
  return { idToken: json.idToken, uid: json.localId };
}

async function put(path, body, idToken) {
  const res = await fetch(`${DB}/${path}.json?auth=${idToken}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) die(`PUT ${path} 失敗 (${res.status}): ${text}`);
  return text;
}

async function del(path, idToken) {
  await fetch(`${DB}/${path}.json?auth=${idToken}`, { method: 'DELETE' });
}

async function get(path, idToken) {
  const res = await fetch(`${DB}/${path}.json?auth=${idToken}`);
  if (!res.ok) return null;
  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function randomCode(len = 8) {
  let s = '';
  for (let i = 0; i < len; i++) {
    s += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  }
  return s;
}

async function main() {
  const { idToken, uid } = await anonSignIn();
  console.log(`匿名サインインOK uid=${uid}`);

  let code;
  let name;
  let centerLat = 33.9312;
  let centerLng = 135.9633;
  let follow = false; // ホスト（ユーザー）の位置を毎tick読み直して中心にする
  let hostUid = null;

  if (mode === 'create') {
    name = args[1] || 'FakeHost';
    code = randomCode();
    // meta を先に書く（root は書き込み前状態のため members と分ける）。
    await put(
      `rooms/${code}/meta`,
      {
        hostUid: uid,
        active: true,
        createdAt: SERVER_TS,
        expiresAt: Date.now() + 24 * 3600 * 1000,
        name,
      },
      idToken,
    );
    await put(`rooms/${code}/members/${uid}`, { name, role: 'host' }, idToken);
    console.log(`ルーム作成: コード = ${code} （このコードで参加できます）`);
  } else if (mode === 'join') {
    code = args[1];
    if (!code) die('ルームコードを指定してください: join <CODE> [name] [lat] [lng]');
    code = code.toUpperCase();
    name = args[2] || 'FakeGuest';
    // join <CODE> <name> follow  … ホスト位置を追従して周回
    // join <CODE> <name> <lat> <lng> … 固定中心で周回
    if (args[3] === 'follow') {
      follow = true;
    } else {
      if (args[3]) centerLat = parseFloat(args[3]);
      if (args[4]) centerLng = parseFloat(args[4]);
    }
    await put(`rooms/${code}/members/${uid}`, { name, role: 'guest' }, idToken);
    console.log(`ルーム ${code} に参加: ${name}`);
    if (follow) {
      hostUid = await get(`rooms/${code}/meta/hostUid`, idToken);
      const hp = hostUid ? await get(`rooms/${code}/live/${hostUid}`, idToken) : null;
      if (hp && typeof hp.lat === 'number') {
        centerLat = hp.lat;
        centerLng = hp.lng;
      }
      console.log(`follow モード: host=${hostUid} の周りを周回`);
    }
  } else {
    die('mode は create か join。例: node tool/party_fake_peer.js join ABCD2345 Fake太郎');
  }

  // クリーンアップ
  let stopping = false;
  const cleanup = async () => {
    if (stopping) return;
    stopping = true;
    console.log('\n退出中（live/members を削除）...');
    await del(`rooms/${code}/live/${uid}`, idToken);
    await del(`rooms/${code}/members/${uid}`, idToken);
    console.log('退出しました。');
    process.exit(0);
  };
  process.on('SIGINT', cleanup);
  process.on('SIGTERM', cleanup);

  // 位置を publish するループ（中心の周りを円運動で周回）。
  let t = 0;
  let battery = 88;
  const R = follow ? 0.0005 : 0.0009; // 度。follow時は約55mで近くを周回。
  const tick = async () => {
    t++;
    // follow: 毎tickでホスト（ユーザー）の最新位置を読み直して中心にする。
    if (follow && hostUid) {
      const hp = await get(`rooms/${code}/live/${hostUid}`, idToken);
      if (hp && typeof hp.lat === 'number' && typeof hp.lng === 'number') {
        centerLat = hp.lat;
        centerLng = hp.lng;
      }
    }
    const lat = centerLat + R * Math.sin(t / 6);
    // 経度は緯度で縮むので cos(lat) で割って画面上で真円にする。
    const lng =
      centerLng + (R * Math.cos(t / 6)) / Math.cos((centerLat * Math.PI) / 180);
    const bearing = (t * 18) % 360;
    if (t % 20 === 0 && battery > 5) battery--;
    await put(
      `rooms/${code}/live/${uid}`,
      {
        lat,
        lng,
        speed: 1.3,
        bearing,
        battery,
        connected: true,
        ts: SERVER_TS,
      },
      idToken,
    );
    process.stdout.write(
      `\r[${t}] publish lat=${lat.toFixed(6)} lng=${lng.toFixed(6)} bearing=${bearing} batt=${battery}%   `,
    );
  };
  await tick();
  setInterval(tick, 3000);
  console.log('位置を3秒ごとに送信中。Ctrl+C で退出。');
}

main().catch((e) => die(e.stack || String(e)));
