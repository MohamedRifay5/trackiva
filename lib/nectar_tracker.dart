import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/rendering.dart';

import 'nectar_tracker_platform_interface.dart';

/// Main class for Nectar Tracker - similar to flutter_background_geolocation
class NectarTracker {
  static final NectarTracker _instance = NectarTracker._internal();
  factory NectarTracker() => _instance;
  NectarTracker._internal() {
    // Optionally, start listening immediately (or only after ready)
    // _startPlatformEventListener();
  }

  // Event streams
  final StreamController<LocationData> _locationController = StreamController<LocationData>.broadcast();
  final StreamController<LocationData> _motionChangeController = StreamController<LocationData>.broadcast();
  final StreamController<ProviderChangeEvent> _providerChangeController =
      StreamController<ProviderChangeEvent>.broadcast();
  final StreamController<ActivityChangeEvent> _activityChangeController =
      StreamController<ActivityChangeEvent>.broadcast();
  final StreamController<GeofenceEvent> _geofenceController = StreamController<GeofenceEvent>.broadcast();
  final StreamController<HeartbeatEvent> _heartbeatController = StreamController<HeartbeatEvent>.broadcast();
  final StreamController<HttpEvent> _httpController = StreamController<HttpEvent>.broadcast();
  final StreamController<ConnectivityChangeEvent> _connectivityChangeController =
      StreamController<ConnectivityChangeEvent>.broadcast();
  final StreamController<PowerSaveChangeEvent> _powerSaveChangeController =
      StreamController<PowerSaveChangeEvent>.broadcast();
  final StreamController<ProviderChangeEvent> _providerChangeController2 =
      StreamController<ProviderChangeEvent>.broadcast();
  final StreamController<MotionChangeEvent> _motionChangeController2 = StreamController<MotionChangeEvent>.broadcast();
  final StreamController<ActivityChangeEvent> _activityChangeController2 =
      StreamController<ActivityChangeEvent>.broadcast();

  // Configuration
  // ignore: unused_field
  NectarTrackerConfig? _config;
  NectarTrackerState? _state;

  StreamSubscription<LocationData>? _platformLocationSubscription;

  /// Listen to the platform event channel and forward locations to handleLocationUpdate
  void _startPlatformEventListener() {
    debugPrint('[NectarTracker] Subscribing to platform onLocationUpdate event channel');
    _platformLocationSubscription?.cancel();
    _platformLocationSubscription = NectarTrackerPlatform.instance.onLocationUpdate.listen(
      (location) {
        debugPrint('[NectarTracker] Received location from platform: $location');
        handleLocationUpdate(location);
      },
      onError: (error) {
        debugPrint('[NectarTracker] Error from platform event channel: $error');
      },
      cancelOnError: false,
    );
  }

  /// Initialize and configure the plugin (similar to ready() method)
  Future<NectarTrackerState> ready(NectarTrackerConfig config) async {
    try {
      developer.log('NectarTracker: Configuring plugin...', name: 'NectarTracker');
      debugPrint('[NectarTracker] ready() called with config: $config');
      _config = config;

      // Initialize platform
      await NectarTrackerPlatform.instance.initialize(
        notificationTitle: config.notificationTitle,
        notificationText: config.notificationText,
        interval: config.interval,
        fastestInterval: config.fastestInterval,
        distanceFilter: config.distanceFilter,
        enableBackgroundMode: !config.stopOnTerminate,
        enableHighAccuracy: config.desiredAccuracy == DesiredAccuracy.high,
        enableBatteryOptimization: config.enableBatteryOptimization,
        notificationIcon: config.notificationIcon,
        notificationColor: config.notificationColor,
        enableLogging: config.debug,
        showLocationNotifications: config.showLocationNotifications,
      );

      // Start listening to platform event channel
      _startPlatformEventListener();

      // Get current state
      final isTracking = await NectarTrackerPlatform.instance.isTracking();
      final isLocationServiceEnabled = await NectarTrackerPlatform.instance.isLocationServiceEnabled();

      _state = NectarTrackerState(
        enabled: isTracking,
        isMoving: false, // Will be updated by motion detection
        locationServicesEnabled: isLocationServiceEnabled,
        authorization: AuthorizationStatus.authorized,
        activity: ActivityType.unknown,
        provider: ProviderChangeEvent(
          gps: isLocationServiceEnabled,
          network: isLocationServiceEnabled,
          enabled: isLocationServiceEnabled,
        ),
      );

      developer.log('NectarTracker: Plugin configured successfully', name: 'NectarTracker');
      debugPrint('[NectarTracker] ready() completed, state: $_state');
      return _state!;
    } catch (e, stack) {
      developer.log('Failed to configure NectarTracker: $e', name: 'NectarTracker', level: 900);
      debugPrint('[NectarTracker] ready() error: $e\n$stack');
      rethrow;
    }
  }

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
    await NectarTrackerPlatform.instance.setMqttConfigAndDetails(
      broker: broker,
      port: port,
      username: username,
      password: password,
      topic: topic,
      userId: '',
      batteryLevel: 0,
      userType: '',
      deviceId: '',
      domain: '',
      usernameField: '',
      identifier: '',
      skills: [],
      status: '',
      name: '',
      geofence: '',
      emailid: '',
      mobile: '',
      jobId: '',
    );
  }

  /// Start location tracking
  Future<bool> start() async {
    debugPrint('[NectarTracker] start() called');
    try {
      developer.log('NectarTracker: Starting location tracking...', name: 'NectarTracker');
      await NectarTrackerPlatform.instance.startTracking();
      _state?.enabled = true;
      developer.log('NectarTracker: Location tracking started successfully', name: 'NectarTracker');
      debugPrint('[NectarTracker] start() success');
      return true;
    } catch (e, stack) {
      developer.log('Failed to start tracking: $e', name: 'NectarTracker', level: 900);
      debugPrint('[NectarTracker] start() error: $e\n$stack');
      return false;
    }
  }

  /// Stop location tracking
  Future<bool> stop() async {
    debugPrint('[NectarTracker] stop() called');
    try {
      developer.log('NectarTracker: Stopping location tracking...', name: 'NectarTracker');
      await NectarTrackerPlatform.instance.stopTracking();
      _state?.enabled = false;
      developer.log('NectarTracker: Location tracking stopped successfully', name: 'NectarTracker');
      debugPrint('[NectarTracker] stop() success');
      return true;
    } catch (e, stack) {
      developer.log('Failed to stop tracking: $e', name: 'NectarTracker', level: 900);
      debugPrint('[NectarTracker] stop() error: $e\n$stack');
      return false;
    }
  }

  /// Get current state
  Future<NectarTrackerState> getState() async {
    debugPrint('[NectarTracker] getState() called');
    if (_state == null) {
      debugPrint('[NectarTracker] getState() error: Not configured');
      throw StateError('NectarTracker not configured. Call ready() first.');
    }
    debugPrint('[NectarTracker] getState() returns: $_state');
    return _state!;
  }

  /// Get current location
  Future<LocationData?> getCurrentPosition() async {
    debugPrint('[NectarTracker] getCurrentPosition() called');
    try {
      final loc = await NectarTrackerPlatform.instance.getCurrentLocation();
      debugPrint('[NectarTracker] getCurrentPosition() result: $loc');
      return loc;
    } catch (e, stack) {
      developer.log('Failed to get current position: $e', name: 'NectarTracker', level: 900);
      debugPrint('[NectarTracker] getCurrentPosition() error: $e\n$stack');
      return null;
    }
  }

  /// Check if location services are enabled
  Future<bool> isLocationServicesEnabled() async {
    debugPrint('[NectarTracker] isLocationServicesEnabled() called');
    try {
      final enabled = await NectarTrackerPlatform.instance.isLocationServiceEnabled();
      debugPrint('[NectarTracker] isLocationServicesEnabled() result: $enabled');
      return enabled;
    } catch (e, stack) {
      developer.log('Failed to check location services: $e', name: 'NectarTracker', level: 900);
      debugPrint('[NectarTracker] isLocationServicesEnabled() error: $e\n$stack');
      return false;
    }
  }

  /// Get tracking statistics
  Future<TrackingStats> getTrackingStats() async {
    debugPrint('[NectarTracker] getTrackingStats() called');
    try {
      final stats = await NectarTrackerPlatform.instance.getTrackingStats();
      debugPrint('[NectarTracker] getTrackingStats() result: $stats');
      return stats;
    } catch (e, stack) {
      developer.log('Failed to get tracking stats: $e', name: 'NectarTracker', level: 900);
      debugPrint('[NectarTracker] getTrackingStats() error: $e\n$stack');
      return TrackingStats();
    }
  }

  /// Clear tracking data
  Future<bool> clearTrackingData() async {
    debugPrint('[NectarTracker] clearTrackingData() called');
    try {
      final result = await NectarTrackerPlatform.instance.clearTrackingData();
      debugPrint('[NectarTracker] clearTrackingData() result: $result');
      return result;
    } catch (e, stack) {
      developer.log('Failed to clear tracking data: $e', name: 'NectarTracker', level: 900);
      debugPrint('[NectarTracker] clearTrackingData() error: $e\n$stack');
      return false;
    }
  }

  /// Get platform version
  Future<String?> getPlatformVersion() async {
    debugPrint('[NectarTracker] getPlatformVersion() called');
    try {
      final version = await NectarTrackerPlatform.instance.getPlatformVersion();
      debugPrint('[NectarTracker] getPlatformVersion() result: $version');
      return version;
    } catch (e, stack) {
      developer.log('Failed to get platform version: $e', name: 'NectarTracker', level: 900);
      debugPrint('[NectarTracker] getPlatformVersion() error: $e\n$stack');
      return null;
    }
  }

  // Event streams (similar to flutter_background_geolocation events)

  /// Fired whenever a location is recorded
  Stream<LocationData> get onLocation => _locationController.stream;

  /// Fired whenever the plugin changes motion-state (stationary->moving and vice-versa)
  Stream<LocationData> get onMotionChange => _motionChangeController.stream;

  /// Fired whenever the state of location-services changes
  Stream<ProviderChangeEvent> get onProviderChange => _providerChangeController.stream;

  /// Fired when user activity changes (walking, running, driving, etc)
  Stream<ActivityChangeEvent> get onActivityChange => _activityChangeController.stream;

  /// Fired when entering/exiting geofences
  Stream<GeofenceEvent> get onGeofence => _geofenceController.stream;

  /// Fired when heartbeat occurs
  Stream<HeartbeatEvent> get onHeartbeat => _heartbeatController.stream;

  /// Fired when HTTP requests complete
  Stream<HttpEvent> get onHttp => _httpController.stream;

  /// Fired when connectivity changes
  Stream<ConnectivityChangeEvent> get onConnectivityChange => _connectivityChangeController.stream;

  /// Fired when power-save mode changes
  Stream<PowerSaveChangeEvent> get onPowerSaveChange => _powerSaveChangeController.stream;

  // Additional event streams for more granular control
  Stream<ProviderChangeEvent> get onProviderChange2 => _providerChangeController2.stream;
  Stream<MotionChangeEvent> get onMotionChange2 => _motionChangeController2.stream;
  Stream<ActivityChangeEvent> get onActivityChange2 => _activityChangeController2.stream;

  /// Internal method to handle location updates from platform
  void handleLocationUpdate(LocationData location) {
    debugPrint('[NectarTracker] handleLocationUpdate() called with: $location');
    _locationController.add(location);

    // Simulate motion change based on speed
    if (location.speed > 0.5) {
      // Moving threshold
      _motionChangeController.add(location);
    }
  }

  /// Dispose all streams
  void dispose() {
    debugPrint('[NectarTracker] dispose() called');
    _platformLocationSubscription?.cancel();
    _locationController.close();
    _motionChangeController.close();
    _providerChangeController.close();
    _activityChangeController.close();
    _geofenceController.close();
    _heartbeatController.close();
    _httpController.close();
    _connectivityChangeController.close();
    _powerSaveChangeController.close();
    _providerChangeController2.close();
    _motionChangeController2.close();
    _activityChangeController2.close();
  }
}

// Configuration class (similar to flutter_background_geolocation Config)
class NectarTrackerConfig {
  final DesiredAccuracy desiredAccuracy;
  final double distanceFilter;
  final bool stopOnTerminate;
  final bool startOnBoot;
  final bool debug;
  final LogLevel logLevel;
  final bool enableBatteryOptimization;
  final String notificationTitle;
  final String notificationText;
  final int interval;
  final int fastestInterval;
  final String? notificationIcon;
  final String? notificationColor;
  final bool showLocationNotifications;

  const NectarTrackerConfig({
    this.desiredAccuracy = DesiredAccuracy.high,
    this.distanceFilter = 10.0,
    this.stopOnTerminate = false,
    this.startOnBoot = true,
    this.debug = true,
    this.logLevel = LogLevel.verbose,
    this.enableBatteryOptimization = false,
    this.notificationTitle = 'Location Tracking',
    this.notificationText = 'Tracking your location in background',
    this.interval = 5000,
    this.fastestInterval = 3000,
    this.notificationIcon,
    this.notificationColor,
    this.showLocationNotifications = false,
  });
}

// State class (similar to flutter_background_geolocation State)
class NectarTrackerState {
  bool enabled;
  bool isMoving;
  bool locationServicesEnabled;
  AuthorizationStatus authorization;
  ActivityType activity;
  ProviderChangeEvent provider;

  NectarTrackerState({
    required this.enabled,
    required this.isMoving,
    required this.locationServicesEnabled,
    required this.authorization,
    required this.activity,
    required this.provider,
  });
}

// Enums (similar to flutter_background_geolocation)
enum DesiredAccuracy { low, medium, high, best }

enum LogLevel { off, error, warning, info, debug, verbose }

enum AuthorizationStatus { denied, authorized, authorizedAlways, authorizedWhenInUse }

enum ActivityType { unknown, still, walking, running, automotive, cycling }

// Event classes (similar to flutter_background_geolocation events)
class ProviderChangeEvent {
  final bool gps;
  final bool network;
  final bool enabled;

  ProviderChangeEvent({required this.gps, required this.network, required this.enabled});

  @override
  String toString() => 'ProviderChangeEvent(gps: $gps, network: $network, enabled: $enabled)';
}

class ActivityChangeEvent {
  final ActivityType activity;
  final LocationData? location;

  ActivityChangeEvent({required this.activity, this.location});

  @override
  String toString() => 'ActivityChangeEvent(activity: $activity)';
}

class MotionChangeEvent {
  final bool isMoving;
  final LocationData? location;

  MotionChangeEvent({required this.isMoving, this.location});

  @override
  String toString() => 'MotionChangeEvent(isMoving: $isMoving)';
}

class GeofenceEvent {
  final String identifier;
  final bool enter;
  final LocationData? location;

  GeofenceEvent({required this.identifier, required this.enter, this.location});

  @override
  String toString() => 'GeofenceEvent(identifier: $identifier, enter: $enter)';
}

class HeartbeatEvent {
  final LocationData? location;

  HeartbeatEvent({this.location});

  @override
  String toString() => 'HeartbeatEvent()';
}

class HttpEvent {
  final bool success;
  final int status;
  final String responseText;

  HttpEvent({required this.success, required this.status, required this.responseText});

  @override
  String toString() => 'HttpEvent(success: $success, status: $status)';
}

class ConnectivityChangeEvent {
  final bool connected;

  ConnectivityChangeEvent({required this.connected});

  @override
  String toString() => 'ConnectivityChangeEvent(connected: $connected)';
}

class PowerSaveChangeEvent {
  final bool isPowerSaveMode;

  PowerSaveChangeEvent({required this.isPowerSaveMode});

  @override
  String toString() => 'PowerSaveChangeEvent(isPowerSaveMode: $isPowerSaveMode)';
}
