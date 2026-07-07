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
/// パーティ位置共有: 地図画面のUI（入口ボタン・作成/参加ダイアログ・ステータス）
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/strings.g.dart';
import '../../../models/party/party_room.dart';
import '../../../providers/party_providers.dart';
import '../../../services/party/party_connection_monitor.dart';

/// 接続状態の表示ラベル
String partyConnectionLabel(PartyConnectionState s) {
  switch (s) {
    case PartyConnectionState.online:
      return t.party.connSharing;
    case PartyConnectionState.connecting:
      return t.party.connConnecting;
    case PartyConnectionState.offline:
      return t.party.connOffline;
  }
}

Color partyConnectionColor(PartyConnectionState s) {
  switch (s) {
    case PartyConnectionState.online:
      return Colors.green;
    case PartyConnectionState.connecting:
      return Colors.orange;
    case PartyConnectionState.offline:
      return Colors.grey;
  }
}

/// パーティ機能の入口。参加中はステータスシート、未参加は作成/参加ダイアログを開く。
///
/// AppBarメニュー・FABなど、どこからでも同じ導線を開くための共通エントリ。
void showPartyEntry(BuildContext context, WidgetRef ref) {
  if (ref.read(partySessionProvider).active) {
    _showStatusSheet(context, ref);
  } else {
    _showJoinCreateDialog(context, ref);
  }
}

/// パーティ（位置共有）入口ボタン（現在は統合テスト用途。本番導線はAppBarメニュー）
class PartyButton extends ConsumerWidget {
  const PartyButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(partySessionProvider);
    final active = session.active;
    final color = active
        ? partyConnectionColor(session.connection)
        : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => active
            ? _showStatusSheet(context, ref)
            : _showJoinCreateDialog(context, ref),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: active ? Colors.white : Colors.grey.shade300,
              width: 2,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                active ? Icons.groups : Icons.groups_outlined,
                color: active ? Colors.white : Colors.blueGrey,
                size: 28,
              ),
              // 参加人数バッジ（自分を除くpeers数）
              if (active && session.peers.isNotEmpty)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '${session.peers.length}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 作成/参加ダイアログ
Future<void> _showJoinCreateDialog(BuildContext context, WidgetRef ref) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _PartyJoinCreateDialog(),
  );
}

class _PartyJoinCreateDialog extends ConsumerStatefulWidget {
  const _PartyJoinCreateDialog();
  @override
  ConsumerState<_PartyJoinCreateDialog> createState() =>
      _PartyJoinCreateDialogState();
}

class _PartyJoinCreateDialogState
    extends ConsumerState<_PartyJoinCreateDialog> {
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(partySessionProvider);
    // 参加成立の「瞬間」だけダイアログを閉じる。
    // active中は members/connection ストリームが更新を流し続けるため、
    // 遷移(false→true)でガードしないと maybePop が連発し、地図ページまで
    // pop してしまう（＝作成後にホーム画面へ戻る不具合）。
    ref.listen(partySessionProvider, (prev, next) {
      final becameActive = next.active && !(prev?.active ?? false);
      if (becameActive && mounted) Navigator.of(context).maybePop();
    });

    return AlertDialog(
      title: Text(t.party.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameCtrl,
            maxLength: 40,
            decoration: InputDecoration(
              labelText: t.party.displayName,
              hintText: t.party.displayNameHint,
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          Text(t.party.joinPrompt, style: const TextStyle(fontSize: 12)),
          TextField(
            controller: _codeCtrl,
            maxLength: 8,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: t.party.roomCodeLabel,
              hintText: t.party.roomCodeHint,
            ),
          ),
          if (session.error != null) ...[
            const SizedBox(height: 8),
            Text(session.error!, style: const TextStyle(color: Colors.red)),
          ],
          if (session.busy) ...[
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: session.busy ? null : () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
        TextButton(
          onPressed: session.busy
              ? null
              : () => ref
                  .read(partySessionProvider.notifier)
                  .joinRoom(code: _codeCtrl.text, name: _nameCtrl.text),
          child: Text(t.party.join),
        ),
        FilledButton(
          onPressed: session.busy
              ? null
              : () => ref
                  .read(partySessionProvider.notifier)
                  .createRoom(name: _nameCtrl.text),
          child: Text(t.party.createHost),
        ),
      ],
    );
  }
}

/// メンバーのバッテリー残量バッジ
class _BatteryBadge extends StatelessWidget {
  final int percent;
  const _BatteryBadge({required this.percent});

  @override
  Widget build(BuildContext context) {
    final low = percent <= 20;
    final color = low ? Colors.red : Colors.grey.shade600;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          low ? Icons.battery_alert : Icons.battery_full,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 2),
        Text('$percent%', style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

/// 参加中のステータスシート
Future<void> _showStatusSheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (_) => const _PartyStatusSheet(),
  );
}

class _PartyStatusSheet extends ConsumerWidget {
  const _PartyStatusSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(partySessionProvider);
    // 退出の「瞬間」(true→false)だけシートを閉じる。遷移でガードしないと
    // maybePop が連発して背後の地図ページまで pop する恐れがある。
    ref.listen(partySessionProvider, (prev, next) {
      final becameInactive = !next.active && (prev?.active ?? true);
      if (becameInactive) Navigator.of(context).maybePop();
    });

    if (!session.active) return const SizedBox.shrink();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(t.party.roomCode,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Chip(
                  backgroundColor:
                      partyConnectionColor(session.connection).withValues(alpha: 0.15),
                  label: Text(partyConnectionLabel(session.connection)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                SelectableText(
                  session.roomCode ?? '',
                  style: const TextStyle(
                      fontSize: 28, letterSpacing: 4, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: t.party.copy,
                  onPressed: () => Clipboard.setData(
                      ClipboardData(text: session.roomCode ?? '')),
                ),
              ],
            ),
            const Divider(),
            // ゴーストモード: 自分の位置を一時的に隠す
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                session.ghost ? Icons.visibility_off : Icons.visibility,
                color: session.ghost ? Colors.deepPurple : null,
              ),
              title: Text(t.party.ghostMode),
              subtitle: Text(
                session.ghost ? t.party.ghostOn : t.party.ghostOff,
                style: const TextStyle(fontSize: 12),
              ),
              value: session.ghost,
              onChanged: (v) =>
                  ref.read(partySessionProvider.notifier).setGhost(v),
            ),
            const Divider(),
            Text(t.party.members(count: session.members.length),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            ...session.members.map((m) {
              final battery = session.peers[m.uid]?.battery;
              return ListTile(
                dense: true,
                leading: Icon(
                  m.role == PartyRole.host ? Icons.star : Icons.person,
                  color: m.role == PartyRole.host ? Colors.amber : null,
                ),
                title: Text(m.name),
                trailing: battery == null
                    ? null
                    : _BatteryBadge(percent: battery),
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                icon: const Icon(Icons.logout),
                label: Text(session.role == PartyRole.host
                    ? t.party.endHost
                    : t.party.leave),
                onPressed: () =>
                    ref.read(partySessionProvider.notifier).leave(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
