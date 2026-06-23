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
/// パーティ位置共有: ピア位置ソースの抽象インターフェイス
///
/// トランスポート非依存の境界。現状の実装は Firebase RTDB
/// （[RtdbPeerSource]）だが、将来 BLEメッシュ・衛星リンク等を
/// 別実装として差し込み、[PartyLocationStore] でマージできるよう
/// この interface に隔離している（`GpsManagerService` と同じマージ点パターン）。
library;

import '../../models/party/peer_position.dart';

/// ピア位置ソース
abstract class PeerSource {
  /// 他メンバーの最新位置（uid -> [PeerPosition]）のスナップショットを流す。
  ///
  /// 自分自身を含むか否かは実装依存。除外は [PartyLocationStore] 側で行う。
  Stream<Map<String, PeerPosition>> get peers;

  /// 実サーバーとの接続状態（RTDBの `.info/connected` 相当）。
  ///
  /// 「インターフェイスがある」ではなく「実際にサーバーと繋がっている」を表す。
  /// これが false→true に跳ねた瞬間が「復帰の瞬間」。
  Stream<bool> get serverConnected;

  /// 自分の位置を publish する（揮発・上書き）。
  ///
  /// サーバー時刻は実装側が付与する（[PeerPosition.serverTimeMs] は無視）。
  Future<void> publishPosition(PeerPosition position);

  /// 圏外区間の軌跡（gap backfill）を publish する。
  ///
  /// [encodedPolyline] は間引き済みのエンコード済みポリライン。
  Future<void> publishTrack({
    required String encodedPolyline,
    required int fromMs,
    required int toMs,
  });

  /// SDKをオンラインへ（`goOnline` 相当）。
  Future<void> goOnline();

  /// SDKをオフラインへ（`goOffline` 相当）。
  ///
  /// 圏外中の再接続リトライを止め、電池・電波を温存するために呼ぶ。
  Future<void> goOffline();

  /// リソース解放。
  Future<void> dispose();
}
