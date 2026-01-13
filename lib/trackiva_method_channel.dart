import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'trackiva_platform_interface.dart';

class MethodChannelTrackiva extends TrackivaPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('trackiva');
  final eventChannel = const EventChannel('trackiva/updates');

  Stream<LocationData>? _locationStream;

  @override
  Future<void> initialize({
    required String notificationTitle,
    required String notificationText,
    required int interval,
    required int fastestInterval,
    required double distanceFilter,
    bool enableBackgroundMode = true,
    bool enableHighAccuracy = true,
    bool enableBatteryOptimization = false,
    String? notificationIcon,
    String? notificationColor,
    String? chatHeadIcon,
    bool enableChatHead = false,
    bool enableLogging = true,
    bool showLocationNotifications = false,
    String? locationNotificationTitle,
    String? locationNotificationBody,
  }) async {
    await methodChannel.invokeMethod('initialize', {
      'notificationTitle': notificationTitle,
      'notificationText': notificationText,
      'interval': interval,
      'fastestInterval': fastestInterval,
      'distanceFilter': distanceFilter,
      'enableBackgroundMode': enableBackgroundMode,
      'enableHighAccuracy': enableHighAccuracy,
      'enableBatteryOptimization': enableBatteryOptimization,
      'notificationIcon': notificationIcon,
      'notificationColor': notificationColor,
      'chatHeadIcon': chatHeadIcon,
      'enableChatHead': enableChatHead,
      'enableLogging': enableLogging,
      'showLocationNotifications': showLocationNotifications,
      'locationNotificationTitle': locationNotificationTitle,
      'locationNotificationBody': locationNotificationBody,
    });
  }

  @override
  Future<void> startTracking() async {
    try {
      await methodChannel.invokeMethod('startTracking');
    } on PlatformException catch (e) {
      if (e.code == 'OVERLAY_PERMISSION_NEEDED') {
        debugPrint('[Trackiva] Overlay permission needed. Settings opened.');
        rethrow;
      }
      rethrow;
    }
  }

  @override
  Future<void> stopTracking() async {
    await methodChannel.invokeMethod('stopTracking');
  }

  @override
  Future<bool> isTracking() async {
    return await methodChannel.invokeMethod('isTracking') ?? false;
  }

  @override
  Future<LocationData?> getCurrentLocation() async {
    try {
      final result = await methodChannel.invokeMethod('getCurrentLocation');
      if (result != null) {
        return LocationData.fromMap(Map<String, dynamic>.from(result));
      }
      return null;
    } catch (e) {
      debugPrint('Error getting current location: $e');
      return null;
    }
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    return await methodChannel.invokeMethod('isLocationServiceEnabled') ?? false;
  }

  @override
  Future<LocationAccuracy> getLocationAccuracy() async {
    try {
      final result = await methodChannel.invokeMethod('getLocationAccuracy');
      if (result != null) {
        return LocationAccuracy.values.firstWhere(
          (e) => e.toString() == 'LocationAccuracy.$result',
          orElse: () => LocationAccuracy.medium,
        );
      }
      return LocationAccuracy.medium;
    } catch (e) {
      debugPrint('Error getting location accuracy: $e');
      return LocationAccuracy.medium;
    }
  }

  @override
  Future<bool> setLocationAccuracy(LocationAccuracy accuracy) async {
    try {
      final accuracyString = accuracy.toString().split('.').last;
      return await methodChannel.invokeMethod('setLocationAccuracy', {'accuracy': accuracyString}) ?? false;
    } catch (e) {
      debugPrint('Error setting location accuracy: $e');
      return false;
    }
  }

  @override
  Future<TrackingStats> getTrackingStats() async {
    try {
      final result = await methodChannel.invokeMethod('getTrackingStats');
      if (result != null) {
        return TrackingStats.fromMap(Map<String, dynamic>.from(result));
      }
      return TrackingStats();
    } catch (e) {
      debugPrint('Error getting tracking stats: $e');
      return TrackingStats();
    }
  }

  @override
  Future<bool> clearTrackingData() async {
    try {
      return await methodChannel.invokeMethod('clearTrackingData') ?? false;
    } catch (e) {
      debugPrint('Error clearing tracking data: $e');
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> getMqttStatus() async {
    try {
      final result = await methodChannel.invokeMethod('getMqttStatus');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } catch (e) {
      debugPrint('Error getting MQTT status: $e');
      return {};
    }
  }

  @override
  Future<void> setHttpConfig({
    required String endpoint,
    required Map<String, String> headers,
    required String method,
  }) async {
    await methodChannel.invokeMethod('setHttpConfig', {'endpoint': endpoint, 'headers': headers, 'method': method});
  }

  @override
  Future<void> setGraphQLConfig({
    required String endpoint,
    required String mutation,
    required Map<String, String> headers,
  }) async {
    await methodChannel.invokeMethod('setGraphQLConfig', {
      'endpoint': endpoint,
      'mutation': mutation,
      'headers': headers,
    });
  }

  @override
  Stream<LocationData> get onLocationUpdate {
    _locationStream ??= eventChannel.receiveBroadcastStream().map((data) {
      try {
        final map = Map<String, dynamic>.from(data);
        return LocationData.fromMap(map);
      } catch (e) {
        throw Exception('Failed to parse location data: $e');
      }
    });
    return _locationStream!;
  }

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<void> setMqttConfigAndDetails({
    required String broker,
    required int port,
    String? username,
    String? password,
    required String topic,
    required Map<String, dynamic> payload,
  }) async {
    await methodChannel.invokeMethod('setMqttConfigAndDetails', {
      'broker': broker,
      'port': port,
      'username': username,
      'password': password,
      'topic': topic,
      'payload': payload,
    });
  }

  @override
  Future<bool> canDrawOverlays() async {
    try {
      return await methodChannel.invokeMethod('canDrawOverlays') ?? false;
    } catch (e) {
      debugPrint('Error checking overlay permission: $e');
      return false;
    }
  }

  @override
  Future<bool> requestOverlayPermission() async {
    try {
      return await methodChannel.invokeMethod('requestOverlayPermission') ?? false;
    } catch (e) {
      debugPrint('Error requesting overlay permission: $e');
      return false;
    }
  }

  @override
  Future<bool> startChatHeadService() async {
    try {
      return await methodChannel.invokeMethod('startChatHeadService') ?? false;
    } catch (e) {
      debugPrint('Error starting chat head service: $e');
      return false;
    }
  }
}
