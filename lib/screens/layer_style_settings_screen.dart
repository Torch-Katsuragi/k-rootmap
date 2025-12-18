/// レイヤ描画設定画面
///
/// 点・線・ポリゴンの描画スタイル（サイズ、太さ、色など）を設定。
/// SharedPreferencesに保存し、マップ表示に反映。
/// 個別レイヤーモード: KMetaに保存
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import '../widgets/settings_widgets.dart';
import '../utils/app_logger.dart';
import '../models/kmeta.dart';
import '../models/nodes/layer_node.dart';
import '../services/kmeta_service.dart';

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

  // ========== KMeta連携メソッド ==========

  /// KMetaLayerStyleをマージしたポイントサイズを取得
  double getPointSize(KMetaLayerStyle? kmetaStyle) {
    return kmetaStyle?.pointSize ?? pointSize;
  }

  /// KMetaLayerStyleをマージしたポイントカラーを取得
  Color getPointColor(KMetaLayerStyle? kmetaStyle) {
    return kmetaStyle?.pointColor ?? pointColor;
  }

  /// KMetaLayerStyleをマージしたラインの太さを取得
  double getLineWidth(KMetaLayerStyle? kmetaStyle) {
    return kmetaStyle?.lineWidth ?? lineWidth;
  }

  /// KMetaLayerStyleをマージしたラインカラーを取得
  Color getLineColor(KMetaLayerStyle? kmetaStyle) {
    return kmetaStyle?.lineColor ?? lineColor;
  }

  /// KMetaLayerStyleをマージしたポリゴン境界線の太さを取得
  double getPolygonBorderWidth(KMetaLayerStyle? kmetaStyle) {
    return kmetaStyle?.polygonBorderWidth ?? polygonBorderWidth;
  }

  /// KMetaLayerStyleをマージしたポリゴン境界線カラーを取得
  Color getPolygonBorderColor(KMetaLayerStyle? kmetaStyle) {
    return kmetaStyle?.polygonBorderColor ?? polygonBorderColor;
  }

  /// KMetaLayerStyleをマージしたポリゴン塗りつぶしカラーを取得
  Color getPolygonFillColor(KMetaLayerStyle? kmetaStyle) {
    return kmetaStyle?.polygonFillColor ?? polygonFillColor;
  }

  /// KMetaLayerStyleをマージしたポリゴン塗りつぶし透過度を取得
  double getPolygonFillOpacity(KMetaLayerStyle? kmetaStyle) {
    return kmetaStyle?.polygonFillOpacity ?? polygonFillOpacity;
  }

  /// KMetaLayerStyleをマージしたポリゴン境界線透過度を取得
  double getPolygonBorderOpacity(KMetaLayerStyle? kmetaStyle) {
    return kmetaStyle?.polygonBorderOpacity ?? polygonBorderOpacity;
  }

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
/// 
/// グローバルモード: SharedPreferencesに保存（全レイヤー共通）
/// 個別レイヤーモード: KMetaに保存（レイヤー固有のスタイル）
class LayerStyleSettingsScreen extends StatefulWidget {
  final bool isEmbedded;

  /// 個別レイヤーモード用: 対象のLayerNode
  final LayerNode? targetLayer;

  /// 個別レイヤーモード用: フォルダパス（KMeta保存先）
  final String? folderPath;

  const LayerStyleSettingsScreen({
    super.key,
    this.isEmbedded = false,
    this.targetLayer,
    this.folderPath,
  });

  /// 個別レイヤーモードかどうか
  bool get isLayerMode => targetLayer != null && folderPath != null;

  @override
  State<LayerStyleSettingsScreen> createState() => _LayerStyleSettingsScreenState();
}

class _LayerStyleSettingsScreenState extends State<LayerStyleSettingsScreen> {
  final LayerStyleConfig _globalConfig = LayerStyleConfig();
  bool _isLoading = true;

  // 個別レイヤーモード用のローカルスタイル
  double _pointSize = LayerStyleDefaults.pointSize;
  Color _pointColor = Color(LayerStyleDefaults.pointColor);
  double _lineWidth = LayerStyleDefaults.lineWidth;
  Color _lineColor = Color(LayerStyleDefaults.lineColor);
  double _polygonBorderWidth = LayerStyleDefaults.polygonBorderWidth;
  Color _polygonBorderColor = Color(LayerStyleDefaults.polygonBorderColor);
  Color _polygonFillColor = Color(LayerStyleDefaults.polygonFillColor);
  double _polygonFillOpacity = LayerStyleDefaults.polygonFillOpacity;
  double _polygonBorderOpacity = LayerStyleDefaults.polygonBorderOpacity;

  /// グローバルモードかどうか
  bool get _isGlobalMode => !widget.isLayerMode;

  /// 現在のポイントサイズ
  double get _currentPointSize => _isGlobalMode ? _globalConfig.pointSize : _pointSize;
  set _currentPointSize(double v) {
    if (_isGlobalMode) {
      _globalConfig.pointSize = v;
    } else {
      _pointSize = v;
    }
  }

  /// 現在のポイントカラー
  Color get _currentPointColor => _isGlobalMode ? _globalConfig.pointColor : _pointColor;
  set _currentPointColor(Color v) {
    if (_isGlobalMode) {
      _globalConfig.pointColor = v;
    } else {
      _pointColor = v;
    }
  }

  /// 現在のラインの太さ
  double get _currentLineWidth => _isGlobalMode ? _globalConfig.lineWidth : _lineWidth;
  set _currentLineWidth(double v) {
    if (_isGlobalMode) {
      _globalConfig.lineWidth = v;
    } else {
      _lineWidth = v;
    }
  }

  /// 現在のラインカラー
  Color get _currentLineColor => _isGlobalMode ? _globalConfig.lineColor : _lineColor;
  set _currentLineColor(Color v) {
    if (_isGlobalMode) {
      _globalConfig.lineColor = v;
    } else {
      _lineColor = v;
    }
  }

  /// 現在のポリゴン境界線の太さ
  double get _currentPolygonBorderWidth =>
      _isGlobalMode ? _globalConfig.polygonBorderWidth : _polygonBorderWidth;
  set _currentPolygonBorderWidth(double v) {
    if (_isGlobalMode) {
      _globalConfig.polygonBorderWidth = v;
    } else {
      _polygonBorderWidth = v;
    }
  }

  /// 現在のポリゴン境界線カラー
  Color get _currentPolygonBorderColor =>
      _isGlobalMode ? _globalConfig.polygonBorderColor : _polygonBorderColor;
  set _currentPolygonBorderColor(Color v) {
    if (_isGlobalMode) {
      _globalConfig.polygonBorderColor = v;
    } else {
      _polygonBorderColor = v;
    }
  }

  /// 現在のポリゴン塗りつぶしカラー
  Color get _currentPolygonFillColor =>
      _isGlobalMode ? _globalConfig.polygonFillColor : _polygonFillColor;
  set _currentPolygonFillColor(Color v) {
    if (_isGlobalMode) {
      _globalConfig.polygonFillColor = v;
    } else {
      _polygonFillColor = v;
    }
  }

  /// 現在のポリゴン塗りつぶし透過度
  double get _currentPolygonFillOpacity =>
      _isGlobalMode ? _globalConfig.polygonFillOpacity : _polygonFillOpacity;
  set _currentPolygonFillOpacity(double v) {
    if (_isGlobalMode) {
      _globalConfig.polygonFillOpacity = v;
    } else {
      _polygonFillOpacity = v;
    }
  }

  /// 現在のポリゴン境界線透過度
  double get _currentPolygonBorderOpacity =>
      _isGlobalMode ? _globalConfig.polygonBorderOpacity : _polygonBorderOpacity;
  set _currentPolygonBorderOpacity(double v) {
    if (_isGlobalMode) {
      _globalConfig.polygonBorderOpacity = v;
    } else {
      _polygonBorderOpacity = v;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (_isGlobalMode) {
      // グローバルモード: SharedPreferencesから読み込み
      await _globalConfig.load();
    } else {
      // 個別レイヤーモード: KMetaから読み込み
      final meta = await KMetaService.instance.getMergedMeta(widget.folderPath!);
      final layerStyle = meta.getLayerStyle(widget.targetLayer!.layerKey);
      if (layerStyle != null) {
        _pointSize = layerStyle.pointSize ?? _globalConfig.pointSize;
        _pointColor = layerStyle.pointColor ?? _globalConfig.pointColor;
        _lineWidth = layerStyle.lineWidth ?? _globalConfig.lineWidth;
        _lineColor = layerStyle.lineColor ?? _globalConfig.lineColor;
        _polygonBorderWidth = layerStyle.polygonBorderWidth ?? _globalConfig.polygonBorderWidth;
        _polygonBorderColor = layerStyle.polygonBorderColor ?? _globalConfig.polygonBorderColor;
        _polygonFillColor = layerStyle.polygonFillColor ?? _globalConfig.polygonFillColor;
        _polygonFillOpacity = layerStyle.polygonFillOpacity ?? _globalConfig.polygonFillOpacity;
        _polygonBorderOpacity = layerStyle.polygonBorderOpacity ?? _globalConfig.polygonBorderOpacity;
      } else {
        // デフォルト値としてグローバル設定を使用
        _pointSize = _globalConfig.pointSize;
        _pointColor = _globalConfig.pointColor;
        _lineWidth = _globalConfig.lineWidth;
        _lineColor = _globalConfig.lineColor;
        _polygonBorderWidth = _globalConfig.polygonBorderWidth;
        _polygonBorderColor = _globalConfig.polygonBorderColor;
        _polygonFillColor = _globalConfig.polygonFillColor;
        _polygonFillOpacity = _globalConfig.polygonFillOpacity;
        _polygonBorderOpacity = _globalConfig.polygonBorderOpacity;
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    if (_isGlobalMode) {
      // グローバルモード: SharedPreferencesに保存
      await _globalConfig.save();
      AppLogger.debug('[LayerStyle] グローバル設定を保存しました');
    } else {
      // 個別レイヤーモード: KMetaに保存
      final style = KMetaLayerStyle(
        pointSize: _pointSize,
        pointColor: _pointColor,
        lineWidth: _lineWidth,
        lineColor: _lineColor,
        polygonBorderWidth: _polygonBorderWidth,
        polygonBorderColor: _polygonBorderColor,
        polygonFillColor: _polygonFillColor,
        polygonFillOpacity: _polygonFillOpacity,
        polygonBorderOpacity: _polygonBorderOpacity,
      );
      await KMetaService.instance.setLayerStyle(
        widget.folderPath!,
        widget.targetLayer!.layerKey,
        style,
      );
      // FolderNodeとLayerNodeのキャッシュをクリア（新しいスタイルを読み込むため）
      widget.targetLayer!.folderNode?.invalidateMetaCache();
      widget.targetLayer!.invalidateKmetaStyleCache();
      AppLogger.debug('[LayerStyle] レイヤー固有設定を保存: ${widget.targetLayer!.layerKey}');
    }
  }

  Future<void> _resetSettings() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('設定をリセット'),
        content: Text(_isGlobalMode
            ? 'すべての描画設定をデフォルト値に戻しますか？'
            : 'このレイヤーの設定をグローバル設定に戻しますか？'),
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
      if (_isGlobalMode) {
        await _globalConfig.reset();
      } else {
        // 個別レイヤー設定を削除（グローバル設定にフォールバック）
        final rawMeta = await KMetaService.instance.getRawMeta(widget.folderPath!) ?? KMeta.empty;
        final updatedLayers = Map<String, KMetaLayerStyle>.from(rawMeta.styles.layers);
        updatedLayers.remove(widget.targetLayer!.layerKey);
        final updatedStyles = KMetaStyles(
          defaultStyle: rawMeta.styles.defaultStyle,
          layers: updatedLayers,
        );
        final updatedMeta = rawMeta.copyWith(styles: updatedStyles);
        await KMetaService.instance.saveMeta(widget.folderPath!, updatedMeta);
        widget.targetLayer!.invalidateKmetaStyleCache();
        // グローバル設定を再読み込み
        _pointSize = _globalConfig.pointSize;
        _pointColor = _globalConfig.pointColor;
        _lineWidth = _globalConfig.lineWidth;
        _lineColor = _globalConfig.lineColor;
        _polygonBorderWidth = _globalConfig.polygonBorderWidth;
        _polygonBorderColor = _globalConfig.polygonBorderColor;
        _polygonFillColor = _globalConfig.polygonFillColor;
        _polygonFillOpacity = _globalConfig.polygonFillOpacity;
        _polygonBorderOpacity = _globalConfig.polygonBorderOpacity;
      }
      setState(() {});
      AppLogger.debug('[LayerStyle] 設定をリセットしました');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isGlobalMode
        ? 'レイヤ描画'
        : 'Style: ${widget.targetLayer!.layerName}';

    return SettingsScaffold(
      title: title,
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
        sections: _buildSections(),
      ),
    );
  }

  /// ジオメトリタイプに応じたセクションリストを構築
  List<Widget> _buildSections() {
    if (_isGlobalMode) {
      // グローバルモード: 全セクション表示
      return [
        _buildPreviewSection(),
        _buildPointSection(),
        _buildLineSection(),
        _buildPolygonSection(),
        _buildSelectionSection(),
      ];
    }

    // 個別レイヤーモード: ジオメトリタイプに応じたセクションのみ
    final layer = widget.targetLayer!;
    final sections = <Widget>[_buildPreviewSection()];

    if (layer is PointLayerNode) {
      sections.add(_buildPointSection());
    } else if (layer is LineLayerNode) {
      sections.add(_buildLineSection());
    } else if (layer is PolygonLayerNode) {
      sections.add(_buildPolygonSection());
    }

    return sections;
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
            painter: _StylePreviewPainter(
              pointColor: _currentPointColor,
              pointSize: _currentPointSize,
              lineColor: _currentLineColor,
              lineWidth: _currentLineWidth,
              polygonBorderColor: _currentPolygonBorderColor,
              polygonBorderWidth: _currentPolygonBorderWidth,
              polygonFillColor: _currentPolygonFillColor,
              polygonFillOpacity: _currentPolygonFillOpacity,
              polygonBorderOpacity: _currentPolygonBorderOpacity,
            ),
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
      iconColor: _currentPointColor,
      collapsible: true,
      initiallyExpanded: false,
      children: [
        // サイズ
        _buildSliderTile(
          title: 'Size',
          value: _currentPointSize,
          min: 4,
          max: 30,
          divisions: 26,
          label: '${_currentPointSize.toInt()} px',
          onChanged: (v) {
            setState(() => _currentPointSize = v);
            _saveSettings();
          },
        ),
        const Divider(),
        // 色
        _buildColorTile(
          title: 'Color',
          color: _currentPointColor,
          onColorChanged: (c) {
            setState(() => _currentPointColor = c);
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
      iconColor: _currentLineColor,
      collapsible: true,
      initiallyExpanded: false,
      children: [
        // 太さ
        _buildSliderTile(
          title: 'Width',
          value: _currentLineWidth,
          min: 1,
          max: 10,
          divisions: 9,
          label: '${_currentLineWidth.toInt()} px',
          onChanged: (v) {
            setState(() => _currentLineWidth = v);
            _saveSettings();
          },
        ),
        const Divider(),
        // 色
        _buildColorTile(
          title: 'Color',
          color: _currentLineColor,
          onColorChanged: (c) {
            setState(() => _currentLineColor = c);
            _saveSettings();
          },
        ),
        // 頂点点描画（グローバルモードのみ）
        if (_isGlobalMode) ...[
          const Divider(),
          SettingsSwitchTile(
            leadingIcon: Icons.scatter_plot_outlined,
            title: 'Draw Vertex Points',
            subtitle: 'Overlay points at each vertex (color follows line)',
            value: _globalConfig.lineVertexPointsEnabled,
            onChanged: (v) {
              setState(() => _globalConfig.lineVertexPointsEnabled = v);
              _saveSettings();
            },
          ),
          if (_globalConfig.lineVertexPointsEnabled) ...[
            _buildSliderTile(
              title: 'Vertex Point Size Factor',
              value: _globalConfig.lineVertexPointSizeFactor,
              min: 0.5,
              max: 6.0,
              divisions: 55,
              label: '${_globalConfig.lineVertexPointSizeFactor.toStringAsFixed(1)}x',
              onChanged: (v) {
                setState(() => _globalConfig.lineVertexPointSizeFactor = v);
                _saveSettings();
              },
            ),
          ],
        ],
      ],
    );
  }

  /// ポリゴンの設定セクション
  Widget _buildPolygonSection() {
    return SettingsSection(
      title: 'Polygon Style',
      icon: Icons.hexagon_outlined,
      iconColor: _currentPolygonBorderColor,
      collapsible: true,
      initiallyExpanded: false,
      children: [
        // 境界線の太さ
        _buildSliderTile(
          title: 'Border Width',
          value: _currentPolygonBorderWidth,
          min: 1,
          max: 8,
          divisions: 7,
          label: '${_currentPolygonBorderWidth.toInt()} px',
          onChanged: (v) {
            setState(() => _currentPolygonBorderWidth = v);
            _saveSettings();
          },
        ),
        const Divider(),
        // 境界線の色
        _buildColorTile(
          title: 'Border Color',
          color: _currentPolygonBorderColor,
          onColorChanged: (c) {
            setState(() => _currentPolygonBorderColor = c);
            _saveSettings();
          },
        ),
        const Divider(),
        // 塗りつぶし色
        _buildColorTile(
          title: 'Fill Color',
          color: _currentPolygonFillColor,
          onColorChanged: (c) {
            setState(() => _currentPolygonFillColor = c);
            _saveSettings();
          },
        ),
        const Divider(),
        // 塗りつぶし透明度
        _buildSliderTile(
          title: 'Fill Opacity',
          value: _currentPolygonFillOpacity,
          min: 0.0,
          max: 1.0,
          divisions: 10,
          label: '${(_currentPolygonFillOpacity * 100).toInt()}%',
          onChanged: (v) {
            setState(() => _currentPolygonFillOpacity = v);
            _saveSettings();
          },
        ),
        // 頂点点描画（グローバルモードのみ）
        if (_isGlobalMode) ...[
          const Divider(),
          SettingsSwitchTile(
            leadingIcon: Icons.scatter_plot_outlined,
            title: 'Draw Vertex Points',
            subtitle: 'Overlay points at each vertex (color follows border)',
            value: _globalConfig.polygonVertexPointsEnabled,
            onChanged: (v) {
              setState(() => _globalConfig.polygonVertexPointsEnabled = v);
              _saveSettings();
            },
          ),
          if (_globalConfig.polygonVertexPointsEnabled) ...[
            _buildSliderTile(
              title: 'Vertex Point Size Factor',
              value: _globalConfig.polygonVertexPointSizeFactor,
              min: 0.5,
              max: 6.0,
              divisions: 55,
              label: '${_globalConfig.polygonVertexPointSizeFactor.toStringAsFixed(1)}x',
              onChanged: (v) {
                setState(() => _globalConfig.polygonVertexPointSizeFactor = v);
                _saveSettings();
              },
            ),
          ],
        ],
      ],
    );
  }

  /// 選択時の設定セクション（グローバルモード専用）
  Widget _buildSelectionSection() {
    return SettingsSection(
      title: 'Selection Highlight',
      icon: Icons.highlight_alt,
      iconColor: _globalConfig.selectedColor,
      collapsible: true,
      initiallyExpanded: false,
      children: [
        // 選択色
        _buildColorTile(
          title: 'Color',
          color: _globalConfig.selectedColor,
          onColorChanged: (c) {
            setState(() => _globalConfig.selectedColor = c);
            _saveSettings();
          },
        ),
        const Divider(),
        // サイズ倍率
        _buildSliderTile(
          title: 'Size Multiplier',
          value: _globalConfig.selectedMultiplier,
          min: 1.0,
          max: 3.0,
          divisions: 20,
          label: '${_globalConfig.selectedMultiplier.toStringAsFixed(1)}x',
          onChanged: (v) {
            setState(() => _globalConfig.selectedMultiplier = v);
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
  final Color pointColor;
  final double pointSize;
  final Color lineColor;
  final double lineWidth;
  final Color polygonBorderColor;
  final double polygonBorderWidth;
  final Color polygonFillColor;
  final double polygonFillOpacity;
  final double polygonBorderOpacity;

  _StylePreviewPainter({
    required this.pointColor,
    required this.pointSize,
    required this.lineColor,
    required this.lineWidth,
    required this.polygonBorderColor,
    required this.polygonBorderWidth,
    required this.polygonFillColor,
    required this.polygonFillOpacity,
    required this.polygonBorderOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pointPaint = Paint()
      ..color = pointColor
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round;

    final polygonFillPaint = Paint()
      ..color = polygonFillColor.withValues(alpha: polygonFillOpacity)
      ..style = PaintingStyle.fill;

    final polygonBorderPaint = Paint()
      ..color = polygonBorderColor.withValues(alpha: polygonBorderOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = polygonBorderWidth;

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

    // ポイント
    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 0.5),
      pointSize / 2,
      pointPaint,
    );
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

