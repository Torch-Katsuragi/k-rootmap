import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:maplibre/maplibre.dart' as ml;

import '../../core/k_map_controller.dart';

typedef KMapControllerCallback = void Function(KMapController controller);
typedef KMapStyleLoadedCallback =
    FutureOr<void> Function(KMapController controller, ml.StyleController style);

/// ネットワーク不要なローカルスタイル。背景色のみ定義し、ソースは動的に追加する。
const kEmptyMapStyle =
    '{"version":8,"sources":{},"layers":[{"id":"bg","type":"background","paint":{"background-color":"#e8e8e8"}}]}';

/// MapLibreMap の生成差分をここに閉じ込める薄いラッパー。
class KMapWidget extends StatefulWidget {
  const KMapWidget({
    super.key,
    this.options = const ml.MapOptions(),
    this.gestureRecognizers,
    this.onMapCreated,
    this.onStyleLoaded,
    this.onEvent,
    this.layers = const [],
    this.children = const [],
  });

  final ml.MapOptions options;
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;
  final KMapControllerCallback? onMapCreated;
  final KMapStyleLoadedCallback? onStyleLoaded;
  final ml.MapEventCallback? onEvent;
  final List<ml.Layer> layers;
  final List<Widget> children;

  @override
  State<KMapWidget> createState() => _KMapWidgetState();
}

class _KMapWidgetState extends State<KMapWidget> {
  final KMapController _controller = KMapController();

  /// maplibre_webview の didUpdateWidget は webViewController（late フィールド）
  /// が初期化される前でも呼ばれる。options/layers/children が前回と異なると
  /// webViewController にアクセスして LateInitializationError が発生するため、
  /// onMapCreated 完了まで全パラメータを初回値に固定する。
  bool _isMapCreated = false;
  late final ml.MapOptions _initialOptions = widget.options;

  @override
  Widget build(BuildContext context) {
    return ml.MapLibreMap(
      options: _isMapCreated ? widget.options : _initialOptions,
      gestureRecognizers: widget.gestureRecognizers,
      onMapCreated: (controller) {
        _controller.attach(controller);
        widget.onMapCreated?.call(_controller);
        if (!_isMapCreated) {
          setState(() => _isMapCreated = true);
        }
      },
      onStyleLoaded: (style) async {
        _controller.attachStyle(style);
        await widget.onStyleLoaded?.call(_controller, style);
      },
      onEvent: widget.onEvent,
      layers: _isMapCreated ? widget.layers : const [],
      children: _isMapCreated ? widget.children : const [],
    );
  }
}
