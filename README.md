# Nectar Tracker

A **Flutter plugin** for robust, background and foreground location tracking, inspired by `flutter_background_geolocation` and `flutter_background_location`.  
Supports **live event streams**, **background/terminated tracking**, and **comprehensive debugging** for both Android and iOS.

---

## 🚀 Features

- **Foreground, background, and terminated location tracking**
- **Event-driven API**: Streams for location, motion, provider, activity, geofence, heartbeat, HTTP, connectivity, power-save
- **Live debug logging**: See every action, error, and event in your console
- **Highly configurable**: Control accuracy, intervals, notifications, and more
- **Production-ready**: Works on Android and iOS, with all required permissions and background modes

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
  ));

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
));
```

### **Start/Stop Tracking**

```dart
await tracker.start();
await tracker.stop();
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
final stats = await tracker.getTrackingStats();
```

### **Clear Data**

```dart
await tracker.clearTrackingData();
```

---

## 📱 Platform Setup

### **Android**

- Add permissions to `android/app/src/main/AndroidManifest.xml`:
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
  ```
 - Foreground service and notification are handled automatically.
 - MQTT uses Paho core `MqttAsyncClient` (no Android service). Dependencies declared in the plugin `android/build.gradle`:
   - `org.eclipse.paho:org.eclipse.paho.client.mqttv3:1.2.5`
   - `com.google.code.gson:gson:2.10.1`

### **iOS**

- Add to `ios/Runner/Info.plist`:
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
- Make sure to request "Always" location permission in your app.

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
| showLocationNotifications | bool            | false   | Show location notifications                 |

### **Events**

- `onLocation` — New location
- `onMotionChange` — Stationary/moving state change
- `onProviderChange` — Location provider state change
- `onActivityChange` — Activity type change
- `onGeofence`, `onHeartbeat`, `onHttp`, `onConnectivityChange`, `onPowerSaveChange`

---

## 🐞 Debugging

- All actions, errors, and events are printed with `[NectarTracker]` in your debug console.
- Use `debug: true` and `logLevel: LogLevel.verbose` for maximum output.

---

## 🧪 Example App

See `example/lib/main.dart` for a full-featured demo with live tracking, event logs, and UI.

---

## ❓ Troubleshooting

- **No location updates?**

  - Check permissions (Android/iOS)
  - Ensure background modes are enabled
  - Watch the debug console for `[NectarTracker]` errors

- **App killed/terminated?**
  - On Android, use `startOnBoot: true` and required permissions
  - On iOS, background modes and "Always" permission are required

---

## 📄 License

MIT

---

## 🙏 Acknowledgments

Inspired by [`flutter_background_geolocation`](https://pub.dev/packages/flutter_background_geolocation) and [`flutter_background_location`](https://pub.dev/packages/flutter_background_location).

---

If you need more advanced usage, custom event handling, or have any issues, just open an issue or ask for help!
