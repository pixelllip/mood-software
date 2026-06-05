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

/// 定位结果（含城市名和编码）
class _CityInfo {
  final String name;
  final String adcode;
  const _CityInfo({this.name = '广州', this.adcode = '440100'});
}

/// GPS坐标缓存
class _GpsCoords {
  final double lat;
  final double lng;
  const _GpsCoords({required this.lat, required this.lng});
}

/// 手机端定位服务
/// 优先级：GPS原生定位 → 高德API反向地理编码 → IP定位 → 默认值
class LocationService {
  /// 最后成功使用的定位方式（用于 debug）
  static String _lastMethod = '未定位';

  /// 获取缓存的GPS坐标（如果GPS定位成功过），用于AI提示
  static String? get gpsCoordsHint {
    if (_gpsCoordsCache == null) return null;
    return '${_gpsCoordsCache!.lat},${_gpsCoordsCache!.lng}';
  }

  /// 获取当前城市信息
  /// 返回 adcode（城市编码），用于天气查询等
  static Future<String> getCityAdcode() async {
    final info = await _getCityInfo();
    return info.adcode;
  }

  /// 获取当前城市名称和adcode
  /// 返回 "城市名,adcode" 格式，如 "广州,440100"
  static Future<String> getCityInfoForAi() async {
    final info = await _getCityInfo();
    final methodTag = _lastMethod;
    debugPrint(">>> 【定位汇总】使用方式: $methodTag → ${info.name}(${info.adcode})");
    return '${info.name},${info.adcode}';
  }

  /// 内部：获取城市信息（名称+编码）
  static Future<_CityInfo> _getCityInfo() async {
    // 标记GPS是否获取到了经纬度
    bool gpsGotCoords = false;

    try {
      // 1️⃣ 优先尝试 GPS 原生定位（手机端）
      if (Platform.isAndroid || Platform.isIOS) {
        final result = await _tryGpsAndReverseGeocode('手机');
        if (result != null) return result;
        if (_gpsCoordsCache != null) gpsGotCoords = true;
      }

      // 1.5️⃣ PC端也尝试GPS定位
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final result = await _tryGpsAndReverseGeocode('PC');
        if (result != null) return result;
        if (_gpsCoordsCache != null) gpsGotCoords = true;
      }

      // 2️⃣ GPS反地理编码失败 或 GPS不可用 → 尝试IP定位获取城市名
      if (gpsGotCoords) {
        // GPS已有坐标，尝试用IP定位补充城市名
        final ipResult = await _tryIpLocation();
        if (ipResult != null) {
          _lastMethod = 'GPS定位+IP定位获取城市名';
          debugPrint(
            ">>> GPS已定位，IP定位补充城市名: ${ipResult.name}(${ipResult.adcode})",
          );
          return ipResult;
        }
        // IP定位也失败 → 用默认城市（广州）作为兜底
        _lastMethod = 'GPS定位+默认城市（广州）';
        debugPrint(
          ">>> GPS已定位(${_gpsCoordsCache!.lat},${_gpsCoordsCache!.lng})，IP获取城市名失败，使用默认城市：广州",
        );
        return _CityInfo(name: '广州', adcode: '440100');
      }

      // 3️⃣ GPS完全不可用，直接尝试IP定位
      final ipResult = await _tryIpLocation();
      if (ipResult != null) {
        _lastMethod = 'IP定位';
        return ipResult;
      }
    } catch (e) {
      debugPrint(">>> 定位服务出错: $e");
    }

    // 4️⃣ 所有方式均失败 → 回退到默认城市（广州）
    _lastMethod = '所有定位方式均失败，使用默认值';
    debugPrint(">>> 所有定位方式均失败，回退到默认城市：广州(440100)");
    return _CityInfo(name: '广州', adcode: '440100');
  }

  /// GPS坐标缓存（用于反地理编码失败后给下游使用）
  static _GpsCoords? _gpsCoordsCache;

  static _GpsCoords? _getAndCacheCoords(Position? data) {
    if (data != null) {
      _gpsCoordsCache = _GpsCoords(lat: data.latitude, lng: data.longitude);
      return _gpsCoordsCache;
    }
    return null;
  }

  /// 尝试GPS定位+反向地理编码
  static Future<_CityInfo?> _tryGpsAndReverseGeocode(String platform) async {
    final gpsData = await _getGpsLocation();
    final coords = _getAndCacheCoords(gpsData);
    if (coords == null) return null;

    debugPrint(">>> $platform端GPS定位成功: ${coords.lat}, ${coords.lng}");
    // 尝试高德API反向地理编码
    final cityInfo = await _reverseGeocodeWithGaode(coords.lat, coords.lng);
    if (cityInfo != null) {
      _lastMethod = '$platform端GPS+高德反地理编码';
      debugPrint(">>> 高德反地理编码获取到: ${cityInfo.name}(${cityInfo.adcode})");
      return cityInfo;
    }
    debugPrint(">>> $platform端GPS反地理编码失败，后续尝试IP定位补充城市名");
    return null; // GPS坐标已缓存，后续用IP定位补充城市名
  }

  /// 尝试IP定位
  static Future<_CityInfo?> _tryIpLocation() async {
    final config = await loadConfigFile();
    final gaodeKey = config['Gaode_API_Key']?.toString() ?? '';
    if (gaodeKey.isEmpty) {
      debugPrint(">>> IP定位跳过：未配置高德API Key");
      return null;
    }
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
      if (response.data is Map) {
        final data = response.data as Map;
        // 检查高德API返回状态
        final status = data['status']?.toString() ?? '';
        if (status != '1') {
          final info = data['info']?.toString() ?? '未知错误';
          debugPrint(">>> IP定位API返回错误: $info");
          return null;
        }
        final adcode = data['adcode']?.toString() ?? '';
        if (adcode.length >= 6) {
          final city = data['city']?.toString() ?? '';
          final province = data['province']?.toString() ?? '';
          final cityName = city.isNotEmpty ? city : province;
          debugPrint(">>> IP定位获取到: $cityName($adcode)");
          return _CityInfo(name: cityName, adcode: adcode);
        } else {
          debugPrint(">>> IP定位返回的adcode无效: $adcode");
        }
      } else {
        debugPrint(">>> IP定位返回数据格式异常");
      }
    } catch (e) {
      debugPrint(">>> IP定位失败: $e");
    }
    return null;
  }

  /// 尝试获取GPS位置
  static Future<Position?> _getGpsLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint(">>> GPS服务未开启，尝试请求用户开启...");
        await Geolocator.openLocationSettings();
        // 等待一小段时间让用户开启GPS，然后重试一次
        await Future.delayed(const Duration(seconds: 2));
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          debugPrint(">>> GPS服务仍未开启，跳过GPS定位");
          return null;
        }
        debugPrint(">>> GPS服务已开启，继续定位");
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
        debugPrint(">>> GPS权限被永久拒绝，请在系统设置中手动授权");
        return null;
      }

      // 获取位置 - 先尝试高精度（30秒超时）
      debugPrint(">>> 正在获取GPS位置（高精度，最多等待30秒）...");
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 30),
          ),
        );
        debugPrint(">>> GPS高精度定位成功");
        return position;
      } catch (e) {
        debugPrint(">>> GPS高精度定位超时/失败: $e");
      }

      // 高精度失败，降级到中精度再试一次
      debugPrint(">>> 降级到中精度定位...");
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return position;
    } catch (e) {
      debugPrint(">>> 获取GPS位置失败: $e");
      return null;
    }
  }

  /// 使用高德API进行反向地理编码（坐标→城市名称+编码）
  static Future<_CityInfo?> _reverseGeocodeWithGaode(
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
          final ac = data['regeocode']['addressComponent'];
          if (ac is Map) {
            final adcode = ac['adcode']?.toString() ?? '';
            if (adcode.length >= 6) {
              // 优先用城市名，没有则用省份名
              final city = ac['city']?.toString() ?? '';
              final province = ac['province']?.toString() ?? '';
              final district = ac['district']?.toString() ?? '';
              final cityName = city.isNotEmpty
                  ? city
                  : (province.isNotEmpty ? province : district);
              return _CityInfo(name: cityName, adcode: adcode);
            }
          }
        }
      }
    } catch (e) {
      debugPrint(">>> 高德反向地理编码失败: $e");
    }
    return null;
  }
}
