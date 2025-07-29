import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nectar_tracker/nectar_tracker.dart';
import 'package:nectar_tracker/nectar_tracker_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NectarTracker', () {
    const MethodChannel channel = MethodChannel('nectar_tracker');
    // ignore: unused_local_variable
    const EventChannel eventChannel = EventChannel('nectar_tracker/updates');
    final log = <MethodCall>[];

    setUp(() {
      channel.setMethodCallHandler((MethodCall methodCall) async {
        log.add(methodCall);
        switch (methodCall.method) {
          case 'initialize':
            return null;
          case 'startTracking':
            return null;
          case 'stopTracking':
            return null;
          case 'isTracking':
            return true;
          case 'getCurrentLocation':
            return {
              'latitude': 37.7749,
              'longitude': -122.4194,
              'accuracy': 10.0,
              'altitude': 0.0,
              'speed': 0.0,
              'bearing': 0.0,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'isBackground': false,
              'provider': 'test',
            };
          case 'isLocationServiceEnabled':
            return true;
          case 'getTrackingStats':
            return {
              'totalLocations': 10,
              'foregroundLocations': 5,
              'backgroundLocations': 5,
              'firstLocationTime': DateTime.now().millisecondsSinceEpoch,
              'lastLocationTime': DateTime.now().millisecondsSinceEpoch,
              'totalDistance': 100.0,
              'averageSpeed': 10.0,
            };
          case 'clearTrackingData':
            return true;
          case 'getPlatformVersion':
            return 'Test Platform';
          default:
            return null;
        }
      });
    });

    tearDown(() {
      log.clear();
    });

    test('ready configures the plugin correctly', () async {
      final nectarTracker = NectarTracker();

      final config = NectarTrackerConfig(
        desiredAccuracy: DesiredAccuracy.high,
        distanceFilter: 10.0,
        stopOnTerminate: false,
        startOnBoot: true,
        debug: true,
        logLevel: LogLevel.verbose,
      );

      final state = await nectarTracker.ready(config);

      expect(log, hasLength(3)); // initialize, isTracking, isLocationServiceEnabled
      expect(log.first.method, 'initialize');
      expect(state.enabled, true);
      expect(state.locationServicesEnabled, true);
      expect(state.authorization, AuthorizationStatus.authorized);
    });

    test('start begins location tracking', () async {
      final nectarTracker = NectarTracker();

      final result = await nectarTracker.start();

      expect(result, true);
      expect(log, hasLength(1));
      expect(log.first.method, 'startTracking');
    });

    test('stop ends location tracking', () async {
      final nectarTracker = NectarTracker();

      final result = await nectarTracker.stop();

      expect(result, true);
      expect(log, hasLength(1));
      expect(log.first.method, 'stopTracking');
    });

    test('getCurrentPosition returns current location', () async {
      final nectarTracker = NectarTracker();

      final location = await nectarTracker.getCurrentPosition();

      expect(location, isNotNull);
      expect(location!.latitude, 37.7749);
      expect(location.longitude, -122.4194);
      expect(log, hasLength(1));
      expect(log.first.method, 'getCurrentLocation');
    });

    test('isLocationServicesEnabled checks location services', () async {
      final nectarTracker = NectarTracker();

      final result = await nectarTracker.isLocationServicesEnabled();

      expect(result, true);
      expect(log, hasLength(1));
      expect(log.first.method, 'isLocationServiceEnabled');
    });

    test('getTrackingStats returns tracking statistics', () async {
      final nectarTracker = NectarTracker();

      final stats = await nectarTracker.getTrackingStats();

      expect(stats.totalLocations, 10);
      expect(stats.totalDistance, 100.0);
      expect(stats.averageSpeed, 10.0);
      expect(log, hasLength(1));
      expect(log.first.method, 'getTrackingStats');
    });

    test('clearTrackingData clears tracking data', () async {
      final nectarTracker = NectarTracker();

      final result = await nectarTracker.clearTrackingData();

      expect(result, true);
      expect(log, hasLength(1));
      expect(log.first.method, 'clearTrackingData');
    });

    test('getState returns current state', () async {
      final nectarTracker = NectarTracker();

      // First configure the plugin
      final config = NectarTrackerConfig();
      await nectarTracker.ready(config);

      final state = await nectarTracker.getState();

      expect(state.enabled, true);
      expect(state.locationServicesEnabled, true);
    });

    // test('getState throws error when not configured', () async {
    //   final nectarTracker = NectarTracker();
    //   expect(() async => await nectarTracker.getState(), throwsA(isA<StateError>()));
    // });

    test('onLocation stream provides location updates', () async {
      final nectarTracker = NectarTracker();
      final mockLocation = LocationData(
        latitude: 37.7749,
        longitude: -122.4194,
        accuracy: 5.0,
        altitude: 10.0,
        speed: 0.0,
        bearing: 0.0,
        timestamp: DateTime.now(),
        isBackground: false,
        provider: 'GPS',
      );

      // Listen to the stream
      final locations = <LocationData>[];
      nectarTracker.onLocation.listen(locations.add);

      // Simulate location update
      nectarTracker.handleLocationUpdate(mockLocation);

      // Wait a bit for the stream to process
      await Future.delayed(Duration(milliseconds: 10));

      expect(locations.length, 1);
      expect(locations.first.latitude, 37.7749);
      expect(locations.first.longitude, -122.4194);
    });

    test('onMotionChange stream provides motion updates', () async {
      final nectarTracker = NectarTracker();
      final mockLocation = LocationData(
        latitude: 37.7749,
        longitude: -122.4194,
        accuracy: 5.0,
        altitude: 10.0,
        speed: 1.0, // Moving speed
        bearing: 0.0,
        timestamp: DateTime.now(),
        isBackground: false,
        provider: 'GPS',
      );

      // Listen to the stream
      final motionUpdates = <LocationData>[];
      nectarTracker.onMotionChange.listen(motionUpdates.add);

      // Simulate location update with movement
      nectarTracker.handleLocationUpdate(mockLocation);

      // Wait a bit for the stream to process
      await Future.delayed(Duration(milliseconds: 10));

      expect(motionUpdates.length, 1);
      expect(motionUpdates.first.speed, 1.0);
    });

    test('getPlatformVersion returns platform version', () async {
      final nectarTracker = NectarTracker();

      final version = await nectarTracker.getPlatformVersion();

      expect(version, 'Test Platform');
      expect(log, hasLength(1));
      expect(log.first.method, 'getPlatformVersion');
    });
  });

  group('NectarTrackerConfig', () {
    test('creates config with default values', () {
      final config = NectarTrackerConfig();

      expect(config.desiredAccuracy, DesiredAccuracy.high);
      expect(config.distanceFilter, 10.0);
      expect(config.stopOnTerminate, false);
      expect(config.startOnBoot, true);
      expect(config.debug, true);
      expect(config.logLevel, LogLevel.verbose);
    });

    test('creates config with custom values', () {
      final config = NectarTrackerConfig(
        desiredAccuracy: DesiredAccuracy.low,
        distanceFilter: 50.0,
        stopOnTerminate: true,
        startOnBoot: false,
        debug: false,
        logLevel: LogLevel.error,
      );

      expect(config.desiredAccuracy, DesiredAccuracy.low);
      expect(config.distanceFilter, 50.0);
      expect(config.stopOnTerminate, true);
      expect(config.startOnBoot, false);
      expect(config.debug, false);
      expect(config.logLevel, LogLevel.error);
    });
  });

  group('NectarTrackerState', () {
    test('creates state with all properties', () {
      final provider = ProviderChangeEvent(gps: true, network: true, enabled: true);

      final state = NectarTrackerState(
        enabled: true,
        isMoving: false,
        locationServicesEnabled: true,
        authorization: AuthorizationStatus.authorized,
        activity: ActivityType.still,
        provider: provider,
      );

      expect(state.enabled, true);
      expect(state.isMoving, false);
      expect(state.locationServicesEnabled, true);
      expect(state.authorization, AuthorizationStatus.authorized);
      expect(state.activity, ActivityType.still);
      expect(state.provider, provider);
    });
  });

  group('Event Classes', () {
    test('ProviderChangeEvent toString', () {
      final event = ProviderChangeEvent(gps: true, network: false, enabled: true);

      expect(event.toString(), 'ProviderChangeEvent(gps: true, network: false, enabled: true)');
    });

    test('ActivityChangeEvent toString', () {
      final event = ActivityChangeEvent(activity: ActivityType.walking);

      expect(event.toString(), 'ActivityChangeEvent(activity: ActivityType.walking)');
    });

    test('MotionChangeEvent toString', () {
      final event = MotionChangeEvent(isMoving: true);

      expect(event.toString(), 'MotionChangeEvent(isMoving: true)');
    });

    test('GeofenceEvent toString', () {
      final event = GeofenceEvent(identifier: 'test-geofence', enter: true);

      expect(event.toString(), 'GeofenceEvent(identifier: test-geofence, enter: true)');
    });

    test('HeartbeatEvent toString', () {
      final event = HeartbeatEvent();

      expect(event.toString(), 'HeartbeatEvent()');
    });

    test('HttpEvent toString', () {
      final event = HttpEvent(success: true, status: 200, responseText: 'OK');

      expect(event.toString(), 'HttpEvent(success: true, status: 200)');
    });

    test('ConnectivityChangeEvent toString', () {
      final event = ConnectivityChangeEvent(connected: true);

      expect(event.toString(), 'ConnectivityChangeEvent(connected: true)');
    });

    test('PowerSaveChangeEvent toString', () {
      final event = PowerSaveChangeEvent(isPowerSaveMode: false);

      expect(event.toString(), 'PowerSaveChangeEvent(isPowerSaveMode: false)');
    });
  });
}
