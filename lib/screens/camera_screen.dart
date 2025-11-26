// K-MAPS: カメラ撮影画面
// camerawesomeパッケージを使用して、安定したカメラ機能を提供
import 'dart:async';
import 'dart:io';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
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
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CameraAwesomeBuilder.custom(
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
              // 上部アクション（フラッシュ切り替えなど）
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AwesomeTopActions(state: state),
              ),
              
              // 下部アクション（撮影ボタンなど）
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.only(bottom: 32, top: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 戻るボタン
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white, size: 32),
                        onPressed: () => Navigator.pop(context),
                      ),
                      
                      // 撮影ボタン
                      AwesomeCaptureButton(state: state),
                      
                      // カメラ切り替えボタン
                      AwesomeCameraSwitchButton(state: state),
                    ],
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
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                         // 重複実行防止のためフラグをチェック（コールバック登録までの間に変わる可能性も考慮）
                         if (!_isProcessing) {
                           _processCapturedImage(mediaCapture.captureRequest.path!);
                         }
                      });
                    }
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          );
        },
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
      
      // ファイル名入力ダイアログ表示
      // 注: カメラプレビューの上にダイアログを出す
      final fileName = await _showFileNameDialog(defaultFileName);
      
      // キャンセルされた場合、一時ファイルを削除して終了
      if (fileName == null) {
        final file = File(tempPath);
        if (await file.exists()) {
          await file.delete();
        }
        // キャンセル時は処理フラグを戻して終了
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
        return;
      }

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
        );
        widget.targetFolder.addChild(photoNode);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('写真を保存しました: $fileName.jpg'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
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
        // エラー時もフラグを戻す
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  /// ファイル名入力ダイアログを表示
  Future<String?> _showFileNameDialog(String defaultName) async {
    final controller = TextEditingController(text: defaultName);
    
    // ナビゲーションのロックを回避するために、少し遅延させてダイアログを表示することを検討する余地もあるが、
    // ここでは標準的なshowDialogを使用。
    // !debugLockedエラーが出る場合、非同期処理の中でNavigatorの状態が不安定な可能性がある。
    // 特にビルドフェーズ中に呼ばれると危険。
    
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
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
            controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: controller.text.length,
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              final fileName = controller.text.trim();
              if (fileName.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('ファイル名を入力してください'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              Navigator.of(dialogContext).pop(fileName);
            },
            child: const Text('決定'),
          ),
        ],
      ),
    );
  }

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
