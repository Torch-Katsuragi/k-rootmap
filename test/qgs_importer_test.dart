// `.qgs` インポータ（寛容側）のテスト
//
// 「読むときは寛容に」を機械的に確かめる。他人が作ったファイルは
// 古い形式で来るし、こちらでは開けない参照も混ざっている。
// **飲めるぶんだけ取り込み、飲めなかったものは必ず報告する**のが要件。
//
// ここで検証するのは、ツリーもDBも要らない純粋な部分:
//   1. OGRのデータソース文字列の分解（subset に `|` が入っても壊れない）
//   2. QGIS 3.x の `<Option>` と、それ以前の `<prop>` の両方を読む
//   3. 単位（QGISはMM、RootMapはpx）と色（R,G,B,A）の変換
//
// ツリーに View を差し込む経路は DB とファイルシステムが要るため、
// integration_test 側の担当（[[docs/technical/qgis-interop]]）。
import 'package:flutter_test/flutter_test.dart';
import 'package:root_maps/models/kmeta.dart';
import 'package:root_maps/services/qgis/qgs_importer.dart';
import 'package:xml/xml.dart';

/// `<maplayer>` のXMLからスタイルを読む（テスト用の薄いラッパー）
KMetaLayerStyle? readStyleForTest(String maplayerXml) =>
    const QgsImporter().readStyle(XmlDocument.parse(maplayerXml).rootElement);

void main() {
  group('データソース文字列の分解', () {
    test('パスとレイヤ名を取り出す', () {
      final source = QgsDataSource.parse('./林小班.gpkg|layername=rinshoban');
      expect(source, isNotNull);
      expect(source!.path, './林小班.gpkg');
      expect(source.layerName, 'rinshoban');
      expect(source.subset, isNull);
    });

    test('subset を取り出す', () {
      final source = QgsDataSource.parse(
        "./a.gpkg|layername=t|subset=\"樹種\" = 'スギ'",
      );
      expect(source!.subset, '"樹種" = \'スギ\'');
    });

    test('subset の中に | があっても壊れない', () {
      // SQLに `|` は普通に入る（文字列連結の `||` など）
      final source = QgsDataSource.parse(
        "./a.gpkg|layername=t|subset=name || '_' = 'x_'",
      );
      expect(source!.layerName, 't');
      expect(source.subset, "name || '_' = 'x_'");
    });

    test('layername より前のキーがあっても読む', () {
      final source = QgsDataSource.parse(
        './a.gpkg|layerid=0|layername=t|geometrytype=Point',
      );
      expect(source!.layerName, 't');
    });

    test('絶対パスもそのまま返す（root外判定は呼び出し側の仕事）', () {
      final source = QgsDataSource.parse(r'C:\work\data.gpkg|layername=t');
      expect(source!.path, r'C:\work\data.gpkg');
    });

    test('空なら null', () {
      expect(QgsDataSource.parse(''), isNull);
      expect(QgsDataSource.parse('   '), isNull);
    });
  });

  group('レンダラの読み取り', () {
    /// QGIS 3.x が書く形（`<Option>`）
    const modernPoint = '''
<maplayer type="vector" geometry="Point">
  <id>l1</id>
  <datasource>./a.gpkg|layername=t</datasource>
  <layername>スギ</layername>
  <provider>ogr</provider>
  <renderer-v2 type="singleSymbol">
    <symbols>
      <symbol name="0" type="marker">
        <layer class="SimpleMarker">
          <Option type="Map">
            <Option name="color" type="QString" value="30,144,255,255"/>
            <Option name="size" type="QString" value="4"/>
          </Option>
        </layer>
      </symbol>
    </symbols>
  </renderer-v2>
</maplayer>
''';

    /// QGIS 3.x より前が書く形（`<prop>`）。**他人のファイルはこれで来る**
    const legacyLine = '''
<maplayer type="vector" geometry="Line">
  <id>l2</id>
  <datasource>./a.gpkg|layername=t</datasource>
  <layername>路網</layername>
  <provider>ogr</provider>
  <renderer-v2 type="singleSymbol">
    <symbols>
      <symbol name="0" type="line">
        <layer class="SimpleLine">
          <prop k="line_color" v="255,0,0,255"/>
          <prop k="line_width" v="1.06"/>
        </layer>
      </symbol>
    </symbols>
  </renderer-v2>
</maplayer>
''';

    test('新しい形式（Option）を読む', () {
      final style = readStyleForTest(modernPoint);
      expect(style, isNotNull);
      expect(style!.pointColor?.toARGB32(), 0xFF1E90FF);
      // QGIS の size は直径(MM)、RootMap は半径感覚の px
      expect(style.pointSize, closeTo(4 * 96 / 25.4 / 2, 0.01));
    });

    test('古い形式（prop）も読む', () {
      final style = readStyleForTest(legacyLine);
      expect(style, isNotNull);
      expect(style!.lineColor?.toARGB32(), 0xFFFF0000);
      expect(style.lineWidth, closeTo(1.06 * 96 / 25.4, 0.01));
    });

    test('塗りは色と不透明度を分けて拾う', () {
      const fill = '''
<maplayer>
  <renderer-v2 type="singleSymbol">
    <symbols>
      <symbol name="0" type="fill">
        <layer class="SimpleFill">
          <prop k="color" v="255,127,0,128"/>
          <prop k="outline_color" v="0,0,0,255"/>
          <prop k="outline_width" v="0.26"/>
        </layer>
      </symbol>
    </symbols>
  </renderer-v2>
</maplayer>
''';
      final style = readStyleForTest(fill);
      expect(style!.polygonFillColor?.toARGB32(), 0xFFFF7F00,
          reason: '色は不透明で持ち、透明度は別フィールドに分ける');
      expect(style.polygonFillOpacity, closeTo(128 / 255, 0.01));
      expect(style.polygonBorderOpacity, 1.0);
    });

    test('レンダラが無ければ null（QGISの既定に任せる）', () {
      final style = readStyleForTest(
        '<maplayer><layername>x</layername></maplayer>',
      );
      expect(style, isNull);
    });

    test('知らないシンボル型は null（黙って壊れた見た目にしない）', () {
      const weird = '''
<maplayer>
  <renderer-v2 type="singleSymbol">
    <symbols>
      <symbol name="0" type="hairline">
        <layer class="Whatever"><prop k="color" v="1,2,3,4"/></layer>
      </symbol>
    </symbols>
  </renderer-v2>
</maplayer>
''';
      expect(readStyleForTest(weird), isNull);
    });
  });
}
