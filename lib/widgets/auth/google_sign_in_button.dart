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
/// Googleのサインインボタン。
///
/// native は普通のボタンで済むが、web は Google が描画したボタンでないと
/// サインインできない（`google_sign_in_web` の `authenticate()` は
/// `UnimplementedError`）。その差をここで吸収する。
library;

import 'package:flutter/widgets.dart';

import 'google_sign_in_button_io.dart'
    if (dart.library.js_interop) 'google_sign_in_button_web.dart' as impl;

/// Googleが描画するサインインボタン。native では null を返す。
///
/// web でも One Tap が通っていれば要らない。ユーザーが取れていないとき
/// （Googleに未ログイン、One Tapを閉じた等）の逃げ道として出す。
Widget? googleRenderedSignInButton() => impl.googleRenderedSignInButton();
