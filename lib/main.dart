/*
K-MAPS: 直感的GeoPackage編集・作成モバイルアプリ

【現状の主な機能・構成】
- ホーム画面でプロジェクト新規作成・ローカル/Driveからインポート
- プロジェクトごとにGeoPackageファイルを新規作成・初期化（必須メタテーブル含む）
- 地図表示（OpenStreetMap, flutter_map使用）
- 地図上でのMultiPointフィーチャ描画（タップで追加、属性テキスト入力）
- GPS現在地の取得・表示（ストリームで常時監視、地図上に反映）
- DrawerでGeoPackage/レイヤの2階層構造管理・追加・削除・切替
- レイヤ追加時に種別（MultiPoint・MultiLineString・MultiPolygon）選択、GeoPackageに対応テーブル作成
- BottomNavigationBarでツール切替（地図/GPS/レイヤ）

【主要クラス構成】
- KMapsApp: アプリ本体
- KMapsHomeScreen: ホーム画面（プロジェクト新規作成・既存プロジェクト/DriveインポートUI）
- KMapsHomePage: 地図・レイヤ・フィーチャ編集画面
- LayerManager: GeoPackage/レイヤ全体管理
- GeoPackageGroup: GeoPackage（レイヤグループ）情報
- Layer: レイヤ情報（名前・種別・MultiPointフィーチャリスト）
- _PointFeature: MultiPointフィーチャ（座標＋属性）

【今後の拡張方針】
- MultiLineString・MultiPolygonフィーチャの描画・属性編集
- GeoPackage属性テーブルの編集・表示
- Google Drive連携によるプロジェクト同期
- サブフォルダ・複数GeoPackageの階層的管理
- フリーハンド描画・Undo/Redo・高度な編集ツール

本ファイルはSpaceインデントで統一。
*/
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:path/path.dart' as p; // ファイル名抽出用
import 'dart:typed_data'; // 追加: WKB生成用
import 'dart:math'; // 角度変換・cos用

/// アプリのエントリーポイント
void main() {
  runApp(const KMapsApp());
}

/// K-MAPSアプリ本体
class KMapsApp extends StatelessWidget {
  const KMapsApp({super.key});

  /// MaterialAppのルート設定
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'K-MAPS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const KMapsHomeScreen(),
    );
  }
}

/// ホーム画面（プロジェクト選択・作成）
class KMapsHomeScreen extends StatelessWidget {
  const KMapsHomeScreen({super.key});

  /// GeoPackageファイル新規作成・初期化
  Future<void> _createGeoPackageFile(String path) async {
    final db = sql.sqlite3.open(path);
    // 必須メタテーブル作成（最低限）
    db.execute('''
      CREATE TABLE IF NOT EXISTS gpkg_spatial_ref_sys (
        srs_name TEXT NOT NULL,
        srs_id INTEGER NOT NULL PRIMARY KEY,
        organization TEXT NOT NULL,
        organization_coordsys_id INTEGER NOT NULL,
        definition TEXT NOT NULL,
        description TEXT
      );
    ''');
    db.execute('''
      INSERT OR IGNORE INTO gpkg_spatial_ref_sys (srs_name, srs_id, organization, organization_coordsys_id, definition, description)
      VALUES ('WGS 84 geodetic', 4326, 'EPSG', 4326, 'GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433]]', 'longitude/latitude coordinates in decimal degrees on the WGS 84 spheroid');
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS gpkg_contents (
        table_name TEXT NOT NULL PRIMARY KEY,
        data_type TEXT NOT NULL,
        identifier TEXT UNIQUE,
        description TEXT DEFAULT '',
        last_change DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
        min_x DOUBLE, min_y DOUBLE, max_x DOUBLE, max_y DOUBLE,
        srs_id INTEGER,
        FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS gpkg_geometry_columns (
        table_name TEXT NOT NULL,
        column_name TEXT NOT NULL,
        geometry_type_name TEXT NOT NULL,
        srs_id INTEGER NOT NULL,
        z TINYINT NOT NULL,
        m TINYINT NOT NULL,
        PRIMARY KEY (table_name, column_name),
        FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
      );
    ''');
    db.dispose();
  }

  /// 新規プロジェクト作成処理
  Future<void> _createProject(BuildContext context) async {
    // ディレクトリ選択ダイアログ
    String? basePath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'プロジェクト作成先を選択',
    );
    if (basePath == null) return; // キャンセル
    // プロジェクト名を入力
    String projectName =
        await showDialog<String>(
          context: context,
          builder: (context) {
            String name = '';
            return AlertDialog(
              title: const Text('プロジェクト名を入力'),
              content: TextField(
                autofocus: true,
                decoration: const InputDecoration(labelText: 'プロジェクト名'),
                onChanged: (v) => name = v,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, ''),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, name),
                  child: const Text('作成'),
                ),
              ],
            );
          },
        ) ??
        '';
    if (projectName.isEmpty) return;
    // ディレクトリ作成
    final projectDir = Directory(
      '$basePath${Platform.pathSeparator}$projectName',
    );
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }
    // GeoPackageファイル新規作成
    final gpkgPath = '${projectDir.path}${Platform.pathSeparator}default.gpkg';
    await _createGeoPackageFile(gpkgPath);
    // 新規作成時のみデフォルトレイヤを追加
    final db = sql.sqlite3.open(gpkgPath);
    db.execute('''
      CREATE TABLE IF NOT EXISTS "デフォルトレイヤ" (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        geom BLOB NOT NULL,
        attr TEXT
      );
    ''');
    db.execute(
      '''
      INSERT OR IGNORE INTO gpkg_contents (table_name, data_type, identifier, description, srs_id)
      VALUES (?, 'features', ?, '', 4326);
    ''',
      ['デフォルトレイヤ', 'デフォルトレイヤ'],
    );
    db.execute(
      '''
      INSERT OR IGNORE INTO gpkg_geometry_columns (table_name, column_name, geometry_type_name, srs_id, z, m)
      VALUES (?, 'geom', 'POINT', 4326, 0, 0);
    ''',
      ['デフォルトレイヤ'],
    );
    db.dispose();
    // プロジェクト画面へ遷移時にパスを渡す
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => KMapsHomePage(
              projectDir: projectDir.path,
              defaultGpkgPath: gpkgPath,
            ),
      ),
    );
  }

  /// ローカルプロジェクトを開く処理
  Future<void> _openLocalProject(BuildContext context) async {
    String? dirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'プロジェクトフォルダを選択',
    );
    if (dirPath == null) return;
    // プロジェクトディレクトリ内のgpkgファイルを探す
    final dir = Directory(dirPath);
    final gpkgFiles =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.gpkg'))
            .toList();
    // gpkgがなくてもそのまま地図画面へ遷移
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => KMapsHomePage(
              projectDir: dirPath,
              defaultGpkgPath: gpkgFiles.isNotEmpty ? gpkgFiles.first.path : '',
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('K-MAPS ホーム')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.create_new_folder),
              label: const Text('新規プロジェクト作成'),
              onPressed: () => _createProject(context),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('ローカルのプロジェクトを開く'),
              onPressed: () => _openLocalProject(context),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.cloud_download),
              label: const Text('Google Driveからインポート'),
              onPressed: () async {
                // TODO: Google Driveインポート処理
                // 仮実装: 空パスで開かないよう修正
                await showDialog(
                  context: context,
                  builder:
                      (context) => AlertDialog(
                        title: const Text('未実装'),
                        content: const Text('Google Driveインポートは未実装です。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                );
                //Navigator.push(
                //  context,
                //  MaterialPageRoute(
                //    builder:
                //        (context) =>
                //            KMapsHomePage(projectDir: '', defaultGpkgPath: ''),
                //  ),
                //);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// ホーム画面（地図・MultiPoint描画・属性入力UI）
class KMapsHomePage extends StatefulWidget {
  final String projectDir;
  final String defaultGpkgPath;
  const KMapsHomePage({
    super.key,
    required this.projectDir,
    required this.defaultGpkgPath,
  });

  @override
  State<KMapsHomePage> createState() => _KMapsHomePageState();
}

/// レイヤ種別
enum LayerType { point, line, polygon }

/// ツール種別
enum ToolType { pen, eraser }

/// フィーチャ基底クラス
abstract class Feature {
  String attr;
  Feature(this.attr);
}

/// MultiPointフィーチャ
class MultiPointFeature extends Feature {
  List<LatLng> points;
  MultiPointFeature(this.points, String attr) : super(attr);
}

/// MultiLineStringフィーチャ（複数LineString＋属性）
class MultiLineStringFeature extends Feature {
  List<List<LatLng>> lines;
  MultiLineStringFeature(this.lines, String attr) : super(attr);
}

/// MultiPolygonフィーチャ（複数Polygon＋属性）
class MultiPolygonFeature extends Feature {
  List<List<List<LatLng>>> polygons;
  MultiPolygonFeature(this.polygons, String attr) : super(attr);
}

/// レイヤ情報クラス
class Layer {
  /// レイヤ名
  String name;

  /// フィーチャリスト（MultiPointFeatureのみ対応）
  List<Feature> features;

  /// レイヤ種別
  LayerType type;
  Layer(this.name, this.type, [List<Feature>? features])
    : features = features ?? [];
}

/// GeoPackage（レイヤグループ）情報クラス
class GeoPackageGroup {
  /// ファイル名（絶対パス）
  String path;

  /// レイヤリスト
  List<Layer> layers;

  /// 展開状態
  bool expanded;
  GeoPackageGroup(this.path, [List<Layer>? layers, this.expanded = true])
    : layers = layers ?? [];
}

/// GeoPackage/レイヤ全体管理クラス
class LayerManager {
  /// GeoPackageグループリスト
  final List<GeoPackageGroup> geoPackages = [];

  /// 選択中GeoPackageインデックス（-1は未選択）
  int selectedGpIndex = -1;

  /// 選択中レイヤインデックス（-1は未選択）
  int selectedLayerIndex = -1;

  /// GeoPackage追加
  void addGeoPackage(String path) {
    if (path.isEmpty || !File(path).existsSync()) return;
    final group = GeoPackageGroup(path);
    final db = sql.sqlite3.open(path);
    final contents = db.select(
      'SELECT table_name FROM gpkg_contents WHERE data_type = "features"',
    );
    for (final row in contents) {
      final tableName = row['table_name'] as String;
      final geomRows = db.select(
        'SELECT geometry_type_name FROM gpkg_geometry_columns WHERE table_name = ?',
        [tableName],
      );
      if (geomRows.isEmpty) continue;
      final geomType = geomRows.first['geometry_type_name'] as String;
      LayerType type;
      if (geomType == 'POINT') {
        type = LayerType.point;
      } else if (geomType == 'LINESTRING') {
        type = LayerType.line;
      } else if (geomType == 'POLYGON') {
        type = LayerType.polygon;
      } else {
        continue;
      }
      // DBから復元: LayerTypeごとに分岐
      final features = <Feature>[];
      final rows = db.select('SELECT geom, attr FROM "$tableName"');
      for (final r in rows) {
        final geom = r['geom'] as Uint8List;
        final attr = r['attr'] as String? ?? '';
        if (type == LayerType.point) {
          // WKBからMultiPointFeature復元（現状は1点のみ対応、今後複数点対応可）
          if (geom.length >= 21 && geom[0] == 1 && geom[1] == 1) {
            final lon = ByteData.sublistView(
              geom,
              5,
              13,
            ).getFloat64(0, Endian.little);
            final lat = ByteData.sublistView(
              geom,
              13,
              21,
            ).getFloat64(0, Endian.little);
            features.add(MultiPointFeature([LatLng(lat, lon)], attr));
          }
        } else if (type == LayerType.line) {
          // WKBからMultiLineStringFeature復元
          final line = parseWkbLineString(geom);
          if (line.isNotEmpty) {
            features.add(MultiLineStringFeature([line], attr));
          }
        } else if (type == LayerType.polygon) {
          // WKBからMultiPolygonFeature復元
          final rings = parseWkbPolygon(geom);
          if (rings.isNotEmpty) {
            features.add(MultiPolygonFeature([rings], attr));
          }
        }
      }
      group.layers.add(Layer(tableName, type, features));
    }
    db.dispose();
    geoPackages.add(group);
    selectedGpIndex = geoPackages.length - 1;
    selectedLayerIndex = group.layers.isNotEmpty ? 0 : -1;
  }

  /// GeoPackage削除
  void removeGeoPackage(int index) {
    geoPackages.removeAt(index);
    if (geoPackages.isEmpty) {
      selectedGpIndex = -1;
      selectedLayerIndex = -1;
      return;
    }
    if (selectedGpIndex >= geoPackages.length) {
      selectedGpIndex = geoPackages.length - 1;
    }
    if (geoPackages[selectedGpIndex].layers.isEmpty) {
      selectedLayerIndex = -1;
    } else {
      selectedLayerIndex = 0;
    }
  }

  /// レイヤ追加
  void addLayer(int gpIndex, String name, LayerType type) {
    final gpkgPath = geoPackages[gpIndex].path;
    geoPackages[gpIndex].layers.add(Layer(name, type));
    selectedGpIndex = gpIndex;
    selectedLayerIndex = geoPackages[gpIndex].layers.length - 1;
    _createFeatureTableInGeoPackage(gpkgPath, name, type);
  }

  /// レイヤ削除
  void removeLayer(int gpIndex, int layerIndex) {
    final gpkgPath = geoPackages[gpIndex].path;
    final tableName = geoPackages[gpIndex].layers[layerIndex].name;
    final db = sql.sqlite3.open(gpkgPath);
    db.execute('DROP TABLE IF EXISTS "$tableName";');
    db.execute('DELETE FROM gpkg_contents WHERE table_name = ?;', [tableName]);
    db.execute('DELETE FROM gpkg_geometry_columns WHERE table_name = ?;', [
      tableName,
    ]);
    db.dispose();
    geoPackages[gpIndex].layers.removeAt(layerIndex);
    if (geoPackages[gpIndex].layers.isEmpty) {
      selectedLayerIndex = -1;
      return;
    }
    if (selectedLayerIndex >= geoPackages[gpIndex].layers.length) {
      selectedLayerIndex = geoPackages[gpIndex].layers.length - 1;
    }
  }

  /// レイヤ選択
  void selectLayer(int gpIndex, int layerIndex) {
    selectedGpIndex = gpIndex;
    selectedLayerIndex = layerIndex;
  }

  /// 選択中レイヤ取得（存在しない場合はnull）
  Layer? get currentLayer {
    if (selectedGpIndex < 0 || selectedGpIndex >= geoPackages.length) {
      return null;
    }
    final gp = geoPackages[selectedGpIndex];
    if (selectedLayerIndex < 0 || selectedLayerIndex >= gp.layers.length) {
      return null;
    }
    return gp.layers[selectedLayerIndex];
  }

  /// GeoPackageにFeatureテーブルを作成
  void _createFeatureTableInGeoPackage(
    String gpkgPath,
    String tableName,
    LayerType type,
  ) {
    final db = sql.sqlite3.open(gpkgPath);
    final geomType =
        type == LayerType.point
            ? 'POINT'
            : type == LayerType.line
            ? 'LINESTRING'
            : 'POLYGON';
    // Featureテーブル作成
    db.execute('''
      CREATE TABLE IF NOT EXISTS "$tableName" (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        geom BLOB NOT NULL,
        attr TEXT
      );
    ''');
    // gpkg_contents登録
    db.execute(
      '''
      INSERT OR IGNORE INTO gpkg_contents (table_name, data_type, identifier, description, srs_id)
      VALUES (?, 'features', ?, '', 4326);
    ''',
      [tableName, tableName],
    );
    // gpkg_geometry_columns登録
    db.execute(
      '''
      INSERT OR IGNORE INTO gpkg_geometry_columns (table_name, column_name, geometry_type_name, srs_id, z, m)
      VALUES (?, 'geom', ?, 4326, 0, 0);
    ''',
      [tableName, geomType],
    );
    db.dispose();
  }

  /// 選択中レイヤにMultiPointを追加（DBにも保存）
  void addPointToCurrentLayer(LatLng latlng, String attr) {
    if (currentLayer == null) return;
    final gpkgPath = geoPackages[selectedGpIndex].path;
    final tableName = currentLayer!.name;
    final db = sql.sqlite3.open(gpkgPath);
    final wkb = createWkbPoint(latlng.longitude, latlng.latitude);
    db.execute('INSERT INTO "$tableName" (geom, attr) VALUES (?, ?);', [
      wkb,
      attr,
    ]);
    db.dispose();
    currentLayer!.features.add(MultiPointFeature([latlng], attr));
  }

  /// 選択中レイヤから最も近いMultiPointを削除（DBにも反映）
  void removeNearestPointFromCurrentLayer(
    LatLng tapLatLng,
    double maxDistanceMeter,
  ) {
    if (currentLayer == null || currentLayer!.type != LayerType.point) return;
    final features = currentLayer!.features.cast<MultiPointFeature>();
    if (features.isEmpty) return;

    int? nearestFeatureIdx;
    int? nearestPointIdx;
    double minDist = double.infinity;
    final dist = const Distance();

    for (int fi = 0; fi < features.length; fi++) {
      final points = features[fi].points;
      for (int pi = 0; pi < points.length; pi++) {
        final d = dist(tapLatLng, points[pi]);
        if (d < minDist) {
          minDist = d;
          nearestFeatureIdx = fi;
          nearestPointIdx = pi;
        }
      }
    }

    if (nearestFeatureIdx != null &&
        nearestPointIdx != null &&
        minDist <= maxDistanceMeter) {
      final feature = features[nearestFeatureIdx];
      final point = feature.points[nearestPointIdx];
      final attr = feature.attr;
      // DBからも削除
      final gpkgPath = geoPackages[selectedGpIndex].path;
      final tableName = currentLayer!.name;
      final db = sql.sqlite3.open(gpkgPath);
      final wkb = createWkbPoint(point.longitude, point.latitude);
      db.execute('DELETE FROM "$tableName" WHERE geom = ? AND attr = ?;', [
        wkb,
        attr,
      ]);
      db.dispose();
      feature.points.removeAt(nearestPointIdx);
      // もしpointsが空になったらfeatures自体も削除
      if (feature.points.isEmpty) {
        currentLayer!.features.remove(feature);
      }
    }
  }

  /// 選択中レイヤにMultiLineStringを追加（DBにも保存）
  void addLineToCurrentLayer(List<LatLng> line, String attr) {
    if (currentLayer == null) return;
    final gpkgPath = geoPackages[selectedGpIndex].path;
    final tableName = currentLayer!.name;
    final db = sql.sqlite3.open(gpkgPath);
    final wkb = createWkbLineString(line);
    db.execute('INSERT INTO "$tableName" (geom, attr) VALUES (?, ?);', [
      wkb,
      attr,
    ]);
    db.dispose();
    currentLayer!.features.add(MultiLineStringFeature([line], attr));
  }

  /// 選択中レイヤにMultiPolygonを追加（DBにも保存）
  void addPolygonToCurrentLayer(List<List<LatLng>> rings, String attr) {
    if (currentLayer == null) return;
    final gpkgPath = geoPackages[selectedGpIndex].path;
    final tableName = currentLayer!.name;
    final db = sql.sqlite3.open(gpkgPath);
    final wkb = createWkbPolygon(rings);
    db.execute('INSERT INTO "$tableName" (geom, attr) VALUES (?, ?);', [
      wkb,
      attr,
    ]);
    db.dispose();
    currentLayer!.features.add(MultiPolygonFeature([rings], attr));
  }
}

/// WKB(Point)生成ユーティリティ
Uint8List createWkbPoint(double lon, double lat) {
  // リトルエンディアン: 0x01
  // ジオメトリタイプ: 1 (POINT)
  final bytes = BytesBuilder();
  bytes.addByte(0x01); // little endian
  bytes.add([0x01, 0x00, 0x00, 0x00]); // type=1 (POINT)
  final bdata = ByteData(16);
  bdata.setFloat64(0, lon, Endian.little); // X=lon
  bdata.setFloat64(8, lat, Endian.little); // Y=lat
  bytes.add(bdata.buffer.asUint8List());
  return bytes.toBytes();
}

/// WKB(LineString)生成ユーティリティ
/// 引数: 線分の座標リスト（必ず2点以上）
/// 戻り値: WKBバイト列（リトルエンディアン）
Uint8List createWkbLineString(List<LatLng> line) {
  // リトルエンディアン: 0x01
  // ジオメトリタイプ: 2 (LINESTRING)
  // 構造: 1byte(Endian) + 4byte(type) + 4byte(点数) + 各点(16byte)
  final bytes = BytesBuilder();
  bytes.addByte(0x01); // little endian
  bytes.add([0x02, 0x00, 0x00, 0x00]); // type=2 (LINESTRING)
  final n = line.length;
  final nBytes = ByteData(4)..setUint32(0, n, Endian.little);
  bytes.add(nBytes.buffer.asUint8List());
  for (final pt in line) {
    final bdata = ByteData(16);
    bdata.setFloat64(0, pt.longitude, Endian.little); // X=lon
    bdata.setFloat64(8, pt.latitude, Endian.little); // Y=lat
    bytes.add(bdata.buffer.asUint8List());
  }
  return bytes.toBytes();
}

/// WKB(Polygon)生成ユーティリティ
/// 引数: 複数のリング（外環＋穴）の座標リスト（各リングは3点以上）
/// 戻り値: WKBバイト列（リトルエンディアン）
Uint8List createWkbPolygon(List<List<LatLng>> rings) {
  // リトルエンディアン: 0x01
  // ジオメトリタイプ: 3 (POLYGON)
  // 構造: 1byte(Endian) + 4byte(type) + 4byte(リング数) + 各リング(4byte点数+各点16byte)
  final bytes = BytesBuilder();
  bytes.addByte(0x01); // little endian
  bytes.add([0x03, 0x00, 0x00, 0x00]); // type=3 (POLYGON)
  final nRings = rings.length;
  final nRingsBytes = ByteData(4)..setUint32(0, nRings, Endian.little);
  bytes.add(nRingsBytes.buffer.asUint8List());
  for (final ring in rings) {
    final nPts = ring.length;
    final nPtsBytes = ByteData(4)..setUint32(0, nPts, Endian.little);
    bytes.add(nPtsBytes.buffer.asUint8List());
    for (final pt in ring) {
      final bdata = ByteData(16);
      bdata.setFloat64(0, pt.longitude, Endian.little); // X=lon
      bdata.setFloat64(8, pt.latitude, Endian.little); // Y=lat
      bytes.add(bdata.buffer.asUint8List());
    }
  }
  return bytes.toBytes();
}

/// WKB(LineString)デコードユーティリティ
/// 引数: WKBバイト列
/// 戻り値: List<LatLng>（線分の座標リスト）
List<LatLng> parseWkbLineString(Uint8List wkb) {
  // 1byte(Endian) + 4byte(type) + 4byte(点数) + 各点(16byte)
  if (wkb.length < 9) return [];
  final n = ByteData.sublistView(wkb, 5, 9).getUint32(0, Endian.little);
  final pts = <LatLng>[];
  for (int i = 0; i < n; i++) {
    final offset = 9 + i * 16;
    if (offset + 16 > wkb.length) break;
    final lon = ByteData.sublistView(
      wkb,
      offset,
      offset + 8,
    ).getFloat64(0, Endian.little);
    final lat = ByteData.sublistView(
      wkb,
      offset + 8,
      offset + 16,
    ).getFloat64(0, Endian.little);
    pts.add(LatLng(lat, lon));
  }
  return pts;
}

/// WKB(Polygon)デコードユーティリティ
/// 引数: WKBバイト列
/// 戻り値: List<List<LatLng>>（外環＋穴の座標リスト）
List<List<LatLng>> parseWkbPolygon(Uint8List wkb) {
  // 1byte(Endian) + 4byte(type) + 4byte(リング数) + 各リング(4byte点数+各点16byte)
  if (wkb.length < 9) return [];
  final nRings = ByteData.sublistView(wkb, 5, 9).getUint32(0, Endian.little);
  int offset = 9;
  final rings = <List<LatLng>>[];
  for (int r = 0; r < nRings; r++) {
    if (offset + 4 > wkb.length) break;
    final nPts = ByteData.sublistView(
      wkb,
      offset,
      offset + 4,
    ).getUint32(0, Endian.little);
    offset += 4;
    final ring = <LatLng>[];
    for (int i = 0; i < nPts; i++) {
      if (offset + 16 > wkb.length) break;
      final lon = ByteData.sublistView(
        wkb,
        offset,
        offset + 8,
      ).getFloat64(0, Endian.little);
      final lat = ByteData.sublistView(
        wkb,
        offset + 8,
        offset + 16,
      ).getFloat64(0, Endian.little);
      ring.add(LatLng(lat, lon));
      offset += 16;
    }
    rings.add(ring);
  }
  return rings;
}

class _KMapsHomePageState extends State<KMapsHomePage> {
  /// 地図中心座標（初期値: 東京駅）
  final LatLng _center = const LatLng(35.681236, 139.767125);

  /// 線・ポリゴン描画用一時リスト
  final List<LatLng> _drawingLine = [];
  final List<LatLng> _drawingPolygon = [];

  /// 地図上のMultiPointフィーチャリスト
  final List<MultiPointFeature> _points = [];

  /// 現在地
  LatLng? _currentLocation;

  /// 現在地ストリーム購読用
  Stream<Position>? _positionStream;
  StreamSubscription<Position>? _positionSubscription; // 購読解除用

  /// 地図コントローラ
  final MapController _mapController = MapController();

  ToolType _selectedTool = ToolType.pen; // ツール選択状態

  int _selectedBottomIndex = 0; // ボトムナビゲーションの選択インデックス

  final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>(); // Scaffold用グローバルキー

  final LayerManager _layerManager = LayerManager();

  /// プロジェクトフォルダツリー（サブフォルダ・GeoPackage含む）
  FolderNode? _folderTree;

  /// カレントディレクトリ（Drawerエクスプローラ用）
  late String _currentDirPath;

  @override
  void initState() {
    super.initState();
    _currentDirPath = widget.projectDir;
    // プロジェクトフォルダツリー構築
    _folderTree = scanProjectFolder(widget.projectDir);
    // デフォルトGeoPackageが指定されていれば追加
    if (widget.defaultGpkgPath.isNotEmpty &&
        File(widget.defaultGpkgPath).existsSync()) {
      _layerManager.addGeoPackage(widget.defaultGpkgPath);
      // --- ここでデフォルトレイヤを自動追加しない ---
      // 既存GeoPackageの場合はDB内のレイヤのみ反映
      // 新規作成時のみ、KMapsHomeScreen._createProjectで明示的に追加する
    }
    // 現在地ストリームを購読し、位置が変わるたびに反映
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    _positionSubscription = _positionStream!.listen((pos) {
      setState(() {
        _currentLocation = LatLng(pos.latitude, pos.longitude);
      });
    });
  }

  @override
  void dispose() {
    // ストリーム購読解除
    _positionSubscription?.cancel();
    super.dispose();
  }

  /// 「現在地に移動」ボタン押下時の処理
  void _moveToCurrentLocation() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 16.0);
    }
  }

  /// 地図タップでMultiPoint/MultiLineString/MultiPolygonフィーチャ追加/削除（ツール・レイヤ種別で切替）
  void _onMapTap(TapPosition tapPosition, LatLng latlng) async {
    final layer = _layerManager.currentLayer;
    if (layer == null) return;
    if (layer.type == LayerType.point) {
      if (_selectedTool == ToolType.pen) {
        // ペン: MultiPoint追加
        String? attr = await showDialog<String>(
          context: context,
          builder: (context) {
            String text = '';
            return AlertDialog(
              title: const Text('属性入力'),
              content: TextField(
                autofocus: true,
                decoration: const InputDecoration(labelText: '属性（テキスト）'),
                onChanged: (v) => text = v,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, text),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
        if (attr != null && attr.isNotEmpty) {
          setState(() {
            _layerManager.addPointToCurrentLayer(latlng, attr);
          });
        }
      } else if (_selectedTool == ToolType.eraser) {
        // 消しゴム: 一定距離以内で最も近いMultiPointを削除
        // 地図の表示範囲から距離閾値を決定
        final mapBox = context.findRenderObject() as RenderBox?;
        double maxDist = 30.0; // デフォルト30m
        if (mapBox != null) {
          final size = mapBox.size;
          // 画面幅の1/20を地図上の距離に換算
          final map = _mapController;
          final center = map.center;
          final zoom = map.zoom;
          // 1ピクセルあたりのメートル換算（大雑把）
          // 公式: 156543.03392 * cos(lat) / 2^zoom (m/px)
          final metersPerPx =
              156543.03392 *
              cos(center.latitude.abs() * pi / 180) /
              (1 << zoom.toInt());
          maxDist = (size.width / 20) * metersPerPx;
          if (maxDist < 10) maxDist = 10; // 最小10m
          if (maxDist > 100) maxDist = 100; // 最大100m
        }
        setState(() {
          _layerManager.removeNearestPointFromCurrentLayer(latlng, maxDist);
        });
      }
    } else if (layer.type == LayerType.line) {
      if (_selectedTool == ToolType.pen) {
        // 線: 一時リストに点追加
        setState(() {
          _drawingLine.add(latlng);
        });
      } else if (_selectedTool == ToolType.eraser) {
        // 線: 全LineStringの全点から最も近い点を削除
        final features = layer.features.cast<MultiLineStringFeature>();
        if (features.isEmpty) return;
        int? nearestFeatureIdx;
        int? nearestPointIdx;
        double minDist = double.infinity;
        final dist = const Distance();
        for (int fi = 0; fi < features.length; fi++) {
          final line = features[fi].lines.first;
          for (int pi = 0; pi < line.length; pi++) {
            final d = dist(latlng, line[pi]);
            if (d < minDist) {
              minDist = d;
              nearestFeatureIdx = fi;
              nearestPointIdx = pi;
            }
          }
        }
        if (nearestFeatureIdx != null &&
            nearestPointIdx != null &&
            minDist <= 100) {
          setState(() {
            final feature = features[nearestFeatureIdx!];
            feature.lines.first.removeAt(nearestPointIdx!);
            if (feature.lines.first.isEmpty) {
              layer.features.remove(feature);
            }
          });
        }
      }
    } else if (layer.type == LayerType.polygon) {
      if (_selectedTool == ToolType.pen) {
        // ポリゴン: 一時リストに点追加
        setState(() {
          _drawingPolygon.add(latlng);
        });
      } else if (_selectedTool == ToolType.eraser) {
        // ポリゴン: 全Polygonの外環の全点から最も近い点を削除
        final features = layer.features.cast<MultiPolygonFeature>();
        if (features.isEmpty) return;
        int? nearestFeatureIdx;
        int? nearestPointIdx;
        double minDist = double.infinity;
        final dist = const Distance();
        for (int fi = 0; fi < features.length; fi++) {
          final ring = features[fi].polygons.first.first;
          for (int pi = 0; pi < ring.length; pi++) {
            final d = dist(latlng, ring[pi]);
            if (d < minDist) {
              minDist = d;
              nearestFeatureIdx = fi;
              nearestPointIdx = pi;
            }
          }
        }
        if (nearestFeatureIdx != null &&
            nearestPointIdx != null &&
            minDist <= 100) {
          setState(() {
            final feature = features[nearestFeatureIdx!];
            feature.polygons.first.first.removeAt(nearestPointIdx!);
            if (feature.polygons.first.first.isEmpty) {
              layer.features.remove(feature);
            }
          });
        }
      }
    }
  }

  /// ボトムナビゲーションタップ時の処理
  void _onBottomNavTapped(int index) async {
    setState(() {
      _selectedBottomIndex = index;
    });
    if (index == 0) {
      // ツールアイコン: ポップアップメニュー
      final RenderBox barBox = context.findRenderObject() as RenderBox;
      final Size barSize = barBox.size;
      final double iconWidth = barSize.width / 3;
      final Offset iconOffset = Offset(
        iconWidth * index + iconWidth / 2,
        barSize.height,
      );
      final RelativeRect position = RelativeRect.fromLTRB(
        iconOffset.dx, // left
        barSize.height, // top
        barSize.width - iconOffset.dx, // right
        0, // bottom
      );
      final selected = await showMenu<ToolType>(
        context: context,
        position: position,
        items: [
          PopupMenuItem(
            value: ToolType.pen,
            child: Row(
              children: [
                Icon(Icons.brush, color: Colors.black),
                SizedBox(width: 8),
                Text('ペン'),
              ],
            ),
          ),
          PopupMenuItem(
            value: ToolType.eraser,
            child: Row(
              children: [
                Icon(Icons.auto_fix_normal, color: Colors.black),
                SizedBox(width: 8),
                Text('消しゴム'),
              ],
            ),
          ),
        ],
      );
      if (selected != null) {
        setState(() {
          _selectedTool = selected;
        });
      }
    } else if (index == 1) {
      // GPSアイコン: フキダシ型メニュー
      final RenderBox barBox = context.findRenderObject() as RenderBox;
      final Size barSize = barBox.size;
      final double iconWidth = barSize.width / 3;
      final Offset iconOffset = Offset(
        iconWidth * index + iconWidth / 2,
        barSize.height,
      );
      final RelativeRect position = RelativeRect.fromLTRB(
        iconOffset.dx, // left
        barSize.height, // top
        barSize.width - iconOffset.dx, // right
        0, // bottom
      );
      await showMenu(
        context: context,
        position: position,
        items: [
          const PopupMenuItem(value: 'high', child: Text('GPS精度: 高')),
          const PopupMenuItem(value: 'low', child: Text('GPS精度: 低')),
          const PopupMenuItem(value: 'history', child: Text('位置履歴を表示')),
        ],
      );
    } else if (index == 2) {
      // レイヤアイコン: 右側からDrawerを開く（GlobalKey経由）
      _scaffoldKey.currentState?.openEndDrawer();
    }
  }

  /// GeoPackageファイル新規作成・初期化（Drawerからの新規作成用）
  Future<void> _createGeoPackageFile(String path) async {
    final db = sql.sqlite3.open(path);
    db.execute('''
      CREATE TABLE IF NOT EXISTS gpkg_spatial_ref_sys (
        srs_name TEXT NOT NULL,
        srs_id INTEGER NOT NULL PRIMARY KEY,
        organization TEXT NOT NULL,
        organization_coordsys_id INTEGER NOT NULL,
        definition TEXT NOT NULL,
        description TEXT
      );
    ''');
    db.execute('''
      INSERT OR IGNORE INTO gpkg_spatial_ref_sys (srs_name, srs_id, organization, organization_coordsys_id, definition, description)
      VALUES ('WGS 84 geodetic', 4326, 'EPSG', 4326, 'GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433]]', 'longitude/latitude coordinates in decimal degrees on the WGS 84 spheroid');
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS gpkg_contents (
        table_name TEXT NOT NULL PRIMARY KEY,
        data_type TEXT NOT NULL,
        identifier TEXT UNIQUE,
        description TEXT DEFAULT '',
        last_change DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
        min_x DOUBLE, min_y DOUBLE, max_x DOUBLE, max_y DOUBLE,
        srs_id INTEGER,
        FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS gpkg_geometry_columns (
        table_name TEXT NOT NULL,
        column_name TEXT NOT NULL,
        geometry_type_name TEXT NOT NULL,
        srs_id INTEGER NOT NULL,
        z TINYINT NOT NULL,
        m TINYINT NOT NULL,
        PRIMARY KEY (table_name, column_name),
        FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
      );
    ''');
    db.dispose();
  }

  /// メインUI
  @override
  Widget build(BuildContext context) {
    final layer = _layerManager.currentLayer;
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('K-MAPS フェーズ1'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _moveToCurrentLocation,
            tooltip: '現在地に移動',
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: _currentLocation ?? _center,
              zoom: 16.0,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.k_maps',
              ),
              PolygonLayer(
                polygons: [
                  // MultiPolygonFeatureの各Polygon（外環＋穴対応）
                  ...?_layerManager.currentLayer?.features
                      .whereType<MultiPolygonFeature>()
                      .expand(
                        (f) => f.polygons.map(
                          (poly) => Polygon(
                            points: closeRing(poly.first), // 外環
                            holePointsList:
                                poly.length > 1
                                    ? poly
                                        .sublist(1)
                                        .map(closeRing)
                                        .toList() // 内環（穴）
                                    : null,
                            color: Colors.orange.withOpacity(0.4),
                            borderColor: Colors.orange,
                            borderStrokeWidth: 2.5,
                            isFilled: true,
                          ),
                        ),
                      ),
                  // ポリゴン描画中のプレビュー
                  if (_layerManager.currentLayer?.type == LayerType.polygon &&
                      _drawingPolygon.length >= 3)
                    Polygon(
                      points: closeRing(_drawingPolygon),
                      color: Colors.orange.withOpacity(0.2),
                      borderColor: Colors.orange,
                      borderStrokeWidth: 2.0,
                      isFilled: true,
                    ),
                ],
              ),
              PolylineLayer(
                polylines: [
                  // MultiLineStringFeatureの各LineString
                  ...?_layerManager.currentLayer?.features
                      .whereType<MultiLineStringFeature>()
                      .expand(
                        (f) => f.lines.map(
                          (line) => Polyline(
                            points: line,
                            color: Colors.green,
                            strokeWidth: 2.5,
                          ),
                        ),
                      ),
                  // 線描画中のプレビュー
                  if (_layerManager.currentLayer?.type == LayerType.line &&
                      _drawingLine.length >= 2)
                    Polyline(
                      points: _drawingLine,
                      color: Colors.green.withOpacity(0.5),
                      strokeWidth: 3.0,
                      isDotted: true,
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  // MultiPoint
                  ...?_layerManager.currentLayer?.features
                      .whereType<MultiPointFeature>()
                      .where((f) => f.points.isNotEmpty)
                      .map(
                        (f) => Marker(
                          point: f.points.first,
                          width: 40,
                          height: 40,
                          child: Tooltip(
                            message: f.attr,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.red,
                              size: 36,
                            ),
                          ),
                        ),
                      ),
                  // 現在地
                  if (_currentLocation != null)
                    Marker(
                      point: _currentLocation!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.blue,
                        size: 32,
                      ),
                    ),
                  // ポリゴン描画中の一時点もマーカーで表示
                  ..._drawingPolygon.map(
                    (pt) => Marker(
                      point: pt,
                      width: 28,
                      height: 28,
                      child: const Icon(
                        Icons.edit,
                        color: Colors.orange,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_layerManager.currentLayer == null)
            Positioned(
              top: 32,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 24,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 8),
                    ],
                  ),
                  child: Text(
                    'GeoPackageやレイヤがありません。Drawerから追加してください。',
                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                  ),
                ),
              ),
            ),
          // 線・ポリゴン描画中は「確定」ボタン
          if (layer != null &&
              _selectedTool == ToolType.pen &&
              ((layer.type == LayerType.line && _drawingLine.length >= 2) ||
                  (layer.type == LayerType.polygon &&
                      _drawingPolygon.length >= 3)))
            Positioned(
              bottom: 32,
              right: 32,
              child: FloatingActionButton.extended(
                icon: const Icon(Icons.check),
                label: Text(layer.type == LayerType.line ? '線を確定' : 'ポリゴンを確定'),
                onPressed: () async {
                  String? attr = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      String text = '';
                      return AlertDialog(
                        title: Text(
                          layer.type == LayerType.line ? '線の属性入力' : 'ポリゴンの属性入力',
                        ),
                        content: TextField(
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: '属性（テキスト）',
                          ),
                          onChanged: (v) => text = v,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, null),
                            child: const Text('キャンセル'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, text),
                            child: const Text('OK'),
                          ),
                        ],
                      );
                    },
                  );
                  if (attr != null && attr.isNotEmpty) {
                    setState(() {
                      if (layer.type == LayerType.line) {
                        _layerManager.addLineToCurrentLayer(
                          List<LatLng>.from(_drawingLine),
                          attr,
                        );
                        _drawingLine.clear();
                      } else if (layer.type == LayerType.polygon) {
                        _layerManager.addPolygonToCurrentLayer([
                          List<LatLng>.from(_drawingPolygon),
                        ], attr);
                        _drawingPolygon.clear();
                      }
                    });
                  }
                },
              ),
            ),
        ],
      ),
      endDrawer: Drawer(
        child: Builder(
          builder: (context) {
            final dir = Directory(_currentDirPath);
            final entities = dir.existsSync() ? dir.listSync() : [];
            final folders = entities.where((e) => e is Directory).toList();
            final gpkgFiles =
                entities
                    .where((e) => e is File && e.path.endsWith('.gpkg'))
                    .toList();
            final isRoot = p.equals(_currentDirPath, widget.projectDir);
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                const SizedBox(
                  height: 56,
                  child: DrawerHeader(
                    decoration: BoxDecoration(color: Colors.blue),
                    margin: EdgeInsets.zero,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'レイヤ構造',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ),
                  ),
                ),
                // 親ディレクトリに戻る
                if (!isRoot)
                  ListTile(
                    leading: const Icon(Icons.arrow_upward),
                    title: const Text('.. 親フォルダへ'),
                    onTap: () {
                      setState(() {
                        _currentDirPath = p.dirname(_currentDirPath);
                      });
                    },
                  ),
                // サブフォルダ一覧
                ...folders.map(
                  (f) => ListTile(
                    leading: const Icon(Icons.folder, color: Colors.amber),
                    title: Text(p.basename(f.path)),
                    onTap: () {
                      setState(() {
                        _currentDirPath = f.path;
                      });
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          tooltip: 'フォルダ名変更',
                          onPressed: () async {
                            String? newName = await showDialog<String>(
                              context: context,
                              builder: (context) {
                                String text = p.basename(f.path);
                                return AlertDialog(
                                  title: const Text('フォルダ名を編集'),
                                  content: TextField(
                                    autofocus: true,
                                    controller: TextEditingController(
                                      text: text,
                                    ),
                                    decoration: const InputDecoration(
                                      labelText: '新しいフォルダ名',
                                    ),
                                    onChanged: (v) => text = v,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(context, null),
                                      child: const Text('キャンセル'),
                                    ),
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(context, text),
                                      child: const Text('保存'),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (newName != null &&
                                newName.isNotEmpty &&
                                newName != p.basename(f.path)) {
                              final newDir = Directory(
                                p.join(p.dirname(f.path), newName),
                              );
                              if (await newDir.exists()) {
                                await showDialog(
                                  context: context,
                                  builder:
                                      (context) => AlertDialog(
                                        title: const Text('エラー'),
                                        content: const Text('同名のフォルダが既に存在します。'),
                                        actions: [
                                          TextButton(
                                            onPressed:
                                                () => Navigator.pop(context),
                                            child: const Text('OK'),
                                          ),
                                        ],
                                      ),
                                );
                                return;
                              }
                              await Directory(f.path).rename(newDir.path);
                              setState(() {});
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          tooltip: '空フォルダ削除',
                          onPressed: () async {
                            final dir = Directory(f.path);
                            if (dir.listSync().isNotEmpty) {
                              await showDialog(
                                context: context,
                                builder:
                                    (context) => AlertDialog(
                                      title: const Text('削除不可'),
                                      content: const Text('空でないフォルダは削除できません。'),
                                      actions: [
                                        TextButton(
                                          onPressed:
                                              () => Navigator.pop(context),
                                          child: const Text('OK'),
                                        ),
                                      ],
                                    ),
                              );
                              return;
                            }
                            final ok = await showDialog<bool>(
                              context: context,
                              builder:
                                  (context) => AlertDialog(
                                    title: const Text('フォルダ削除'),
                                    content: Text(
                                      '「${p.basename(f.path)}」を削除しますか？',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed:
                                            () => Navigator.pop(context, false),
                                        child: const Text('キャンセル'),
                                      ),
                                      TextButton(
                                        onPressed:
                                            () => Navigator.pop(context, true),
                                        child: const Text('削除'),
                                      ),
                                    ],
                                  ),
                            );
                            if (ok == true) {
                              await dir.delete();
                              setState(() {});
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                // GeoPackageファイル一覧
                ...gpkgFiles.map((f) {
                  final gpkgPath = f.path;
                  final gpIdx = _layerManager.geoPackages.indexWhere(
                    (g) => g.path == gpkgPath,
                  );
                  if (gpIdx == -1) {
                    _layerManager.addGeoPackage(gpkgPath);
                  }
                  final gp = _layerManager.geoPackages.firstWhere(
                    (g) => g.path == gpkgPath,
                  );
                  final gpIdx2 = _layerManager.geoPackages.indexOf(gp);
                  return ExpansionTile(
                    title: Row(
                      children: [
                        const Icon(
                          Icons.storage,
                          color: Colors.blueGrey,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _InlineEditGpkgName(
                            initialName: p.basename(gp.path),
                            dirPath: p.dirname(gp.path),
                            existingNames:
                                _layerManager.geoPackages
                                    .map((g) => p.basename(g.path))
                                    .toList(),
                            onRename: (newName) {
                              final dir = p.dirname(gp.path);
                              final ext = p.extension(gp.path);
                              final newBase =
                                  newName.endsWith(ext)
                                      ? newName.substring(
                                        0,
                                        newName.length - ext.length,
                                      )
                                      : newName;
                              final newPath = p.join(dir, '$newBase$ext');
                              if (gp.path == newPath) return;
                              File(gp.path).renameSync(newPath);
                              setState(() {
                                gp.path = newPath;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          tooltip: 'GeoPackage削除',
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder:
                                  (context) => AlertDialog(
                                    title: const Text('GeoPackage削除'),
                                    content: Text(
                                      '「${p.basename(gp.path)}」を削除しますか？\nファイル自体も完全に削除されます。',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed:
                                            () => Navigator.pop(context, false),
                                        child: const Text('キャンセル'),
                                      ),
                                      TextButton(
                                        onPressed:
                                            () => Navigator.pop(context, true),
                                        child: const Text('削除'),
                                      ),
                                    ],
                                  ),
                            );
                            if (ok == true) {
                              try {
                                File(gp.path).deleteSync();
                              } catch (_) {}
                              setState(() {
                                _layerManager.removeGeoPackage(gpIdx2);
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    initiallyExpanded: gp.expanded,
                    onExpansionChanged: (v) => setState(() => gp.expanded = v),
                    children: [
                      // レイヤ一覧
                      ...List.generate(gp.layers.length, (lIdx) {
                        final isSelected =
                            gpIdx2 == _layerManager.selectedGpIndex &&
                            lIdx == _layerManager.selectedLayerIndex;
                        return ListTile(
                          leading: GestureDetector(
                            onTap: () {
                              setState(() {
                                _layerManager.selectLayer(gpIdx2, lIdx);
                              });
                              Navigator.pop(context);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border:
                                    isSelected
                                        ? Border.all(
                                          color: Colors.blue,
                                          width: 3,
                                        )
                                        : null,
                              ),
                              child: Icon(
                                _layerTypeIcon(gp.layers[lIdx].type),
                                color:
                                    isSelected ? Colors.blue : Colors.grey[700],
                                size: 28,
                              ),
                            ),
                          ),
                          title: Text(
                            gp.layers[lIdx].name,
                            style: TextStyle(
                              fontWeight:
                                  isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                              color: isSelected ? Colors.blue : null,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            tooltip: 'レイヤ削除',
                            onPressed: () {
                              setState(() {
                                _layerManager.removeLayer(gpIdx2, lIdx);
                              });
                            },
                          ),
                          onTap: () {
                            setState(() {
                              _layerManager.selectLayer(gpIdx2, lIdx);
                            });
                            Navigator.pop(context);
                          },
                        );
                      }),
                      // 新規レイヤ作成
                      ListTile(
                        leading: const Icon(Icons.add),
                        title: const Text('新規レイヤ作成'),
                        onTap: () async {
                          String? name;
                          LayerType? type;
                          await showDialog<void>(
                            context: context,
                            builder: (context) {
                              String text = '';
                              LayerType selectedType = LayerType.point;
                              return StatefulBuilder(
                                builder: (context, setState) {
                                  return AlertDialog(
                                    title: const Text('レイヤ名・種別を入力'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextField(
                                          autofocus: true,
                                          decoration: const InputDecoration(
                                            labelText: 'レイヤ名',
                                          ),
                                          onChanged: (v) => text = v,
                                        ),
                                        const SizedBox(height: 12),
                                        DropdownButton<LayerType>(
                                          value: selectedType,
                                          items: const [
                                            DropdownMenuItem(
                                              value: LayerType.point,
                                              child: Text('MultiPointレイヤ'),
                                            ),
                                            DropdownMenuItem(
                                              value: LayerType.line,
                                              child: Text('MultiLineStringレイヤ'),
                                            ),
                                            DropdownMenuItem(
                                              value: LayerType.polygon,
                                              child: Text('MultiPolygonレイヤ'),
                                            ),
                                          ],
                                          onChanged:
                                              (v) => setState(
                                                () => selectedType = v!,
                                              ),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('キャンセル'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          name = text;
                                          type = selectedType;
                                          Navigator.pop(context);
                                        },
                                        child: const Text('作成'),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          );
                          if (name != null &&
                              name!.isNotEmpty &&
                              type != null) {
                            setState(() {
                              _layerManager.addLayer(gpIdx2, name!, type!);
                            });
                          }
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  );
                }),
                // 新規サブフォルダ作成
                ListTile(
                  leading: const Icon(Icons.create_new_folder),
                  title: const Text('サブフォルダ新規作成'),
                  onTap: () async {
                    String? name = await showDialog<String>(
                      context: context,
                      builder: (context) {
                        String text = '';
                        return AlertDialog(
                          title: const Text('サブフォルダ名を入力'),
                          content: TextField(
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'サブフォルダ名',
                            ),
                            onChanged: (v) => text = v,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, null),
                              child: const Text('キャンセル'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, text),
                              child: const Text('作成'),
                            ),
                          ],
                        );
                      },
                    );
                    if (name != null && name.isNotEmpty) {
                      final newDir = Directory(p.join(_currentDirPath, name));
                      if (await newDir.exists()) {
                        await showDialog(
                          context: context,
                          builder:
                              (context) => AlertDialog(
                                title: const Text('エラー'),
                                content: const Text('同名のフォルダが既に存在します。'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                        );
                        return;
                      }
                      await newDir.create(recursive: true);
                      setState(() {});
                    }
                  },
                ),
                // 新規GeoPackage作成
                ListTile(
                  leading: const Icon(Icons.add_box),
                  title: const Text('GeoPackage新規作成'),
                  onTap: () async {
                    String? name = await showDialog<String>(
                      context: context,
                      builder: (context) {
                        String text = '';
                        return AlertDialog(
                          title: const Text('GeoPackage名を入力'),
                          content: TextField(
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'GeoPackage名（.gpkg）',
                            ),
                            onChanged: (v) => text = v,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, null),
                              child: const Text('キャンセル'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, text),
                              child: const Text('作成'),
                            ),
                          ],
                        );
                      },
                    );
                    if (name != null && name.isNotEmpty) {
                      final gpkgPath =
                          '${widget.projectDir}${Platform.pathSeparator}${name.endsWith('.gpkg') ? name : '$name.gpkg'}';
                      await _createGeoPackageFile(gpkgPath);
                      setState(() {
                        _layerManager.addGeoPackage(gpkgPath);
                      });
                    }
                    Navigator.pop(context); // Drawer閉じる
                  },
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedBottomIndex,
        onTap: _onBottomNavTapped,
        items: [
          BottomNavigationBarItem(
            icon: Icon(
              _selectedTool == ToolType.pen
                  ? Icons.brush
                  : Icons.auto_fix_normal,
            ),
            label: 'ツール',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.gps_fixed),
            label: 'GPS',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.layers), label: 'レイヤ'),
        ],
      ),
    );
  }

  /// フォルダツリーを再帰的にExpansionTileで展開するWidgetリストを生成
  List<Widget> _buildFolderTreeTiles(FolderNode node) {
    final tiles = <Widget>[];
    // サブフォルダ
    for (final sub in node.subfolders) {
      tiles.add(
        ExpansionTile(
          title: Row(
            children: [
              const Icon(Icons.folder, color: Colors.amber, size: 20),
              const SizedBox(width: 4),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    // フォルダ名リネーム
                    String? newName = await showDialog<String>(
                      context: context,
                      builder: (context) {
                        String text = sub.name;
                        return AlertDialog(
                          title: const Text('フォルダ名を編集'),
                          content: TextField(
                            autofocus: true,
                            controller: TextEditingController(text: text),
                            decoration: const InputDecoration(
                              labelText: '新しいフォルダ名',
                            ),
                            onChanged: (v) => text = v,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, null),
                              child: const Text('キャンセル'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, text),
                              child: const Text('保存'),
                            ),
                          ],
                        );
                      },
                    );
                    if (newName != null &&
                        newName.isNotEmpty &&
                        newName != sub.name) {
                      final parentDir = Directory(node.path);
                      final oldDir = Directory(sub.path);
                      final newDir = Directory(p.join(parentDir.path, newName));
                      if (await newDir.exists()) {
                        await showDialog(
                          context: context,
                          builder:
                              (context) => AlertDialog(
                                title: const Text('エラー'),
                                content: const Text('同名のフォルダが既に存在します。'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                        );
                        return;
                      }
                      await oldDir.rename(newDir.path);
                      setState(() {
                        // 再スキャンで反映
                        _folderTree = scanProjectFolder(widget.projectDir);
                      });
                    }
                  },
                  child: Text(
                    sub.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              // サブフォルダ新規作成
              IconButton(
                icon: const Icon(Icons.create_new_folder, size: 18),
                tooltip: 'サブフォルダ作成',
                onPressed: () async {
                  String? name = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      String text = '';
                      return AlertDialog(
                        title: const Text('サブフォルダ名を入力'),
                        content: TextField(
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'サブフォルダ名',
                          ),
                          onChanged: (v) => text = v,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, null),
                            child: const Text('キャンセル'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, text),
                            child: const Text('作成'),
                          ),
                        ],
                      );
                    },
                  );
                  if (name != null && name.isNotEmpty) {
                    final newDir = Directory(p.join(sub.path, name));
                    if (await newDir.exists()) {
                      await showDialog(
                        context: context,
                        builder:
                            (context) => AlertDialog(
                              title: const Text('エラー'),
                              content: const Text('同名のフォルダが既に存在します。'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                      );
                      return;
                    }
                    await newDir.create(recursive: true);
                    setState(() {
                      _folderTree = scanProjectFolder(widget.projectDir);
                    });
                  }
                },
              ),
              // フォルダ削除（空フォルダのみ）
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: '空フォルダ削除',
                onPressed: () async {
                  final dir = Directory(sub.path);
                  if (dir.listSync().isNotEmpty) {
                    await showDialog(
                      context: context,
                      builder:
                          (context) => AlertDialog(
                            title: const Text('削除不可'),
                            content: const Text('空でないフォルダは削除できません。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                    );
                    return;
                  }
                  final ok = await showDialog<bool>(
                    context: context,
                    builder:
                        (context) => AlertDialog(
                          title: const Text('フォルダ削除'),
                          content: Text('「${sub.name}」を削除しますか？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('キャンセル'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('削除'),
                            ),
                          ],
                        ),
                  );
                  if (ok == true) {
                    await dir.delete();
                    setState(() {
                      _folderTree = scanProjectFolder(widget.projectDir);
                    });
                  }
                },
              ),
              // サブフォルダ内でGeoPackage新規作成
              IconButton(
                icon: const Icon(Icons.add_box, size: 18),
                tooltip: 'このフォルダにGeoPackage新規作成',
                onPressed: () async {
                  String? name = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      String text = '';
                      return AlertDialog(
                        title: const Text('GeoPackage名を入力'),
                        content: TextField(
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'GeoPackage名（.gpkg）',
                          ),
                          onChanged: (v) => text = v,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, null),
                            child: const Text('キャンセル'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, text),
                            child: const Text('作成'),
                          ),
                        ],
                      );
                    },
                  );
                  if (name != null && name.isNotEmpty) {
                    final gpkgPath = p.join(
                      sub.path,
                      name.endsWith('.gpkg') ? name : '$name.gpkg',
                    );
                    if (await File(gpkgPath).exists()) {
                      await showDialog(
                        context: context,
                        builder:
                            (context) => AlertDialog(
                              title: const Text('エラー'),
                              content: const Text('同名のGeoPackageが既に存在します。'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                      );
                      return;
                    }
                    await _createGeoPackageFile(gpkgPath);
                    setState(() {
                      _layerManager.addGeoPackage(gpkgPath);
                      _layerManager.addLayer(
                        _layerManager.geoPackages.length - 1,
                        '新規レイヤ',
                        LayerType.point,
                      );
                      _folderTree = scanProjectFolder(widget.projectDir);
                    });
                  }
                },
              ),
            ],
          ),
          children: _buildFolderTreeTiles(sub),
        ),
      );
    }
    // このフォルダ直下のGeoPackage
    for (final gpkgPath in node.gpkgFiles) {
      // 既存のGeoPackageGroupを検索
      final gpIdx = _layerManager.geoPackages.indexWhere(
        (g) => g.path == gpkgPath,
      );
      if (gpIdx == -1) {
        // 未登録なら追加
        _layerManager.addGeoPackage(gpkgPath);
      }
      final gp = _layerManager.geoPackages.firstWhere(
        (g) => g.path == gpkgPath,
      );
      final gpIdx2 = _layerManager.geoPackages.indexOf(gp);
      tiles.add(
        ExpansionTile(
          title: Row(
            children: [
              const Icon(Icons.storage, color: Colors.blueGrey, size: 18),
              const SizedBox(width: 4),
              Expanded(
                child: _InlineEditGpkgName(
                  initialName: p.basename(gp.path),
                  dirPath: p.dirname(gp.path),
                  existingNames:
                      _layerManager.geoPackages
                          .map((g) => p.basename(g.path))
                          .toList(),
                  onRename: (newName) {
                    final dir = p.dirname(gp.path);
                    final ext = p.extension(gp.path);
                    final newBase =
                        newName.endsWith(ext)
                            ? newName.substring(0, newName.length - ext.length)
                            : newName;
                    final newPath = p.join(dir, '$newBase$ext');
                    if (gp.path == newPath) return;
                    File(gp.path).renameSync(newPath);
                    setState(() {
                      gp.path = newPath;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete),
                tooltip: 'GeoPackage削除',
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder:
                        (context) => AlertDialog(
                          title: const Text('GeoPackage削除'),
                          content: Text(
                            '「${p.basename(gp.path)}」を削除しますか？\nファイル自体も完全に削除されます。',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('キャンセル'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('削除'),
                            ),
                          ],
                        ),
                  );
                  if (ok == true) {
                    try {
                      File(gp.path).deleteSync();
                    } catch (_) {}
                    setState(() {
                      _layerManager.removeGeoPackage(gpIdx2);
                    });
                  }
                },
              ),
            ],
          ),
          initiallyExpanded: gp.expanded,
          onExpansionChanged: (v) => setState(() => gp.expanded = v),
          children: [
            // レイヤ一覧
            ...List.generate(gp.layers.length, (lIdx) {
              final isSelected =
                  gpIdx2 == _layerManager.selectedGpIndex &&
                  lIdx == _layerManager.selectedLayerIndex;
              return ListTile(
                leading: GestureDetector(
                  onTap: () {
                    setState(() {
                      _layerManager.selectLayer(gpIdx2, lIdx);
                    });
                    Navigator.pop(context);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          isSelected
                              ? Border.all(color: Colors.blue, width: 3)
                              : null,
                    ),
                    child: Icon(
                      _layerTypeIcon(gp.layers[lIdx].type),
                      color: isSelected ? Colors.blue : Colors.grey[700],
                      size: 28,
                    ),
                  ),
                ),
                title: Text(
                  gp.layers[lIdx].name,
                  style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.blue : null,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: 'レイヤ削除',
                  onPressed: () {
                    setState(() {
                      _layerManager.removeLayer(gpIdx2, lIdx);
                    });
                  },
                ),
                onTap: () {
                  setState(() {
                    _layerManager.selectLayer(gpIdx2, lIdx);
                  });
                  Navigator.pop(context);
                },
              );
            }),
            // 新規レイヤ作成
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('新規レイヤ作成'),
              onTap: () async {
                String? name;
                LayerType? type;
                await showDialog<void>(
                  context: context,
                  builder: (context) {
                    String text = '';
                    LayerType selectedType = LayerType.point;
                    return StatefulBuilder(
                      builder: (context, setState) {
                        return AlertDialog(
                          title: const Text('レイヤ名・種別を入力'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                autofocus: true,
                                decoration: const InputDecoration(
                                  labelText: 'レイヤ名',
                                ),
                                onChanged: (v) => text = v,
                              ),
                              const SizedBox(height: 12),
                              DropdownButton<LayerType>(
                                value: selectedType,
                                items: const [
                                  DropdownMenuItem(
                                    value: LayerType.point,
                                    child: Text('MultiPointレイヤ'),
                                  ),
                                  DropdownMenuItem(
                                    value: LayerType.line,
                                    child: Text('MultiLineStringレイヤ'),
                                  ),
                                  DropdownMenuItem(
                                    value: LayerType.polygon,
                                    child: Text('MultiPolygonレイヤ'),
                                  ),
                                ],
                                onChanged:
                                    (v) => setState(() => selectedType = v!),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('キャンセル'),
                            ),
                            TextButton(
                              onPressed: () {
                                name = text;
                                type = selectedType;
                                Navigator.pop(context);
                              },
                              child: const Text('作成'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
                if (name != null && name!.isNotEmpty && type != null) {
                  setState(() {
                    _layerManager.addLayer(gpIdx2, name!, type!);
                  });
                }
                Navigator.pop(context);
              },
            ),
          ],
        ),
      );
    }
    return tiles;
  }
}

/// GeoPackage名インライン編集用Widget
class _InlineEditGpkgName extends StatefulWidget {
  final String initialName;
  final String dirPath;
  final void Function(String newName) onRename;
  final List<String> existingNames;
  const _InlineEditGpkgName({
    required this.initialName,
    required this.dirPath,
    required this.onRename,
    required this.existingNames,
  });
  @override
  State<_InlineEditGpkgName> createState() => _InlineEditGpkgNameState();
}

class _InlineEditGpkgNameState extends State<_InlineEditGpkgName> {
  bool editing = false;
  late TextEditingController controller;
  String? errorText;
  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _submit() {
    final newName = controller.text.trim();
    if (newName.isEmpty) {
      setState(() => errorText = '空欄不可');
      return;
    }
    if (newName != widget.initialName &&
        widget.existingNames.contains(newName)) {
      setState(() => errorText = '同名ファイルが存在');
      return;
    }
    if (newName != widget.initialName) {
      widget.onRename(newName);
    }
    setState(() {
      editing = false;
      errorText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return editing
        ? SizedBox(
          width: 140,
          child: Focus(
            onFocusChange: (hasFocus) {
              if (!hasFocus) _submit();
            },
            child: TextField(
              controller: controller,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                isDense: true,
                errorText: errorText,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 8,
                ),
              ),
            ),
          ),
        )
        : GestureDetector(
          onTap:
              () => setState(() {
                editing = true;
              }),
          child: Text(
            widget.initialName,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        );
  }
}

/// レイヤ名インライン編集用Widget
class _InlineEditLayerName extends StatefulWidget {
  final String initialName;
  final void Function(String newName) onRename;
  final List<String> existingNames;
  const _InlineEditLayerName({
    required this.initialName,
    required this.onRename,
    required this.existingNames,
  });
  @override
  State<_InlineEditLayerName> createState() => _InlineEditLayerNameState();
}

class _InlineEditLayerNameState extends State<_InlineEditLayerName> {
  bool editing = false;
  late TextEditingController controller;
  String? errorText;
  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _submit() {
    final newName = controller.text.trim();
    if (newName.isEmpty) {
      setState(() => errorText = '空欄不可');
      return;
    }
    if (newName != widget.initialName &&
        widget.existingNames.contains(newName)) {
      setState(() => errorText = '同名レイヤが存在');
      return;
    }
    if (newName != widget.initialName) {
      widget.onRename(newName);
    }
    setState(() {
      editing = false;
      errorText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return editing
        ? SizedBox(
          width: 120,
          child: Focus(
            onFocusChange: (hasFocus) {
              if (!hasFocus) _submit();
            },
            child: TextField(
              controller: controller,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                isDense: true,
                errorText: errorText,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 8,
                ),
              ),
            ),
          ),
        )
        : GestureDetector(
          onTap:
              () => setState(() {
                editing = true;
              }),
          child: Text(
            widget.initialName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
  }
}

// ポリゴン点列を自動で閉じるユーティリティ（値比較）
List<LatLng> closeRing(List<LatLng> pts) {
  if (pts.length < 3) return [];
  final first = pts.first;
  final last = pts.last;
  bool isClosed =
      (first.latitude == last.latitude) && (first.longitude == last.longitude);
  if (!isClosed) {
    return List<LatLng>.from(pts)..add(first);
  }
  return pts;
}

/// プロジェクトフォルダ・サブフォルダ・GeoPackageファイルのツリー構造ノード
class FolderNode {
  /// フォルダ名
  final String name;

  /// フォルダの絶対パス
  final String path;

  /// サブフォルダリスト
  final List<FolderNode> subfolders;

  /// このフォルダ直下の.gpkgファイル（絶対パス）
  final List<String> gpkgFiles;
  FolderNode(
    this.name,
    this.path, {
    this.subfolders = const [],
    this.gpkgFiles = const [],
  });
}

/// 指定ディレクトリ配下を再帰的に探索し、FolderNodeツリーを構築
FolderNode scanProjectFolder(String dirPath) {
  final dir = Directory(dirPath);
  final subfolders = <FolderNode>[];
  final gpkgFiles = <String>[];
  for (var entity in dir.listSync()) {
    if (entity is Directory) {
      subfolders.add(scanProjectFolder(entity.path));
    } else if (entity is File && entity.path.endsWith('.gpkg')) {
      gpkgFiles.add(entity.path);
    }
  }
  return FolderNode(
    p.basename(dirPath),
    dirPath,
    subfolders: subfolders,
    gpkgFiles: gpkgFiles,
  );
}

// レイヤ種別ごとのアイコン取得関数
IconData _layerTypeIcon(LayerType type) {
  switch (type) {
    case LayerType.point:
      return Icons.location_on;
    case LayerType.line:
      return Icons.show_chart;
    case LayerType.polygon:
      return Icons.pentagon;
  }
}
