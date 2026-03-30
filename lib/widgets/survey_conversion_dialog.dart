/// 測量ポイント→ライン/ポリゴン変換ダイアログ
///
/// survey_stn チェーンを解決し、補正オプション（偏角・閉合補正・高さ）を
/// 選択したうえでライン/ポリゴンに変換する。
library;

import 'package:flutter/material.dart';
import '../models/nodes/layer_node.dart';
import '../presentation/node_presenter.dart';
import '../services/survey/survey_chain_resolver.dart';
import '../services/survey/traverse_adjuster.dart';
import '../utils/wmm_declination.dart';

/// ダイアログの戻り値
class SurveyConversionResult {
  final LayerNode targetLayer;
  final TraverseChain chain;
  final TraverseAdjustmentOptions options;
  final String? featureName;

  /// 閉合トラバースとして処理するか（起点に接続して閉合差を補正）
  final bool closePath;

  const SurveyConversionResult({
    required this.targetLayer,
    required this.chain,
    required this.options,
    this.featureName,
    this.closePath = false,
  });
}

class SurveyConversionDialog extends StatefulWidget {
  final PointLayerNode sourceLayer;
  final List<TraverseChain> chains;
  final List<LayerNode> availableLayers;

  const SurveyConversionDialog({
    super.key,
    required this.sourceLayer,
    required this.chains,
    required this.availableLayers,
  });

  @override
  State<SurveyConversionDialog> createState() => _SurveyConversionDialogState();
}

class _SurveyConversionDialogState extends State<SurveyConversionDialog> {
  late TraverseChain _selectedChain;
  late LayerNode _selectedLayer;
  bool _closePath = false;
  AdjustmentMethod _method = AdjustmentMethod.none;
  bool _useDeclination = true;
  bool _useHeightCorrection = false;
  final _declinationCtrl = TextEditingController(text: '0.0');
  final _instrumentHeightCtrl = TextEditingController(text: '0.0');
  final _targetHeightCtrl = TextEditingController(text: '0.0');
  final _nameCtrl = TextEditingController();

  /// OFFなら必ず0 -- テキストフィールドの値は無視する
  double get _declination =>
      _useDeclination ? (double.tryParse(_declinationCtrl.text) ?? 0) : 0;

  @override
  void initState() {
    super.initState();
    _selectedChain = widget.chains.first;
    _selectedLayer = widget.availableLayers.first;
    _nameCtrl.text = widget.sourceLayer.name;
    _updateDeclinationFromChain(_selectedChain);
  }

  void _updateDeclinationFromChain(TraverseChain chain) {
    final origin = chain.origin.point;
    final dec = WmmDeclination.calculate(origin.latitude, origin.longitude);
    _declinationCtrl.text = dec.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _declinationCtrl.dispose();
    _instrumentHeightCtrl.dispose();
    _targetHeightCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  String _layerTypeLabel(LayerNode layer) {
    if (layer is LineLayerNode) return 'ライン';
    if (layer is PolygonLayerNode) return 'ポリゴン';
    return '不明';
  }

  @override
  Widget build(BuildContext context) {
    final preview = TraverseAdjuster.previewClosure(
      _selectedChain,
      declination: _declination,
    );
    final typeLabel = _layerTypeLabel(_selectedLayer);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.straighten, color: Colors.blue),
          SizedBox(width: 8),
          Text('測量データ変換'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // チェーン選択（複数チェーンがある場合）
              if (widget.chains.length > 1) ...[
                const _SectionHeader('測量チェーン'),
                DropdownButtonFormField<TraverseChain>(
                  value: _selectedChain,
                  items: widget.chains.asMap().entries.map((e) {
                    final c = e.value;
                    return DropdownMenuItem(
                      value: c,
                      child: Text('チェーン ${e.key + 1} (${c.length}点, ${c.totalDistance.toStringAsFixed(1)}m)'),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _selectedChain = v);
                      _updateDeclinationFromChain(v);
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],

              // チェーン情報
              _ClosureInfoCard(
                chain: _selectedChain,
                closureError: preview.error,
                totalDistance: preview.distance,
                closureRatioN: preview.ratioN,
              ),
              const SizedBox(height: 16),

              // 変換先レイヤー
              const _SectionHeader('変換先レイヤー'),
              _LayerDropdown(
                layers: widget.availableLayers,
                selected: _selectedLayer,
                onChanged: (v) => setState(() => _selectedLayer = v),
                labelBuilder: _layerTypeLabel,
              ),
              const SizedBox(height: 12),

              // フィーチャ名
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'フィーチャ名（任意）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),

              // 閉合オプション
              SwitchListTile(
                title: const Text('閉合トラバース（起点に接続）'),
                subtitle: const Text(
                  'ONにすると閉合差を計算し、補正を適用できます',
                  style: TextStyle(fontSize: 11),
                ),
                value: _closePath,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() {
                  _closePath = v;
                  _method = v ? AdjustmentMethod.bowditch : AdjustmentMethod.none;
                }),
              ),

              // 閉合補正方式（閉合ON時のみ: Bowditch / Transit の2択）
              if (_closePath) ...[
                const _SectionHeader('閉合補正'),
                ...[AdjustmentMethod.bowditch, AdjustmentMethod.transit]
                    .map((m) => RadioListTile<AdjustmentMethod>(
                          title: Text(_methodLabel(m)),
                          subtitle: Text(_methodDescription(m), style: const TextStyle(fontSize: 11)),
                          value: m,
                          groupValue: _method,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) {
                            if (v != null) setState(() => _method = v);
                          },
                        )),
              ],
              const SizedBox(height: 12),

              // 磁気偏角トグル
              SwitchListTile(
                title: const Text('磁気偏角補正'),
                subtitle: const Text(
                  'TruPulse本体で偏角を設定済みの場合はOFFにしてください',
                  style: TextStyle(fontSize: 11),
                ),
                value: _useDeclination,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _useDeclination = v),
              ),
              if (_useDeclination) ...[
                Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _declinationCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: const InputDecoration(
                          suffixText: '\u00b0',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'WMM2025から自動算出。東偏: +, 西偏: -',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),

              // 器械高・目標高トグル
              SwitchListTile(
                title: const Text('高さ補正（器械高・目標高）'),
                subtitle: const Text(
                  '三脚・ターゲットポール使用時に設定',
                  style: TextStyle(fontSize: 11),
                ),
                value: _useHeightCorrection,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _useHeightCorrection = v),
              ),
              if (_useHeightCorrection)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _instrumentHeightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: '器械高 (m)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _targetHeightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: '目標高 (m)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            Navigator.pop(
              context,
              SurveyConversionResult(
                targetLayer: _selectedLayer,
                chain: _selectedChain,
                options: TraverseAdjustmentOptions(
                  method: _closePath ? _method : AdjustmentMethod.none,
                  declination: _useDeclination
                      ? (double.tryParse(_declinationCtrl.text) ?? 0)
                      : 0,
                  instrumentHeight: _useHeightCorrection
                      ? (double.tryParse(_instrumentHeightCtrl.text) ?? 0)
                      : 0,
                  targetHeight: _useHeightCorrection
                      ? (double.tryParse(_targetHeightCtrl.text) ?? 0)
                      : 0,
                ),
                featureName: name.isNotEmpty ? name : null,
                closePath: _closePath,
              ),
            );
          },
          icon: Icon(_selectedLayer is PolygonLayerNode ? Icons.pentagon_outlined : Icons.show_chart),
          label: Text('$typeLabel に変換'),
        ),
      ],
    );
  }

  String _methodLabel(AdjustmentMethod m) => switch (m) {
        AdjustmentMethod.none => '補正なし',
        AdjustmentMethod.bowditch => 'コンパス法則（Bowditch法）',
        AdjustmentMethod.transit => 'トランシット法則',
      };

  String _methodDescription(AdjustmentMethod m) => switch (m) {
        AdjustmentMethod.none => '生データのまま変換',
        AdjustmentMethod.bowditch => '路線長に比例して閉合差を配分',
        AdjustmentMethod.transit => '緯距・経距の絶対値に比例して配分',
      };
}

// =========================================================
// Sub-widgets
// =========================================================

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }
}

class _ClosureInfoCard extends StatelessWidget {
  final TraverseChain chain;
  final double closureError;
  final double totalDistance;
  final double closureRatioN;

  const _ClosureInfoCard({
    required this.chain,
    required this.closureError,
    required this.totalDistance,
    required this.closureRatioN,
  });

  @override
  Widget build(BuildContext context) {
    final isGoodClosure = closureRatioN > 500;
    final ratioText = closureRatioN.isInfinite
        ? '完全閉合'
        : '1/${closureRatioN.toStringAsFixed(0)}';

    return Card(
      color: isGoodClosure ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isGoodClosure ? Icons.check_circle : Icons.warning,
                  size: 16,
                  color: isGoodClosure ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  '測量チェーン: ${chain.length}点',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _StatChip('路線長', '${totalDistance.toStringAsFixed(1)}m'),
                _StatChip('閉合差', '${closureError.toStringAsFixed(3)}m'),
                _StatChip('閉合比', ratioText),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _LayerDropdown extends StatelessWidget {
  final List<LayerNode> layers;
  final LayerNode selected;
  final ValueChanged<LayerNode> onChanged;
  final String Function(LayerNode) labelBuilder;

  const _LayerDropdown({
    required this.layers,
    required this.selected,
    required this.onChanged,
    required this.labelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<LayerNode>(
          value: selected,
          isExpanded: true,
          items: layers.map((layer) {
            final typeLabel = labelBuilder(layer);
            return DropdownMenuItem(
              value: layer,
              child: Row(
                children: [
                  NodePresenter.buildIcon(layer, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${layer.geoPackageNode.name} / ${layer.name} ($typeLabel)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
