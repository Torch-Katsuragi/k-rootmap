// Copyright (C) 2024-2026 Torch-Katsuragi
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
/// パーティ位置共有: [PeerSource] の Firebase Realtime Database 実装
///
/// 1ルーム分の `/rooms/{roomCode}/live` と `/tracks` を担当する。
/// Android/iOS 限定（firebase_database は Windows 未対応）。
///
/// 接続検出は RTDB の `.info/connected` を権威とする。接続確立時に
/// onDisconnect を仕掛け、切断時に自分の `connected` を false へ自動更新する。
library;

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import '../../models/party/peer_position.dart';
import '../../utils/app_logger.dart';
import 'peer_source.dart';

/// RTDB を使うピア位置ソース
class RtdbPeerSource implements PeerSource {
  static const String _logTag = 'RtdbPeerSource';

  final FirebaseDatabase _db;

  /// 参加中のルームコード
  final String roomCode;

  /// 自分のuid（匿名認証）
  final String selfUid;

  RtdbPeerSource({
    required this.roomCode,
    required this.selfUid,
    FirebaseDatabase? database,
  }) : _db = database ?? FirebaseDatabase.instance;

  final StreamController<Map<String, PeerPosition>> _peersController =
      StreamController<Map<String, PeerPosition>>.broadcast();
  final StreamController<bool> _connectedController =
      StreamController<bool>.broadcast();

  StreamSubscription<DatabaseEvent>? _liveSub;
  StreamSubscription<DatabaseEvent>? _connectedSub;
  bool _started = false;

  DatabaseReference get _roomRef => _db.ref('rooms/$roomCode');
  DatabaseReference get _liveRef => _roomRef.child('live');
  DatabaseReference get _selfLiveRef => _liveRef.child(selfUid);
  DatabaseReference get _connectedRef => _db.ref('.info/connected');

  @override
  Stream<Map<String, PeerPosition>> get peers => _peersController.stream;

  @override
  Stream<bool> get serverConnected => _connectedController.stream;

  /// 購読開始
  void start() {
    if (_started) return;
    _started = true;

    // 全メンバーの現在位置（自分含む。自分の除外は PartyLocationStore 側）
    _liveSub = _liveRef.onValue.listen(
      (event) {
        final result = <String, PeerPosition>{};
        for (final child in event.snapshot.children) {
          final key = child.key;
          final val = child.value;
          if (key == null || val is! Map) continue;
          try {
            result[key] = PeerPosition.fromMap(key, val);
          } catch (e) {
            AppLogger.debug('$_logTag: live parse skip ($key): $e');
          }
        }
        _peersController.add(result);
      },
      onError: (Object e) => AppLogger.debug('$_logTag: live購読エラー: $e'),
    );

    // 実サーバー接続状態（.info/connected）
    _connectedSub = _connectedRef.onValue.listen((event) {
      final connected = event.snapshot.value == true;
      if (connected) {
        // 接続確立時にonDisconnectを仕掛ける（切断検知でconnected=false）。
        // 部分更新なので ts(=== now) 検証には触れない。
        _selfLiveRef.child('connected').onDisconnect().set(false);
      }
      _connectedController.add(connected);
    });
  }

  @override
  Future<void> publishPosition(PeerPosition position) async {
    final data = position.toLiveMap();
    data['ts'] = ServerValue.timestamp; // サーバー時刻を強制（ルール: ts === now）
    await _selfLiveRef.set(data);
  }

  @override
  Future<void> publishTrack({
    required String encodedPolyline,
    required int fromMs,
    required int toMs,
  }) async {
    await _roomRef.child('tracks/$selfUid').push().set({
      'pts': encodedPolyline,
      'from': fromMs,
      'to': toMs,
    });
  }

  @override
  Future<void> goOnline() async => _db.goOnline();

  @override
  Future<void> goOffline() async => _db.goOffline();

  @override
  Future<void> dispose() async {
    await _liveSub?.cancel();
    await _connectedSub?.cancel();
    await _peersController.close();
    await _connectedController.close();
  }
}
