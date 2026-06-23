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
/// パーティ位置共有: connectivity_plus → インターフェイス有無ブールへの変換
///
/// [PartyConnectionMonitor.hasInterface] へ渡す `Stream<bool>` を供給する。
/// 「インターフェイスがある」だけでパケットが流れる保証は無い（特に山中）。
/// 真の接続判定は `.info/connected`（[PeerSource.serverConnected]）が担い、
/// こちらは goOffline/goOnline を切り替える安価なトリガーとして使う。
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// connectivity_plus の結果リストから「インターフェイス有無」を判定する純関数。
///
/// [ConnectivityResult.none] のみ、または空なら false。
bool hasInterfaceFrom(List<ConnectivityResult> results) {
  if (results.isEmpty) return false;
  return results.any((r) => r != ConnectivityResult.none);
}

/// connectivity_plus を `Stream<bool>` にラップするアダプタ
class ConnectivityInterfaceMonitor {
  final Connectivity _connectivity;

  ConnectivityInterfaceMonitor([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  /// インターフェイス有無のストリーム（初期値も即時に流す）
  Stream<bool> get hasInterface async* {
    yield hasInterfaceFrom(await _connectivity.checkConnectivity());
    yield* _connectivity.onConnectivityChanged.map(hasInterfaceFrom);
  }
}
