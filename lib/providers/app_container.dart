import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Non-widget code (tools, services) からプロバイダーにアクセスするためのグローバルコンテナ
/// Widget内では ref.watch/read を使用すること
late ProviderContainer appContainer;
