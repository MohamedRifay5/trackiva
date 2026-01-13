import 'trackiva_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

abstract class TrackivaPlatform extends PlatformInterface {
  TrackivaPlatform() : super(token: _token);

  static final Object _token = Object();
  static TrackivaPlatform _instance = MethodChannelTrackiva();

  static TrackivaPlatform get instance => _instance;

  static set instance(TrackivaPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  // Enhanced initialization method
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
  }) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// Set MQTT configuration with flexible payload
  Future<void> setMqttConfigAndDetails({
    required String broker,
    required int port,
    String? username,
    String? password,
    required String topic,
    required Map<String, dynamic> payload,
  });

  /// Set HTTP configuration
  Future<void> setHttpConfig({required String endpoint, required Map<String, String> headers, required String method}) {
    throw UnimplementedError('setHttpConfig() has not been implemented.');
  }

  /// Set GraphQL configuration
  Future<void> setGraphQLConfig({
    required String endpoint,
    required String mutation,
    required Map<String, String> headers,
  }) {
    throw UnimplementedError('setGraphQLConfig() has not been implemented.');
  }

  Future<void> startTracking() {
    throw UnimplementedError('startTracking() has not been implemented.');
  }

  Future<void> stopTracking() {
    throw UnimplementedError('stopTracking() has not been implemented.');
  }

  Future<bool> isTracking() {
    throw UnimplementedError('isTracking() has not been implemented.');
  }

  Future<LocationData?> getCurrentLocation() {
    throw UnimplementedError('getCurrentLocation() has not been implemented.');
  }

  Future<bool> isLocationServiceEnabled() {
    throw UnimplementedError('isLocationServiceEnabled() has not been implemented.');
  }

  Future<LocationAccuracy> getLocationAccuracy() {
    throw UnimplementedError('getLocationAccuracy() has not been implemented.');
  }

  Future<bool> setLocationAccuracy(LocationAccuracy accuracy) {
    throw UnimplementedError('setLocationAccuracy() has not been implemented.');
  }

  Future<TrackingStats> getTrackingStats() {
    throw UnimplementedError('getTrackingStats() has not been implemented.');
  }

  Future<bool> clearTrackingData() {
    throw UnimplementedError('clearTrackingData() has not been implemented.');
  }

  Future<Map<String, dynamic>> getMqttStatus() {
    throw UnimplementedError('getMqttStatus() has not been implemented.');
  }

  Stream<LocationData> get onLocationUpdate {
    throw UnimplementedError('onLocationUpdate has not been implemented.');
  }

  /// Check if overlay permission is granted (Android only)
  Future<bool> canDrawOverlays() {
    throw UnimplementedError('canDrawOverlays() has not been implemented.');
  }

  /// Request overlay permission (Android only)
  /// Opens system settings for the user to grant permission
  Future<bool> requestOverlayPermission() {
    throw UnimplementedError('requestOverlayPermission() has not been implemented.');
  }

  /// Manually start chat head service (Android only)
  /// Useful after overlay permission is granted
  Future<bool> startChatHeadService() {
    throw UnimplementedError('startChatHeadService() has not been implemented.');
  }
}

/// Location accuracy levels
enum LocationAccuracy { low, medium, high, best }

/// Location data model
class LocationData {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double altitude;
  final double speed;
  final double bearing;
  final DateTime timestamp;
  final bool isBackground;
  final String? provider;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.altitude,
    required this.speed,
    required this.bearing,
    required this.timestamp,
    this.isBackground = false,
    this.provider,
  });

  factory LocationData.fromMap(Map<String, dynamic> map) {
    return LocationData(
      latitude: _parseDouble(map['latitude']),
      longitude: _parseDouble(map['longitude']),
      accuracy: _parseDouble(map['accuracy']),
      altitude: _parseDouble(map['altitude']),
      speed: _parseDouble(map['speed']),
      bearing: _parseDouble(map['bearing']),
      timestamp: _parseTimestamp(map['timestamp']),
      isBackground: map['isBackground'] ?? false,
      provider: map['provider'],
    );
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is double) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return DateTime.now();
  }

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'altitude': altitude,
      'speed': speed,
      'bearing': bearing,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isBackground': isBackground,
      'provider': provider,
    };
  }

  @override
  String toString() {
    return 'LocationData(lat: $latitude, lng: $longitude, accuracy: $accuracy, timestamp: $timestamp, background: $isBackground)';
  }
}

/// Tracking statistics
class TrackingStats {
  final int totalLocations;
  final int foregroundLocations;
  final int backgroundLocations;
  final DateTime? firstLocationTime;
  final DateTime? lastLocationTime;
  final double totalDistance; // in meters
  final double averageSpeed; // in m/s

  TrackingStats({
    this.totalLocations = 0,
    this.foregroundLocations = 0,
    this.backgroundLocations = 0,
    this.firstLocationTime,
    this.lastLocationTime,
    this.totalDistance = 0.0,
    this.averageSpeed = 0.0,
  });

  factory TrackingStats.fromMap(Map<String, dynamic> map) {
    return TrackingStats(
      totalLocations: map['totalLocations'] ?? 0,
      foregroundLocations: map['foregroundLocations'] ?? 0,
      backgroundLocations: map['backgroundLocations'] ?? 0,
      firstLocationTime: map['firstLocationTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['firstLocationTime'])
          : null,
      lastLocationTime: map['lastLocationTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastLocationTime'])
          : null,
      totalDistance: (map['totalDistance'] ?? 0.0).toDouble(),
      averageSpeed: (map['averageSpeed'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'totalLocations': totalLocations,
      'foregroundLocations': foregroundLocations,
      'backgroundLocations': backgroundLocations,
      'firstLocationTime': firstLocationTime?.millisecondsSinceEpoch,
      'lastLocationTime': lastLocationTime?.millisecondsSinceEpoch,
      'totalDistance': totalDistance,
      'averageSpeed': averageSpeed,
    };
  }
}
