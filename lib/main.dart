// K-MAPS: エントリーポイント
// 本ファイルはアプリ起動・ルーティングのみを担当
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'screens/home_screen.dart';

void main() async {
  // sqflite使用前に必須の初期化処理
  WidgetsFlutterBinding.ensureInitialized();

  // デスクトップ環境での sqflite_common_ffi 初期化
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // sqflite_common_ffi を初期化
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

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
