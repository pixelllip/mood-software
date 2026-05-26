import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';
import 'package:ai_agent/backend_utils.dart';

/// 定位结果
class LocationResult {
  final double latitude;
  final double longitude;
  final String cityName;
  final String adcode; // 中国城市编码

  const LocationResult({
    required this.latitude,
    required this.longitude,
    this.cityName = '',
    this.adcode = '440100', // 默认广州
  });
}

/// 手机端定位服务
/// 优先级：GPS原生定位 → 高德API反向地理编码 → IP定位 → 默认值
class LocationService {
  /// 获取当前城市信息
  /// 返回 adcode（城市编码），用于天气查询等
  static Future<String> getCityAdcode() async {
    try {
      // 1️⃣ 优先尝试 GPS 原生定位
      if (Platform.isAndroid || Platform.isIOS) {
        final location = await _getGpsLocation();
        if (location != null) {
          debugPrint(
            ">>> GPS定位成功: ${location.latitude}, ${location.longitude}",
          );

          // 1a. 尝试用高德API反向地理编码获取城市编码
          final adcode = await _reverseGeocodeWithGaode(
            location.latitude,
            location.longitude,
          );
          if (adcode != null) {
            debugPrint(">>> 高德反地理编码获取到adcode: $adcode");
            return adcode;
          }
        }
      }

      // 1.5️⃣ PC端也尝试GPS定位（使用 geolocator 桌面端支持）
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final location = await _getGpsLocation();
        if (location != null) {
          debugPrint(
            ">>> PC端GPS定位成功: ${location.latitude}, ${location.longitude}",
          );
          // GPS定位后尝试高德API反向地理编码
          final adcode = await _reverseGeocodeWithGaode(
            location.latitude,
            location.longitude,
          );
          if (adcode != null) {
            debugPrint(">>> 高德反地理编码获取到adcode: $adcode");
            return adcode;
          }
        }
      }

      // 2️⃣ GPS不可用，尝试IP定位（从配置文件读取高德Key）
      final config = await loadConfigFile();
      final gaodeKey = config['Gaode_API_Key']?.toString() ?? '';
      if (gaodeKey.isNotEmpty) {
        try {
          final dio = Dio();
          final response = await dio.get(
            'https://restapi.amap.com/v3/ip',
            queryParameters: {'key': gaodeKey},
            options: Options(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ),
          );
          if (response.data is Map && response.data['adcode'] != null) {
            final adcode = response.data['adcode'].toString();
            if (adcode.length >= 6) {
              debugPrint(">>> IP定位获取到adcode: $adcode");
              return adcode;
            }
          }
        } catch (e) {
          debugPrint(">>> IP定位失败: $e");
        }
      }
    } catch (e) {
      debugPrint(">>> 定位服务出错: $e");
    }

    // 3️⃣ 默认返回广州
    debugPrint(">>> 所有定位方式均失败，使用默认城市: 广州(440100)");
    return '440100';
  }

  /// 尝试获取GPS位置
  static Future<Position?> _getGpsLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint(">>> GPS服务未开启");
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint(">>> GPS权限被拒绝");
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint(">>> GPS权限被永久拒绝");
        return null;
      }

      // 获取位置（中等精度即可）
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return position;
    } catch (e) {
      debugPrint(">>> 获取GPS位置失败: $e");
      return null;
    }
  }

  /// 使用高德API进行反向地理编码（坐标→城市编码）
  static Future<String?> _reverseGeocodeWithGaode(
    double lat,
    double lng,
  ) async {
    try {
      final config = await loadConfigFile();
      final gaodeKey = config['Gaode_API_Key']?.toString() ?? '';
      if (gaodeKey.isEmpty) return null;

      final dio = Dio();
      final response = await dio.get(
        'https://restapi.amap.com/v3/geocode/regeo',
        queryParameters: {
          'location': '$lng,$lat',
          'key': gaodeKey,
          'radius': 1000,
          'extensions': 'base',
        },
        options: Options(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.data is Map) {
        final data = response.data as Map;
        if (data['status'] == '1' && data['regeocode'] != null) {
          final adcode = data['regeocode']['addressComponent']?['adcode']
              ?.toString();
          if (adcode != null && adcode.length >= 6) {
            return adcode;
          }
        }
      }
    } catch (e) {
      debugPrint(">>> 高德反向地理编码失败: $e");
    }
    return null;
  }
}
