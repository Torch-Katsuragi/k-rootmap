// K-MAPS: エントリーポイント
// 本ファイルはアプリ起動・ルーティングのみを担当
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const KMapsApp());
}

class KMapsApp extends StatelessWidget {
  const KMapsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'K-MAPS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
