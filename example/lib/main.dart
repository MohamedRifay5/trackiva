import 'package:flutter/material.dart';
import 'package:nectar_tracker/nectar_tracker.dart';
import 'package:nectar_tracker/nectar_tracker_platform_interface.dart';
import 'dart:math';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _nectarTracker = NectarTracker();

  // State variables
  String _platformVersion = 'Unknown';
  String _status = 'Not configured';
  bool _isConfigured = false;
  bool _isTracking = false;
  NectarTrackerState? _currentState;

  // Live location tracking
  LocationData? _currentLocation;
  final List<LocationData> _locationHistory = [];
  double _totalDistance = 0.0;
  double _averageSpeed = 0.0;
  DateTime? _lastLocationTime;
  int _locationCount = 0;

  // Event logs
  final List<String> _locationLogs = [];
  final List<String> _motionLogs = [];
  final List<String> _providerLogs = [];
  final List<String> _activityLogs = [];
  final List<String> _geofenceLogs = [];
  final List<String> _heartbeatLogs = [];
  final List<String> _httpLogs = [];
  final List<String> _connectivityLogs = [];
  final List<String> _powerSaveLogs = [];
  final List<String> _actionLogs = [];

  // Configuration
  NectarTrackerConfig _config = NectarTrackerConfig();

  @override
  void initState() {
    super.initState();
    _requestPermissions().then((_) {
      _initPlatformState();
      _setupEventListeners();
    });
  }

  Future<void> _requestPermissions() async {
    _addLog(_actionLogs, '[Permissions] Requesting location and notification permissions...');

    // Request location permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.locationWhenInUse,
      Permission.locationAlways,
      Permission.notification,
    ].request();

    // Log permission results
    for (var permission in statuses.keys) {
      var status = statuses[permission];
      _addLog(_actionLogs, '[Permissions] ${permission.toString()}: $status');
    }

    // Check if we have the necessary permissions
    bool hasLocationPermission =
        statuses[Permission.location]?.isGranted == true ||
        statuses[Permission.locationWhenInUse]?.isGranted == true ||
        statuses[Permission.locationAlways]?.isGranted == true;

    bool hasNotificationPermission = statuses[Permission.notification]?.isGranted == true;

    if (hasLocationPermission) {
      _addLog(_actionLogs, '[Permissions] Location permission granted');
    } else {
      _addLog(_actionLogs, '[Permissions] WARNING: Location permission not granted');
    }

    if (hasNotificationPermission) {
      _addLog(_actionLogs, '[Permissions] Notification permission granted');
    } else {
      _addLog(_actionLogs, '[Permissions] WARNING: Notification permission not granted');
    }

    return;
  }

  Future<void> _initPlatformState() async {
    String platformVersion;
    try {
      platformVersion = await _nectarTracker.getPlatformVersion() ?? 'Unknown';
    } catch (e) {
      platformVersion = 'Failed to get platform version: $e';
    }

    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  void _setupEventListeners() {
    // Location events
    _nectarTracker.onLocation.listen((location) {
      _updateLiveLocation(location);
      _addLog(
        _locationLogs,
        'Location: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)} (${location.isBackground ? "Background" : "Foreground"})',
      );
      _addLog(
        _actionLogs,
        '[Location] ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)} (${location.isBackground ? "BG" : "FG"})',
      );
    });

    // Motion change events
    _nectarTracker.onMotionChange.listen((location) {
      _addLog(
        _motionLogs,
        'Motion Change: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)} (Speed: ${location.speed.toStringAsFixed(2)} m/s)',
      );
      _addLog(_actionLogs, '[MotionChange] Speed: ${location.speed.toStringAsFixed(2)} m/s');
    });

    // Provider change events
    _nectarTracker.onProviderChange.listen((event) {
      _addLog(_providerLogs, 'Provider Change: GPS=${event.gps}, Network=${event.network}, Enabled=${event.enabled}');
      _addLog(_actionLogs, '[ProviderChange] GPS=${event.gps}, Network=${event.network}, Enabled=${event.enabled}');
    });

    // Activity change events
    _nectarTracker.onActivityChange.listen((event) {
      _addLog(_activityLogs, 'Activity Change: ${event.activity.toString().split('.').last}');
      _addLog(_actionLogs, '[ActivityChange] ${event.activity.toString().split('.').last}');
    });

    // Geofence events
    _nectarTracker.onGeofence.listen((event) {
      _addLog(_geofenceLogs, 'Geofence: ${event.identifier} ${event.enter ? "ENTER" : "EXIT"}');
      _addLog(_actionLogs, '[Geofence] ${event.identifier} ${event.enter ? "ENTER" : "EXIT"}');
    });

    // Heartbeat events
    _nectarTracker.onHeartbeat.listen((event) {
      _addLog(_heartbeatLogs, 'Heartbeat: ${DateTime.now().toIso8601String().substring(11, 19)}');
      _addLog(_actionLogs, '[Heartbeat]');
    });

    // HTTP events
    _nectarTracker.onHttp.listen((event) {
      _addLog(_httpLogs, 'HTTP: ${event.success ? "SUCCESS" : "FAILED"} (${event.status})');
      _addLog(_actionLogs, '[HTTP] ${event.success ? "SUCCESS" : "FAILED"} (${event.status})');
    });

    // Connectivity change events
    _nectarTracker.onConnectivityChange.listen((event) {
      _addLog(_connectivityLogs, 'Connectivity: ${event.connected ? "CONNECTED" : "DISCONNECTED"}');
      _addLog(_actionLogs, '[Connectivity] ${event.connected ? "CONNECTED" : "DISCONNECTED"}');
    });

    // Power save change events
    _nectarTracker.onPowerSaveChange.listen((event) {
      _addLog(_powerSaveLogs, 'Power Save: ${event.isPowerSaveMode ? "ENABLED" : "DISABLED"}');
      _addLog(_actionLogs, '[PowerSave] ${event.isPowerSaveMode ? "ENABLED" : "DISABLED"}');
    });
  }

  void _updateLiveLocation(LocationData location) {
    setState(() {
      _currentLocation = location;
      _locationCount++;
      _lastLocationTime = DateTime.now();

      // Add to history (keep last 100 locations)
      _locationHistory.add(location);
      if (_locationHistory.length > 100) {
        _locationHistory.removeAt(0);
      }

      // Calculate total distance
      if (_locationHistory.length > 1) {
        final previousLocation = _locationHistory[_locationHistory.length - 2];
        final distance = _calculateDistance(
          previousLocation.latitude,
          previousLocation.longitude,
          location.latitude,
          location.longitude,
        );
        _totalDistance += distance;
      }

      // Calculate average speed
      if (_locationHistory.length > 1) {
        double totalSpeed = 0;
        int speedCount = 0;
        for (final loc in _locationHistory) {
          if (loc.speed > 0) {
            totalSpeed += loc.speed;
            speedCount++;
          }
        }
        _averageSpeed = speedCount > 0 ? totalSpeed / speedCount : 0;
      }
    });
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);
    final double a =
        sin(dLat / 2) * sin(dLat / 2) +
        sin(_degreesToRadians(lat1)) * sin(_degreesToRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * asin(sqrt(a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (3.14159265359 / 180);
  }

  void _addLog(List<String> logList, String message) {
    setState(() {
      final time = DateTime.now().toIso8601String().substring(11, 19);
      logList.add('$time: $message');
      if (logList.length > 50) {
        logList.removeAt(0);
      }
    });
  }

  Future<void> _configurePlugin() async {
    try {
      setState(() {
        _status = 'Configuring...';
      });
      _addLog(_actionLogs, '[Action] Configuring plugin...');
      // Configure with current settings
      final state = await _nectarTracker.ready(_config);
      setState(() {
        _status = 'Configured successfully';
        _isConfigured = true;
        _isTracking = state.enabled;
        _currentState = state;
      });
      _addLog(_actionLogs, '[Action] Plugin configured. Tracking: ${state.enabled ? "ON" : "OFF"}');
    } catch (e) {
      setState(() {
        _status = 'Configuration failed: $e';
      });
      _addLog(_actionLogs, '[Error] Configuration failed: $e');
    }
  }

  Future<void> _startTracking() async {
    try {
      // Set all MQTT and user/device/job details before starting tracking
      _nectarTracker.setMqttConfigAndDetails(
        broker: "messages.nectarit.com",
        port: 8884,
        username: "mobile-ui",
        password: "NecAws@123",
        topic: "your/location/topic",
        userId: "17826",
        batteryLevel: 28,
        userType: "Mechanic",
        deviceId: "da8905647e2853b8",
        domain: "dha",
        usernameField: "thahir",
        identifier: "thahir@dha",
        skills: [],
        status: "ONLINE",
        name: "THAHIR AbduKareem",
        geofence: "Muhaisnah MFC Area",
        emailid: "riyas@nectarit.com",
        mobile: "000000000",
        jobId: "",
      );
      setState(() {
        _status = 'Starting tracking...';
      });
      _addLog(_actionLogs, '[Action] Starting tracking...');
      final success = await _nectarTracker.start();
      if (success) {
        setState(() {
          _status = 'Tracking active';
          _isTracking = true;
        });
        _addLog(_actionLogs, '[Action] Tracking started.');
      } else {
        setState(() {
          _status = 'Start tracking failed';
        });
        _addLog(_actionLogs, '[Error] Start tracking failed.');
      }
    } catch (e) {
      setState(() {
        _status = 'Start tracking failed: $e';
      });
      _addLog(_actionLogs, '[Error] Start tracking failed: $e');
      // If it's a permission error, show a helpful message
      if (e.toString().contains('PERMISSION_DENIED')) {
        _addLog(_actionLogs, '[Error] Please grant location permissions in app settings');
      }
    }
  }

  Future<void> _stopTracking() async {
    try {
      setState(() {
        _status = 'Stopping tracking...';
      });
      _addLog(_actionLogs, '[Action] Stopping tracking...');
      final success = await _nectarTracker.stop();
      if (success) {
        setState(() {
          _status = 'Tracking stopped';
          _isTracking = false;
        });
        _addLog(_actionLogs, '[Action] Tracking stopped.');
      } else {
        setState(() {
          _status = 'Stop tracking failed';
        });
        _addLog(_actionLogs, '[Error] Stop tracking failed.');
      }
    } catch (e) {
      setState(() {
        _status = 'Stop tracking failed: $e';
      });
      _addLog(_actionLogs, '[Error] Stop tracking failed: $e');
    }
  }

  Future<void> _getCurrentPosition() async {
    try {
      setState(() {
        _status = 'Getting current position...';
      });
      _addLog(_actionLogs, '[Action] Getting current position...');
      final location = await _nectarTracker.getCurrentPosition();
      if (location != null) {
        _updateLiveLocation(location);
        _addLog(
          _locationLogs,
          'CURRENT: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
        );
        setState(() {
          _status = 'Current position retrieved';
        });
        _addLog(_actionLogs, '[Action] Got current position.');
      } else {
        setState(() {
          _status = 'Failed to get current position';
        });
        _addLog(_actionLogs, '[Error] Failed to get current position.');
      }
    } catch (e) {
      setState(() {
        _status = 'Get current position failed: $e';
      });
      _addLog(_actionLogs, '[Error] Get current position failed: $e');
    }
  }

  Future<void> _getState() async {
    try {
      final state = await _nectarTracker.getState();
      setState(() {
        _currentState = state;
        _status =
            'State: enabled=${state.enabled}, moving=${state.isMoving}, locationServices=${state.locationServicesEnabled}';
      });
      _addLog(_actionLogs, '[Action] Got state. Tracking: ${state.enabled ? "ON" : "OFF"}');
    } catch (e) {
      setState(() {
        _status = 'Get state failed: $e';
      });
      _addLog(_actionLogs, '[Error] Get state failed: $e');
    }
  }

  Future<void> _checkLocationServices() async {
    try {
      final isEnabled = await _nectarTracker.isLocationServicesEnabled();
      setState(() {
        _status = 'Location services: ${isEnabled ? "Enabled" : "Disabled"}';
      });
      _addLog(_actionLogs, '[Action] Location services: ${isEnabled ? "Enabled" : "Disabled"}');
    } catch (e) {
      setState(() {
        _status = 'Check location services failed: $e';
      });
      _addLog(_actionLogs, '[Error] Check location services failed: $e');
    }
  }

  Future<void> _getTrackingStats() async {
    try {
      final stats = await _nectarTracker.getTrackingStats();
      setState(() {
        _status =
            'Stats: ${stats.totalLocations} locations, ${stats.totalDistance.toStringAsFixed(2)}m distance, ${stats.averageSpeed.toStringAsFixed(2)} m/s avg speed';
      });
      _addLog(_actionLogs, '[Action] Got tracking stats.');
    } catch (e) {
      setState(() {
        _status = 'Get tracking stats failed: $e';
      });
      _addLog(_actionLogs, '[Error] Get tracking stats failed: $e');
    }
  }

  Future<void> _clearTrackingData() async {
    try {
      final success = await _nectarTracker.clearTrackingData();
      if (success) {
        setState(() {
          _locationLogs.clear();
          _motionLogs.clear();
          _providerLogs.clear();
          _activityLogs.clear();
          _geofenceLogs.clear();
          _heartbeatLogs.clear();
          _httpLogs.clear();
          _connectivityLogs.clear();
          _powerSaveLogs.clear();
          _locationHistory.clear();
          _currentLocation = null;
          _totalDistance = 0.0;
          _averageSpeed = 0.0;
          _locationCount = 0;
          _lastLocationTime = null;
          _status = 'Tracking data cleared';
        });
        _addLog(_actionLogs, '[Action] Tracking data cleared.');
      } else {
        setState(() {
          _status = 'Failed to clear tracking data';
        });
        _addLog(_actionLogs, '[Error] Failed to clear tracking data.');
      }
    } catch (e) {
      setState(() {
        _status = 'Clear tracking data failed: $e';
      });
      _addLog(_actionLogs, '[Error] Clear tracking data failed: $e');
    }
  }

  Future<void> _checkMqttStatus() async {
    try {
      final status = await _nectarTracker.getMqttStatus();
      setState(() {
        _status = 'MQTT Status: ${status['connected'] ? "Connected" : "Disconnected"} (${status['connectionState']})';
      });
      _addLog(
        _actionLogs,
        '[Action] MQTT Status: ${status['connected'] ? "Connected" : "Disconnected"} (${status['connectionState']})',
      );
      _addLog(_actionLogs, '[Action] MQTT Broker: ${status['broker']}:${status['port']}');
      _addLog(_actionLogs, '[Action] MQTT Topic: ${status['topic']}');
      _addLog(_actionLogs, '[Action] MQTT UserId: ${status['userId']}');
    } catch (e) {
      setState(() {
        _status = 'Check MQTT status failed: $e';
      });
      _addLog(_actionLogs, '[Error] Check MQTT status failed: $e');
    }
  }

  void _updateConfig() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Configure Nectar Tracker'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<DesiredAccuracy>(
                initialValue: _config.desiredAccuracy,
                decoration: InputDecoration(labelText: 'Desired Accuracy'),
                items: DesiredAccuracy.values.map((accuracy) {
                  return DropdownMenuItem(
                    value: accuracy,
                    child: Text(accuracy.toString().split('.').last.toUpperCase()),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _config = NectarTrackerConfig(
                        desiredAccuracy: value,
                        distanceFilter: _config.distanceFilter,
                        stopOnTerminate: _config.stopOnTerminate,
                        startOnBoot: _config.startOnBoot,
                        debug: _config.debug,
                        logLevel: _config.logLevel,
                        enableBatteryOptimization: _config.enableBatteryOptimization,
                        notificationTitle: _config.notificationTitle,
                        notificationText: _config.notificationText,
                        interval: _config.interval,
                        fastestInterval: _config.fastestInterval,
                        showLocationNotifications: _config.showLocationNotifications,
                      );
                    });
                  }
                },
              ),
              SizedBox(height: 16),
              TextFormField(
                initialValue: _config.distanceFilter.toString(),
                decoration: InputDecoration(labelText: 'Distance Filter (meters)'),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final distance = double.tryParse(value) ?? 10.0;
                  setState(() {
                    _config = NectarTrackerConfig(
                      desiredAccuracy: _config.desiredAccuracy,
                      distanceFilter: distance,
                      stopOnTerminate: _config.stopOnTerminate,
                      startOnBoot: _config.startOnBoot,
                      debug: _config.debug,
                      logLevel: _config.logLevel,
                      enableBatteryOptimization: _config.enableBatteryOptimization,
                      notificationTitle: _config.notificationTitle,
                      notificationText: _config.notificationText,
                      interval: _config.interval,
                      fastestInterval: _config.fastestInterval,
                      showLocationNotifications: _config.showLocationNotifications,
                    );
                  });
                },
              ),
              SizedBox(height: 16),
              CheckboxListTile(
                title: Text('Stop on Terminate'),
                value: _config.stopOnTerminate,
                onChanged: (value) {
                  setState(() {
                    _config = NectarTrackerConfig(
                      desiredAccuracy: _config.desiredAccuracy,
                      distanceFilter: _config.distanceFilter,
                      stopOnTerminate: value ?? false,
                      startOnBoot: _config.startOnBoot,
                      debug: _config.debug,
                      logLevel: _config.logLevel,
                      enableBatteryOptimization: _config.enableBatteryOptimization,
                      notificationTitle: _config.notificationTitle,
                      notificationText: _config.notificationText,
                      interval: _config.interval,
                      fastestInterval: _config.fastestInterval,
                      showLocationNotifications: _config.showLocationNotifications,
                    );
                  });
                },
              ),
              CheckboxListTile(
                title: Text('Start on Boot'),
                value: _config.startOnBoot,
                onChanged: (value) {
                  setState(() {
                    _config = NectarTrackerConfig(
                      desiredAccuracy: _config.desiredAccuracy,
                      distanceFilter: _config.distanceFilter,
                      stopOnTerminate: _config.stopOnTerminate,
                      startOnBoot: value ?? true,
                      debug: _config.debug,
                      logLevel: _config.logLevel,
                      enableBatteryOptimization: _config.enableBatteryOptimization,
                      notificationTitle: _config.notificationTitle,
                      notificationText: _config.notificationText,
                      interval: _config.interval,
                      fastestInterval: _config.fastestInterval,
                      showLocationNotifications: _config.showLocationNotifications,
                    );
                  });
                },
              ),
              CheckboxListTile(
                title: Text('Debug Mode'),
                value: _config.debug,
                onChanged: (value) {
                  setState(() {
                    _config = NectarTrackerConfig(
                      desiredAccuracy: _config.desiredAccuracy,
                      distanceFilter: _config.distanceFilter,
                      stopOnTerminate: _config.stopOnTerminate,
                      startOnBoot: _config.startOnBoot,
                      debug: value ?? true,
                      logLevel: _config.logLevel,
                      enableBatteryOptimization: _config.enableBatteryOptimization,
                      notificationTitle: _config.notificationTitle,
                      notificationText: _config.notificationText,
                      interval: _config.interval,
                      fastestInterval: _config.fastestInterval,
                      showLocationNotifications: _config.showLocationNotifications,
                    );
                  });
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _configurePlugin();
            },
            child: Text('Apply'),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveLocationDisplay() {
    if (_currentLocation == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Live Location Tracking',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue),
              ),
              SizedBox(height: 8),
              Text('No location data available', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: Colors.red, size: 24),
                SizedBox(width: 8),
                Text(
                  'Live Location Tracking',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue),
                ),
                Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _currentLocation!.isBackground ? Colors.orange : Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _currentLocation!.isBackground ? 'BACKGROUND' : 'FOREGROUND',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // Coordinates
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Latitude', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(
                        _currentLocation!.latitude.toStringAsFixed(8),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Longitude', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(
                        _currentLocation!.longitude.toStringAsFixed(8),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // Speed and Accuracy
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Speed', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(
                        '${_currentLocation!.speed.toStringAsFixed(2)} m/s',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Accuracy', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(
                        '${_currentLocation!.accuracy.toStringAsFixed(1)}m',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Altitude', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(
                        '${_currentLocation!.altitude.toStringAsFixed(1)}m',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.purple),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            // Tracking Stats
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tracking Statistics', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total Distance', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Text(
                              '${_totalDistance.toStringAsFixed(2)}m',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Avg Speed', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Text(
                              '${_averageSpeed.toStringAsFixed(2)} m/s',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Locations', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Text('$_locationCount', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 8),

            // Last Update Time
            if (_lastLocationTime != null) ...[
              Text(
                'Last Update: ${_lastLocationTime!.toIso8601String().substring(11, 19)}',
                style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLogSection(String title, List<String> logs, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
            ),
            SizedBox(height: 8),
            Container(
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final log = logs[logs.length - 1 - index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(
                      log,
                      style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggerPanel() {
    return Card(
      color: Colors.black,
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SizedBox(
          height: 120,
          child: ListView.builder(
            reverse: true,
            itemCount: _actionLogs.length,
            itemBuilder: (context, index) {
              final log = _actionLogs[_actionLogs.length - 1 - index];
              return Text(
                log,
                style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Nectar Tracker Demo'),
          backgroundColor: Colors.green,
          actions: [IconButton(icon: Icon(Icons.settings), onPressed: _updateConfig)],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tracking Status Bar
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _isTracking ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    _isTracking ? 'TRACKING: ON' : 'TRACKING: OFF',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Live Location Display
              _buildLiveLocationDisplay(),
              SizedBox(height: 16),

              // Status Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      SizedBox(height: 8),
                      Text('Platform: $_platformVersion'),
                      Text('Status: $_status'),
                      Text('Configured: ${_isConfigured ? "Yes" : "No"}'),
                      Text('Tracking: ${_isTracking ? "Active" : "Inactive"}'),
                      if (_currentState != null) ...[
                        Text('Enabled: ${_currentState!.enabled}'),
                        Text('Moving: ${_currentState!.isMoving}'),
                        Text('Location Services: ${_currentState!.locationServicesEnabled}'),
                        Text('Authorization: ${_currentState!.authorization.toString().split('.').last}'),
                        Text('Activity: ${_currentState!.activity.toString().split('.').last}'),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),

              // Control Buttons
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Controls', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isConfigured ? null : _configurePlugin,
                              child: Text('Configure'),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isConfigured && !_isTracking ? _startTracking : null,
                              child: Text('Start'),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(onPressed: _isTracking ? _stopTracking : null, child: Text('Stop')),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isConfigured ? _getCurrentPosition : null,
                              child: Text('Get Position'),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isConfigured ? _getState : null,
                              child: Text('Get State'),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isConfigured ? _checkLocationServices : null,
                              child: Text('Check Services'),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isConfigured ? _getTrackingStats : null,
                              child: Text('Get Stats'),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isConfigured ? _clearTrackingData : null,
                              child: Text('Clear Data'),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isConfigured ? _checkMqttStatus : null,
                              child: Text('Check MQTT'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),

              // Event Logs
              Text('Event Logs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              SizedBox(height: 8),

              _buildLogSection('Location Events', _locationLogs, Colors.blue),
              SizedBox(height: 8),

              _buildLogSection('Motion Change Events', _motionLogs, Colors.green),
              SizedBox(height: 8),

              _buildLogSection('Provider Change Events', _providerLogs, Colors.orange),
              SizedBox(height: 8),

              _buildLogSection('Activity Change Events', _activityLogs, Colors.purple),
              SizedBox(height: 8),

              _buildLogSection('Geofence Events', _geofenceLogs, Colors.red),
              SizedBox(height: 8),

              _buildLogSection('Heartbeat Events', _heartbeatLogs, Colors.teal),
              SizedBox(height: 8),

              _buildLogSection('HTTP Events', _httpLogs, Colors.indigo),
              SizedBox(height: 8),

              _buildLogSection('Connectivity Events', _connectivityLogs, Colors.cyan),
              SizedBox(height: 8),

              _buildLogSection('Power Save Events', _powerSaveLogs, Colors.amber),
              SizedBox(height: 16),

              // Logger Panel
              Text('Logger', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              _buildLoggerPanel(),
            ],
          ),
        ),
      ),
    );
  }
}
