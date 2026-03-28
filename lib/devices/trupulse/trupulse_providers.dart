/// TruPulse固有のRiverpodプロバイダー
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'trupulse_service.dart';
import 'trupulse_tool.dart';

part 'trupulse_providers.g.dart';

/// TruPulseServiceのシングルトンインスタンス
@Riverpod(keepAlive: true)
TruPulseService trupulseService(Ref ref) => TruPulseService();

/// TruPulseToolのシングルトンインスタンス
@Riverpod(keepAlive: true)
TruPulseTool trupulseTool(Ref ref) =>
    TruPulseTool(ref, ref.read(trupulseServiceProvider));
