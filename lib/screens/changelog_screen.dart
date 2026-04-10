/// チェンジログ表示画面
///
/// CHANGELOG.mdの内容をMarkdownとしてレンダリングする。
/// 画面表示時に既読マークを付ける。
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../i18n/strings.g.dart';
import '../services/changelog_service.dart';

/// チェンジログ表示画面
class ChangelogScreen extends StatefulWidget {
  /// 画面を閉じる際に呼ばれるコールバック（未読状態の更新通知用）
  final VoidCallback? onRead;

  const ChangelogScreen({super.key, this.onRead});

  @override
  State<ChangelogScreen> createState() => _ChangelogScreenState();
}

class _ChangelogScreenState extends State<ChangelogScreen> {
  String? _content;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final content = await ChangelogService.instance.loadChangelog();
    // 既読としてマーク
    await ChangelogService.instance.markAsRead();
    if (mounted) {
      setState(() {
        _content = content;
        _isLoading = false;
      });
      // 呼び出し元に既読通知
      widget.onRead?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t.changelog.title),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _content == null || _content!.isEmpty
              ? Center(
                  child: Text(
                    t.changelog.noContent,
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : Markdown(
                  data: _content!,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(
                    Theme.of(context),
                  ).copyWith(
                    // h1スタイル
                    h1: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    // h2スタイル（バージョン見出し）
                    h2: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                    // h3スタイル（カテゴリ見出し）
                    h3: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    // 水平線のスタイル
                    horizontalRuleDecoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                ),
    );
  }
}
