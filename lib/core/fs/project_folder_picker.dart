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
/// プロジェクトフォルダの選択。
///
/// native は OS のフォルダピッカー、web は File System Access API と、
/// 中身は別物だが呼び出し側からは同じ「フォルダを選ばせてパスを得る」に見せる。
library;

import 'project_folder_picker_io.dart'
    if (dart.library.js_interop) 'project_folder_picker_web.dart' as impl;

/// このプラットフォーム／ブラウザでフォルダを選べるか。
///
/// ⚠ web は Chrome / Edge のみ true（Firefox / Safari には
/// `showDirectoryPicker` が無い）。false のときは選択UIを出さないこと。
bool get canPickProjectFolder => impl.canPickProjectFolder;

/// フォルダを選ばせ、そのパスを返す。キャンセル・非対応なら null。
///
/// web が返すのはOSのパスではなく、`WebFileSystem` が解決できる**仮想パス**。
Future<String?> pickProjectFolder() => impl.pickProjectFolder();
