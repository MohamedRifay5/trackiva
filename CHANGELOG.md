## 0.0.3

- MQTT Enchancement

## 0.0.2

### Major Changes

- **Complete rebranding**: Renamed from Nectar Tracker to Trackiva across all files, packages, and documentation
- **Flexible payload support**: MQTT configuration now accepts a flexible `Map<String, dynamic>` payload instead of fixed fields
- **HTTP support**: Added HTTP endpoint configuration for sending location data via REST API
- **GraphQL support**: Added GraphQL endpoint and mutation configuration for sending location data
- **Offline storage & sync**: Implemented local SQLite database storage with automatic sync when connectivity is restored
- **Connectivity monitoring**: Added real-time network connectivity detection and automatic sync triggering

### Features Added

- `setHttpConfig()` method for configuring HTTP endpoints
- `setGraphQLConfig()` method for configuring GraphQL endpoints
- Automatic offline storage of location data
- Automatic sync of pending locations when online
- `onConnectivityChange` event stream for monitoring network status
- Enhanced `onHttp` event stream for HTTP request tracking

### Improvements

- Updated all package names from `nectar_tracker` to `trackiva`
- Updated all class names from `NectarTracker*` to `Trackiva*`
- Updated all method channel names to use `trackiva` prefix
- Comprehensive README.md with all features documented
- Updated example app to use new Trackiva API

### Breaking Changes

- `setMqttConfigAndDetails()` now requires a `payload` parameter (Map<String, dynamic>) instead of individual fields
- All package imports changed from `package:nectar_tracker/nectar_tracker.dart` to `package:trackiva/trackiva.dart`
- All class names changed (e.g., `NectarTracker` → `Trackiva`, `NectarTrackerConfig` → `TrackivaConfig`)

### Bug Fixes

- Fixed connectivity_plus API usage (corrected to use List<ConnectivityResult>)
- Fixed GraphQL mutation parsing with proper gql function usage
- Removed all nectar-related references from codebase

## 0.0.1

- Initial release with basic location tracking and MQTT support
