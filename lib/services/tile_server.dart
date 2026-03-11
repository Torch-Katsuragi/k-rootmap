/// ローカルHTTPタイルサーバー
///
/// MapLibreのRasterSourceはhttp/httpsのみ対応のため、
/// BaseMapServiceのキャッシュ機能をlocalhostプロキシ経由で提供する。
library;

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/basemap_provider.dart';
import '../utils/app_logger.dart';
import 'basemap_service.dart';

class TileServer {
  final BaseMapService _baseMapService;
  HttpServer? _server;

  /// オフライン対応: ネットワーク不要なローカルスタイルの file:// URI（遅延初期化）
  static String? _localStyleUri;
  static String? get localStyleUri => _localStyleUri;

  /// 空のローカルスタイルJSONをファイルに書き出しパスを返す。
  /// オフラインでも onStyleLoaded を確実に発火させるための最小スタイル。
  static Future<String> ensureLocalStyle() async {
    if (_localStyleUri != null) return _localStyleUri!;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/k_maps_style.json');
    const style = '{"version":8,"sources":{},'
        '"glyphs":"https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf",'
        '"layers":[{"id":"bg","type":"background","paint":{"background-color":"#e8e8e8"}}]}';
    await file.writeAsString(style);
    _localStyleUri = file.path.startsWith('/') ? file.path : style;
    return _localStyleUri!;
  }

  /// サーバーが待ち受けているポート（起動後に有効）
  int get port => _server?.port ?? 0;

  /// サーバー稼働中か
  bool get isRunning => _server != null;

  TileServer(this._baseMapService);

  /// サーバー起動（ポート0でOS自動割り当て）
  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    AppLogger.debug('[TileServer] started on port $port');
    _server!.listen(_handleRequest);
  }

  /// サーバー停止
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    AppLogger.debug('[TileServer] stopped');
  }

  /// 指定プロバイダのタイルURL テンプレートを返す
  String urlTemplate(String providerId) {
    return 'http://127.0.0.1:$port/tiles/$providerId/{z}/{x}/{y}.png';
  }

  /// 現在のプロバイダのタイルURL テンプレートを返す
  String get currentUrlTemplate =>
      urlTemplate(_baseMapService.currentProvider.id);

  /// リクエスト処理: GET /tiles/{providerId}/{z}/{x}/{y}.{ext}
  Future<void> _handleRequest(HttpRequest request) async {
    // CORSヘッダー（Windows WebView対応）
    request.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET');

    if (request.method == 'OPTIONS') {
      request.response
        ..statusCode = HttpStatus.noContent
        ..close();
      return;
    }

    if (request.method != 'GET') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..close();
      return;
    }

    try {
      final segments = request.uri.pathSegments;
      AppLogger.debug('[TileServer] request: ${request.uri}');
      // /tiles/{providerId}/{z}/{x}/{y}.ext → 5セグメント
      if (segments.length != 5 || segments[0] != 'tiles') {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
        return;
      }

      final providerId = segments[1];
      final z = int.parse(segments[2]);
      final x = int.parse(segments[3]);
      // ファイル名から拡張子を除去
      final yFile = segments[4];
      final y = int.parse(yFile.split('.').first);

      final provider = BaseMapProvider.getProviderById(providerId);
      if (provider == null) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
        return;
      }

      final tileData = await _baseMapService.getTile(provider, z, x, y);

      if (tileData != null && tileData.isNotEmpty) {
        final contentType =
            yFile.endsWith('.jpg') ? 'image/jpeg' : 'image/png';
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.parse(contentType)
          ..add(tileData);
      } else {
        // タイル無し → 透明PNG
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.parse('image/png')
          ..add(BaseMapService.transparentTile);
      }
    } on FormatException {
      request.response.statusCode = HttpStatus.badRequest;
    } catch (e) {
      AppLogger.debug('[TileServer] error: $e');
      request.response.statusCode = HttpStatus.internalServerError;
    } finally {
      await request.response.close();
    }
  }
}
