# Trackiva Migration Summary

## ✅ Completed Tasks

### 1. Package Renaming

- ✅ Renamed package from `nectar_tracker` to `trackiva`
- ✅ Updated `pubspec.yaml` files (main and example)
- ✅ Created new library files:
  - `lib/trackiva.dart` (main library)
  - `lib/trackiva_platform_interface.dart`
  - `lib/trackiva_method_channel.dart`
  - `lib/trackiva_storage.dart` (new offline storage)
- ✅ Updated example app (`example/lib/main.dart`) to use Trackiva

### 2. GraphQL Support

- ✅ Added `graphql: ^5.1.2` dependency
- ✅ Implemented GraphQL client in `trackiva.dart`
- ✅ Added `setGraphQLConfig()` method
- ✅ Added GraphQL mutation support for location data
- ✅ Integrated GraphQL with offline sync

### 3. HTTP Support

- ✅ Added `http: ^1.2.0` dependency
- ✅ Implemented HTTP client in `trackiva.dart`
- ✅ Added `setHttpConfig()` method
- ✅ Added HTTP POST support for location data
- ✅ Integrated HTTP with offline sync

### 4. Offline Storage & Sync

- ✅ Added `sqflite: ^2.3.0` and `path_provider: ^2.1.1` dependencies
- ✅ Created `TrackivaStorage` class for local database
- ✅ Implemented SQLite database for storing pending locations
- ✅ Added `connectivity_plus: ^5.0.2` for network monitoring
- ✅ Implemented automatic sync when device comes online
- ✅ Location data is saved locally when offline
- ✅ Pending locations are synced when connectivity is restored

### 5. Configuration Updates

- ✅ Updated `TrackivaConfig` to include:
  - `enableHttp` and `httpEndpoint` for HTTP support
  - `enableGraphQL`, `graphqlEndpoint`, and `graphqlMutation` for GraphQL support
  - HTTP and GraphQL headers support

## 🔄 How Offline Sync Works

1. **When Offline:**

   - Location updates are saved to local SQLite database
   - Data includes location coordinates, metadata, and timestamp
   - Locations are marked as `synced = 0` (pending)

2. **When Online:**

   - Connectivity listener detects network availability
   - Automatically triggers sync process
   - Attempts to send pending locations via:
     - MQTT (handled by platform)
     - HTTP (if enabled)
     - GraphQL (if enabled)
   - Successfully synced locations are marked as `synced = 1`

3. **Sync Priority:**
   - MQTT is tried first (platform-level)
   - HTTP is tried if MQTT fails or is not configured
   - GraphQL is tried if HTTP fails or is not configured

## ⚠️ Remaining Tasks

### Native Code Updates Required

#### Android (`android/src/main/kotlin/`)

1. **Rename Plugin Class:**

   - Rename `NectarTrackerPlugin.kt` to `TrackivaPlugin.kt`
   - Update class name from `NectarTrackerPlugin` to `TrackivaPlugin`
   - Update package name from `com.example.nectar_tracker` to `com.example.trackiva`
   - Update method channel name from `nectar_tracker` to `trackiva`
   - Update event channel name from `nectar_tracker/updates` to `trackiva/updates`

2. **Update AndroidManifest.xml:**

   - Update package name references
   - Update service class names
   - Update receiver class names

3. **Add HTTP/GraphQL Support (Optional):**
   - Native HTTP/GraphQL support can be added, but current implementation works at Dart level

#### iOS (`ios/Classes/`)

1. **Rename Plugin Class:**

   - Rename `NectarTrackerPlugin.swift` to `TrackivaPlugin.swift`
   - Update class name from `NectarTrackerPlugin` to `TrackivaPlugin`
   - Update method channel name from `nectar_tracker` to `trackiva`
   - Update event channel name from `nectar_tracker/updates` to `trackiva/updates`

2. **Update Podspec:**
   - Update `ios/nectar_tracker.podspec` to `ios/trackiva.podspec`
   - Update all references

### Example App Updates

- ✅ Main Dart file updated
- ⚠️ May need to update Android/iOS native configurations in example app

## 📝 Usage Example

```dart
import 'package:trackiva/trackiva.dart';

final tracker = Trackiva();

// Configure with HTTP and GraphQL support
await tracker.ready(TrackivaConfig(
  desiredAccuracy: DesiredAccuracy.high,
  distanceFilter: 10.0,
  enableHttp: true,
  httpEndpoint: 'https://api.example.com/location',
  httpHeaders: {'Authorization': 'Bearer token'},
  enableGraphQL: true,
  graphqlEndpoint: 'https://api.example.com/graphql',
  graphqlMutation: '''
    mutation SendLocation(\$location: LocationInput!) {
      sendLocation(location: \$location) {
        id
        timestamp
      }
    }
  ''',
));

// Configure MQTT (existing)
await tracker.setMqttConfigAndDetails(...);

// Configure HTTP
await tracker.setHttpConfig(
  endpoint: 'https://api.example.com/location',
  headers: {'Authorization': 'Bearer token'},
  method: 'POST',
);

// Configure GraphQL
await tracker.setGraphQLConfig(
  endpoint: 'https://api.example.com/graphql',
  mutation: 'mutation SendLocation(...) { ... }',
  headers: {'Authorization': 'Bearer token'},
);

// Start tracking - offline sync is automatic
await tracker.start();

// Listen to connectivity changes
tracker.onConnectivityChange.listen((event) {
  print('Online: ${event.connected}');
});
```

## 🔧 Next Steps

1. **Update Native Android Code:**

   - Rename plugin class and update all references
   - Update method/event channel names
   - Test MQTT, HTTP, and GraphQL integration

2. **Update Native iOS Code:**

   - Rename plugin class and update all references
   - Update method/event channel names
   - Test MQTT, HTTP, and GraphQL integration

3. **Testing:**

   - Test offline storage functionality
   - Test sync when coming online
   - Test all three transport methods (MQTT, HTTP, GraphQL)
   - Test on both Android and iOS

4. **Documentation:**
   - Update README.md with new features
   - Add examples for HTTP and GraphQL usage
   - Document offline sync behavior

## 📦 Dependencies Added

- `http: ^1.2.0` - HTTP client
- `graphql: ^5.1.2` - GraphQL client
- `sqflite: ^2.3.0` - SQLite database
- `path_provider: ^2.1.1` - Path utilities
- `connectivity_plus: ^5.0.2` - Network connectivity monitoring

## ✨ Features

✅ **Yes, offline storage with sync is possible and implemented!**

The implementation:

- Stores locations in SQLite when offline
- Monitors network connectivity
- Automatically syncs when online
- Supports multiple transport methods (MQTT, HTTP, GraphQL)
- Handles sync failures gracefully
- Maintains data integrity
