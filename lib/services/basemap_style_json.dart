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
/// 背景地図を埋め込んだMapLibreスタイルJSONの組み立て。
///
/// > [!IMPORTANT] web ではこれが**唯一**の背景地図の入れ方
/// > maplibre_web 0.3.5 の `StyleController.addSource()` は `RasterSource` を
/// > 渡すと `tiles` と `url` の**両方**をJSオブジェクトに書く。片方は必ず null に
/// > なるため、maplibre-gl の style バリデータが
/// > `sources.<id>.url: string expected, null found` で弾き、ソースが登録されない。
/// > 例外は飛ばず、タイルのリクエストも発生しないので**無言で地図が真っさらになる**。
/// >
/// > スタイルJSONに最初から書いてしまえばこの経路を通らない
/// > （`jsonDecode` → `jsify` で null が混ざらない）。
library;

import 'dart:convert';

import '../models/basemap_provider.dart';

/// MapLibreのデフォルトフォント配信元（ネットワーク必須）
const _kFallbackGlyphs =
    'https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf';

/// 背景色のみのレイヤID
const kBackgroundLayerId = 'bg';

/// プロバイダIDからソースIDを作る（`map_page.dart` の命名と一致させること）
String basemapSourceId(String providerId) => 'basemap-$providerId';

/// プロバイダIDからレイヤIDを作る（`map_page.dart` の命名と一致させること）
String basemapLayerId(String providerId) => 'basemap-layer-$providerId';

/// [layers]（プロバイダと累積補正済みopacityの組）を焼き込んだスタイルJSONを返す。
///
/// [layers] が空なら背景色だけの最小スタイルになる（オフラインでも
/// `onStyleLoaded` が発火する）。
String buildBasemapStyleJson({
  required List<(BaseMapProvider, double)> layers,
  String glyphsUrl = _kFallbackGlyphs,
}) {
  final sources = <String, dynamic>{};
  final styleLayers = <Map<String, dynamic>>[
    {
      'id': kBackgroundLayerId,
      'type': 'background',
      'paint': {'background-color': '#e8e8e8'},
    },
  ];

  for (final (provider, opacity) in layers) {
    sources[basemapSourceId(provider.id)] = {
      'type': 'raster',
      'tiles': [provider.urlTemplate],
      'tileSize': 256,
      'minzoom': provider.minZoom,
      'maxzoom': provider.maxZoom,
      'attribution': provider.attribution,
    };
    styleLayers.add({
      'id': basemapLayerId(provider.id),
      'type': 'raster',
      'source': basemapSourceId(provider.id),
      'paint': {'raster-opacity': opacity},
    });
  }

  return jsonEncode({
    'version': 8,
    'glyphs': glyphsUrl,
    'sources': sources,
    'layers': styleLayers,
  });
}
