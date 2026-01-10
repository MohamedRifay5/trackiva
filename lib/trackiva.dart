import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:graphql/client.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'trackiva_platform_interface.dart';
import 'trackiva_storage.dart';

/// Main class for Trackiva - location tracking with MQTT, GraphQL, HTTP, and offline sync
class Trackiva {
  static final Trackiva _instance = Trackiva._internal();
  factory Trackiva() => _instance;
  Trackiva._internal() {
    _initConnectivityListener();
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
  TrackivaConfig? _config;
  TrackivaState? _state;

  StreamSubscription<LocationData>? _platformLocationSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Storage and sync
  TrackivaStorage? _storage;
  bool _isOnline = false;
  bool _isSyncing = false;

  // HTTP client
  http.Client? _httpClient;

  // GraphQL client
  GraphQLClient? _graphqlClient;

  /// Initialize storage
  Future<void> _initStorage() async {
    _storage ??= TrackivaStorage();
    await _storage!.initialize();
  }

  /// Initialize connectivity listener
  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final wasOnline = _isOnline;
      _isOnline = results.any((result) => result != ConnectivityResult.none);

      if (_isOnline != wasOnline) {
        _connectivityChangeController.add(ConnectivityChangeEvent(connected: _isOnline));
        debugPrint('[Trackiva] Connectivity changed: ${_isOnline ? "ONLINE" : "OFFLINE"}');

        if (_isOnline && !_isSyncing) {
          _syncPendingLocations();
        }
      }
    });
  }

  /// Check current connectivity status
  Future<void> _checkConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    _isOnline = results.any((result) => result != ConnectivityResult.none);
  }

  /// Listen to the platform event channel and forward locations to handleLocationUpdate
  void _startPlatformEventListener() {
    debugPrint('[Trackiva] Subscribing to platform onLocationUpdate event channel');
    _platformLocationSubscription?.cancel();
    _platformLocationSubscription = TrackivaPlatform.instance.onLocationUpdate.listen(
      (location) {
        debugPrint('[Trackiva] Received location from platform: $location');
        handleLocationUpdate(location);
      },
      onError: (error) {
        debugPrint('[Trackiva] Error from platform event channel: $error');
      },
      cancelOnError: false,
    );
  }

  /// Initialize and configure the plugin
  Future<TrackivaState> ready(TrackivaConfig config) async {
    try {
      developer.log('Trackiva: Configuring plugin...', name: 'Trackiva');
      debugPrint('[Trackiva] ready() called with config: $config');
      _config = config;

      // Initialize storage
      await _initStorage();

      // Check connectivity
      await _checkConnectivity();

      // Initialize HTTP client if HTTP is enabled
      if (config.enableHttp) {
        _httpClient = http.Client();
      }

      // Initialize GraphQL client if GraphQL is enabled
      if (config.enableGraphQL && config.graphqlEndpoint != null) {
        final httpLink = HttpLink(config.graphqlEndpoint!);
        _graphqlClient = GraphQLClient(link: httpLink, cache: GraphQLCache());
      }

      // Initialize platform
      await TrackivaPlatform.instance.initialize(
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
        chatHeadIcon: config.chatHeadIcon,
        enableLogging: config.debug,
        showLocationNotifications: config.showLocationNotifications,
      );

      // Start listening to platform event channel
      _startPlatformEventListener();

      // Get current state
      final isTracking = await TrackivaPlatform.instance.isTracking();
      final isLocationServiceEnabled = await TrackivaPlatform.instance.isLocationServiceEnabled();

      _state = TrackivaState(
        enabled: isTracking,
        isMoving: false,
        locationServicesEnabled: isLocationServiceEnabled,
        authorization: AuthorizationStatus.authorized,
        activity: ActivityType.unknown,
        provider: ProviderChangeEvent(
          gps: isLocationServiceEnabled,
          network: isLocationServiceEnabled,
          enabled: isLocationServiceEnabled,
        ),
      );

      developer.log('Trackiva: Plugin configured successfully', name: 'Trackiva');
      debugPrint('[Trackiva] ready() completed, state: $_state');
      return _state!;
    } catch (e, stack) {
      developer.log('Failed to configure Trackiva: $e', name: 'Trackiva', level: 900);
      debugPrint('[Trackiva] ready() error: $e\n$stack');
      rethrow;
    }
  }

  /// Configure MQTT with flexible payload
  ///
  /// [broker] - MQTT broker hostname
  /// [port] - MQTT broker port (use 8883 or 8884 for SSL/TLS)
  /// [username] - MQTT username (optional)
  /// [password] - MQTT password (optional)
  /// [topic] - MQTT topic to publish location data
  // ignore: unintended_html_in_doc_comment
  /// [payload] - Flexible Map<String, dynamic> containing any custom data to include in location payload
  ///             This will be merged with location data when publishing to MQTT
  Future<void> setMqttConfigAndDetails({
    required String broker,
    required int port,
    required String username,
    required String password,
    required String topic,
    required Map<String, dynamic> payload,
  }) async {
    await TrackivaPlatform.instance.setMqttConfigAndDetails(
      broker: broker,
      port: port,
      username: username,
      password: password,
      topic: topic,
      payload: payload,
    );
  }

  /// Configure HTTP endpoint
  Future<void> setHttpConfig({required String endpoint, Map<String, String>? headers, String? method}) async {
    await TrackivaPlatform.instance.setHttpConfig(endpoint: endpoint, headers: headers ?? {}, method: method ?? 'POST');
  }

  /// Configure GraphQL endpoint and mutation
  Future<void> setGraphQLConfig({
    required String endpoint,
    required String mutation,
    Map<String, String>? headers,
  }) async {
    if (_graphqlClient == null && endpoint.isNotEmpty) {
      final httpLink = HttpLink(endpoint);
      _graphqlClient = GraphQLClient(link: httpLink, cache: GraphQLCache());
    }
    await TrackivaPlatform.instance.setGraphQLConfig(endpoint: endpoint, mutation: mutation, headers: headers ?? {});
  }

  /// Start location tracking
  Future<bool> start() async {
    debugPrint('[Trackiva] start() called');
    try {
      developer.log('Trackiva: Starting location tracking...', name: 'Trackiva');
      await TrackivaPlatform.instance.startTracking();
      _state?.enabled = true;
      developer.log('Trackiva: Location tracking started successfully', name: 'Trackiva');
      debugPrint('[Trackiva] start() success');
      return true;
    } on PlatformException catch (e) {
      if (e.code == 'OVERLAY_PERMISSION_NEEDED') {
        developer.log(
          'Trackiva: Overlay permission needed. User should grant permission and try again.',
          name: 'Trackiva',
        );
        debugPrint('[Trackiva] Overlay permission needed: ${e.message}');
        rethrow;
      }
      developer.log('Failed to start tracking: $e', name: 'Trackiva', level: 900);
      debugPrint('[Trackiva] start() error: $e');
      return false;
    } catch (e, stack) {
      developer.log('Failed to start tracking: $e', name: 'Trackiva', level: 900);
      debugPrint('[Trackiva] start() error: $e\n$stack');
      return false;
    }
  }

  /// Stop location tracking
  Future<bool> stop() async {
    debugPrint('[Trackiva] stop() called');
    try {
      developer.log('Trackiva: Stopping location tracking...', name: 'Trackiva');
      await TrackivaPlatform.instance.stopTracking();
      _state?.enabled = false;
      developer.log('Trackiva: Location tracking stopped successfully', name: 'Trackiva');
      debugPrint('[Trackiva] stop() success');
      return true;
    } catch (e, stack) {
      developer.log('Failed to stop tracking: $e', name: 'Trackiva', level: 900);
      debugPrint('[Trackiva] stop() error: $e\n$stack');
      return false;
    }
  }

  /// Get current state
  Future<TrackivaState> getState() async {
    debugPrint('[Trackiva] getState() called');
    if (_state == null) {
      debugPrint('[Trackiva] getState() error: Not configured');
      throw StateError('Trackiva not configured. Call ready() first.');
    }
    debugPrint('[Trackiva] getState() returns: $_state');
    return _state!;
  }

  /// Get current location
  Future<LocationData?> getCurrentPosition() async {
    debugPrint('[Trackiva] getCurrentPosition() called');
    try {
      final loc = await TrackivaPlatform.instance.getCurrentLocation();
      debugPrint('[Trackiva] getCurrentPosition() result: $loc');
      return loc;
    } catch (e, stack) {
      developer.log('Failed to get current position: $e', name: 'Trackiva', level: 900);
      debugPrint('[Trackiva] getCurrentPosition() error: $e\n$stack');
      return null;
    }
  }

  /// Check if location services are enabled
  Future<bool> isLocationServicesEnabled() async {
    debugPrint('[Trackiva] isLocationServicesEnabled() called');
    try {
      final enabled = await TrackivaPlatform.instance.isLocationServiceEnabled();
      debugPrint('[Trackiva] isLocationServicesEnabled() result: $enabled');
      return enabled;
    } catch (e, stack) {
      developer.log('Failed to check location services: $e', name: 'Trackiva', level: 900);
      debugPrint('[Trackiva] isLocationServicesEnabled() error: $e\n$stack');
      return false;
    }
  }

  /// Get tracking statistics
  Future<TrackingStats> getTrackingStats() async {
    debugPrint('[Trackiva] getTrackingStats() called');
    try {
      final stats = await TrackivaPlatform.instance.getTrackingStats();
      debugPrint('[Trackiva] getTrackingStats() result: $stats');
      return stats;
    } catch (e, stack) {
      developer.log('Failed to get tracking stats: $e', name: 'Trackiva', level: 900);
      debugPrint('[Trackiva] getTrackingStats() error: $e\n$stack');
      return TrackingStats();
    }
  }

  /// Clear tracking data
  Future<bool> clearTrackingData() async {
    debugPrint('[Trackiva] clearTrackingData() called');
    try {
      final result = await TrackivaPlatform.instance.clearTrackingData();
      if (_storage != null) {
        await _storage!.clearAll();
      }
      debugPrint('[Trackiva] clearTrackingData() result: $result');
      return result;
    } catch (e, stack) {
      developer.log('Failed to clear tracking data: $e', name: 'Trackiva', level: 900);
      debugPrint('[Trackiva] clearTrackingData() error: $e\n$stack');
      return false;
    }
  }

  /// Get platform version
  Future<String?> getPlatformVersion() async {
    debugPrint('[Trackiva] getPlatformVersion() called');
    try {
      final version = await TrackivaPlatform.instance.getPlatformVersion();
      debugPrint('[Trackiva] getPlatformVersion() result: $version');
      return version;
    } catch (e, stack) {
      developer.log('Failed to get platform version: $e', name: 'Trackiva', level: 900);
      debugPrint('[Trackiva] getPlatformVersion() error: $e\n$stack');
      return null;
    }
  }

  /// Get MQTT connection status
  Future<Map<String, dynamic>> getMqttStatus() async {
    debugPrint('[Trackiva] getMqttStatus() called');
    try {
      final status = await TrackivaPlatform.instance.getMqttStatus();
      debugPrint('[Trackiva] getMqttStatus() result: $status');
      return status;
    } catch (e, stack) {
      developer.log('Failed to get MQTT status: $e', name: 'Trackiva', level: 900);
      debugPrint('[Trackiva] getMqttStatus() error: $e\n$stack');
      return {};
    }
  }

  /// Send location via HTTP
  Future<bool> _sendLocationViaHttp(LocationData location, Map<String, dynamic> metadata) async {
    if (_httpClient == null || _config?.httpEndpoint == null) {
      return false;
    }

    try {
      final payload = {
        'location': {
          'latitude': location.latitude,
          'longitude': location.longitude,
          'accuracy': location.accuracy,
          'altitude': location.altitude,
          'speed': location.speed,
          'bearing': location.bearing,
          'timestamp': location.timestamp.toIso8601String(),
        },
        ...metadata,
      };

      final response = await _httpClient!
          .post(
            Uri.parse(_config!.httpEndpoint!),
            headers: {'Content-Type': 'application/json', ...?(_config!.httpHeaders)},
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: 10));

      final success = response.statusCode >= 200 && response.statusCode < 300;
      _httpController.add(HttpEvent(success: success, status: response.statusCode, responseText: response.body));

      return success;
    } catch (e) {
      debugPrint('[Trackiva] HTTP send failed: $e');
      _httpController.add(HttpEvent(success: false, status: 0, responseText: e.toString()));
      return false;
    }
  }

  /// Send location via GraphQL
  Future<bool> _sendLocationViaGraphQL(LocationData location, Map<String, dynamic> metadata) async {
    if (_graphqlClient == null || _config?.graphqlMutation == null) {
      return false;
    }

    try {
      final variables = {
        'location': {
          'latitude': location.latitude,
          'longitude': location.longitude,
          'accuracy': location.accuracy,
          'altitude': location.altitude,
          'speed': location.speed,
          'bearing': location.bearing,
          'timestamp': location.timestamp.toIso8601String(),
        },
        ...metadata,
      };

      // Parse GraphQL mutation string to DocumentNode
      // Using gql function which should be available from graphql package
      DocumentNode mutation;
      try {
        // Try to use gql if available, otherwise parse manually
        mutation = gql(_config!.graphqlMutation!);
      } catch (e) {
        // Fallback: parse the string using gql package
        mutation = parseString(_config!.graphqlMutation!);
      }

      final result = await _graphqlClient!
          .mutate(MutationOptions(document: mutation, variables: variables))
          .timeout(Duration(seconds: 10));

      final success = result.hasException == false;
      _httpController.add(
        HttpEvent(
          success: success,
          status: success ? 200 : 500,
          responseText: result.data?.toString() ?? result.exception?.toString() ?? '',
        ),
      );

      return success;
    } catch (e) {
      debugPrint('[Trackiva] GraphQL send failed: $e');
      _httpController.add(HttpEvent(success: false, status: 0, responseText: e.toString()));
      return false;
    }
  }

  /// Save location to offline storage
  Future<void> _saveLocationOffline(LocationData location, Map<String, dynamic> metadata) async {
    if (_storage == null) {
      await _initStorage();
    }

    try {
      await _storage!.saveLocation(location, metadata);
      debugPrint('[Trackiva] Location saved offline');
    } catch (e) {
      debugPrint('[Trackiva] Failed to save location offline: $e');
    }
  }

  /// Sync pending locations when online
  Future<void> _syncPendingLocations() async {
    if (_isSyncing || _storage == null) return;

    _isSyncing = true;
    debugPrint('[Trackiva] Starting sync of pending locations...');

    try {
      final pendingLocations = await _storage!.getPendingLocations();
      debugPrint('[Trackiva] Found ${pendingLocations.length} pending locations');

      for (final item in pendingLocations) {
        final location = item['location'] as LocationData;
        final metadata = item['metadata'] as Map<String, dynamic>;

        bool success = false;

        // Try MQTT (handled by platform)
        // Try HTTP
        if (_config?.enableHttp == true && _config?.httpEndpoint != null) {
          success = await _sendLocationViaHttp(location, metadata);
        }

        // Try GraphQL
        if (!success && _config?.enableGraphQL == true && _config?.graphqlMutation != null) {
          success = await _sendLocationViaGraphQL(location, metadata);
        }

        if (success) {
          await _storage!.markLocationAsSynced(item['id'] as int);
          debugPrint('[Trackiva] Synced location ${item['id']}');
        }
      }

      debugPrint('[Trackiva] Sync completed');
    } catch (e) {
      debugPrint('[Trackiva] Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Internal method to handle location updates from platform
  void handleLocationUpdate(LocationData location) {
    debugPrint('[Trackiva] handleLocationUpdate() called with: $location');
    _locationController.add(location);

    // Simulate motion change based on speed
    if (location.speed > 0.5) {
      _motionChangeController.add(location);
    }

    // Get metadata from platform
    _getLocationMetadata().then((metadata) {
      // Save to offline storage first
      _saveLocationOffline(location, metadata);

      // If online, try to send immediately
      if (_isOnline) {
        // MQTT is handled by platform
        // Try HTTP
        if (_config?.enableHttp == true) {
          _sendLocationViaHttp(location, metadata);
        }
        // Try GraphQL
        if (_config?.enableGraphQL == true) {
          _sendLocationViaGraphQL(location, metadata);
        }
      }
    });
  }

  /// Get location metadata from platform (flexible payload)
  Future<Map<String, dynamic>> _getLocationMetadata() async {
    try {
      final mqttStatus = await getMqttStatus();
      // Return the flexible payload stored in MQTT status
      final payload = mqttStatus['payload'] as Map<String, dynamic>?;
      return payload ?? {};
    } catch (e) {
      return {};
    }
  }

  // Event streams

  /// Fired whenever a location is recorded
  Stream<LocationData> get onLocation => _locationController.stream;

  /// Fired whenever the plugin changes motion-state
  Stream<LocationData> get onMotionChange => _motionChangeController.stream;

  /// Fired whenever the state of location-services changes
  Stream<ProviderChangeEvent> get onProviderChange => _providerChangeController.stream;

  /// Fired when user activity changes
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

  // Additional event streams
  Stream<ProviderChangeEvent> get onProviderChange2 => _providerChangeController2.stream;
  Stream<MotionChangeEvent> get onMotionChange2 => _motionChangeController2.stream;
  Stream<ActivityChangeEvent> get onActivityChange2 => _activityChangeController2.stream;

  /// Dispose all streams
  void dispose() {
    debugPrint('[Trackiva] dispose() called');
    _platformLocationSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _httpClient?.close();
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

// Configuration class
class TrackivaConfig {
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
  final String? chatHeadIcon;
  final bool showLocationNotifications;

  // HTTP support
  final bool enableHttp;
  final String? httpEndpoint;
  final Map<String, String>? httpHeaders;

  // GraphQL support
  final bool enableGraphQL;
  final String? graphqlEndpoint;
  final String? graphqlMutation;
  final Map<String, String>? graphqlHeaders;

  const TrackivaConfig({
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
    this.chatHeadIcon,
    this.showLocationNotifications = false,
    this.enableHttp = false,
    this.httpEndpoint,
    this.httpHeaders,
    this.enableGraphQL = false,
    this.graphqlEndpoint,
    this.graphqlMutation,
    this.graphqlHeaders,
  });
}

// State class
class TrackivaState {
  bool enabled;
  bool isMoving;
  bool locationServicesEnabled;
  AuthorizationStatus authorization;
  ActivityType activity;
  ProviderChangeEvent provider;

  TrackivaState({
    required this.enabled,
    required this.isMoving,
    required this.locationServicesEnabled,
    required this.authorization,
    required this.activity,
    required this.provider,
  });
}

// Enums
enum DesiredAccuracy { low, medium, high, best }

enum LogLevel { off, error, warning, info, debug, verbose }

enum AuthorizationStatus { denied, authorized, authorizedAlways, authorizedWhenInUse }

enum ActivityType { unknown, still, walking, running, automotive, cycling }

// Event classes
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
