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
/// TruPulse キャリブレーション ガイド画面
///
/// デバイス本体で実行するキャリブレーション手順を
/// ステップバイステップで案内する（アプリからのコマンド送信なし）。
/// 手順は TruPulse 360R マニュアル Section 4 に基づく。
library;

import 'package:flutter/material.dart';
import 'trupulse_service.dart';

enum CalibrationType { tilt, compass }

class TruPulseCalibrationGuide extends StatefulWidget {
  final TruPulseService service;
  final CalibrationType type;

  const TruPulseCalibrationGuide({
    super.key,
    required this.service,
    required this.type,
  });

  @override
  State<TruPulseCalibrationGuide> createState() =>
      _TruPulseCalibrationGuideState();
}

class _TruPulseCalibrationGuideState extends State<TruPulseCalibrationGuide> {
  bool get _isTilt => widget.type == CalibrationType.tilt;
  int _currentStep = 0;

  List<_Step> get _steps => _isTilt ? _tiltSteps : _compassSteps;

  // ======== Tilt Cal: マニュアル p.24-26 ========

  static const _tiltSteps = [
    _Step(
      icon: Icons.settings,
      title: 'Enter Tilt Calibration mode',
      detail: 'On the device:\n'
          '1. Press-and-hold DOWN 4 sec → "UnitS" appears\n'
          '2. Press DOWN until "inC" appears\n'
          '3. Press FIRE → "no CAL" appears\n'
          '4. Press UP or DOWN → "YES CAL" appears\n'
          '5. Press FIRE → "C1_Fd" appears (calibration starts)',
    ),
    _Step(
      icon: Icons.phone_android,
      title: 'Place on a flat, level surface',
      detail: 'Put the TruPulse on a flat, stable surface '
          '(within 15° of level).\n'
          'Lenses facing forward. '
          'Make sure buttons are accessible for each position.',
    ),
    _Step(
      icon: Icons.looks_one,
      title: 'C1: Lenses FORWARD → FIRE',
      detail: 'Lenses face forward (away from you).\n'
          'Wait ~1 sec until steady, then press FIRE.\n'
          'LCD shows "C2_Fd".',
    ),
    _Step(
      icon: Icons.looks_two,
      title: 'C2: Lenses DOWN → FIRE',
      detail: 'Rotate 90° so lenses face DOWN.\n'
          'Wait ~1 sec, press FIRE.\n'
          'LCD shows "C3_Fd".',
    ),
    _Step(
      icon: Icons.looks_3,
      title: 'C3: Lenses BACK → FIRE  /  C4: Lenses UP → FIRE',
      detail: 'C3: Rotate 90° → lenses face BACK (toward you).\n'
          '⚠ 360R: Hang buttons over edge of surface.\n'
          'Wait ~1 sec, press FIRE (short press!).\n\n'
          'C4: Rotate 90° → lenses face UP.\n'
          'Wait ~1 sec, press FIRE. LCD shows "C5_Fd".',
    ),
    _Step(
      icon: Icons.looks_4,
      title: 'C5: Rotate along optical axis → Lenses FORWARD → FIRE',
      detail: 'Rotate 90° ALONG the optical axis (roll the device).\n'
          'Lenses should face forward again, but the device is now '
          'rotated 90° from Position 1.\n'
          'Wait ~1 sec, press FIRE. LCD shows "C6_Fd".',
    ),
    _Step(
      icon: Icons.looks_5,
      title: 'C6–C8: DOWN → BACK → UP → FIRE each',
      detail: 'Same rotation as C2–C4, but in the rolled orientation:\n\n'
          'C6: Rotate 90° → lenses DOWN → wait, FIRE.\n'
          'C7: Rotate 90° → lenses BACK → wait, FIRE.\n'
          'C8: Rotate 90° → lenses UP → FIRE.\n\n'
          'Device calculates result.',
    ),
    _Step(
      icon: Icons.check_circle_outline,
      title: 'Check the result',
      detail: 'PASS → Press FIRE to save and return.\n\n'
          'FAiL1: Excessive motion (not held steady)\n'
          'FAiL2: Magnetic saturation\n'
          'FAiL3: Mathematical fit error\n'
          'FAiL4: Convergence error\n'
          'FAiL6: Wrong orientations\n\n'
          'On FAIL → press FIRE, repeat from C1.\n'
          'Abort anytime: long-press UP or DOWN '
          '(previous calibration restored).',
    ),
  ];

  // ======== Compass Cal: マニュアル p.32-34 ========

  static const _compassSteps = [
    _Step(
      icon: Icons.warning_amber,
      title: 'Go outdoors, away from metal',
      detail: 'Compass calibration must be performed outdoors.\n'
          'Stand away from vehicles, fences, buildings,\n'
          'electronics, and any metal objects.\n\n'
          'Face towards Magnetic North (±15°).',
    ),
    _Step(
      icon: Icons.settings,
      title: 'Enter Compass Calibration mode',
      detail: 'On the device:\n'
          '1. Press-and-hold DOWN 4 sec → "UnitS" appears\n'
          '2. Press DOWN until "H_Ang" appears\n'
          '3. Press FIRE → "dECLn" appears\n'
          '4. Press DOWN → "HACAL" appears\n'
          '5. Press FIRE → "no CAL" appears\n'
          '6. Press UP or DOWN → "YES CAL" appears\n'
          '7. Press FIRE → "C1_Fd" appears (calibration starts)',
    ),
    _Step(
      icon: Icons.looks_one,
      title: 'C1: Facing North, lenses FORWARD → FIRE',
      detail: 'Hold the device facing North, lenses forward.\n'
          'Wait ~1 sec until steady, press FIRE.\n'
          'LCD shows "C2_Fd".',
    ),
    _Step(
      icon: Icons.looks_two,
      title: 'C2: Lenses DOWN → FIRE',
      detail: 'Rotate 90° so lenses face DOWN.\n'
          'Wait ~1 sec, press FIRE.\n'
          'LCD shows "C3_Fd".',
    ),
    _Step(
      icon: Icons.looks_3,
      title: 'C3: Lenses BACK → FIRE  /  C4: Lenses UP → FIRE',
      detail: 'C3: Rotate 90° → lenses face BACK (toward you).\n'
          'Wait ~1 sec, press FIRE.\n\n'
          'C4: Rotate 90° → lenses face UP.\n'
          'Wait ~1 sec, press FIRE. LCD shows "C5_Fd".',
    ),
    _Step(
      icon: Icons.looks_4,
      title: 'C5: Rotate along optical axis → Lenses FORWARD → FIRE',
      detail: 'Rotate 90° ALONG the optical axis (roll the device).\n'
          'Lenses forward again, serial port pointing UP.\n'
          'Wait ~1 sec, press FIRE. LCD shows "C6_Fd".',
    ),
    _Step(
      icon: Icons.looks_5,
      title: 'C6–C8: DOWN → BACK → UP → FIRE each',
      detail: 'Same rotation as C2–C4, in the rolled orientation:\n\n'
          'C6: Rotate 90° → lenses DOWN → wait, FIRE.\n'
          'C7: Rotate 90° → lenses BACK → wait, FIRE.\n'
          'C8: Rotate 90° → lenses UP → FIRE.\n\n'
          'Device calculates result.',
    ),
    _Step(
      icon: Icons.check_circle_outline,
      title: 'Check the result',
      detail: 'PASS → Press FIRE to save and return.\n\n'
          'FAiL1: Excessive motion (not held steady)\n'
          'FAiL2: Magnetic saturation (field too strong)\n'
          'FAiL3: Mathematical fit error\n'
          'FAiL4: Convergence error\n'
          'FAiL6: Wrong orientations\n\n'
          'On FAIL → press FIRE, repeat from C1.\n'
          'If it fails repeatedly, do Tilt Cal first.\n'
          'Abort anytime: long-press UP or DOWN '
          '(previous calibration restored).',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _isTilt ? 'Tilt Calibration' : 'Compass Calibration';
    final step = _steps[_currentStep];
    final isFirst = _currentStep == 0;
    final isLast = _currentStep == _steps.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_currentStep + 1) / _steps.length,
          ),
        ),
      ),
      body: Column(
        children: [
          // Step indicator
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    '${_currentStep + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Step ${_currentStep + 1} of ${_steps.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        step.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(step.icon, size: 32, color: theme.colorScheme.primary),
              ],
            ),
          ),

          const Divider(height: 1),

          // Step detail
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      step.detail,
                      style: const TextStyle(fontSize: 14, height: 1.6),
                    ),
                  ),
                  // Overview: all steps (mini list)
                  const SizedBox(height: 24),
                  Text(
                    'All Steps',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (int i = 0; i < _steps.length; i++)
                    _miniStepRow(i, theme),
                ],
              ),
            ),
          ),

          // Navigation
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (!isFirst)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => _currentStep--),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back'),
                    ),
                  ),
                if (!isFirst && !isLast) const SizedBox(width: 12),
                if (!isLast)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          setState(() => _currentStep++),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Next'),
                    ),
                  ),
                if (isLast)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.check),
                      label: const Text('Done'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStepRow(int index, ThemeData theme) {
    final isCurrent = index == _currentStep;
    final isPast = index < _currentStep;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: () => setState(() => _currentStep = index),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: isCurrent
                    ? theme.colorScheme.primary
                    : isPast
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isCurrent
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _steps[index].title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isCurrent ? FontWeight.w600 : null,
                    color: isCurrent
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (isPast)
                Icon(Icons.check, size: 16,
                    color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step {
  final IconData icon;
  final String title;
  final String detail;
  const _Step({required this.icon, required this.title, required this.detail});
}
