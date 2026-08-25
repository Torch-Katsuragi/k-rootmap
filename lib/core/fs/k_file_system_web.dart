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
/// web の [KFileSystem] 実装。
///
/// > [!WARNING] まだ空っぽ（段2の前半）
/// > File System Access API を繋ぐのは段2の後半。今は「何も無いファイルシステム」
/// > として振る舞う。
/// >
/// > web はまだプロジェクトフォルダを開けない（`canOpenLocalProject` が false）ので、
/// > ツリー探索はパス解決の時点で null になり、ここまで到達しない。
/// > 到達しうる**問い合わせ系**（exists/list/length）は「無い」と答えて素通りさせ、
/// > **読み書き系**は黙って成功したふりをせず例外を投げる。
library;

import 'dart:typed_data';

import 'k_file_system.dart';

KFileSystem createKFileSystem() => const EmptyFileSystem();

class EmptyFileSystem implements KFileSystem {
  const EmptyFileSystem();

  @override
  bool get hasRealPaths => false;

  @override
  Future<bool> exists(String path) async => false;

  @override
  Future<bool> isDirectory(String path) async => false;

  @override
  Future<List<KFileEntry>> list(String path) async => const [];

  @override
  Future<int?> length(String path) async => null;

  Never _unsupported(String op) => throw UnsupportedError(
        'web ではまだ $op を実行できません（段2後半で File System Access API を繋ぐ）',
      );

  @override
  Future<Uint8List> readAsBytes(String path) async => _unsupported('readAsBytes');

  @override
  Future<String> readAsString(String path) async => _unsupported('readAsString');

  @override
  Future<void> writeAsBytes(String path, Uint8List bytes) async =>
      _unsupported('writeAsBytes');

  @override
  Future<void> writeAsString(String path, String contents) async =>
      _unsupported('writeAsString');

  @override
  Future<void> createDirectory(String path) async =>
      _unsupported('createDirectory');

  @override
  Future<void> delete(String path, {bool recursive = false}) async =>
      _unsupported('delete');

  @override
  Future<void> rename(String from, String to) async => _unsupported('rename');
}
