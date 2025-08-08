import Flutter
import UIKit
import CoreLocation
import UserNotifications
import CocoaMQTT

public class NectarTrackerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, CLLocationManagerDelegate, CocoaMQTTDelegate {
    private static let CHANNEL_NAME = "nectar_tracker"
    private static let EVENT_CHANNEL_NAME = "nectar_tracker/updates"
    
    private var mqttClient: CocoaMQTT?
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
    
    // MQTT config
    private var mqttBroker: String = "broker.hivemq.com"
    private var mqttPort: Int = 1883
    private var mqttUsername: String = ""
    private var mqttPassword: String = ""
    private var mqttTopic: String = "nectar/location"
    
    // User/device/job info
    private var userId: String = ""
    private var batteryLevel: Int = 0
    private var userType: String = ""
    private var deviceId: String = ""
    private var domain: String = ""
    private var usernameField: String = ""
    private var identifier: String = ""
    private var skills: [Any] = []
    private var status: String = ""
    private var name: String = ""
    private var geofence: String = ""
    private var emailid: String = ""
    private var mobile: String = ""
    private var jobId: String = ""
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = NectarTrackerPlugin()
        
        let methodChannel = FlutterMethodChannel(name: CHANNEL_NAME, binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        
        let eventChannel = FlutterEventChannel(name: EVENT_CHANNEL_NAME, binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(instance)
    }
    
    override init() {
        super.init()
        setupMqttClient()
    }
    
    private func setupMqttClient() {
        mqttClient = CocoaMQTT(clientID: "nectar_ios_\(UUID().uuidString)", host: mqttBroker, port: UInt16(mqttPort))
        mqttClient?.username = mqttUsername
        mqttClient?.password = mqttPassword
        mqttClient?.delegate = self
        mqttClient?.autoReconnect = true
        mqttClient?.logLevel = enableLogging ? .debug : .off
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
                return
            }
            
            enableLogging = args["enableLogging"] as? Bool ?? true
            showLocationNotifications = args["showLocationNotifications"] as? Bool ?? false
            enableBackgroundMode = args["enableBackgroundMode"] as? Bool ?? true
            enableHighAccuracy = args["enableHighAccuracy"] as? Bool ?? true
            distanceFilter = args["distanceFilter"] as? Double ?? 10.0
            interval = TimeInterval((args["interval"] as? Int ?? 5000) / 1000)
            
            if enableLogging {
                print("NectarTracker: Initializing with logging enabled")
            }
            
            locationManager = CLLocationManager()
            locationManager?.delegate = self
            locationManager?.allowsBackgroundLocationUpdates = enableBackgroundMode
            locationManager?.pausesLocationUpdatesAutomatically = false
            locationManager?.showsBackgroundLocationIndicator = true
            
            if enableHighAccuracy {
                locationManager?.desiredAccuracy = kCLLocationAccuracyBest
                currentAccuracy = "high"
            } else {
                locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
                currentAccuracy = "medium"
            }
            
            locationManager?.distanceFilter = distanceFilter
            locationManager?.requestAlwaysAuthorization()
            
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
            locationManager?.startUpdatingLocation()
            if #available(iOS 9.0, *) {
                locationManager?.startMonitoringSignificantLocationChanges()
            }
            
            startBackgroundTask()
            mqttClient?.connect()
            
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
            mqttClient?.disconnect()
            
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
            
        case "setTrackingDetails":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
                return
            }
            userId = args["userId"] as? String ?? ""
            batteryLevel = args["batteryLevel"] as? Int ?? 0
            userType = args["userType"] as? String ?? ""
            deviceId = args["deviceId"] as? String ?? ""
            domain = args["domain"] as? String ?? ""
            usernameField = args["username"] as? String ?? ""
            identifier = args["identifier"] as? String ?? ""
            skills = args["skills"] as? [Any] ?? []
            status = args["status"] as? String ?? ""
            name = args["name"] as? String ?? ""
            geofence = args["geofence"] as? String ?? ""
            emailid = args["emailid"] as? String ?? ""
            mobile = args["mobile"] as? String ?? ""
            jobId = args["jobId"] as? String ?? ""
            result(nil)
            
        case "setMqttConfigAndDetails":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
                return
            }
            mqttBroker = args["broker"] as? String ?? mqttBroker
            mqttPort = args["port"] as? Int ?? mqttPort
            mqttUsername = args["username"] as? String ?? mqttUsername
            mqttPassword = args["password"] as? String ?? mqttPassword
            mqttTopic = args["topic"] as? String ?? mqttTopic
            userId = args["userId"] as? String ?? userId
            batteryLevel = args["batteryLevel"] as? Int ?? batteryLevel
            userType = args["userType"] as? String ?? userType
            deviceId = args["deviceId"] as? String ?? deviceId
            domain = args["domain"] as? String ?? domain
            usernameField = args["usernameField"] as? String ?? usernameField
            identifier = args["identifier"] as? String ?? identifier
            skills = args["skills"] as? [Any] ?? skills
            status = args["status"] as? String ?? status
            name = args["name"] as? String ?? name
            geofence = args["geofence"] as? String ?? geofence
            emailid = args["emailid"] as? String ?? emailid
            mobile = args["mobile"] as? String ?? mobile
            jobId = args["jobId"] as? String ?? jobId
            
            mqttClient?.disconnect()
            setupMqttClient()
            if isTracking {
                mqttClient?.connect()
            }
            
            if enableLogging {
                print("NectarTracker: MQTT config updated - Broker: \(mqttBroker), Topic: \(mqttTopic)")
            }
            
            result(nil)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - CocoaMQTTDelegate
    
    @objc public func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        if enableLogging {
            print("NectarTracker: MQTT connected with ACK: \(ack.rawValue)")
        }
    }
    
    @objc public func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        if enableLogging {
            print("NectarTracker: Message published - ID: \(id), Topic: \(message.topic)")
        }
    }
    
    @objc public func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        if enableLogging {
            print("NectarTracker: Received message - ID: \(id), Topic: \(message.topic), Payload: \(message.string ?? "")")
        }
    }
    
    @objc public func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics topics: [String]) {
        if enableLogging {
            print("NectarTracker: Subscribed to topics: \(topics)")
        }
    }
    
    @objc public func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        if enableLogging {
            print("NectarTracker: Unsubscribed from topics: \(topics)")
        }
    }
    
    @objc public func mqtt(_ mqtt: CocoaMQTT, didReceivePong: CocoaMQTT) {
        if enableLogging {
            print("NectarTracker: MQTT pong received")
        }
    }
    
    @objc public func mqttDidPing(_ mqtt: CocoaMQTT) {
        if enableLogging {
            print("NectarTracker: MQTT ping sent")
        }
    }
    
    @objc public func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        if enableLogging {
            print("NectarTracker: MQTT disconnected with error: \(err?.localizedDescription ?? "No error")")
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
        updateTrackingStats(location: location, isBackground: false)
        
        if enableLogging {
            print("NectarTracker: Location update: \(location.coordinate.latitude), \(location.coordinate.longitude) (Foreground)")
        }
        
        if showLocationNotifications {
            showLocationNotification(location: location, isBackground: false)
        }
        
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
        
        if mqttClient?.connState == .connected {
            let payload: [String: Any] = [
                "location": "POINT(\(location.coordinate.longitude) \(location.coordinate.latitude))",
                "id": userId,
                "batteryLevel": batteryLevel,
                "type": userType,
                "time": Int(Date().timeIntervalSince1970 * 1000),
                "deviceId": deviceId,
                "domain": domain,
                "username": usernameField,
                "identifier": identifier,
                "skills": skills,
                "status": status,
                "name": name,
                "geofence": geofence,
                "emailid": emailid,
                "mobile": mobile,
                "jobId": jobId
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
               let jsonString = String(data: data, encoding: .utf8) {
                mqttClient?.publish(mqttTopic, withString: jsonString, qos: .qos1)
            }
        } else if enableLogging {
            print("NectarTracker: MQTT not connected, skipping publish")
        }
        
        if enableBackgroundMode && isTracking {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self.isTracking {
                    self.updateTrackingStats(location: location, isBackground: true)
                    if self.enableLogging {
                        print("NectarTracker: Location update: \(location.coordinate.latitude), \(location.coordinate.longitude) (Background)")
                    }
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

                    // Also publish to MQTT when in background
                    if self.mqttClient?.connState == .connected {
                        let payload: [String: Any] = [
                            "location": "POINT(\(location.coordinate.longitude) \(location.coordinate.latitude))",
                            "id": self.userId,
                            "batteryLevel": self.batteryLevel,
                            "type": self.userType,
                            "time": Int(Date().timeIntervalSince1970 * 1000),
                            "deviceId": self.deviceId,
                            "domain": self.domain,
                            "username": self.usernameField,
                            "identifier": self.identifier,
                            "skills": self.skills,
                            "status": self.status,
                            "name": self.name,
                            "geofence": self.geofence,
                            "emailid": self.emailid,
                            "mobile": self.mobile,
                            "jobId": self.jobId
                        ]
                        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
                           let jsonString = String(data: data, encoding: .utf8) {
                            self.mqttClient?.publish(self.mqttTopic, withString: jsonString, qos: .qos1)
                        }
                    } else if self.enableLogging {
                        print("NectarTracker: MQTT not connected (background), skipping publish")
                    }
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