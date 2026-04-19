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
// Root Maps: インライン編集ウィジェット
// GeoPackage名・レイヤ名のインライン編集用Widget
import 'package:flutter/material.dart';
import '../i18n/strings.g.dart';

/// GeoPackage名インライン編集用Widget
class InlineEditGpkgName extends StatefulWidget {
  final String initialName;
  final String dirPath;
  final void Function(String newName) onRename;
  final List<String> existingNames;
  const InlineEditGpkgName({
    required this.initialName,
    required this.dirPath,
    required this.onRename,
    required this.existingNames,
    super.key,
  });
  @override
  State<InlineEditGpkgName> createState() => _InlineEditGpkgNameState();
}

class _InlineEditGpkgNameState extends State<InlineEditGpkgName> {
  bool editing = false;
  late TextEditingController controller;
  String? errorText;
  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _submit() {
    final newName = controller.text.trim();
    if (newName.isEmpty) {
      setState(() => errorText = t.inlineEdit.emptyError);
      return;
    }
    if (newName != widget.initialName &&
        widget.existingNames.contains(newName)) {
      setState(() => errorText = t.inlineEdit.duplicateFile);
      return;
    }
    if (newName != widget.initialName) {
      widget.onRename(newName);
    }
    setState(() {
      editing = false;
      errorText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return editing
        ? SizedBox(
          width: 140,
          child: Focus(
            onFocusChange: (hasFocus) {
              if (!hasFocus) _submit();
            },
            child: TextField(
              controller: controller,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                isDense: true,
                errorText: errorText,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 8,
                ),
              ),
            ),
          ),
        )
        : GestureDetector(
          onTap:
              () => setState(() {
                editing = true;
              }),
          child: Text(
            widget.initialName,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        );
  }
}

/// レイヤ名インライン編集用Widget
class InlineEditLayerName extends StatefulWidget {
  final String initialName;
  final void Function(String newName) onRename;
  final List<String> existingNames;
  const InlineEditLayerName({
    required this.initialName,
    required this.onRename,
    required this.existingNames,
    super.key,
  });
  @override
  State<InlineEditLayerName> createState() => _InlineEditLayerNameState();
}

class _InlineEditLayerNameState extends State<InlineEditLayerName> {
  bool editing = false;
  late TextEditingController controller;
  String? errorText;
  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _submit() {
    final newName = controller.text.trim();
    if (newName.isEmpty) {
      setState(() => errorText = t.inlineEdit.emptyError);
      return;
    }
    if (newName != widget.initialName &&
        widget.existingNames.contains(newName)) {
      setState(() => errorText = t.inlineEdit.duplicateLayer);
      return;
    }
    if (newName != widget.initialName) {
      widget.onRename(newName);
    }
    setState(() {
      editing = false;
      errorText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return editing
        ? SizedBox(
          width: 120,
          child: Focus(
            onFocusChange: (hasFocus) {
              if (!hasFocus) _submit();
            },
            child: TextField(
              controller: controller,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                isDense: true,
                errorText: errorText,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 8,
                ),
              ),
            ),
          ),
        )
        : GestureDetector(
          onTap:
              () => setState(() {
                editing = true;
              }),
          child: Text(
            widget.initialName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
  }
}
