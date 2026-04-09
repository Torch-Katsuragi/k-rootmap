// K-MAPS: インライン編集ウィジェット
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
