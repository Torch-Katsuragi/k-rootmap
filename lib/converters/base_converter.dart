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
// Root Maps: Base Converter Classes
// Import/Export操作のための基本コンバータークラス群
import 'dart:async';
import '../services/import_export_service.dart';
import '../models/nodes/layer_node.dart';

/// 変換操作の結果を表すクラス
class ConversionResult {
  final bool success;
  final String? errorMessage;
  final Map<String, dynamic>? metadata;
  final dynamic data;

  ConversionResult({
    required this.success,
    this.errorMessage,
    this.metadata,
    this.data,
  });

  factory ConversionResult.success({
    dynamic data,
    Map<String, dynamic>? metadata,
  }) {
    return ConversionResult(success: true, data: data, metadata: metadata);
  }

  factory ConversionResult.error(String message) {
    return ConversionResult(success: false, errorMessage: message);
  }
}

/// 進行状況を通知するためのコールバック型
typedef ProgressCallback = void Function(double progress, String message);

/// 基本コンバータークラス
abstract class BaseConverter<TInput, TOutput> {
  /// サービスインスタンス（サブクラスからアクセス可能）
  final ImportExportService service = ImportExportService();

  /// 進行状況コールバック
  ProgressCallback? _progressCallback;

  /// 進行状況コールバックを設定
  void setProgressCallback(ProgressCallback? callback) {
    _progressCallback = callback;
  }

  /// 進行状況を通知
  void notifyProgress(double progress, String message) {
    _progressCallback?.call(progress, message);
  }

  /// 変換処理（サブクラスで実装）
  Future<ConversionResult> convert(TInput input);

  /// バリデーション処理（サブクラスでオーバーライド可能）
  Future<bool> validate(TInput input) async {
    return true;
  }

  /// 前処理（サブクラスでオーバーライド可能）
  Future<TInput> preProcess(TInput input) async {
    return input;
  }

  /// 後処理（サブクラスでオーバーライド可能）
  Future<TOutput> postProcess(TOutput output) async {
    return output;
  }

  /// 変換処理の完全なワークフロー
  Future<ConversionResult> execute(TInput input) async {
    try {
      notifyProgress(0.0, 'Starting conversion...');

      // バリデーション
      notifyProgress(0.1, 'Validating input...');
      final isValid = await validate(input);
      if (!isValid) {
        return ConversionResult.error('Input validation failed');
      }

      // 前処理
      notifyProgress(0.2, 'Pre-processing...');
      final processedInput = await preProcess(input);

      // メイン変換処理
      notifyProgress(0.3, 'Converting...');
      final result = await convert(processedInput);

      if (!result.success) {
        return result;
      }

      // 後処理
      notifyProgress(0.9, 'Post-processing...');
      final finalOutput = await postProcess(result.data);

      notifyProgress(1.0, 'Conversion completed!');

      return ConversionResult.success(
        data: finalOutput,
        metadata: result.metadata,
      );
    } catch (e) {
      return ConversionResult.error('Conversion failed: $e');
    }
  }
}

/// ファイル変換のためのパラメータ
class FileConversionParams {
  final String filePath;
  final FileFormat sourceFormat;
  final FileFormat targetFormat;
  final Map<String, dynamic> options;

  FileConversionParams({
    required this.filePath,
    required this.sourceFormat,
    required this.targetFormat,
    this.options = const {},
  });
}

/// レイヤー変換のためのパラメータ
class LayerConversionParams {
  final LayerNode sourceLayer;
  final String outputPath;
  final FileFormat targetFormat;
  final Map<String, dynamic> options;

  LayerConversionParams({
    required this.sourceLayer,
    required this.outputPath,
    required this.targetFormat,
    this.options = const {},
  });
}

/// フィーチャ変換のためのパラメータ
class FeatureConversionParams {
  final LayerNode? targetLayer;
  final List<Map<String, dynamic>> features;
  final List<int>? selectedFeatureIds;
  final Map<String, dynamic> options;

  FeatureConversionParams({
    this.targetLayer,
    required this.features,
    this.selectedFeatureIds,
    this.options = const {},
  });
}
