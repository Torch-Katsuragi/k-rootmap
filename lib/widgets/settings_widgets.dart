/// 設定画面用の共通ウィジェットテンプレート
///
/// 設定画面のUIを統一するための再利用可能なコンポーネント群。
/// 背景地図設定画面のスタイルをベースとしています。
library;

import 'package:flutter/material.dart';

/// 設定セクション（カード形式）
///
/// 設定項目をグループ化するためのカードコンポーネント。
/// [title] と [children] を指定してセクションを構成します。
///
/// スクロール負担を下げるため、[collapsible] を true にすると
/// セクションを折りたたみ（タップで展開）できるようになります。
class SettingsSection extends StatefulWidget {
  final String title;
  final List<Widget> children;
  final IconData? icon;
  final Color? iconColor;
  final Color? backgroundColor;
  final double elevation;
  final Widget? trailing;
  final bool collapsible;
  final bool initiallyExpanded;

  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.iconColor,
    this.backgroundColor,
    this.elevation = 1.0,
    this.trailing,
    this.collapsible = false,
    this.initiallyExpanded = true,
  });

  @override
  State<SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<SettingsSection>
    with SingleTickerProviderStateMixin {
  late bool _expanded = widget.initiallyExpanded;

  void _toggleExpanded() {
    if (!widget.collapsible) return;
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: widget.elevation,
      color: widget.backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // セクションヘッダー
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.collapsible ? _toggleExpanded : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    if (widget.icon != null) ...[
                      Icon(
                        widget.icon,
                        color: widget.iconColor ?? Colors.blue,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (widget.trailing != null) ...[
                      widget.trailing!,
                      const SizedBox(width: 8),
                    ],
                    if (widget.collapsible)
                      AnimatedRotation(
                        duration: const Duration(milliseconds: 150),
                        turns: _expanded ? 0.5 : 0.0,
                        child: const Icon(Icons.expand_more),
                      ),
                  ],
                ),
              ),
            ),
            if (!widget.collapsible || _expanded) ...[
              const SizedBox(height: 12),
              ...widget.children,
            ],
          ],
        ),
      ),
    );
  }
}

/// 強調表示セクション
///
/// 重要な機能や操作を目立たせるためのセクション。
/// 背景色付きで視覚的に区別されます。
class SettingsHighlightSection extends StatelessWidget {
  final String title;
  final String? description;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Widget actionButton;

  const SettingsHighlightSection({
    super.key,
    required this.title,
    this.description,
    required this.icon,
    this.iconColor = Colors.blue,
    required this.backgroundColor,
    required this.actionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(description!, style: const TextStyle(fontSize: 14)),
            ],
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: actionButton),
          ],
        ),
      ),
    );
  }
}

/// 設定タイル（基本）
///
/// アイコン、タイトル、サブタイトルを持つ基本的な設定項目。
class SettingsTile extends StatelessWidget {
  final IconData? leadingIcon;
  final Color? leadingIconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  const SettingsTile({
    super.key,
    this.leadingIcon,
    this.leadingIconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leadingIcon != null
          ? Icon(
              leadingIcon,
              color: enabled ? (leadingIconColor ?? Colors.blue) : Colors.grey,
            )
          : null,
      title: Text(
        title,
        style: TextStyle(color: enabled ? null : Colors.grey),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(color: enabled ? null : Colors.grey),
            )
          : null,
      trailing: trailing,
      onTap: enabled ? onTap : null,
      enabled: enabled,
    );
  }
}

/// スイッチ付き設定タイル
///
/// ON/OFF の切り替えを行う設定項目。
class SettingsSwitchTile extends StatelessWidget {
  final IconData? leadingIcon;
  final Color? activeIconColor;
  final Color? inactiveIconColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  const SettingsSwitchTile({
    super.key,
    this.leadingIcon,
    this.activeIconColor,
    this.inactiveIconColor,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: leadingIcon != null
          ? Icon(
              leadingIcon,
              color: value
                  ? (activeIconColor ?? Colors.green)
                  : (inactiveIconColor ?? Colors.grey),
            )
          : null,
      title: Text(
        title,
        style: TextStyle(color: enabled ? null : Colors.grey),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(color: enabled ? null : Colors.grey),
            )
          : null,
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

/// 選択可能な設定タイル
///
/// 複数の選択肢から1つを選ぶ設定項目。
class SettingsSelectionTile extends StatelessWidget {
  final IconData? leadingIcon;
  final Color? leadingIconColor;
  final String title;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback? onTap;

  const SettingsSelectionTile({
    super.key,
    this.leadingIcon,
    this.leadingIconColor,
    required this.title,
    this.subtitle,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leadingIcon != null
          ? Icon(
              leadingIcon,
              color: isSelected ? (leadingIconColor ?? Colors.blue) : Colors.grey,
            )
          : null,
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Colors.blue)
          : null,
      onTap: onTap,
    );
  }
}

/// アクションボタン付き設定タイル
///
/// 右側にボタンを配置した設定項目。
class SettingsActionTile extends StatelessWidget {
  final IconData? leadingIcon;
  final Color? leadingIconColor;
  final String title;
  final String? subtitle;
  final String buttonLabel;
  final Color? buttonColor;
  final VoidCallback? onPressed;
  final bool enabled;

  const SettingsActionTile({
    super.key,
    this.leadingIcon,
    this.leadingIconColor,
    required this.title,
    this.subtitle,
    required this.buttonLabel,
    this.buttonColor,
    this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leadingIcon != null
          ? Icon(
              leadingIcon,
              color: enabled ? (leadingIconColor ?? Colors.blue) : Colors.grey,
            )
          : null,
      title: Text(
        title,
        style: TextStyle(color: enabled ? null : Colors.grey),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(color: enabled ? null : Colors.grey),
            )
          : null,
      trailing: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor ?? Colors.blue,
          foregroundColor: Colors.white,
        ),
        child: Text(buttonLabel),
      ),
    );
  }
}

/// 情報表示行
///
/// ラベルと値のペアを表示するシンプルな行。
class SettingsInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final FontWeight? valueFontWeight;

  const SettingsInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.valueFontWeight,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: valueFontWeight ?? FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// エラー表示カード
///
/// エラーメッセージを目立つ形で表示。
class SettingsErrorCard extends StatelessWidget {
  final String message;

  const SettingsErrorCard({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 設定画面の共通Scaffold
///
/// 統一されたAppBarスタイルを提供。
class SettingsScaffold extends StatelessWidget {
  final String title;
  final bool isEmbedded;
  final List<Widget>? actions;
  final Widget body;
  final bool isLoading;

  const SettingsScaffold({
    super.key,
    required this.title,
    this.isEmbedded = false,
    this.actions,
    required this.body,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: !isEmbedded,
        actions: actions,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : body,
    );
  }
}

/// 設定画面の共通ボディ
///
/// スクロール可能なパディング付きコンテンツ。
class SettingsBody extends StatelessWidget {
  final List<Widget> sections;
  final double spacing;

  const SettingsBody({
    super.key,
    required this.sections,
    this.spacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < sections.length; i++) ...[
            sections[i],
            if (i < sections.length - 1) SizedBox(height: spacing),
          ],
        ],
      ),
    );
  }
}

