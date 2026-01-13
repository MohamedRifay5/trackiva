# Trackiva

A **comprehensive Flutter plugin** for robust, background and foreground location tracking with **MQTT**, **GraphQL**, and **HTTP** support, plus **offline storage with automatic sync** and **chat head support** (Android).

Inspired by `flutter_background_geolocation` and `flutter_background_location`.  
Supports **live event streams**, **background/terminated tracking**, **multiple data transport protocols**, **offline-first architecture**, and **comprehensive debugging** for both Android and iOS.

---

## 🚀 Features

### Core Location Tracking

- ✅ **Foreground, background, and terminated state location tracking**
- ✅ **High-precision GPS tracking** with configurable accuracy levels
- ✅ **Distance-based filtering** to reduce battery consumption
- ✅ **Configurable update intervals** (interval and fastest interval)
- ✅ **Automatic restart on device boot** (Android)
- ✅ **Production-ready** with all required permissions and background modes

### Data Transport Protocols

- 📡 **MQTT Integration** - Real-time location publishing to MQTT broker
- 🌐 **HTTP Support** - Send location data via REST API endpoints
- 🔷 **GraphQL Support** - Mutate location data via GraphQL mutations
- 🔄 **Automatic Fallback** - Try HTTP/GraphQL if MQTT fails

### Offline Storage & Sync

- 💾 **Local SQLite Database** - Store location data when offline
- 🔄 **Automatic Sync** - Sync pending locations when connectivity is restored
- 📶 **Connectivity Monitoring** - Detects network status changes
- 🎯 **Smart Sync Strategy** - Syncs in order (oldest first) when online

### Event-Driven Architecture

- 📊 **Live Event Streams** - Real-time location, motion, provider, activity events
- 🔔 **Connectivity Events** - Monitor network status changes
- ⚡ **HTTP Events** - Track HTTP request success/failure
- 📍 **Geofence Events** - Enter/exit geofence notifications
- 💓 **Heartbeat Events** - Periodic location updates

### Android-Specific Features

- 🎈 **Chat Head (Floating Bubble)** - Messenger-style floating bubble when tracking
- 🔔 **Automatic Overlay Permission** - Requests overlay permission when needed
- 🎨 **Custom Chat Head Icon** - Configure your own icon
- 🔋 **Battery Optimization** - Configurable battery optimization settings

### Developer Experience

- 🐛 **Comprehensive Debug Logging** - See every action, error, and event
- 📈 **Tracking Statistics** - Total locations, distance, foreground/background counts
- 🎛️ **Highly Configurable** - Control every aspect of tracking behavior
- 📱 **Platform Agnostic** - Works seamlessly on Android and iOS

---

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  trackiva: ^0.0.1
```

Then run:

```sh
flutter pub get
```

### Dependencies

Trackiva uses the following packages:

- `mqtt_client` - MQTT protocol support
- `http` - HTTP requests
- `graphql` - GraphQL client
- `sqflite` - Local SQLite database
- `path_provider` - Database path management
- `connectivity_plus` - Network connectivity monitoring

---

## ⚡ Quick Start

```dart
import 'package:trackiva/trackiva.dart';

final tracker = Trackiva();

void main() async {
  // 1. Configure the plugin
  await tracker.ready(TrackivaConfig(
    desiredAccuracy: DesiredAccuracy.high,
    distanceFilter: 10.0,
    stopOnTerminate: false,
    startOnBoot: true,
    debug: true,
    logLevel: LogLevel.verbose,
    chatHeadIcon: 'ic_launcher', // Android: Custom chat head icon
  ));

  // 2. Configure MQTT with flexible payload (optional)
  await tracker.setMqttConfigAndDetails(
    broker: 'broker.hivemq.com',
    port: 8884,
    // username and password are optional - omit if not needed
    // username: 'your_username',
    // password: 'your_password',
    topic: 'trackiva/location',
    payload: {
      'userId': 'user123',
      'batteryLevel': 85,
      'userType': 'driver',
      'deviceId': 'device456',
      // Add any custom fields you need
    },
  );

  // 3. Configure HTTP endpoint (optional)
  await tracker.setHttpConfig(
    endpoint: 'https://api.example.com/location',
    headers: {'Authorization': 'Bearer token'},
    method: 'POST',
  );

  // 4. Configure GraphQL endpoint (optional)
  await tracker.setGraphQLConfig(
    endpoint: 'https://api.example.com/graphql',
    mutation: '''
      mutation UpdateLocation(\$location: LocationInput!) {
        updateLocation(location: \$location) {
          id
          timestamp
        }
      }
    ''',
    headers: {'Authorization': 'Bearer token'},
  );

  // 5. Listen to location events
  tracker.onLocation.listen((location) {
    print('Location: ${location.latitude}, ${location.longitude}');
  });

  // 6. Listen to connectivity changes
  tracker.onConnectivityChange.listen((event) {
    print('Connectivity: ${event.connected ? "ONLINE" : "OFFLINE"}');
  });

  // 7. Start tracking
  try {
    await tracker.start();
  } on PlatformException catch (e) {
    if (e.code == 'OVERLAY_PERMISSION_NEEDED') {
      // User needs to grant overlay permission (Android)
      // Settings screen is already opened
    }
  }
}
```

---

## 🛠️ Configuration

### TrackivaConfig

The main configuration class for Trackiva:

```dart
await tracker.ready(TrackivaConfig(
  // Location Accuracy
  desiredAccuracy: DesiredAccuracy.high, // low, medium, high, best
  distanceFilter: 10.0, // Minimum distance in meters for updates

  // Lifecycle
  stopOnTerminate: false, // Stop tracking when app is terminated
  startOnBoot: true, // Auto-start after device reboot (Android)

  // Logging
  debug: true, // Enable debug logging
  logLevel: LogLevel.verbose, // off, error, warning, info, debug, verbose

  // Battery & Performance
  enableBatteryOptimization: false, // Enable battery optimization
  interval: 5000, // Update interval in milliseconds
  fastestInterval: 3000, // Fastest update interval in milliseconds

  // Notifications (Android)
  notificationTitle: 'Location Tracking',
  notificationText: 'Tracking your location in background',
  notificationIcon: 'ic_notification', // Optional: Custom icon
  notificationColor: '#4CAF50', // Optional: Notification color
  showLocationNotifications: false, // Show location update notifications

  // Chat Head (Android only)
  enableChatHead: false, // Enable chat head feature (requires overlay permission)
  chatHeadIcon: 'ic_launcher', // Custom icon for floating bubble (only used if enableChatHead is true)
  // Icon can be:
  // - Drawable resource name: 'ic_launcher', 'my_icon' (from res/drawable/)
  // - Mipmap resource name: 'ic_launcher' (from res/mipmap/ - for app icons)
  // - Asset file path: 'assets/my_icon.png' (from assets/ folder)
  // - If not specified or not found, app icon will be used automatically

  // HTTP Support
  enableHttp: true,
  httpEndpoint: 'https://api.example.com/location',
  httpHeaders: {'Authorization': 'Bearer token'},

  // GraphQL Support
  enableGraphQL: true,
  graphqlEndpoint: 'https://api.example.com/graphql',
  graphqlMutation: '''
    mutation UpdateLocation(\$location: LocationInput!) {
      updateLocation(location: \$location) {
        id
      }
    }
  ''',
  graphqlHeaders: {'Authorization': 'Bearer token'},
));
```

---

## 📡 MQTT Configuration

### Basic MQTT Setup

```dart
await tracker.setMqttConfigAndDetails(
  broker: 'broker.hivemq.com',
  port: 1883, // Use 8883 or 8884 for SSL/TLS
  username: 'your_username', // Optional
  password: 'your_password', // Optional
  topic: 'trackiva/location',
  payload: {
    // Flexible payload - add any fields you need
    'userId': 'user123',
    'batteryLevel': 85,
    'userType': 'driver',
    'deviceId': 'device456',
    'domain': 'example.com',
    'usernameField': 'john_doe',
    'identifier': 'unique_id',
    'skills': ['delivery', 'pickup'],
    'status': 'active',
    'name': 'John Doe',
    'geofence': 'zone1',
    'emailid': 'john@example.com',
    'mobile': '+1234567890',
    'jobId': 'job789',
    // Add any custom fields
    'customField1': 'value1',
    'customField2': 123,
  },
);
```

### MQTT Payload Format

Location data is automatically merged with your flexible payload:

```json
{
  "location": "POINT(longitude latitude)",
  "time": 1234567890123,
  "userId": "user123",
  "batteryLevel": 85,
  "userType": "driver",
  "deviceId": "device456",
  "domain": "example.com",
  "usernameField": "john_doe",
  "identifier": "unique_id",
  "skills": ["delivery", "pickup"],
  "status": "active",
  "name": "John Doe",
  "geofence": "zone1",
  "emailid": "john@example.com",
  "mobile": "+1234567890",
  "jobId": "job789",
  "customField1": "value1",
  "customField2": 123
}
```

### SSL/TLS Support

Use ports `8883` or `8884` for SSL/TLS connections:

```dart
await tracker.setMqttConfigAndDetails(
  broker: 'secure.broker.com',
  port: 8883, // SSL port
  // ...
);
```

### Check MQTT Status

```dart
final mqttStatus = await tracker.getMqttStatus();
print('Connected: ${mqttStatus['connected']}');
print('State: ${mqttStatus['connectionState']}');
print('Broker: ${mqttStatus['broker']}');
print('Topic: ${mqttStatus['topic']}');
print('Payload: ${mqttStatus['payload']}');
```

---

## 🌐 HTTP Configuration

### Basic HTTP Setup

```dart
// Configure in TrackivaConfig
await tracker.ready(TrackivaConfig(
  enableHttp: true,
  httpEndpoint: 'https://api.example.com/location',
  httpHeaders: {
    'Authorization': 'Bearer token',
    'Content-Type': 'application/json',
  },
  // ...
));

// Or configure separately
await tracker.setHttpConfig(
  endpoint: 'https://api.example.com/location',
  headers: {
    'Authorization': 'Bearer token',
    'Content-Type': 'application/json',
  },
  method: 'POST', // Default: POST
);
```

### HTTP Payload Format

```json
{
  "location": {
    "latitude": 37.7749,
    "longitude": -122.4194,
    "accuracy": 10.5,
    "altitude": 100.0,
    "speed": 5.2,
    "bearing": 90.0,
    "timestamp": "2024-01-01T12:00:00Z"
  },
  "userId": "user123",
  "deviceId": "device456"
  // ... your custom payload fields
}
```

### Listen to HTTP Events

```dart
tracker.onHttp.listen((event) {
  if (event.success) {
    print('HTTP request succeeded: ${event.status}');
  } else {
    print('HTTP request failed: ${event.status} - ${event.responseText}');
  }
});
```

---

## 🔷 GraphQL Configuration

### Basic GraphQL Setup

```dart
// Configure in TrackivaConfig
await tracker.ready(TrackivaConfig(
  enableGraphQL: true,
  graphqlEndpoint: 'https://api.example.com/graphql',
  graphqlMutation: '''
    mutation UpdateLocation(\$location: LocationInput!) {
      updateLocation(location: \$location) {
        id
        timestamp
        latitude
        longitude
      }
    }
  ''',
  graphqlHeaders: {
    'Authorization': 'Bearer token',
  },
  // ...
));

// Or configure separately
await tracker.setGraphQLConfig(
  endpoint: 'https://api.example.com/graphql',
  mutation: '''
    mutation UpdateLocation(\$location: LocationInput!) {
      updateLocation(location: \$location) {
        id
      }
    }
  ''',
  headers: {'Authorization': 'Bearer token'},
);
```

### GraphQL Variables Format

The mutation receives variables in this format:

```json
{
  "location": {
    "latitude": 37.7749,
    "longitude": -122.4194,
    "accuracy": 10.5,
    "altitude": 100.0,
    "speed": 5.2,
    "bearing": 90.0,
    "timestamp": "2024-01-01T12:00:00Z"
  },
  "userId": "user123",
  "deviceId": "device456"
  // ... your custom payload fields
}
```

---

## 💾 Offline Storage & Sync

Trackiva automatically saves location data to a local SQLite database when offline and syncs it when connectivity is restored.

### How It Works

1. **Location Update Received** → Saved to local database
2. **If Online** → Attempts to send via MQTT/HTTP/GraphQL immediately
3. **If Offline** → Location is stored locally with `synced: false`
4. **Connectivity Restored** → Automatically syncs pending locations
5. **Sync Order** → Oldest locations are synced first

### Manual Sync

The sync happens automatically, but you can monitor it:

```dart
tracker.onConnectivityChange.listen((event) {
  if (event.connected) {
    print('Online - sync will start automatically');
  } else {
    print('Offline - locations will be stored locally');
  }
});
```

### Clear Offline Data

```dart
await tracker.clearTrackingData(); // Clears both platform and local storage
```

---

## 📊 Event Streams

Trackiva provides comprehensive event streams for real-time monitoring:

### Location Events

```dart
// New location update
tracker.onLocation.listen((location) {
  print('Location: ${location.latitude}, ${location.longitude}');
  print('Accuracy: ${location.accuracy}m');
  print('Speed: ${location.speed}m/s');
  print('Background: ${location.isBackground}');
  print('Timestamp: ${location.timestamp}');
});
```

### Motion Change Events

```dart
// Stationary/moving state change
tracker.onMotionChange.listen((location) {
  print('Motion detected: ${location.speed > 0.5 ? "Moving" : "Stationary"}');
});
```

### Provider Change Events

```dart
// Location provider state change (GPS, Network, etc.)
tracker.onProviderChange.listen((event) {
  print('GPS: ${event.gps}, Network: ${event.network}, Enabled: ${event.enabled}');
});
```

### Activity Change Events

```dart
// Activity type change (walking, running, driving, etc.)
tracker.onActivityChange.listen((event) {
  print('Activity: ${event.activity}'); // unknown, still, walking, running, automotive, cycling
});
```

### Connectivity Events

```dart
// Network connectivity changes
tracker.onConnectivityChange.listen((event) {
  print('Connectivity: ${event.connected ? "ONLINE" : "OFFLINE"}');
});
```

### HTTP Events

```dart
// HTTP request completion
tracker.onHttp.listen((event) {
  if (event.success) {
    print('HTTP Success: ${event.status}');
  } else {
    print('HTTP Failed: ${event.status} - ${event.responseText}');
  }
});
```

### Geofence Events

```dart
// Geofence enter/exit
tracker.onGeofence.listen((event) {
  print('Geofence ${event.identifier}: ${event.enter ? "ENTER" : "EXIT"}');
});
```

### Heartbeat Events

```dart
// Periodic heartbeat
tracker.onHeartbeat.listen((event) {
  print('Heartbeat: ${event.location?.latitude}, ${event.location?.longitude}');
});
```

### Power Save Events

```dart
// Power save mode changes
tracker.onPowerSaveChange.listen((event) {
  print('Power Save Mode: ${event.isPowerSaveMode}');
});
```

---

## 🎈 Chat Head Feature (Android Only)

The chat head is a floating bubble that appears on screen when tracking is active, similar to Facebook Messenger's chat heads.

### Features

- ✅ **Draggable** - Touch and drag to move around screen
- ✅ **Clickable** - Tap to show status (shows toast by default)
- ✅ **Custom Icon** - Configure your own icon
- ✅ **Auto-start** - Appears automatically when tracking starts
- ✅ **Auto-stop** - Disappears when tracking stops
- ✅ **Persistent** - Works even when app is terminated

### Setup

1. **Add Overlay Permission** (already in AndroidManifest.xml)
2. **Configure Icon** (optional):
   ```dart
   chatHeadIcon: 'ic_launcher', // Your drawable resource name
   ```
3. **Start Tracking** - Chat head appears automatically

### Permission Flow

1. When you call `start()`, the plugin checks overlay permission
2. If not granted, it automatically opens system settings
3. User grants permission in settings
4. User returns to app
5. Chat head appears automatically (or call `startChatHeadService()` manually)

### Customization

The chat head uses a circular green background by default. The icon is customizable via `chatHeadIcon` in config.

---

## 📱 Platform Setup

### Android

#### Permissions

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/> <!-- For chat head -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

#### Chat Head Icon

The chat head icon can be loaded from multiple sources with automatic fallback:

1. **Drawable Resources** (Recommended)

   ```dart
   chatHeadIcon: 'ic_chat_head', // From res/drawable/ic_chat_head.png
   ```

2. **Mipmap Resources** (For app icons)

   ```dart
   chatHeadIcon: 'ic_launcher', // From res/mipmap/ic_launcher.png
   ```

3. **Assets Folder**

   ```dart
   chatHeadIcon: 'assets/my_icon.png', // From assets/my_icon.png
   ```

4. **Automatic App Icon** (If no icon specified or not found)
   - The plugin will automatically use your app's launcher icon
   - No configuration needed

**Icon Loading Priority:**

1. Drawable resources (`res/drawable/`)
2. Mipmap resources (`res/mipmap/`)
3. Assets folder (`assets/`)
4. App launcher icon (automatic)
5. Default location icon (fallback)

#### Dependencies

MQTT dependencies are automatically included:

- `org.eclipse.paho:org.eclipse.paho.client.mqttv3:1.2.5`
- `com.google.code.gson:gson:2.10.1`

#### Foreground Service

The plugin automatically creates and manages a foreground service for background tracking. No additional setup required.

### iOS

#### Info.plist

Add to `ios/Runner/Info.plist`:

```xml
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We use your location to track your activity in the background.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>We use your location to track your activity.</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
  <string>fetch</string>
  <string>processing</string>
</array>
```

#### Permissions

Make sure to request "Always" location permission in your app:

```dart
import 'package:permission_handler/permission_handler.dart';

final status = await Permission.locationAlways.request();
```

**Note**: Chat head feature is **Android only**. iOS does not support overlay windows.

---

## 🧩 API Reference

### Core Methods

#### `ready(TrackivaConfig config)`

Initialize and configure the plugin. Must be called before using other methods.

#### `start()`

Start location tracking. Returns `Future<bool>`.

- Throws `PlatformException` with code `OVERLAY_PERMISSION_NEEDED` if overlay permission is needed (Android)

#### `stop()`

Stop location tracking. Returns `Future<bool>`.

#### `getState()`

Get current tracking state. Returns `TrackivaState`.

#### `getCurrentPosition()`

Get current location. Returns `Future<LocationData?>`.

#### `isLocationServicesEnabled()`

Check if location services are enabled. Returns `Future<bool>`.

#### `getTrackingStats()`

Get tracking statistics. Returns `TrackingStats`:

- `totalLocations` - Total number of locations recorded
- `foregroundLocations` - Locations recorded in foreground
- `backgroundLocations` - Locations recorded in background
- `totalDistance` - Total distance traveled in meters
- `firstLocationTime` - Timestamp of first location
- `lastLocationTime` - Timestamp of last location

#### `clearTrackingData()`

Clear all tracking data (platform and local storage). Returns `Future<bool>`.

#### `getPlatformVersion()`

Get platform version string. Returns `Future<String?>`.

### MQTT Methods

#### `setMqttConfigAndDetails(...)`

Configure MQTT broker and flexible payload:

- `broker` - MQTT broker hostname
- `port` - MQTT broker port (use 8883/8884 for SSL)
- `username` - MQTT username (optional)
- `password` - MQTT password (optional)
- `topic` - MQTT topic to publish to
- `payload` - Flexible `Map<String, dynamic>` with custom data

#### `getMqttStatus()`

Get MQTT connection status. Returns `Map<String, dynamic>`:

- `connected` - Connection status (bool)
- `connectionState` - State string ("Connected", "Disconnected", etc.)
- `broker` - Broker hostname
- `port` - Broker port
- `topic` - MQTT topic
- `payload` - Current payload configuration
- `isConnecting` - Whether connection is in progress

### HTTP Methods

#### `setHttpConfig(...)`

Configure HTTP endpoint:

- `endpoint` - HTTP endpoint URL
- `headers` - HTTP headers (optional)
- `method` - HTTP method (default: "POST")

### GraphQL Methods

#### `setGraphQLConfig(...)`

Configure GraphQL endpoint:

- `endpoint` - GraphQL endpoint URL
- `mutation` - GraphQL mutation string
- `headers` - HTTP headers (optional)

### Event Streams

- `onLocation` - `Stream<LocationData>`
- `onMotionChange` - `Stream<LocationData>`
- `onProviderChange` - `Stream<ProviderChangeEvent>`
- `onActivityChange` - `Stream<ActivityChangeEvent>`
- `onGeofence` - `Stream<GeofenceEvent>`
- `onHeartbeat` - `Stream<HeartbeatEvent>`
- `onHttp` - `Stream<HttpEvent>`
- `onConnectivityChange` - `Stream<ConnectivityChangeEvent>`
- `onPowerSaveChange` - `Stream<PowerSaveChangeEvent>`

### Enums

- `DesiredAccuracy`: `low`, `medium`, `high`, `best`
- `LogLevel`: `off`, `error`, `warning`, `info`, `debug`, `verbose`
- `AuthorizationStatus`: `denied`, `authorized`, `authorizedAlways`, `authorizedWhenInUse`
- `ActivityType`: `unknown`, `still`, `walking`, `running`, `automotive`, `cycling`

---

## 🎯 Usage Examples

### Complete Example with All Features

```dart
import 'package:trackiva/trackiva.dart';
import 'package:flutter/material.dart';

class TrackingScreen extends StatefulWidget {
  @override
  _TrackingScreenState createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final _tracker = Trackiva();
  LocationData? _currentLocation;
  bool _isTracking = false;
  String _mqttStatus = 'Disconnected';
  List<String> _events = [];

  @override
  void initState() {
    super.initState();
    _initializeTracker();
  }

  Future<void> _initializeTracker() async {
    // Configure plugin
    await _tracker.ready(TrackivaConfig(
      desiredAccuracy: DesiredAccuracy.high,
      distanceFilter: 10.0,
      debug: true,
      enableHttp: true,
      httpEndpoint: 'https://api.example.com/location',
      enableGraphQL: true,
      graphqlEndpoint: 'https://api.example.com/graphql',
      graphqlMutation: '''
        mutation UpdateLocation(\$location: LocationInput!) {
          updateLocation(location: \$location) { id }
        }
      ''',
    ));

    // Configure MQTT
    await _tracker.setMqttConfigAndDetails(
      broker: 'broker.hivemq.com',
      port: 1883,
      username: 'user',
      password: 'pass',
      topic: 'trackiva/location',
      payload: {
        'userId': 'user123',
        'deviceId': 'device456',
      },
    );

    // Listen to events
    _tracker.onLocation.listen((location) {
      setState(() {
        _currentLocation = location;
        _events.add('Location: ${location.latitude}, ${location.longitude}');
      });
    });

    _tracker.onConnectivityChange.listen((event) {
      setState(() {
        _events.add('Connectivity: ${event.connected ? "ONLINE" : "OFFLINE"}');
      });
    });

    _tracker.onHttp.listen((event) {
      setState(() {
        _events.add('HTTP: ${event.success ? "Success" : "Failed"}');
      });
    });
  }

  Future<void> _startTracking() async {
    try {
      final success = await _tracker.start();
      if (success) {
        setState(() => _isTracking = true);
      }
    } on PlatformException catch (e) {
      if (e.code == 'OVERLAY_PERMISSION_NEEDED') {
        // Handle overlay permission
      }
    }
  }

  Future<void> _stopTracking() async {
    await _tracker.stop();
    setState(() => _isTracking = false);
  }

  Future<void> _checkMqttStatus() async {
    final status = await _tracker.getMqttStatus();
    setState(() {
      _mqttStatus = status['connectionState'] ?? 'Unknown';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Trackiva Demo')),
      body: Column(
        children: [
          Text('Tracking: ${_isTracking ? "ON" : "OFF"}'),
          Text('MQTT: $_mqttStatus'),
          if (_currentLocation != null)
            Text('Location: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}'),
          ElevatedButton(
            onPressed: _isTracking ? _stopTracking : _startTracking,
            child: Text(_isTracking ? 'Stop' : 'Start'),
          ),
          ElevatedButton(
            onPressed: _checkMqttStatus,
            child: Text('Check MQTT Status'),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _events.length,
              itemBuilder: (context, index) => ListTile(
                title: Text(_events[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tracker.dispose();
    super.dispose();
  }
}
```

---

## 🐞 Debugging

- All actions, errors, and events are printed with `[Trackiva]` in your debug console
- Use `debug: true` and `logLevel: LogLevel.verbose` for maximum output
- Check logs for:
  - `[Trackiva]` - General plugin logs
  - `LocationForegroundService` - Android service logs
  - `ChatHeadService` - Chat head service logs

---

## ❓ Troubleshooting

### No location updates?

- ✅ Check permissions (Android/iOS)
- ✅ Ensure background modes are enabled
- ✅ Watch the debug console for `[Trackiva]` errors
- ✅ Verify location services are enabled on device

### Chat head not appearing (Android)?

- ✅ Grant "Display over other apps" permission
- ✅ Check if overlay permission is granted
- ✅ Verify icon resource exists in `res/drawable/`
- ✅ Check logs for `ChatHeadService` errors

### MQTT not connecting?

- ✅ Check broker URL and port
- ✅ Verify network connectivity
- ✅ Check credentials (if required)
- ✅ For SSL, use ports 8883 or 8884
- ✅ Check `getMqttStatus()` for connection state

### HTTP/GraphQL not working?

- ✅ Verify endpoint URLs are correct
- ✅ Check network connectivity
- ✅ Verify headers (authentication, etc.)
- ✅ Check `onHttp` events for error details
- ✅ Ensure endpoints accept JSON payloads

### Offline sync not working?

- ✅ Check connectivity status via `onConnectivityChange`
- ✅ Verify SQLite database is initialized
- ✅ Check logs for sync errors
- ✅ Ensure at least one transport (HTTP/GraphQL) is configured

### App killed/terminated?

- ✅ On Android: Use `startOnBoot: true` and required permissions
- ✅ On iOS: Background modes and "Always" permission are required
- ✅ Chat head continues even when app is terminated (Android)

### ProGuard/R8 Issues (Release Builds)?

- ✅ **ProGuard rules are automatically included** - No manual configuration needed
- ✅ The plugin includes `proguard-rules.pro` that protects all necessary classes
- ✅ If you encounter issues, check that your app's `build.gradle` includes:
  ```gradle
  buildTypes {
      release {
          minifyEnabled true
          proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
      }
  }
  ```
- ✅ The plugin's ProGuard rules protect:
  - Trackiva plugin classes
  - MQTT client (Eclipse Paho)
  - Gson for JSON serialization
  - Location services
  - Notification classes
  - Services and broadcast receivers
- ✅ See `README_PROGUARD.md` for detailed ProGuard configuration

---

## 📄 License

MIT License

---

## 🙏 Acknowledgments

Inspired by [`flutter_background_geolocation`](https://pub.dev/packages/flutter_background_geolocation) and [`flutter_background_location`](https://pub.dev/packages/flutter_background_location).

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## 📞 Support

If you need more advanced usage, custom event handling, or have any issues:

- Open an issue on GitHub
- Check the example app for usage patterns
- Review the debug logs for detailed information

---

**Made with ❤️ for Flutter developers**
