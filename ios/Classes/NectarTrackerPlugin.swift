import Flutter
import UIKit
import CoreLocation
import UserNotifications

public class NectarTrackerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, CLLocationManagerDelegate {
    private static let CHANNEL_NAME = "nectar_tracker"
    private static let EVENT_CHANNEL_NAME = "nectar_tracker/updates"
    
    private var eventSink: FlutterEventSink?
    private var locationManager: CLLocationManager?
    private var locationData: [String: Any] = [:]
    private var currentLocation: CLLocation?
    private var isTracking = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // Tracking statistics
    private var totalLocations = 0
    private var foregroundLocations = 0
    private var backgroundLocations = 0
    private var firstLocationTime: Date?
    private var lastLocationTime: Date?
    private var totalDistance: Double = 0.0
    private var lastLocation: CLLocation?
    private var currentAccuracy: String = "medium"
    
    // Settings
    private var enableLogging = true
    private var showLocationNotifications = false
    private var enableBackgroundMode = true
    private var enableHighAccuracy = true
    private var distanceFilter: Double = 10.0
    private var interval: TimeInterval = 5.0
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = NectarTrackerPlugin()
        
        let methodChannel = FlutterMethodChannel(name: CHANNEL_NAME, binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        
        let eventChannel = FlutterEventChannel(name: EVENT_CHANNEL_NAME, binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
                return
            }
            
            // Get settings
            enableLogging = args["enableLogging"] as? Bool ?? true
            showLocationNotifications = args["showLocationNotifications"] as? Bool ?? false
            enableBackgroundMode = args["enableBackgroundMode"] as? Bool ?? true
            enableHighAccuracy = args["enableHighAccuracy"] as? Bool ?? true
            distanceFilter = args["distanceFilter"] as? Double ?? 10.0
            interval = TimeInterval((args["interval"] as? Int ?? 5000) / 1000)
            
            if enableLogging {
                print("NectarTracker: Initializing with logging enabled")
            }
            
            // Initialize location manager
            locationManager = CLLocationManager()
            locationManager?.delegate = self
            locationManager?.allowsBackgroundLocationUpdates = enableBackgroundMode
            locationManager?.pausesLocationUpdatesAutomatically = false
            locationManager?.showsBackgroundLocationIndicator = true
            
            // Configure accuracy based on settings
            if enableHighAccuracy {
                locationManager?.desiredAccuracy = kCLLocationAccuracyBest
                currentAccuracy = "high"
            } else {
                locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
                currentAccuracy = "medium"
            }
            
            locationManager?.distanceFilter = distanceFilter
            
            // Request permissions
            locationManager?.requestAlwaysAuthorization()
            
            // Configure notification
            if #available(iOS 10.0, *) {
                let center = UNUserNotificationCenter.current()
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if self.enableLogging {
                        print("NectarTracker: Notification permission granted: \(granted)")
                    }
                }
            }
            
            if enableLogging {
                print("NectarTracker: Initialized successfully")
            }
            
            result(nil)
            
        case "startTracking":
            guard CLLocationManager.locationServicesEnabled() else {
                result(FlutterError(code: "LOCATION_DISABLED", message: "Location services are disabled", details: nil))
                return
            }
            
            if enableLogging {
                print("NectarTracker: Starting location tracking")
            }
            
            isTracking = true
            
            // Start location updates
            locationManager?.startUpdatingLocation()
            
            // Start significant location changes for background tracking
            if #available(iOS 9.0, *) {
                locationManager?.startMonitoringSignificantLocationChanges()
            }
            
            // Start background task
            startBackgroundTask()
            
            if enableLogging {
                print("NectarTracker: Location tracking started successfully")
            }
            
            result(nil)
            
        case "stopTracking":
            if enableLogging {
                print("NectarTracker: Stopping location tracking")
            }
            
            isTracking = false
            locationManager?.stopUpdatingLocation()
            
            if #available(iOS 9.0, *) {
                locationManager?.stopMonitoringSignificantLocationChanges()
            }
            
            endBackgroundTask()
            
            if enableLogging {
                print("NectarTracker: Location tracking stopped successfully")
            }
            
            result(nil)
            
        case "isTracking":
            result(isTracking)
            
        case "getCurrentLocation":
            if enableLogging {
                print("NectarTracker: Getting current location")
            }
            
            if let location = currentLocation {
                if enableLogging {
                    print("NectarTracker: Current location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                }
                
                let locationMap: [String: Any] = [
                    "latitude": location.coordinate.latitude,
                    "longitude": location.coordinate.longitude,
                    "accuracy": location.horizontalAccuracy,
                    "altitude": location.altitude,
                    "speed": location.speed,
                    "bearing": location.course,
                    "timestamp": Int(location.timestamp.timeIntervalSince1970 * 1000),
                    "isBackground": false,
                    "provider": "iOS"
                ]
                result(locationMap)
            } else {
                result(nil)
            }
            
        case "isLocationServiceEnabled":
            result(CLLocationManager.locationServicesEnabled())
            
        case "getLocationAccuracy":
            result(currentAccuracy)
            
        case "setLocationAccuracy":
            guard let args = call.arguments as? [String: Any],
                  let accuracy = args["accuracy"] as? String else {
                result(false)
                return
            }
            
            if enableLogging {
                print("NectarTracker: Setting location accuracy to: \(accuracy)")
            }
            
            switch accuracy {
            case "low":
                locationManager?.desiredAccuracy = kCLLocationAccuracyKilometer
                currentAccuracy = "low"
            case "medium":
                locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
                currentAccuracy = "medium"
            case "high":
                locationManager?.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
                currentAccuracy = "high"
            case "best":
                locationManager?.desiredAccuracy = kCLLocationAccuracyBest
                currentAccuracy = "best"
            default:
                locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
                currentAccuracy = "medium"
            }
            
            result(true)
            
        case "getTrackingStats":
            let stats: [String: Any] = [
                "totalLocations": totalLocations,
                "foregroundLocations": foregroundLocations,
                "backgroundLocations": backgroundLocations,
                "firstLocationTime": firstLocationTime?.timeIntervalSince1970 ?? 0,
                "lastLocationTime": lastLocationTime?.timeIntervalSince1970 ?? 0,
                "totalDistance": totalDistance,
                "averageSpeed": totalLocations > 0 ? totalDistance / Double(totalLocations) : 0.0
            ]
            
            if enableLogging {
                print("NectarTracker: Tracking stats: \(totalLocations) locations, \(String(format: "%.2f", totalDistance))m distance")
            }
            
            result(stats)
            
        case "clearTrackingData":
            if enableLogging {
                print("NectarTracker: Clearing tracking data")
            }
            
            totalLocations = 0
            foregroundLocations = 0
            backgroundLocations = 0
            firstLocationTime = nil
            lastLocationTime = nil
            totalDistance = 0.0
            lastLocation = nil
            
            if enableLogging {
                print("NectarTracker: Tracking data cleared successfully")
            }
            
            result(true)
            
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func startBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "NectarTrackerBackgroundTask") {
            self.endBackgroundTask()
        }
        
        if enableLogging {
            print("NectarTracker: Background task started")
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
            
            if enableLogging {
                print("NectarTracker: Background task ended")
            }
        }
    }
    
    private func updateTrackingStats(location: CLLocation, isBackground: Bool) {
        totalLocations += 1
        if isBackground {
            backgroundLocations += 1
        } else {
            foregroundLocations += 1
        }
        
        if firstLocationTime == nil {
            firstLocationTime = location.timestamp
        }
        lastLocationTime = location.timestamp
        
        // Calculate distance
        if let last = lastLocation {
            let distance = last.distance(from: location)
            totalDistance += distance
        }
        lastLocation = location
    }
    
    private func showLocationNotification(location: CLLocation, isBackground: Bool) {
        if #available(iOS 10.0, *) {
            let content = UNMutableNotificationContent()
            content.title = "Location Update"
            let status = isBackground ? "Background" : "Foreground"
            content.body = "\(location.coordinate.latitude), \(location.coordinate.longitude) (\(status))"
            content.sound = nil
            
            let request = UNNotificationRequest(
                identifier: "nectar_tracker_location_\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("NectarTracker: Failed to show notification: \(error)")
                }
            }
        }
    }
    
    // MARK: - FlutterStreamHandler
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
    
    // MARK: - CLLocationManagerDelegate
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        currentLocation = location
        
        // Update tracking stats for foreground
        updateTrackingStats(location: location, isBackground: false)
        
        // Log location update
        if enableLogging {
            print("NectarTracker: Location update: \(location.coordinate.latitude), \(location.coordinate.longitude) (Foreground)")
        }
        
        // Show notification if enabled
        if showLocationNotifications {
            showLocationNotification(location: location, isBackground: false)
        }
        
        // Send foreground location data
        let foregroundData: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy,
            "altitude": location.altitude,
            "speed": location.speed,
            "bearing": location.course,
            "timestamp": Int(location.timestamp.timeIntervalSince1970 * 1000),
            "isBackground": false,
            "provider": "iOS"
        ]
        
        eventSink?(foregroundData)
        
        // If background mode is enabled, also send background location data
        if enableBackgroundMode && isTracking {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self.isTracking {
                    // Update tracking stats for background
                    self.updateTrackingStats(location: location, isBackground: true)
                    
                    // Log background location update
                    if self.enableLogging {
                        print("NectarTracker: Location update: \(location.coordinate.latitude), \(location.coordinate.longitude) (Background)")
                    }
                    
                    // Show notification if enabled
                    if self.showLocationNotifications {
                        self.showLocationNotification(location: location, isBackground: true)
                    }
                    
                    let backgroundData: [String: Any] = [
                        "latitude": location.coordinate.latitude,
                        "longitude": location.coordinate.longitude,
                        "accuracy": location.horizontalAccuracy,
                        "altitude": location.altitude,
                        "speed": location.speed,
                        "bearing": location.course,
                        "timestamp": Int(location.timestamp.timeIntervalSince1970 * 1000),
                        "isBackground": true,
                        "provider": "iOS"
                    ]
                    
                    self.eventSink?(backgroundData)
                }
            }
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if enableLogging {
            print("NectarTracker: Location error: \(error.localizedDescription)")
        }
        eventSink?(FlutterError(code: "LOCATION_ERROR", message: error.localizedDescription, details: nil))
    }
    
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let authorizationStatus: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            authorizationStatus = manager.authorizationStatus
        } else {
            authorizationStatus = CLLocationManager.authorizationStatus()
        }
        
        if enableLogging {
            switch authorizationStatus {
            case .authorizedAlways:
                print("NectarTracker: Location authorization: Always")
            case .authorizedWhenInUse:
                print("NectarTracker: Location authorization: When in use")
            case .denied, .restricted:
                print("NectarTracker: Location authorization: Denied")
            case .notDetermined:
                print("NectarTracker: Location authorization: Not determined")
            @unknown default:
                print("NectarTracker: Location authorization: Unknown")
            }
        }
    }
    
    public func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        if enableLogging {
            print("NectarTracker: Location updates paused")
        }
    }
    
    public func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        if enableLogging {
            print("NectarTracker: Location updates resumed")
        }
    }
}