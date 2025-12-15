/// レイヤ描画設定画面
///
/// 点・線・ポリゴンの描画スタイル（サイズ、太さ、色など）を設定。
/// SharedPreferencesに保存し、マップ表示に反映。
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import '../widgets/settings_widgets.dart';
import '../utils/app_logger.dart';

/// レイヤ描画設定のデフォルト値
class LayerStyleDefaults {
  // 点（ポイント）
  static const double pointSize = 12.0;
  static const int pointColor = 0xFFF44336; // Red（現在位置との差別化）

  // 線（ライン）
  static const double lineWidth = 3.0;
  static const int lineColor = 0xFF4CAF50; // Green
  static const bool lineVertexPointsEnabled = false;
  static const double lineVertexPointSizeFactor = 2.0; // 頂点点サイズ = lineWidth × f

  // ポリゴン
  static const double polygonBorderWidth = 2.0;
  static const int polygonBorderColor = 0xFFFF9800; // Orange
  static const int polygonFillColor = 0xFFFF9800; // Orange
  static const double polygonFillOpacity = 0.3;
  static const double polygonBorderOpacity = 1.0;
  static const bool polygonVertexPointsEnabled = false;
  static const double polygonVertexPointSizeFactor = 2.0; // 頂点点サイズ = borderWidth × f

  // 選択時のハイライト
  static const int selectedColor = 0xFFE91E63; // Pink
  static const double selectedMultiplier = 1.5;
}

/// レイヤ描画設定を管理するシングルトン（ChangeNotifier）
class LayerStyleConfig extends ChangeNotifier {
  static final LayerStyleConfig _instance = LayerStyleConfig._internal();
  factory LayerStyleConfig() => _instance;
  LayerStyleConfig._internal();

  // 点の設定
  double pointSize = LayerStyleDefaults.pointSize;
  Color pointColor = Color(LayerStyleDefaults.pointColor);

  // 線の設定
  double lineWidth = LayerStyleDefaults.lineWidth;
  Color lineColor = Color(LayerStyleDefaults.lineColor);
  bool lineVertexPointsEnabled = LayerStyleDefaults.lineVertexPointsEnabled;
  double lineVertexPointSizeFactor = LayerStyleDefaults.lineVertexPointSizeFactor;

  // ポリゴンの設定
  double polygonBorderWidth = LayerStyleDefaults.polygonBorderWidth;
  Color polygonBorderColor = Color(LayerStyleDefaults.polygonBorderColor);
  Color polygonFillColor = Color(LayerStyleDefaults.polygonFillColor);
  double polygonFillOpacity = LayerStyleDefaults.polygonFillOpacity;
  double polygonBorderOpacity = LayerStyleDefaults.polygonBorderOpacity;
  bool polygonVertexPointsEnabled = LayerStyleDefaults.polygonVertexPointsEnabled;
  double polygonVertexPointSizeFactor = LayerStyleDefaults.polygonVertexPointSizeFactor;

  // 選択時
  Color selectedColor = Color(LayerStyleDefaults.selectedColor);
  double selectedMultiplier = LayerStyleDefaults.selectedMultiplier;

  /// SharedPreferencesから設定を読み込み
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    
    pointSize = prefs.getDouble('layer_style_point_size') ?? LayerStyleDefaults.pointSize;
    pointColor = Color(prefs.getInt('layer_style_point_color') ?? LayerStyleDefaults.pointColor);

    lineWidth = prefs.getDouble('layer_style_line_width') ?? LayerStyleDefaults.lineWidth;
    lineColor = Color(prefs.getInt('layer_style_line_color') ?? LayerStyleDefaults.lineColor);
    lineVertexPointsEnabled =
        prefs.getBool('layer_style_line_vertex_points_enabled') ??
            LayerStyleDefaults.lineVertexPointsEnabled;
    lineVertexPointSizeFactor =
        prefs.getDouble('layer_style_line_vertex_point_size_factor') ??
            LayerStyleDefaults.lineVertexPointSizeFactor;

    polygonBorderWidth = prefs.getDouble('layer_style_polygon_border_width') ?? LayerStyleDefaults.polygonBorderWidth;
    polygonBorderColor = Color(prefs.getInt('layer_style_polygon_border_color') ?? LayerStyleDefaults.polygonBorderColor);
    polygonFillColor = Color(prefs.getInt('layer_style_polygon_fill_color') ?? LayerStyleDefaults.polygonFillColor);
    polygonFillOpacity = prefs.getDouble('layer_style_polygon_fill_opacity') ?? LayerStyleDefaults.polygonFillOpacity;
    polygonBorderOpacity = prefs.getDouble('layer_style_polygon_border_opacity') ?? LayerStyleDefaults.polygonBorderOpacity;
    polygonVertexPointsEnabled =
        prefs.getBool('layer_style_polygon_vertex_points_enabled') ??
            LayerStyleDefaults.polygonVertexPointsEnabled;
    polygonVertexPointSizeFactor =
        prefs.getDouble('layer_style_polygon_vertex_point_size_factor') ??
            LayerStyleDefaults.polygonVertexPointSizeFactor;

    selectedColor = Color(prefs.getInt('layer_style_selected_color') ?? LayerStyleDefaults.selectedColor);
    selectedMultiplier = prefs.getDouble('layer_style_selected_multiplier') ?? LayerStyleDefaults.selectedMultiplier;
  }

  /// SharedPreferencesに設定を保存
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setDouble('layer_style_point_size', pointSize);
    await prefs.setInt('layer_style_point_color', pointColor.toARGB32());

    await prefs.setDouble('layer_style_line_width', lineWidth);
    await prefs.setInt('layer_style_line_color', lineColor.toARGB32());
    await prefs.setBool(
      'layer_style_line_vertex_points_enabled',
      lineVertexPointsEnabled,
    );
    await prefs.setDouble(
      'layer_style_line_vertex_point_size_factor',
      lineVertexPointSizeFactor,
    );

    await prefs.setDouble('layer_style_polygon_border_width', polygonBorderWidth);
    await prefs.setInt(
      'layer_style_polygon_border_color',
      polygonBorderColor.toARGB32(),
    );
    await prefs.setInt(
      'layer_style_polygon_fill_color',
      polygonFillColor.toARGB32(),
    );
    await prefs.setDouble('layer_style_polygon_fill_opacity', polygonFillOpacity);
    await prefs.setDouble('layer_style_polygon_border_opacity', polygonBorderOpacity);
    await prefs.setBool(
      'layer_style_polygon_vertex_points_enabled',
      polygonVertexPointsEnabled,
    );
    await prefs.setDouble(
      'layer_style_polygon_vertex_point_size_factor',
      polygonVertexPointSizeFactor,
    );

    await prefs.setInt('layer_style_selected_color', selectedColor.toARGB32());
    await prefs.setDouble('layer_style_selected_multiplier', selectedMultiplier);

    // リスナーに変更を通知（マップ再描画用）
    notifyListeners();
  }

  /// デフォルト値にリセット
  Future<void> reset() async {
    pointSize = LayerStyleDefaults.pointSize;
    pointColor = Color(LayerStyleDefaults.pointColor);

    lineWidth = LayerStyleDefaults.lineWidth;
    lineColor = Color(LayerStyleDefaults.lineColor);
    lineVertexPointsEnabled = LayerStyleDefaults.lineVertexPointsEnabled;
    lineVertexPointSizeFactor = LayerStyleDefaults.lineVertexPointSizeFactor;

    polygonBorderWidth = LayerStyleDefaults.polygonBorderWidth;
    polygonBorderColor = Color(LayerStyleDefaults.polygonBorderColor);
    polygonFillColor = Color(LayerStyleDefaults.polygonFillColor);
    polygonFillOpacity = LayerStyleDefaults.polygonFillOpacity;
    polygonBorderOpacity = LayerStyleDefaults.polygonBorderOpacity;
    polygonVertexPointsEnabled = LayerStyleDefaults.polygonVertexPointsEnabled;
    polygonVertexPointSizeFactor = LayerStyleDefaults.polygonVertexPointSizeFactor;

    selectedColor = Color(LayerStyleDefaults.selectedColor);
    selectedMultiplier = LayerStyleDefaults.selectedMultiplier;

    await save();
  }
}

/// レイヤ描画設定画面
class LayerStyleSettingsScreen extends StatefulWidget {
  final bool isEmbedded;

  const LayerStyleSettingsScreen({
    super.key,
    this.isEmbedded = false,
  });

  @override
  State<LayerStyleSettingsScreen> createState() => _LayerStyleSettingsScreenState();
}

class _LayerStyleSettingsScreenState extends State<LayerStyleSettingsScreen> {
  final LayerStyleConfig _config = LayerStyleConfig();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _config.load();
    setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    await _config.save();
    AppLogger.debug('[LayerStyle] 設定を保存しました');
  }

  Future<void> _resetSettings() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('設定をリセット'),
        content: const Text('すべての描画設定をデフォルト値に戻しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('リセット'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _config.reset();
      setState(() {});
      AppLogger.debug('[LayerStyle] 設定をリセットしました');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'レイヤ描画',
      isEmbedded: widget.isEmbedded,
      isLoading: _isLoading,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'リセット',
          onPressed: _resetSettings,
        ),
      ],
      body: SettingsBody(
        sections: [
          // プレビュー
          _buildPreviewSection(),

          // 点の設定
          _buildPointSection(),

          // 線の設定
          _buildLineSection(),

          // ポリゴンの設定
          _buildPolygonSection(),

          // 選択時の設定
          _buildSelectionSection(),
        ],
      ),
    );
  }

  /// プレビューセクション
  Widget _buildPreviewSection() {
    return SettingsSection(
      title: 'Preview',
      icon: Icons.preview,
      iconColor: Colors.purple,
      collapsible: true,
      initiallyExpanded: true,
      children: [
        SizedBox(
          height: 100,
          child: CustomPaint(
            painter: _StylePreviewPainter(_config),
            size: const Size(double.infinity, 100),
          ),
        ),
      ],
    );
  }

  /// 点の設定セクション
  Widget _buildPointSection() {
    return SettingsSection(
      title: 'Point Style',
      icon: Icons.place,
      iconColor: _config.pointColor,
      collapsible: true,
      initiallyExpanded: false,
      children: [
        // サイズ
        _buildSliderTile(
          title: 'Size',
          value: _config.pointSize,
          min: 4,
          max: 30,
          divisions: 26,
          label: '${_config.pointSize.toInt()} px',
          onChanged: (v) {
            setState(() => _config.pointSize = v);
            _saveSettings();
          },
        ),
        const Divider(),
        // 色
        _buildColorTile(
          title: 'Color',
          color: _config.pointColor,
          onColorChanged: (c) {
            setState(() => _config.pointColor = c);
            _saveSettings();
          },
        ),
      ],
    );
  }

  /// 線の設定セクション
  Widget _buildLineSection() {
    return SettingsSection(
      title: 'Line Style',
      icon: Icons.show_chart,
      iconColor: _config.lineColor,
      collapsible: true,
      initiallyExpanded: false,
      children: [
        // 太さ
        _buildSliderTile(
          title: 'Width',
          value: _config.lineWidth,
          min: 1,
          max: 10,
          divisions: 9,
          label: '${_config.lineWidth.toInt()} px',
          onChanged: (v) {
            setState(() => _config.lineWidth = v);
            _saveSettings();
          },
        ),
        const Divider(),
        // 色
        _buildColorTile(
          title: 'Color',
          color: _config.lineColor,
          onColorChanged: (c) {
            setState(() => _config.lineColor = c);
            _saveSettings();
          },
        ),
        const Divider(),
        // 頂点点描画ON/OFF
        SettingsSwitchTile(
          leadingIcon: Icons.scatter_plot_outlined,
          title: 'Draw Vertex Points',
          subtitle: 'Overlay points at each vertex (color follows line)',
          value: _config.lineVertexPointsEnabled,
          onChanged: (v) {
            setState(() => _config.lineVertexPointsEnabled = v);
            _saveSettings();
          },
        ),
        // 頂点点サイズ倍率（有効時のみ）
        if (_config.lineVertexPointsEnabled) ...[
          _buildSliderTile(
            title: 'Vertex Point Size Factor',
            value: _config.lineVertexPointSizeFactor,
            min: 0.5,
            max: 6.0,
            divisions: 55,
            label: '${_config.lineVertexPointSizeFactor.toStringAsFixed(1)}x',
            onChanged: (v) {
              setState(() => _config.lineVertexPointSizeFactor = v);
              _saveSettings();
            },
          ),
        ],
      ],
    );
  }

  /// ポリゴンの設定セクション
  Widget _buildPolygonSection() {
    return SettingsSection(
      title: 'Polygon Style',
      icon: Icons.hexagon_outlined,
      iconColor: _config.polygonBorderColor,
      collapsible: true,
      initiallyExpanded: false,
      children: [
        // 境界線の太さ
        _buildSliderTile(
          title: 'Border Width',
          value: _config.polygonBorderWidth,
          min: 1,
          max: 8,
          divisions: 7,
          label: '${_config.polygonBorderWidth.toInt()} px',
          onChanged: (v) {
            setState(() => _config.polygonBorderWidth = v);
            _saveSettings();
          },
        ),
        const Divider(),
        // 境界線の色
        _buildColorTile(
          title: 'Border Color',
          color: _config.polygonBorderColor,
          onColorChanged: (c) {
            setState(() => _config.polygonBorderColor = c);
            _saveSettings();
          },
        ),
        const Divider(),
        // 塗りつぶし色
        _buildColorTile(
          title: 'Fill Color',
          color: _config.polygonFillColor,
          onColorChanged: (c) {
            setState(() => _config.polygonFillColor = c);
            _saveSettings();
          },
        ),
        const Divider(),
        // 塗りつぶし透明度
        _buildSliderTile(
          title: 'Fill Opacity',
          value: _config.polygonFillOpacity,
          min: 0.0,
          max: 1.0,
          divisions: 10,
          label: '${(_config.polygonFillOpacity * 100).toInt()}%',
          onChanged: (v) {
            setState(() => _config.polygonFillOpacity = v);
            _saveSettings();
          },
        ),
        const Divider(),
        // 頂点点描画ON/OFF
        SettingsSwitchTile(
          leadingIcon: Icons.scatter_plot_outlined,
          title: 'Draw Vertex Points',
          subtitle: 'Overlay points at each vertex (color follows border)',
          value: _config.polygonVertexPointsEnabled,
          onChanged: (v) {
            setState(() => _config.polygonVertexPointsEnabled = v);
            _saveSettings();
          },
        ),
        // 頂点点サイズ倍率（有効時のみ）
        if (_config.polygonVertexPointsEnabled) ...[
          _buildSliderTile(
            title: 'Vertex Point Size Factor',
            value: _config.polygonVertexPointSizeFactor,
            min: 0.5,
            max: 6.0,
            divisions: 55,
            label: '${_config.polygonVertexPointSizeFactor.toStringAsFixed(1)}x',
            onChanged: (v) {
              setState(() => _config.polygonVertexPointSizeFactor = v);
              _saveSettings();
            },
          ),
        ],
      ],
    );
  }

  /// 選択時の設定セクション
  Widget _buildSelectionSection() {
    return SettingsSection(
      title: 'Selection Highlight',
      icon: Icons.highlight_alt,
      iconColor: _config.selectedColor,
      collapsible: true,
      initiallyExpanded: false,
      children: [
        // 選択色
        _buildColorTile(
          title: 'Color',
          color: _config.selectedColor,
          onColorChanged: (c) {
            setState(() => _config.selectedColor = c);
            _saveSettings();
          },
        ),
        const Divider(),
        // サイズ倍率
        _buildSliderTile(
          title: 'Size Multiplier',
          value: _config.selectedMultiplier,
          min: 1.0,
          max: 3.0,
          divisions: 20,
          label: '${_config.selectedMultiplier.toStringAsFixed(1)}x',
          onChanged: (v) {
            setState(() => _config.selectedMultiplier = v);
            _saveSettings();
          },
        ),
      ],
    );
  }

  /// スライダー付きタイル
  Widget _buildSliderTile({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title),
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }

  /// 色選択タイル
  Widget _buildColorTile({
    required String title,
    required Color color,
    required ValueChanged<Color> onColorChanged,
  }) {
    return ListTile(
      title: Text(title),
      trailing: GestureDetector(
        onTap: () => _showColorPicker(color, onColorChanged),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade400),
          ),
        ),
      ),
    );
  }

  /// 色選択ダイアログ (パレット + カラーホイール)
  Future<void> _showColorPicker(Color currentColor, ValueChanged<Color> onColorChanged) async {
    Color pickedColor = currentColor;
    
    final result = await showColorPickerDialog(
      context,
      pickedColor,
      title: const Text('色を選択', style: TextStyle(fontWeight: FontWeight.bold)),
      width: 44,           // 色アイテムの幅 (15-150)
      height: 44,          // 色アイテムの高さ (15-150)
      spacing: 6,


      
      runSpacing: 6,
      borderRadius: 8,
      wheelDiameter: 220,
      wheelWidth: 24,
      enableOpacity: false,
      showColorCode: true,
      colorCodeHasColor: true,
      pickersEnabled: const <ColorPickerType, bool>{
        ColorPickerType.both: false,
        ColorPickerType.primary: true,     // マテリアルカラー パレット
        ColorPickerType.accent: false,
        ColorPickerType.bw: false,
        ColorPickerType.custom: false,
        ColorPickerType.wheel: true,       // HSV カラーホイール
      },
      actionButtons: const ColorPickerActionButtons(
        okButton: true,
        closeButton: true,
        dialogActionButtons: true,
        dialogOkButtonType: ColorPickerActionButtonType.elevated,
        dialogOkButtonLabel: 'OK',
        dialogCancelButtonLabel: 'キャンセル',
      ),
    );

    if (result != currentColor) {
      onColorChanged(result);
    }
  }
}

/// スタイルプレビュー用のCustomPainter
class _StylePreviewPainter extends CustomPainter {
  final LayerStyleConfig config;

  _StylePreviewPainter(this.config);

  @override
  void paint(Canvas canvas, Size size) {
    final pointPaint = Paint()
      ..color = config.pointColor
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = config.lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = config.lineWidth
      ..strokeCap = StrokeCap.round;

    final polygonFillPaint = Paint()
      ..color = config.polygonFillColor.withValues(alpha: config.polygonFillOpacity)
      ..style = PaintingStyle.fill;

    final polygonBorderPaint = Paint()
      ..color = config.polygonBorderColor.withValues(alpha: config.polygonBorderOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = config.polygonBorderWidth;

    // ポリゴン（六角形）
    final polygonPath = Path();
    final cx = size.width * 0.75;
    final cy = size.height * 0.5;
    final r = 35.0;
    for (int i = 0; i < 6; i++) {
      final angle = (i * 60 - 90) * 3.14159 / 180;
      final x = cx + r * _cos(angle);
      final y = cy + r * _sin(angle);
      if (i == 0) {
        polygonPath.moveTo(x, y);
      } else {
        polygonPath.lineTo(x, y);
      }
    }
    polygonPath.close();
    canvas.drawPath(polygonPath, polygonFillPaint);
    canvas.drawPath(polygonPath, polygonBorderPaint);

    // ライン
    final linePath = Path()
      ..moveTo(size.width * 0.35, size.height * 0.7)
      ..quadraticBezierTo(
        size.width * 0.5, size.height * 0.2,
        size.width * 0.65, size.height * 0.5,
      );
    canvas.drawPath(linePath, linePaint);

    // ライン頂点点（簡易プレビュー）
    if (config.lineVertexPointsEnabled) {
      final r = (config.lineWidth * config.lineVertexPointSizeFactor / 2)
          .clamp(2.0, 12.0);
      final vertexPaint = Paint()..color = config.lineColor;
      canvas.drawCircle(Offset(size.width * 0.35, size.height * 0.7), r, vertexPaint);
      canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.2), r, vertexPaint);
      canvas.drawCircle(Offset(size.width * 0.65, size.height * 0.5), r, vertexPaint);
    }

    // ポイント
    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 0.5),
      config.pointSize / 2,
      pointPaint,
    );

    // ポリゴン頂点点（簡易プレビュー）
    if (config.polygonVertexPointsEnabled) {
      final r =
          (config.polygonBorderWidth * config.polygonVertexPointSizeFactor / 2)
              .clamp(2.0, 12.0);
      final vertexPaint = Paint()
        ..color = config.polygonBorderColor.withValues(alpha: config.polygonBorderOpacity);
      // 六角形の各頂点に点を描画（既にpolygonPathを作っているので再計算）
      final cx = size.width * 0.75;
      final cy = size.height * 0.5;
      final rr = 35.0;
      for (int i = 0; i < 6; i++) {
        final angle = (i * 60 - 90) * 3.14159 / 180;
        final x = cx + rr * _cos(angle);
        final y = cy + rr * _sin(angle);
        canvas.drawCircle(Offset(x, y), r, vertexPaint);
      }
    }
  }

  double _cos(double radians) => radians.cos();
  double _sin(double radians) => radians.sin();

  @override
  bool shouldRepaint(covariant _StylePreviewPainter oldDelegate) => true;
}

// dart:math の cos/sin を使用するための拡張
extension on double {
  double cos() => _cosValue(this);
  double sin() => _sinValue(this);
}

double _cosValue(double x) {
  // Taylor series approximation
  double result = 1.0;
  double term = 1.0;
  for (int i = 1; i <= 10; i++) {
    term *= -x * x / ((2 * i - 1) * (2 * i));
    result += term;
  }
  return result;
}

double _sinValue(double x) {
  // Taylor series approximation
  double result = x;
  double term = x;
  for (int i = 1; i <= 10; i++) {
    term *= -x * x / ((2 * i) * (2 * i + 1));
    result += term;
  }
  return result;
}

