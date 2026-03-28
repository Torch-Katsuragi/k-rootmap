/// TruPulse測量ステータスパネル
///
/// 機器接続状態・計測値・Station情報を表示するパネル。
/// [TruPulseTool.buildStatusPanel] から返される。
library;

import 'package:flutter/material.dart';
import 'trupulse_detail_screen.dart';
import 'trupulse_tool.dart';

class TruPulseStatusPanel extends StatelessWidget {
  final TruPulseTool tool;

  const TruPulseStatusPanel({super.key, required this.tool});

  @override
  Widget build(BuildContext context) {
    final service = tool.service;
    final stn = tool.station;
    final lastM = service.lastMeasurement;

    return Positioned(
      right: 8,
      bottom: 8,
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TruPulseDetailScreen(service: tool.service),
          ),
        ),
        child: Card(
          elevation: 4,
          child: Container(
            width: 240,
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      Icons.explore,
                      size: 16,
                      color: service.isConnected ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      service.deviceTypeName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 8),

                // Station info
                _InfoRow(
                  label: 'STN',
                  value: stn != null
                      ? '${stn.name.isNotEmpty ? stn.name : "Point"} '
                          '(${stn.point.latitude.toStringAsFixed(5)}, '
                          '${stn.point.longitude.toStringAsFixed(5)})'
                      : 'Tap a point to set station',
                ),

                // Latest measurement
                if (lastM != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _MeasChip('HD', '${lastM.hd.toStringAsFixed(1)}m'),
                      _MeasChip('AZ', '${lastM.az.toStringAsFixed(1)}°'),
                      _MeasChip('INC', '${lastM.inc.toStringAsFixed(1)}°'),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MeasChip extends StatelessWidget {
  final String label;
  final String value;
  const _MeasChip(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
            Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
