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
/// ファイルシステム抽象。
///
/// `dart:io` の `File` / `Directory` を直に触る代わりに、ここを通す。
/// web は `dart:io` を呼んだ瞬間に落ちるため、実装をプラットフォームごとに
/// 差し替えられるようにする（[[docs/technical/project-format-design]] 段2）。
///
/// > [!IMPORTANT] 同期APIは**意図的に生やさない**
/// > web の File System Access API に同期版は無い。`existsSync()` に相当するものが
/// > そもそも存在しないので、ここに同期メソッドを1つでも足すと web で実装できなくなる。
/// > 呼び出し側が `async` に変わるのは、この制約を受け入れた結果であって手抜きではない。
///
/// > [!NOTE] アドレスは今までどおり「パス文字列」
/// > web にファイルパスという概念は無く、あるのはディレクトリハンドルだけ。
/// > それでもこの抽象がパス文字列を受けるのは、`PathResolver` から
/// > `LayerTreeNode` まで既存の設計が全てパスで組まれているため。
/// > web実装側が「ルートハンドル + 相対パス」を解決して辻褄を合わせる。
library;

import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'k_file_system_io.dart'
    if (dart.library.js_interop) 'k_file_system_web.dart' as impl;

/// ディレクトリ列挙の1件
class KFileEntry {
  const KFileEntry({required this.path, required this.isDirectory});

  /// 絶対パス（web では仮想ルートからのパス）
  final String path;

  final bool isDirectory;

  String get name => p.basename(path);

  @override
  String toString() =>
      'KFileEntry($path, ${isDirectory ? "dir" : "file"})';
}

/// ファイルシステムの実体。プラットフォームごとに実装が差し替わる。
abstract class KFileSystem {
  /// ファイル・ディレクトリを問わず存在するか
  Future<bool> exists(String path);

  /// ディレクトリとして存在するか
  Future<bool> isDirectory(String path);

  /// 直下の要素を列挙する。存在しなければ空リスト
  Future<List<KFileEntry>> list(String path);

  Future<Uint8List> readAsBytes(String path);

  Future<String> readAsString(String path);

  Future<void> writeAsBytes(String path, Uint8List bytes);

  Future<void> writeAsString(String path, String contents);

  /// ディレクトリを作る（親が無ければ再帰的に作る／既にあれば何もしない）
  Future<void> createDirectory(String path);

  Future<void> delete(String path, {bool recursive = false});

  Future<void> rename(String from, String to);

  /// バイト長。存在しなければ null
  Future<int?> length(String path);

  /// ローカルの実ファイルとして扱えるか。
  ///
  /// ⚠ web は false。`sqflite` や外部プロセスに**パスを渡して開かせる**類の処理は
  /// この抽象では肩代わりできないので、呼ぶ前にここで弾く。
  bool get hasRealPaths;
}

KFileSystem? _override;
KFileSystem? _instance;

/// 現在のファイルシステム。
KFileSystem get fs => _override ?? (_instance ??= impl.createKFileSystem());

/// テスト用に差し替える。[reset] で戻す。
void setFileSystemOverrideForTest(KFileSystem? value) => _override = value;
