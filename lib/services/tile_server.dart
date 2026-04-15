/// ローカルHTTPタイルサーバー
///
/// MapLibreのRasterSourceはhttp/httpsのみ対応のため、
/// BaseMapServiceのキャッシュ機能をlocalhostプロキシ経由で提供する。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../models/basemap_provider.dart';
import '../utils/app_logger.dart';
import 'basemap_service.dart';
import 'geotiff_service.dart';

class TileServer {
  final BaseMapService _baseMapService;
  HttpServer? _server;

  /// オフライン対応: ネットワーク不要なローカルスタイルの file:// URI（遅延初期化）
  static String? _localStyleUri;
  static Completer<String>? _localStyleCompleter;
  static String? get localStyleUri => _localStyleUri;

  /// フォントPBFキャッシュディレクトリ（遅延初期化）
  static Directory? _fontCacheDir;

  /// フォントPBFをダウンロード＆キャッシュし、キャッシュディレクトリのパスを返す。
  ///
  /// MapLibreのデフォルトフォント (Open Sans Regular) の全Unicode範囲を先行取得。
  /// 既にキャッシュ済みなら即座にパスを返す。
  /// オフライン時はダウンロードをスキップし、既存キャッシュがあればそのパスを返す。
  static Future<String?> ensureFontCache() async {
    try {
      _fontCacheDir ??= Directory(
        '${(await getTemporaryDirectory()).path}/k_maps_fonts',
      );

      // ディレクトリ名はMapLibreの{fontstack}置換と完全一致させる
      const fontstack = 'Open Sans Semibold';
      final cacheDir = Directory('${_fontCacheDir!.path}/$fontstack');

      // 既にキャッシュ済みならパスを返す
      final testFile = File('${cacheDir.path}/0-255.pbf');
      if (await testFile.exists()) {
        AppLogger.debug('[TileServer] font cache already populated');
        return _fontCacheDir!.path;
      }

      AppLogger.debug('[TileServer] downloading font glyphs...');
      await cacheDir.create(recursive: true);

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);

      try {
        // 必須レンジのみダウンロード（数字・ASCII・日本語の主要範囲）
        // 全256レンジではなく実際に使うものだけに絞る
        final ranges = <String>[
          '0-255',       // Basic Latin (数字、英字、記号)
          '256-511',     // Latin Extended
          '8192-8447',   // General Punctuation
          '12288-12543', // CJK Symbols (日本語句読点等)
          '12544-12799', // Katakana
          '12800-13055', // CJK Compatibility
          '19968-20223', // CJK Unified Ideographs (漢字の一部)
          '20224-20479',
          '20480-20735',
          '65280-65535', // Halfwidth/Fullwidth Forms
        ];

        var cached = 0;
        for (final range in ranges) {
          final file = File('${cacheDir.path}/$range.pbf');
          if (await file.exists()) {
            cached++;
            continue;
          }

          try {
            final url = Uri.parse(
              'https://demotiles.maplibre.org/font/'
              '${Uri.encodeComponent(fontstack)}/$range.pbf',
            );
            AppLogger.debug('[TileServer] fetching font: $url');
            final req = await client.getUrl(url);
            final res = await req.close();
            if (res.statusCode == HttpStatus.ok) {
              final chunks = <int>[];
              await for (final chunk in res) {
                chunks.addAll(chunk);
              }
              await file.writeAsBytes(Uint8List.fromList(chunks));
              cached++;
            } else {
              AppLogger.debug('[TileServer] font HTTP ${res.statusCode}: $range');
              await res.drain<void>();
            }
          } catch (e) {
            AppLogger.debug('[TileServer] font download error ($range): $e');
          }
        }

        AppLogger.debug('[TileServer] font download complete ($cached/${ranges.length} ranges)');
      } finally {
        client.close();
      }

      // ダウンロード後、テストファイルが存在すればパスを返す
      if (await testFile.exists()) {
        return _fontCacheDir!.path;
      }
      return null; // オフライン等でダウンロード失敗
    } catch (e) {
      AppLogger.debug('[TileServer] font cache error: $e');
      return null;
    }
  }

  /// 空のローカルスタイルJSONをファイルに書き出しパスを返す。
  /// オフラインでも onStyleLoaded を確実に発火させるための最小スタイル。
  ///
  /// [fontDir] を渡すと glyphs URL を file:// パスにする。
  /// null の場合はオンラインフォールバック URL を使用。
  static Future<String> ensureLocalStyle({String? fontDir}) async {
    // 毎回再生成（ポート・フォントパスが変わる可能性があるため）
    _localStyleUri = null;

    if (_localStyleCompleter != null) {
      return _localStyleCompleter!.future;
    }

    _localStyleCompleter = Completer<String>();
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/k_maps_style.json');

      // glyphs URL: file:// (キャッシュあり) or オンラインフォールバック
      String glyphsUrl;
      if (fontDir != null) {
        glyphsUrl = 'file://$fontDir/{fontstack}/{range}.pbf';
      } else {
        glyphsUrl = 'https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf';
      }

      AppLogger.debug('[TileServer] glyphs URL: $glyphsUrl');

      final style = '{"version":8,'
          '"glyphs":"$glyphsUrl",'
          '"sources":{},'
          '"layers":[{"id":"bg","type":"background","paint":{"background-color":"#e8e8e8"}}]}';
      await file.writeAsString(style);
      _localStyleUri = file.path.startsWith('/') ? file.path : style;
      _localStyleCompleter!.complete(_localStyleUri!);
      return _localStyleUri!;
    } catch (e) {
      _localStyleCompleter!.completeError(e);
      rethrow;
    } finally {
      _localStyleCompleter = null;
    }
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

  /// オーバーレイ画像のHTTP URLを生成
  /// ローカルファイルパスをHTTP経由で配信するためのURL
  String imageUrlForPath(String absolutePath) {
    final encoded = Uri.encodeComponent(absolutePath);
    return 'http://127.0.0.1:$port/overlay?path=$encoded';
  }

  /// リクエスト処理
  Future<void> _handleRequest(HttpRequest request) async {

    if (request.method != 'GET') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..close();
      return;
    }

    try {
      final segments = request.uri.pathSegments;



      // /overlay?path=... → オーバーレイ画像配信
      if (segments.length == 1 && segments[0] == 'overlay') {
        await _handleOverlayRequest(request);
        return;
      }

      // /tiles/{providerId}/{z}/{x}/{y}.ext → タイル配信
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
        AppLogger.debug('[TileServer] tile not available → transparent fallback');
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

  /// オーバーレイPNG変換キャッシュディレクトリ（遅延初期化）
  static Directory? _overlayCacheDir;

  /// オーバーレイ画像リクエスト処理: `GET /overlay?path=<encoded_path>`
  ///
  /// JPG/PNG: そのまま配信（従来通り）
  /// TIFF/TIF: image pkg でデコード→PNG変換→キャッシュ→配信
  /// MapLibreのImageSourceがTIFF非対応のため、PNG変換を行う。
  Future<void> _handleOverlayRequest(HttpRequest request) async {
    try {
      final filePath = request.uri.queryParameters['path'];
      if (filePath == null || filePath.isEmpty) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..close();
        return;
      }

      final file = File(filePath);
      if (!await file.exists()) {
        AppLogger.debug('[TileServer] overlay file not found: $filePath');
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
        return;
      }

      final ext = filePath.toLowerCase();
      final isTiff = ext.endsWith('.tif') || ext.endsWith('.tiff');

      if (isTiff) {
        // TIFF → PNG変換（キャッシュ付き）
        final pngBytes = await _getOrConvertTiffToPng(filePath, file);
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.parse('image/png')
          ..add(pngBytes);
      } else {
        // JPG/PNG等: そのまま配信
        String contentType;
        if (ext.endsWith('.jpg') || ext.endsWith('.jpeg')) {
          contentType = 'image/jpeg';
        } else if (ext.endsWith('.png')) {
          contentType = 'image/png';
        } else {
          contentType = 'application/octet-stream';
        }

        final bytes = await file.readAsBytes();
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.parse(contentType)
          ..add(bytes);
      }
    } catch (e) {
      AppLogger.debug('[TileServer] overlay error: $e');
      request.response.statusCode = HttpStatus.internalServerError;
    }
  }

  /// TIFF→PNG変換（キャッシュ付き）
  ///
  /// tempディレクトリにPNG変換結果を保存し、
  /// TIFFの更新日時がキャッシュより新しい場合のみ再変換する。
  Future<Uint8List> _getOrConvertTiffToPng(
    String tiffPath,
    File tiffFile,
  ) async {
    _overlayCacheDir ??= Directory(
      '${(await getTemporaryDirectory()).path}/k_maps_overlay_cache',
    );
    await _overlayCacheDir!.create(recursive: true);

    // キャッシュファイル名: パスのSHA1ハッシュ + .png
    final hash = sha1.convert(utf8.encode(tiffPath)).toString();
    final cacheFile = File('${_overlayCacheDir!.path}/$hash.png');

    // キャッシュ有効判定: キャッシュ存在 かつ TIFFより更新日時が新しい
    if (await cacheFile.exists()) {
      final cacheMod = await cacheFile.lastModified();
      final tiffMod = await tiffFile.lastModified();
      if (cacheMod.isAfter(tiffMod)) {
        return cacheFile.readAsBytes();
      }
    }

    // TIFF→PNG変換
    AppLogger.debug('[TileServer] converting TIFF to PNG: $tiffPath');
    final pngBytes = await GeoTiffService.decodeTiffToPng(tiffPath);
    await cacheFile.writeAsBytes(pngBytes, flush: true);
    return pngBytes;
  }


}
