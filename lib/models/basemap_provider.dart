/// 背景地図プロバイダー定義
/// OpenStreetMap、国土地理院地図などの背景地図を管理
library;
import 'package:flutter/material.dart';

/// 背景地図の種類を定義するenum
enum BaseMapType {
  openStreetMap,
  gsiStandard,
  gsiPale,
  gsiPhoto,
  gsiRelief,
  gsiBlank,
}

/// 背景地図プロバイダーの情報を格納するクラス
class BaseMapProvider {
  final String id;
  final String name;
  final String description;
  final String urlTemplate;
  final int maxZoom;
  final int minZoom;
  final String attribution;
  final String? userAgentPackageName;
  final BaseMapType type;
  final IconData icon;

  const BaseMapProvider({
    required this.id,
    required this.name,
    required this.description,
    required this.urlTemplate,
    this.maxZoom = 18,
    this.minZoom = 1,
    required this.attribution,
    this.userAgentPackageName,
    required this.type,
    required this.icon,
  });

  /// 利用可能な背景地図プロバイダーのリスト
  static const List<BaseMapProvider> availableProviders = [
    // OpenStreetMap
    BaseMapProvider(
      id: 'osm',
      name: 'OpenStreetMap',
      description: 'オープンソースの世界地図',
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      maxZoom: 19,
      attribution: '© OpenStreetMap contributors',
      userAgentPackageName: 'com.example.k_maps',
      type: BaseMapType.openStreetMap,
      icon: Icons.public,
    ),

    // 国土地理院地図 - 標準地図
    BaseMapProvider(
      id: 'gsi_std',
      name: '国土地理院（標準）',
      description: '国土地理院の標準地図',
      urlTemplate: 'https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png',
      maxZoom: 18,
      attribution: '国土地理院',
      type: BaseMapType.gsiStandard,
      icon: Icons.map,
    ),

    // 国土地理院地図 - 淡色地図
    BaseMapProvider(
      id: 'gsi_pale',
      name: '国土地理院（淡色）',
      description: '国土地理院の淡色地図（背景用）',
      urlTemplate: 'https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png',
      maxZoom: 18,
      attribution: '国土地理院',
      type: BaseMapType.gsiPale,
      icon: Icons.layers_outlined,
    ),

    // 国土地理院地図 - 写真
    BaseMapProvider(
      id: 'gsi_photo',
      name: '国土地理院（写真）',
      description: '国土地理院の航空写真',
      urlTemplate:
          'https://cyberjapandata.gsi.go.jp/xyz/seamlessphoto/{z}/{x}/{y}.jpg',
      maxZoom: 18,
      attribution: '国土地理院',
      type: BaseMapType.gsiPhoto,
      icon: Icons.satellite_alt,
    ),

    // 国土地理院地図 - 色別標高図
    BaseMapProvider(
      id: 'gsi_relief',
      name: '国土地理院（標高）',
      description: '国土地理院の色別標高図',
      urlTemplate:
          'https://cyberjapandata.gsi.go.jp/xyz/relief/{z}/{x}/{y}.png',
      maxZoom: 15,
      attribution: '国土地理院',
      type: BaseMapType.gsiRelief,
      icon: Icons.terrain,
    ),

    // 国土地理院地図 - 白地図
    BaseMapProvider(
      id: 'gsi_blank',
      name: '国土地理院（白地図）',
      description: '国土地理院の白地図',
      urlTemplate: 'https://cyberjapandata.gsi.go.jp/xyz/blank/{z}/{x}/{y}.png',
      maxZoom: 14,
      attribution: '国土地理院',
      type: BaseMapType.gsiBlank,
      icon: Icons.crop_landscape,
    ),
  ];

  /// IDから背景地図プロバイダーを取得
  static BaseMapProvider? getProviderById(String id) {
    try {
      return availableProviders.firstWhere((provider) => provider.id == id);
    } catch (e) {
      return null;
    }
  }

  /// デフォルトの背景地図プロバイダー（OpenStreetMap）
  static BaseMapProvider get defaultProvider => availableProviders.first;

  /// 国土地理院地図のプロバイダーのみを取得
  static List<BaseMapProvider> get gsiProviders =>
      availableProviders
          .where(
            (provider) =>
                provider.type.toString().startsWith('BaseMapType.gsi'),
          )
          .toList();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BaseMapProvider &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'BaseMapProvider(id: $id, name: $name)';
}
