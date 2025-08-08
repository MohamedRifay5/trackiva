import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'nectar_tracker_platform_interface.dart';

class MethodChannelNectarTracker extends NectarTrackerPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('nectar_tracker');
  final eventChannel = const EventChannel('nectar_tracker/updates');

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
    bool enableLogging = true,
    bool showLocationNotifications = false,
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
      'enableLogging': enableLogging,
      'showLocationNotifications': showLocationNotifications,
    });
  }

  @override
  Future<void> startTracking() async {
    await methodChannel.invokeMethod('startTracking');
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
    required String username,
    required String password,
    required String topic,
    required String userId,
    required int batteryLevel,
    required String userType,
    required String deviceId,
    required String domain,
    required String usernameField,
    required String identifier,
    required List<String> skills,
    required String status,
    required String name,
    required String geofence,
    required String emailid,
    required String mobile,
    required String jobId,
  }) async {
    await methodChannel.invokeMethod('setMqttConfigAndDetails', {
      'broker': broker,
      'port': port,
      'username': username,
      'password': password,
      'topic': topic,
      'userId': userId,
      'batteryLevel': batteryLevel,
      'userType': userType,
      'deviceId': deviceId,
      'domain': domain,
      'usernameField': usernameField,
      'identifier': identifier,
      'skills': skills,
      'status': status,
      'name': name,
      'geofence': geofence,
      'emailid': emailid,
      'mobile': mobile,
      'jobId': jobId,
    });
  }
}
