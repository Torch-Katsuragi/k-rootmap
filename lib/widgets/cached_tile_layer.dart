/**
 * キャッシュ機能付きタイルレイヤー
 * 
 * BaseMapServiceと連携してタイルをキャッシュし、オフライン表示を可能にします。
 */

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../models/basemap_provider.dart';
import '../services/basemap_service.dart';

/// キャッシュ機能付きカスタムタイルレイヤー
class CachedTileLayer extends StatelessWidget {
  final BaseMapProvider provider;
  final BaseMapService baseMapService;

  const CachedTileLayer({
    super.key,
    required this.provider,
    required this.baseMapService,
  });

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: provider.urlTemplate,
      userAgentPackageName: provider.userAgentPackageName ?? 'k-maps',
      // フォールバック機能を使用するため、実際のプロバイダー制限より高く設定
      maxZoom: 22.0, // 十分高い値に設定してフォールバック機能を有効化
      minZoom: provider.minZoom.toDouble(),
      tileDimension: 256,
      // flutter_map v8で新しく導入されたカスタムタイルプロバイダーを使用
      tileProvider: CachedTileProvider(
        provider: provider,
        baseMapService: baseMapService,
      ),
    );
  }
}

/// キャッシュ機能付きカスタムタイルプロバイダー
class CachedTileProvider extends TileProvider {
  final BaseMapProvider provider;
  final BaseMapService baseMapService;

  CachedTileProvider({required this.provider, required this.baseMapService});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return CachedTileImageProvider(
      coordinates: coordinates,
      provider: provider,
      baseMapService: baseMapService,
    );
  }
}

/// キャッシュ機能付きカスタムイメージプロバイダー
class CachedTileImageProvider extends ImageProvider<CachedTileImageProvider> {
  final TileCoordinates coordinates;
  final BaseMapProvider provider;
  final BaseMapService baseMapService;

  const CachedTileImageProvider({
    required this.coordinates,
    required this.provider,
    required this.baseMapService,
  });

  @override
  Future<CachedTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<CachedTileImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    CachedTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(_loadTileAsync(decode));
  }

  /// タイルを非同期で読み込み
  Future<ImageInfo> _loadTileAsync(ImageDecoderCallback decode) async {
    try {
      print(
        '[DEBUG] CachedTileImageProvider: タイル読み込み開始 - z=${coordinates.z}, x=${coordinates.x}, y=${coordinates.y}',
      );

      // BaseMapServiceからタイルデータを取得（キャッシュ優先・フォールバック機能付き）
      final tileData = await baseMapService.getTile(
        provider,
        coordinates.z,
        coordinates.x,
        coordinates.y,
      );

      if (tileData != null && tileData.isNotEmpty) {
        print(
          '[DEBUG] CachedTileImageProvider: タイル取得成功 - サイズ: ${tileData.length}バイト',
        );
        final buffer = await ui.ImmutableBuffer.fromUint8List(tileData);
        final codec = await decode(buffer);
        final frame = await codec.getNextFrame();
        return ImageInfo(image: frame.image);
      } else {
        // タイルが取得できない場合は透明な画像を返す
        print('[WARN] CachedTileImageProvider: タイル取得失敗、透明タイルを表示');
        return await _createTransparentTile(decode);
      }
    } catch (e) {
      print('[ERROR] CachedTileImageProvider: タイル読み込み中にエラー - $e');
      return await _createErrorTile(decode);
    }
  }

  /// 透明なタイルを作成
  Future<ImageInfo> _createTransparentTile(ImageDecoderCallback decode) async {
    // 256x256の透明PNGを生成
    final transparentPng = Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x08,
      0x04,
      0x00,
      0x00,
      0x00,
      0x5C,
      0x72,
      0xA8,
      0x66,
      0x00,
      0x00,
      0x00,
      0x0B,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0xF8,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x01,
      0x02,
      0x9A,
      0x65,
      0x1C,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ]);

    final buffer = await ui.ImmutableBuffer.fromUint8List(transparentPng);
    final codec = await decode(buffer);
    final frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image);
  }

  /// エラー表示用タイルを作成
  Future<ImageInfo> _createErrorTile(ImageDecoderCallback decode) async {
    // シンプルな透明タイルをエラー時にも使用
    return await _createTransparentTile(decode);
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is CachedTileImageProvider &&
        other.coordinates == coordinates &&
        other.provider.id == provider.id;
  }

  @override
  int get hashCode => Object.hash(coordinates, provider.id);
}
