// K-MAPS: カメラ撮影画面
// camerawesomeパッケージを使用して、安定したカメラ機能を提供
import 'dart:async';
import 'dart:io';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // SystemChrome用
import 'package:geolocator/geolocator.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path/path.dart' as p;
import 'package:latlong2/latlong.dart';
import '../models/nodes/folder_node.dart';
import '../models/nodes/photo_node.dart';

/// カメラ撮影画面
class CameraScreen extends StatefulWidget {
  /// 写真の保存先フォルダ
  final FolderNode targetFolder;

  const CameraScreen({
    super.key,
    required this.targetFolder,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  
  // 処理中のフラグ
  bool _isProcessing = false;
  // 撮影が行われたかどうか（戻るボタンで更新をかけるため）
  bool _hasCaptured = false;
  // 処理済みの画像パスを保持するセット（重複処理防止）
  final Set<String> _processedPaths = {};

  // ズーム制御用
  double _currentZoom = 0.0;
  double _startZoom = 0.0;
  
  @override
  void initState() {
    super.initState();
    // 画面回転を許可
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // 必要であれば固定に戻すが、地図アプリなので全方向許可のままで良いかもしれない
    // SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // ステータスバー領域などの背景色
      // 戻るボタンでの終了時に撮影フラグを返す
      body: PopScope(
        canPop: false,
        onPopInvoked: (didPop) async {
          if (didPop) return;
          Navigator.pop(context, _hasCaptured);
        },
        child: CameraAwesomeBuilder.custom(
          saveConfig: SaveConfig.photo(
          pathBuilder: (sensors) async {
            // 一時ファイルパスを生成
            final now = DateTime.now();
            final timestamp = now.toIso8601String().replaceAll(':', '-').split('.').first;
            final fileName = 'IMG_$timestamp.jpg';
            
            final folderPath = widget.targetFolder.getAbsoluteFilePath();
            final dirPath = folderPath ?? Directory.systemTemp.path;
            
            // 決定前の仮ファイルとして保存
            return SingleCaptureRequest(p.join(dirPath, 'TEMP_$fileName'), sensors.first);
          },
        ),
        sensorConfig: SensorConfig.single(
          sensor: Sensor.position(SensorPosition.back),
          flashMode: FlashMode.auto,
          aspectRatio: CameraAspectRatios.ratio_4_3,
          zoom: 0.0,
        ),
        // CameraLayoutBuilderのシグネチャに合わせる
        builder: (state, preview) {
          // カスタムUIを構築
          return Stack(
            children: [
              // ピンチズーム用ジェスチャー検知（プレビューの上に配置）
              Positioned.fill(
                child: GestureDetector(
                  onScaleStart: (details) {
                    // ジェスチャー開始時のズームレベルを保持
                    _startZoom = _currentZoom;
                  },
                  onScaleUpdate: (details) {
                    // details.scale は開始時からの累積拡大率 (1.0基準)
                    // 線形で加算する方式に変更 (指に追従しやすくする)
                    
                    // 感度係数: 画面サイズやセンサー特性によるが、1.0前後が自然
                    const sensitivity = 0.8; 
                    
                    final delta = (details.scale - 1.0) * sensitivity;
                    final newZoom = (_startZoom + delta).clamp(0.0, 1.0);
                    
                    // 状態更新して反映
                    if (newZoom != _currentZoom) {
                      state.sensorConfig.setZoom(newZoom);
                      _currentZoom = newZoom;
                    }
                  },
                ),
              ),

              // 上部アクション（フラッシュ切り替えなど）
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: AwesomeTopActions(state: state),
                ),
              ),
              
              // 下部アクション（撮影ボタンなど）
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    color: Colors.transparent, // 背景色なしに変更（プレビューを隠さないため）
                    padding: const EdgeInsets.only(bottom: 16, top: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // 戻るボタン
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 32),
                          onPressed: () => Navigator.pop(context, _hasCaptured),
                        ),
                        
                        // 撮影ボタン
                        AwesomeCaptureButton(state: state),
                        
                        // カメラ切り替えボタン
                        AwesomeCameraSwitchButton(state: state),
                      ],
                    ),
                  ),
                ),
              ),
              
              // メディア撮影後の処理をフックするためのリスナー
              StreamBuilder<MediaCapture?>(
                stream: state.captureState$,
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data != null) {
                    final mediaCapture = snapshot.data!;
                    // 処理中でなく、かつ撮影成功時のみ処理を実行
                    if (!_isProcessing && mediaCapture.status == MediaCaptureStatus.success && mediaCapture.isPicture) {
                      // ビルド完了後に処理を実行するためにaddPostFrameCallbackを使用
                      // 注: StreamBuilderは何度もイベントを受け取る可能性があるため、
                      // 一度処理を開始したらフラグでガードし、かつキャプチャIDなどを確認するのがベストだが、
                      // ここでは簡易的にフラグでガードする。
                      
                      // 重要な修正: 
                      // _isProcessingフラグのチェックは addPostFrameCallback の外で行わないと、
                      // 複数回のイベントに対してすべてコールバックが登録されてしまう可能性がある。
                      // さらに、処理が完了して _isProcessing が false になった直後に
                      // まだ古いイベントが流れてくると再実行される恐れがある。
                      // これを防ぐために、撮影リクエストIDなどを管理する必要があるが、
                      // camerawesomeの仕様上、MediaCaptureオブジェクトが更新されるたびに呼ばれる。
                      
                      // ここでの根本的な問題は、StreamBuilderが再ビルドされるたびに、
                      // またはStreamから同じキャプチャ状態が複数回流れてくるたびに
                      // 処理が走ってしまうこと。
                      
                      // 対策: 処理済みのパスを記録しておく
                      if (!_processedPaths.contains(mediaCapture.captureRequest.path)) {
                         _processedPaths.add(mediaCapture.captureRequest.path!);
                         
                         WidgetsBinding.instance.addPostFrameCallback((_) {
                           if (!_isProcessing) {
                             _processCapturedImage(mediaCapture.captureRequest.path!);
                           }
                         });
                      }
                    }
                  }
                  return const SizedBox.shrink();
                },
              ),
          ],
        );
      },
    ),
  ),
);
}

/// 撮影後の画像処理
  Future<void> _processCapturedImage(String tempPath) async {
    // 連続処理を防ぐ
    if (_isProcessing) return;
    
    setState(() {
      _isProcessing = true;
    });

    try {
      // GPS座標を取得
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
        ).timeout(const Duration(seconds: 3));
      } catch (e) {
        print('[CameraScreen] GPS取得エラー: $e');
      }

      final now = DateTime.now();
      final timestamp = now.toIso8601String().replaceAll(':', '-').split('.').first;
      final defaultFileName = 'IMG_$timestamp';

      if (!mounted) return;
      
      // 自動命名（ファイル名入力ダイアログを削除）
      final fileName = defaultFileName;

      // 正式なパス
      final folderPath = widget.targetFolder.getAbsoluteFilePath();
      if (folderPath == null) {
         throw Exception('フォルダパスの取得に失敗しました');
      }
      final targetPath = p.join(folderPath, '$fileName.jpg');
      
      // リネーム（移動）
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        await tempFile.rename(targetPath);
      } else {
        throw Exception('撮影されたファイルが見つかりません');
      }
      
      final targetFile = File(targetPath);

      // EXIF情報を付与
      if (position != null) {
        await _addExifData(targetFile, position, now);
      }

      // PhotoNodeとして登録
      if (position != null) {
        final stats = await targetFile.stat();
        final photoNode = PhotoNode(
          targetPath,
          LatLng(position.latitude, position.longitude),
          PhotoMetadata(
            fileSize: stats.size,
            width: null,
            height: null,
            camera: null,
          ),
          takenAt: now,
          visible: true,
          parent: widget.targetFolder,
          isPhoto: true,
        );
        widget.targetFolder.addChild(photoNode);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('写真を保存しました: $fileName.jpg'),
            backgroundColor: Colors.green,
            duration: const Duration(milliseconds: 1500),
          ),
        );
        // 撮影フラグを立てる
        _hasCaptured = true;
      }

    } catch (e) {
      print('[CameraScreen] 画像処理エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存処理に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // 成功・失敗・キャンセルに関わらず、必ず処理中フラグを下ろす
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // ファイル名入力ダイアログメソッドは削除


  /// EXIF情報を画像ファイルに追加
  Future<void> _addExifData(File imageFile, Position position, DateTime timestamp) async {
    try {
      final exif = await Exif.fromPath(imageFile.path);
      
      final dateTimeStr = '${timestamp.year}:${timestamp.month.toString().padLeft(2, '0')}:${timestamp.day.toString().padLeft(2, '0')} '
          '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
      
      await exif.writeAttributes({
        'DateTimeOriginal': dateTimeStr,
        'DateTime': dateTimeStr,
        'DateTimeDigitized': dateTimeStr,
        'GPSLatitude': position.latitude.abs(),
        'GPSLatitudeRef': position.latitude >= 0 ? 'N' : 'S',
        'GPSLongitude': position.longitude.abs(),
        'GPSLongitudeRef': position.longitude >= 0 ? 'E' : 'W',
      });
      
      if (position.altitude != 0) {
        await exif.writeAttributes({
          'GPSAltitude': position.altitude.abs(),
          'GPSAltitudeRef': position.altitude >= 0 ? 0 : 1,
        });
      }
      
      await exif.close();
      
    } catch (e) {
      print('[CameraScreen] EXIF書き込みエラー: $e');
    }
  }
}
