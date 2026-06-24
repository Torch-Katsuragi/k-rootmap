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
/// パーティ位置共有: セッション状態プロバイダ
///
/// コア層（[RtdbRoomRepository] / [RtdbPeerSource] / [PartyConnectionMonitor] /
/// [PartyLocationStore] / [ConnectivityInterfaceMonitor]）と内蔵GPS
/// （[InternalGpsLocationStore]）を束ね、ルーム作成/参加/退出と、
/// peers・接続状態・メンバーをUIへ公開する。
///
/// Android/iOS 限定（Firebase未初期化のWindowsでは createRoom/joinRoom が
/// 例外になり、UIはエラー表示する）。手書き NotifierProvider（コア層を
/// 直接保持するため codegen ではなくこちらを採用）。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/party/party_room.dart';
import '../models/party/peer_position.dart';
import '../services/internal_gps_location_store.dart';
import '../services/party/connectivity_interface_monitor.dart';
import '../services/party/party_connection_monitor.dart';
import '../services/party/party_location_store.dart';
import '../services/party/rtdb_peer_source.dart';
import '../services/party/rtdb_room_repository.dart';

/// パーティセッションの状態スナップショット
class PartySessionState {
  /// 参加中のルームコード（null = 未参加）
  final String? roomCode;

  /// 自分の役割
  final PartyRole? role;

  /// 接続状態
  final PartyConnectionState connection;

  /// 他メンバーの最新位置（自分を除く）
  final Map<String, PeerPosition> peers;

  /// メンバー一覧
  final List<PartyMember> members;

  /// 処理中（作成/参加の最中）
  final bool busy;

  /// 直近のエラーメッセージ
  final String? error;

  const PartySessionState({
    this.roomCode,
    this.role,
    this.connection = PartyConnectionState.offline,
    this.peers = const {},
    this.members = const [],
    this.busy = false,
    this.error,
  });

  /// 参加中か
  bool get active => roomCode != null;

  PartySessionState copyWith({
    String? roomCode,
    PartyRole? role,
    PartyConnectionState? connection,
    Map<String, PeerPosition>? peers,
    List<PartyMember>? members,
    bool? busy,
    String? error,
    bool clearError = false,
  }) {
    return PartySessionState(
      roomCode: roomCode ?? this.roomCode,
      role: role ?? this.role,
      connection: connection ?? this.connection,
      peers: peers ?? this.peers,
      members: members ?? this.members,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// パーティセッション
final partySessionProvider =
    NotifierProvider<PartySession, PartySessionState>(PartySession.new);

/// パーティセッションの司令塔
class PartySession extends Notifier<PartySessionState> {
  RtdbRoomRepository? _repo;
  RtdbPeerSource? _source;
  PartyConnectionMonitor? _monitor;
  PartyLocationStore? _store;
  StreamSubscription<Map<String, PeerPosition>>? _peersSub;
  StreamSubscription<PartyConnectionState>? _connSub;
  StreamSubscription<List<PartyMember>>? _membersSub;

  @override
  PartySessionState build() {
    ref.onDispose(_teardown);
    return const PartySessionState();
  }

  RtdbRoomRepository get _repository => _repo ??= RtdbRoomRepository();

  /// ルームを作成（host）
  Future<void> createRoom({String? name}) async {
    if (state.busy || state.active) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final meta = await _repository.createRoom(name: name);
      await _activate(meta.roomCode, PartyRole.host);
    } catch (e) {
      state = state.copyWith(busy: false, error: '$e');
    }
  }

  /// ルームに参加（guest）
  Future<void> joinRoom({required String code, required String name}) async {
    if (state.busy || state.active) return;
    final normalized = code.trim().toUpperCase();
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _repository.joinRoom(code: normalized, name: name);
      await _activate(normalized, PartyRole.guest);
    } catch (e) {
      state = state.copyWith(busy: false, error: '$e');
    }
  }

  /// 参加成立後のストリーム配線
  Future<void> _activate(String code, PartyRole role) async {
    final uid = _repository.currentUid;
    if (uid == null) {
      state = state.copyWith(busy: false, error: 'サインインが確認できません');
      return;
    }

    final source = RtdbPeerSource(roomCode: code, selfUid: uid)..start();
    final connMonitor = ConnectivityInterfaceMonitor();
    final monitor = PartyConnectionMonitor(
      hasInterface: connMonitor.hasInterface,
      serverConnected: source.serverConnected,
      requestOnline: source.goOnline,
      requestOffline: source.goOffline,
    );
    final store = PartyLocationStore(
      peerSource: source,
      monitor: monitor,
      ownPositions: InternalGpsLocationStore().positionStream,
      selfUid: uid,
    )..start();

    _source = source;
    _monitor = monitor;
    _store = store;

    _peersSub = store.peersStream
        .listen((peers) => state = state.copyWith(peers: peers));
    _connSub = monitor.stateStream
        .listen((c) => state = state.copyWith(connection: c));
    _membersSub = _repository
        .watchMembers(code)
        .listen((m) => state = state.copyWith(members: m));

    state = state.copyWith(
      roomCode: code,
      role: role,
      busy: false,
      connection: monitor.state,
      clearError: true,
    );
  }

  /// 退出（host の場合はルームを終了）
  Future<void> leave() async {
    final code = state.roomCode;
    final wasHost = state.role == PartyRole.host;
    await _teardown();
    if (code != null) {
      try {
        await _repository.leaveRoom(code); // active===true のうちに自己削除
        if (wasHost) await _repository.endRoom(code);
      } catch (_) {
        // 退出時のエラーは致命的でないため握りつぶす
      }
    }
    state = const PartySessionState();
  }

  Future<void> _teardown() async {
    await _peersSub?.cancel();
    await _connSub?.cancel();
    await _membersSub?.cancel();
    await _store?.dispose();
    await _monitor?.dispose();
    await _source?.dispose();
    _peersSub = null;
    _connSub = null;
    _membersSub = null;
    _store = null;
    _monitor = null;
    _source = null;
  }
}
