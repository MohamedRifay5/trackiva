# Nectar Tracker

A **comprehensive Flutter plugin** for robust, background and foreground location tracking with MQTT integration and chat head support (Android).  
Inspired by `flutter_background_geolocation` and `flutter_background_location`.  
Supports **live event streams**, **background/terminated tracking**, **MQTT publishing**, and **comprehensive debugging** for both Android and iOS.

---

## 🚀 Features

### Core Features

- ✅ **Foreground, background, and terminated location tracking**
- ✅ **Event-driven API**: Streams for location, motion, provider, activity, geofence, heartbeat, HTTP, connectivity, power-save
- ✅ **Live debug logging**: See every action, error, and event in your console
- ✅ **Highly configurable**: Control accuracy, intervals, notifications, and more
- ✅ **Production-ready**: Works on Android and iOS, with all required permissions and background modes

### Android-Specific Features

- 🎈 **Chat Head (Floating Bubble)**: Messenger-style floating bubble that appears when tracking starts
- 🔔 **Automatic Overlay Permission**: Automatically requests overlay permission when needed
- 🎨 **Custom Chat Head Icon**: Configure your own icon for the chat head
- 📡 **MQTT Integration**: Publish location data to MQTT broker in real-time
- 🔄 **Auto-restart on Boot**: Automatically restarts tracking after device reboot

### MQTT Features

- Real-time location publishing to MQTT broker
- Configurable broker, port, topic, and credentials
- Automatic reconnection on disconnect
- SSL/TLS support (ports 8883, 8884)
- User/device metadata support (userId, deviceId, jobId, skills, etc.)

---

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  nectar_tracker: ^0.0.1
```

Then run:

```sh
flutter pub get
```

---

## ⚡ Quick Start

```dart
import 'package:nectar_tracker/nectar_tracker.dart';

final tracker = NectarTracker();

void main() async {
  // Configure the plugin
  await tracker.ready(NectarTrackerConfig(
    desiredAccuracy: DesiredAccuracy.high,
    distanceFilter: 10.0,
    stopOnTerminate: false,
    startOnBoot: true,
    debug: true,
    logLevel: LogLevel.verbose,
    chatHeadIcon: 'ic_launcher', // Android: Custom chat head icon
  ));

  // Configure MQTT (optional)
  await tracker.setMqttConfigAndDetails(
    broker: 'broker.hivemq.com',
    port: 1883,
    username: 'your_username',
    password: 'your_password',
    topic: 'nectar/location',
    userId: 'user123',
    deviceId: 'device456',
    // ... other fields
  );

  // Listen to live location events
  tracker.onLocation.listen((location) {
    print('Location: ${location.latitude}, ${location.longitude}');
  });

  // Start tracking
  await tracker.start();
}
```

---

## 🛠️ Usage

### **Configure**

```dart
await tracker.ready(NectarTrackerConfig(
  desiredAccuracy: DesiredAccuracy.high,
  distanceFilter: 10.0,
  stopOnTerminate: false,
  startOnBoot: true,
  debug: true,
  logLevel: LogLevel.verbose,
  enableBatteryOptimization: false,
  notificationTitle: 'Location Tracking',
  notificationText: 'Tracking your location in background',
  interval: 5000,
  fastestInterval: 3000,
  chatHeadIcon: 'ic_launcher', // Android only: Custom icon for chat head
  showLocationNotifications: false,
));
```

### **Start/Stop Tracking**

```dart
// Start tracking (will automatically request overlay permission on Android if needed)
try {
  await tracker.start();
} on PlatformException catch (e) {
  if (e.code == 'OVERLAY_PERMISSION_NEEDED') {
    // Settings screen opened, user needs to grant permission
    // After granting, call start() again or use startChatHeadService()
  }
}

// Stop tracking
await tracker.stop();
```

### **Chat Head (Android Only)**

The chat head appears automatically when tracking starts (if overlay permission is granted).

```dart
// Check if overlay permission is granted
bool hasPermission = await NectarTrackerPlatform.instance.canDrawOverlays();

if (!hasPermission) {
  // Request permission (opens system settings)
  await NectarTrackerPlatform.instance.requestOverlayPermission();
  // After user grants permission, manually start chat head
  await NectarTrackerPlatform.instance.startChatHeadService();
}

// Or manually start chat head after permission is granted
if (await NectarTrackerPlatform.instance.canDrawOverlays()) {
  await NectarTrackerPlatform.instance.startChatHeadService();
}
```

### **MQTT Configuration**

```dart
await tracker.setMqttConfigAndDetails(
  broker: 'broker.hivemq.com',
  port: 1883, // Use 8883 for SSL/TLS
  username: 'your_username', // Optional
  password: 'your_password', // Optional
  topic: 'nectar/location',
  userId: 'user123',
  batteryLevel: 85,
  userType: 'driver',
  deviceId: 'device456',
  domain: 'example.com',
  usernameField: 'john_doe',
  identifier: 'unique_id',
  skills: ['delivery', 'pickup'],
  status: 'active',
  name: 'John Doe',
  geofence: 'zone1',
  emailid: 'john@example.com',
  mobile: '+1234567890',
  jobId: 'job789',
);

// Check MQTT connection status
final mqttStatus = await tracker.getMqttStatus();
print('MQTT Connected: ${mqttStatus['connected']}');
print('Connection State: ${mqttStatus['connectionState']}');
```

### **Get Current Location**

```dart
final location = await tracker.getCurrentPosition();
print('Current: ${location?.latitude}, ${location?.longitude}');
```

### **Listen to Events**

```dart
tracker.onLocation.listen((location) => print('Location: $location'));
tracker.onMotionChange.listen((location) => print('Motion: $location'));
tracker.onProviderChange.listen((event) => print('Provider: $event'));
tracker.onActivityChange.listen((event) => print('Activity: $event'));
```

### **Get State & Stats**

```dart
final state = await tracker.getState();
print('Tracking: ${state.enabled}');
print('Moving: ${state.isMoving}');

final stats = await tracker.getTrackingStats();
print('Total Locations: ${stats.totalLocations}');
print('Total Distance: ${stats.totalDistance}m');
print('Foreground: ${stats.foregroundLocations}');
print('Background: ${stats.backgroundLocations}');
```

### **Clear Data**

```dart
await tracker.clearTrackingData();
```

---

## 📱 Platform Setup

### **Android**

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

Place your custom icon in `android/app/src/main/res/drawable/` (e.g., `ic_chat_head.png`), then reference it in config:

```dart
chatHeadIcon: 'ic_chat_head', // Without file extension
```

#### Dependencies

MQTT dependencies are automatically included:

- `org.eclipse.paho:org.eclipse.paho.client.mqttv3:1.2.5`
- `com.google.code.gson:gson:2.10.1`

#### Foreground Service

The plugin automatically creates and manages a foreground service for background tracking. No additional setup required.

### **iOS**

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

### **NectarTrackerConfig**

| Property                  | Type            | Default | Description                                 |
| ------------------------- | --------------- | ------- | ------------------------------------------- |
| desiredAccuracy           | DesiredAccuracy | high    | Location accuracy (low, medium, high, best) |
| distanceFilter            | double          | 10.0    | Minimum distance (meters) for updates       |
| stopOnTerminate           | bool            | false   | Stop tracking on app terminate              |
| startOnBoot               | bool            | true    | Start tracking after device reboot          |
| debug                     | bool            | true    | Enable debug logging                        |
| logLevel                  | LogLevel        | verbose | Log verbosity                               |
| enableBatteryOptimization | bool            | false   | Enable battery optimization                 |
| notificationTitle         | String          | ...     | Android notification title                  |
| notificationText          | String          | ...     | Android notification text                   |
| interval                  | int             | 5000    | Update interval (ms)                        |
| fastestInterval           | int             | 3000    | Fastest update interval (ms)                |
| notificationIcon          | String?         | null    | Android notification icon resource name     |
| notificationColor         | String?         | null    | Android notification color                  |
| chatHeadIcon              | String?         | null    | Android: Chat head icon resource name       |
| showLocationNotifications | bool            | false   | Show location update notifications          |

### **Methods**

#### Core Methods

- `ready(NectarTrackerConfig config)` - Initialize and configure the plugin
- `start()` - Start location tracking (returns `Future<bool>`)
- `stop()` - Stop location tracking
- `getState()` - Get current tracking state
- `getCurrentPosition()` - Get current location
- `isLocationServicesEnabled()` - Check if location services are enabled
- `getTrackingStats()` - Get tracking statistics
- `clearTrackingData()` - Clear all tracking data
- `getPlatformVersion()` - Get platform version

#### MQTT Methods

- `setMqttConfigAndDetails(...)` - Configure MQTT broker and user details
- `getMqttStatus()` - Get MQTT connection status

#### Android-Only Methods (via Platform Interface)

- `canDrawOverlays()` - Check if overlay permission is granted
- `requestOverlayPermission()` - Open settings to request overlay permission
- `startChatHeadService()` - Manually start chat head service

### **Events**

- `onLocation` - New location update
- `onMotionChange` - Stationary/moving state change
- `onProviderChange` - Location provider state change
- `onActivityChange` - Activity type change
- `onGeofence` - Geofence enter/exit events
- `onHeartbeat` - Heartbeat events
- `onHttp` - HTTP request events
- `onConnectivityChange` - Network connectivity changes
- `onPowerSaveChange` - Power save mode changes

### **Enums**

- `DesiredAccuracy`: `low`, `medium`, `high`, `best`
- `LogLevel`: `off`, `error`, `warning`, `info`, `debug`, `verbose`
- `AuthorizationStatus`: `denied`, `authorized`, `authorizedAlways`, `authorizedWhenInUse`
- `ActivityType`: `unknown`, `still`, `walking`, `running`, `automotive`, `cycling`

---

## 🎈 Chat Head Feature (Android)

The chat head is a floating bubble that appears on screen when tracking is active, similar to Facebook Messenger's chat heads.

### Features

- ✅ Draggable - Touch and drag to move around screen
- ✅ Clickable - Tap to show status (shows toast by default)
- ✅ Custom Icon - Configure your own icon
- ✅ Auto-start - Appears automatically when tracking starts
- ✅ Auto-stop - Disappears when tracking stops
- ✅ Persistent - Works even when app is terminated

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

## 📡 MQTT Integration

### MQTT Payload Format

Location data is published as JSON to the configured MQTT topic:

```json
{
  "location": "POINT(longitude latitude)",
  "id": "userId",
  "batteryLevel": 85,
  "type": "userType",
  "time": 1234567890123,
  "deviceId": "deviceId",
  "domain": "domain",
  "username": "username",
  "identifier": "identifier",
  "skills": ["skill1", "skill2"],
  "status": "status",
  "name": "name",
  "geofence": "geofence",
  "emailid": "email",
  "mobile": "mobile",
  "jobId": "jobId"
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

### Connection Management

- Automatic reconnection on disconnect
- Connection status available via `getMqttStatus()`
- Graceful disconnection on service stop

---

## 🐞 Debugging

- All actions, errors, and events are printed with `[NectarTracker]` in your debug console
- Use `debug: true` and `logLevel: LogLevel.verbose` for maximum output
- Check logs for:
  - `[NectarTracker]` - General plugin logs
  - `LocationForegroundService` - Android service logs
  - `ChatHeadService` - Chat head service logs

---

## 🧪 Example App

See `example/lib/main.dart` for a full-featured demo with:

- Live tracking UI
- Event logs
- MQTT configuration
- Chat head controls
- Statistics display

---

## ❓ Troubleshooting

### **No location updates?**

- ✅ Check permissions (Android/iOS)
- ✅ Ensure background modes are enabled
- ✅ Watch the debug console for `[NectarTracker]` errors
- ✅ Verify location services are enabled on device

### **Chat head not appearing (Android)?**

- ✅ Grant "Display over other apps" permission
- ✅ Check if overlay permission is granted: `canDrawOverlays()`
- ✅ Verify icon resource exists in `res/drawable/`
- ✅ Check logs for `ChatHeadService` errors
- ✅ Try manually starting: `startChatHeadService()`

### **MQTT not connecting?**

- ✅ Check broker URL and port
- ✅ Verify network connectivity
- ✅ Check credentials (if required)
- ✅ For SSL, use ports 8883 or 8884
- ✅ Check `getMqttStatus()` for connection state

### **App killed/terminated?**

- ✅ On Android: Use `startOnBoot: true` and required permissions
- ✅ On iOS: Background modes and "Always" permission are required
- ✅ Chat head continues even when app is terminated (Android)

### **Service crashes on stop?**

- ✅ Fixed in latest version - MQTT disconnection is now handled gracefully
- ✅ Service checks connection state before disconnecting

---

## 📄 License

MIT

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
