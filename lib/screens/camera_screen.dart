// K-MAPS: カメラ撮影画面
// スマホカメラと同様のUI、ズーム機能付き
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_exif/native_exif.dart';
import 'dart:io';
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

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isTakingPicture = false;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  int _currentCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  /// カメラの初期化
  Future<void> _initializeCamera() async {
    try {
      // 利用可能なカメラを取得
      _cameras = await availableCameras();

      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('カメラが見つかりません'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // カメラコントローラーを初期化
      final camera = _cameras![_currentCameraIndex];
      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();

      if (!mounted) return;

      // ズームレベルの範囲を取得
      _minZoom = await _controller!.getMinZoomLevel();
      _maxZoom = await _controller!.getMaxZoomLevel();
      _currentZoom = _minZoom;

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      print('[CameraScreen] カメラ初期化エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('カメラの初期化に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// カメラを切り替え（前面/背面）
  Future<void> _switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;

    _currentCameraIndex = (_currentCameraIndex + 1) % _cameras!.length;
    
    setState(() {
      _isInitialized = false;
    });

    await _controller?.dispose();
    await _initializeCamera();
  }

  /// ズームレベルを設定
  Future<void> _setZoomLevel(double zoom) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final clampedZoom = zoom.clamp(_minZoom, _maxZoom);
    await _controller!.setZoomLevel(clampedZoom);
    
    setState(() {
      _currentZoom = clampedZoom;
    });
  }

  /// 写真を撮影
  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isTakingPicture) {
      return;
    }

    setState(() {
      _isTakingPicture = true;
    });

    try {
      // 写真を撮影
      final XFile image = await _controller!.takePicture();

      // GPS座標を取得
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        print('[CameraScreen] GPS取得エラー: $e');
        // GPS取得失敗時は座標なしで保存
      }

      // ファイル名を生成（タイムスタンプ）
      final now = DateTime.now();
      final timestamp = now.toIso8601String().replaceAll(':', '-').split('.').first;
      final defaultFileName = 'IMG_$timestamp';

      // ユーザーにファイル名を入力してもらう
      if (!mounted) return;
      final fileName = await _showFileNameDialog(defaultFileName);
      
      // キャンセルされた場合は処理を中止
      if (fileName == null) {
        setState(() {
          _isTakingPicture = false;
        });
        return;
      }

      // 保存先パスを取得
      final folderPath = widget.targetFolder.getAbsoluteFilePath();
      if (folderPath == null) {
        throw Exception('フォルダパスの取得に失敗しました');
      }
      final targetPath = p.join(folderPath, '$fileName.jpg');

      // 画像ファイルをコピー
      final File sourceFile = File(image.path);
      final File targetFile = File(targetPath);
      await sourceFile.copy(targetPath);

      // EXIF情報を確認
      if (position != null) {
        await _addExifData(targetFile, position, now);
      }

      // PhotoNodeとして登録（GPS座標がある場合のみ）
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
        );
        widget.targetFolder.addChild(photoNode);
      }

      if (mounted) {
        // 成功メッセージを表示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('写真を保存しました: $fileName.jpg'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        // 画面を閉じる（更新が必要であることを通知）
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('[CameraScreen] 撮影エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('撮影に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTakingPicture = false;
        });
      }
    }
  }

  /// ファイル名入力ダイアログを表示
  Future<String?> _showFileNameDialog(String defaultName) async {
    final controller = TextEditingController(text: defaultName);
    
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('ファイル名を入力'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'ファイル名（拡張子なし）',
            hintText: 'IMG_2025-11-16T12-00-00',
            border: OutlineInputBorder(),
          ),
          onTap: () {
            // フォーカス時に全選択
            controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: controller.text.length,
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              final fileName = controller.text.trim();
              if (fileName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('ファイル名を入力してください'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              Navigator.pop(context, fileName);
            },
            child: const Text('決定'),
          ),
        ],
      ),
    );
  }

  /// EXIF情報を画像ファイルに追加
  /// 
  /// native_exifパッケージを使用してGPS座標と撮影日時をEXIFデータとして書き込みます。
  Future<void> _addExifData(File imageFile, Position position, DateTime timestamp) async {
    try {
      // native_exifを使用してEXIFデータにアクセス
      final exif = await Exif.fromPath(imageFile.path);
      
      // 撮影日時を設定（EXIF標準形式: "YYYY:MM:DD HH:MM:SS"）
      final dateTimeStr = '${timestamp.year}:${timestamp.month.toString().padLeft(2, '0')}:${timestamp.day.toString().padLeft(2, '0')} '
          '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
      
      await exif.writeAttributes({
        'DateTimeOriginal': dateTimeStr,
        'DateTime': dateTimeStr,
        'DateTimeDigitized': dateTimeStr,
      });
      
      // GPS座標を設定
      await exif.writeAttributes({
        'GPSLatitude': position.latitude.abs(),
        'GPSLatitudeRef': position.latitude >= 0 ? 'N' : 'S',
        'GPSLongitude': position.longitude.abs(),
        'GPSLongitudeRef': position.longitude >= 0 ? 'E' : 'W',
      });
      
      // 高度を設定
      if (position.altitude != 0) {
        await exif.writeAttributes({
          'GPSAltitude': position.altitude.abs(),
          'GPSAltitudeRef': position.altitude >= 0 ? 0 : 1,
        });
      }
      
      // EXIF情報をファイルに保存
      await exif.close();
      
      print('[CameraScreen] EXIF情報を書き込みました');
      print('  GPS: ${position.latitude}, ${position.longitude}');
      print('  高度: ${position.altitude}m');
      print('  精度: ±${position.accuracy}m');
      print('  撮影日時: $dateTimeStr');
      
    } catch (e) {
      print('[CameraScreen] EXIF書き込みエラー: $e');
      // EXIF書き込みに失敗しても、位置情報はPhotoNodeに保存済み
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('カメラ'),
          backgroundColor: Colors.black,
        ),
        backgroundColor: Colors.black,
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('カメラ'),
        backgroundColor: Colors.black,
        actions: [
          // カメラ切り替えボタン
          if (_cameras != null && _cameras!.length > 1)
            IconButton(
              icon: const Icon(Icons.flip_camera_ios),
              onPressed: _switchCamera,
              tooltip: 'カメラ切り替え',
            ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // カメラプレビュー
          Positioned.fill(
            child: Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: CameraPreview(_controller!),
              ),
            ),
          ),

          // ズームスライダー
          Positioned(
            right: 16,
            top: 16,
            bottom: 100,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white38,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white24,
                  trackHeight: 3.0,
                ),
                child: Slider(
                  value: _currentZoom,
                  min: _minZoom,
                  max: _maxZoom,
                  onChanged: _setZoomLevel,
                ),
              ),
            ),
          ),

          // ズーム表示
          Positioned(
            right: 16,
            top: MediaQuery.of(context).size.height / 2 - 30,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${_currentZoom.toStringAsFixed(1)}x',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // 撮影ボタン
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isTakingPicture ? null : _takePicture,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isTakingPicture ? Colors.grey : Colors.white,
                    border: Border.all(
                      color: Colors.white,
                      width: 4,
                    ),
                  ),
                  child: _isTakingPicture
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

