// ピアの圏外区間軌跡（gap backfill 受信側）の変換テスト
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:root_maps/models/party/peer_track.dart';
import 'package:root_maps/services/party/polyline_codec.dart';

void main() {
  group('PeerTrack.fromMap', () {
    final points = [
      const LatLng(34.0, 135.9),
      const LatLng(34.001, 135.901),
      const LatLng(34.002, 135.903),
    ];

    test('エンコード済みポリラインをデコードして復元する', () {
      final track = PeerTrack.fromMap('u1', {
        'pts': PolylineCodec.encode(points),
        'from': 1000,
        'to': 2000,
      });
      expect(track, isNotNull);
      expect(track!.uid, 'u1');
      expect(track.fromMs, 1000);
      expect(track.toMs, 2000);
      expect(track.points, hasLength(3));
      expect(track.points.first.latitude, closeTo(34.0, 1e-4));
      expect(track.points.last.longitude, closeTo(135.903, 1e-4));
    });

    test('欠損・型不正は null（読むときは寛容に）', () {
      expect(PeerTrack.fromMap('u1', {'from': 1, 'to': 2}), isNull);
      expect(
        PeerTrack.fromMap('u1', {'pts': 123, 'from': 1, 'to': 2}),
        isNull,
      );
      expect(
        PeerTrack.fromMap('u1', {'pts': 'x', 'from': '1', 'to': 2}),
        isNull,
      );
    });

    test('1点しか無い軌跡は null（線にならない）', () {
      final track = PeerTrack.fromMap('u1', {
        'pts': PolylineCodec.encode([const LatLng(34, 135)]),
        'from': 1,
        'to': 2,
      });
      expect(track, isNull);
    });
  });
}
