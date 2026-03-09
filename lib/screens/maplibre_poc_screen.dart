// MapLibre PoC画面: flutter_map → maplibre 移行の技術検証用
library;

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

class MapLibrePocScreen extends StatefulWidget {
  const MapLibrePocScreen({super.key});

  @override
  State<MapLibrePocScreen> createState() => _MapLibrePocScreenState();
}

class _MapLibrePocScreenState extends State<MapLibrePocScreen> {
  MapController? _mapController;
  double _pitch = 0;
  bool _hillshadeEnabled = false;
  bool _styleLoaded = false;

  // テスト用ポリゴン（皇居周辺）
  final _testPolygons = <Feature<Polygon>>[
    Feature(
      geometry: Polygon.from(const [
        [
          Geographic(lon: 139.7528, lat: 35.6852),
          Geographic(lon: 139.7580, lat: 35.6852),
          Geographic(lon: 139.7580, lat: 35.6800),
          Geographic(lon: 139.7528, lat: 35.6800),
          Geographic(lon: 139.7528, lat: 35.6852),
        ],
      ]),
    ),
  ];

  // テスト用ポリライン（東京駅→皇居）
  final _testPolylines = <Feature<LineString>>[
    Feature(
      geometry: LineString.from(const [
        Geographic(lon: 139.7671, lat: 35.6812),
        Geographic(lon: 139.7630, lat: 35.6820),
        Geographic(lon: 139.7580, lat: 35.6830),
        Geographic(lon: 139.7550, lat: 35.6840),
      ]),
    ),
  ];

  // テスト用マーカー
  final _testMarkers = <Feature<Point>>[
    const Feature(
      geometry: Point(Geographic(lon: 139.7671, lat: 35.6812)),
      properties: {'name': '東京駅'},
    ),
    const Feature(
      geometry: Point(Geographic(lon: 139.7528, lat: 35.6852)),
      properties: {'name': '皇居'},
    ),
    const Feature(
      geometry: Point(Geographic(lon: 139.7454, lat: 35.6586)),
      properties: {'name': '東京タワー'},
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MapLibre PoC'),
        actions: [
          // Hillshade切替
          IconButton(
            icon: Icon(
              Icons.terrain,
              color: _hillshadeEnabled ? Colors.blue : null,
            ),
            onPressed: _styleLoaded ? _toggleHillshade : null,
            tooltip: 'Hillshade 切替',
          ),
        ],
      ),
      body: Stack(
        children: [
          MapLibreMap(
            options: MapOptions(
              initCenter: const Geographic(lon: 139.7671, lat: 35.6812),
              initZoom: 14,
              initPitch: _pitch,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
            },
            onStyleLoaded: _onStyleLoaded,
            layers: [
              // ポリゴンレイヤ
              PolygonLayer(
                polygons: _testPolygons,
                color: Colors.blue.withValues(alpha: 0.3),
                outlineColor: Colors.blue,
              ),
              // ポリラインレイヤ
              PolylineLayer(
                polylines: _testPolylines,
                color: Colors.red,
                width: 3,
              ),
              // マーカーレイヤ
              MarkerLayer(
                points: _testMarkers,
                textField: '{name}',
                textAllowOverlap: true,
                iconImage: _styleLoaded ? 'poi-marker' : null,
                iconSize: 0.15,
                iconAnchor: IconAnchor.bottom,
                textOffset: const [0, 1],
              ),
            ],
          ),
          // Pitch コントロール
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Text('Pitch:'),
                    Expanded(
                      child: Slider(
                        value: _pitch,
                        min: 0,
                        max: 60,
                        divisions: 12,
                        label: '${_pitch.round()}°',
                        onChanged: (value) {
                          setState(() => _pitch = value);
                          _mapController?.animateCamera(pitch: value);
                        },
                      ),
                    ),
                    Text('${_pitch.round()}°'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// スタイル読み込み完了時: 国土地理院タイルを追加
  Future<void> _onStyleLoaded(StyleController style) async {
    // マーカーアイコン追加
    await style.addImageFromIconData(
      id: 'poi-marker',
      iconData: Icons.location_on,
      color: Colors.red,
    );

    // 国土地理院 標準地図タイルソース
    const gsiSource = RasterSource(
      id: 'gsi-std',
      tiles: ['https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png'],
      maxZoom: 18,
      tileSize: 256,
      attribution: '国土地理院',
    );
    await style.addSource(gsiSource);

    // 国土地理院タイルレイヤ（最背面に追加）
    const gsiLayer = RasterStyleLayer(
      id: 'gsi-std-layer',
      sourceId: 'gsi-std',
    );
    await style.addLayer(gsiLayer);

    setState(() => _styleLoaded = true);
  }

  /// Hillshade 表示切替
  Future<void> _toggleHillshade() async {
    final style = _mapController?.style;
    if (style == null) return;

    if (_hillshadeEnabled) {
      // 削除
      await style.removeLayer('hillshade-layer');
      await style.removeSource('dem-source');
    } else {
      // 追加: MapLibre デモタイルを使用（国土地理院DEM変換は後で対応）
      const demSource = RasterDemSource(
        id: 'dem-source',
        url: 'https://demotiles.maplibre.org/terrain-tiles/tiles.json',
        tileSize: 256,
      );
      await style.addSource(demSource);

      const hillshadeLayer = HillshadeStyleLayer(
        id: 'hillshade-layer',
        sourceId: 'dem-source',
        paint: {'hillshade-shadow-color': '#473B24'},
      );
      await style.addLayer(hillshadeLayer);
    }

    setState(() => _hillshadeEnabled = !_hillshadeEnabled);
  }
}
