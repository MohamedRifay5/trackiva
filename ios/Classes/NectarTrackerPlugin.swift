import Flutter
import UIKit
import CoreLocation
import UserNotifications
import CocoaMQTT

public class NectarTrackerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, CLLocationManagerDelegate, CocoaMQTTDelegate {
    private static let CHANNEL_NAME = "nectar_tracker"
    private static let EVENT_CHANNEL_NAME = "nectar_tracker/updates"
    private static let TAG = "NectarTracker"
    
    private var mqttClient: CocoaMQTT?
    private var eventSink: FlutterEventSink?
    private var locationManager: CLLocationManager? 
    private var currentLocation: CLLocation?
    private var isTracking = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var isConnecting = false
    
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
    private var mqttConnected = false
    
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
        loadMqttConfig()
        setupMqttClient()
        
        if enableLogging {
            print("\(TAG): NectarTrackerPlugin initialized")
            print("\(TAG): MQTT Config - Broker: \(mqttBroker):\(mqttPort), Topic: \(mqttTopic)")
        }
    }
    
    private func loadMqttConfig() {
        let defaults = UserDefaults.standard
        mqttBroker = defaults.string(forKey: "broker") ?? mqttBroker
        mqttPort = defaults.integer(forKey: "port")
        if mqttPort == 0 { mqttPort = 1883 }
        mqttUsername = defaults.string(forKey: "username") ?? ""
        mqttPassword = defaults.string(forKey: "password") ?? ""
        mqttTopic = defaults.string(forKey: "topic") ?? mqttTopic
        userId = defaults.string(forKey: "userId") ?? ""
        batteryLevel = defaults.integer(forKey: "batteryLevel")
        userType = defaults.string(forKey: "userType") ?? ""
        deviceId = defaults.string(forKey: "deviceId") ?? ""
        domain = defaults.string(forKey: "domain") ?? ""
        usernameField = defaults.string(forKey: "usernameField") ?? ""
        identifier = defaults.string(forKey: "identifier") ?? ""
        if let skillsData = defaults.data(forKey: "skillsJson"),
           let skillsArray = try? JSONSerialization.jsonObject(with: skillsData) as? [Any] {
            skills = skillsArray
        }
        status = defaults.string(forKey: "status") ?? ""
        name = defaults.string(forKey: "name") ?? ""
        geofence = defaults.string(forKey: "geofence") ?? ""
        emailid = defaults.string(forKey: "emailid") ?? ""
        mobile = defaults.string(forKey: "mobile") ?? ""
        jobId = defaults.string(forKey: "jobId") ?? ""
    }
    
    private func saveMqttConfig() {
        let defaults = UserDefaults.standard
        defaults.set(mqttBroker, forKey: "broker")
        defaults.set(mqttPort, forKey: "port")
        defaults.set(mqttUsername, forKey: "username")
        defaults.set(mqttPassword, forKey: "password")
        defaults.set(mqttTopic, forKey: "topic")
        defaults.set(userId, forKey: "userId")
        defaults.set(batteryLevel, forKey: "batteryLevel")
        defaults.set(userType, forKey: "userType")
        defaults.set(deviceId, forKey: "deviceId")
        defaults.set(domain, forKey: "domain")
        defaults.set(usernameField, forKey: "usernameField")
        defaults.set(identifier, forKey: "identifier")
        if let skillsData = try? JSONSerialization.data(withJSONObject: skills) {
            defaults.set(skillsData, forKey: "skillsJson")
        }
        defaults.set(status, forKey: "status")
        defaults.set(name, forKey: "name")
        defaults.set(geofence, forKey: "geofence")
        defaults.set(emailid, forKey: "emailid")
        defaults.set(mobile, forKey: "mobile")
        defaults.set(jobId, forKey: "jobId")
    }
    
    private func setupMqttClient() {
        // Clean up existing connection
        mqttClient?.disconnect()
        
        let clientID = "nectar_ios_\(Int(Date().timeIntervalSince1970))"
        let mqtt = CocoaMQTT(clientID: clientID, host: mqttBroker, port: UInt16(mqttPort))
        mqtt.username = mqttUsername.isEmpty ? nil : mqttUsername
        mqtt.password = mqttPassword.isEmpty ? nil : mqttPassword
        mqtt.keepAlive = 60
        mqtt.delegate = self
        mqtt.autoReconnect = true
        mqtt.logLevel = enableLogging ? .debug : .off
        
        // Configure SSL correctly - only for SSL ports (8883, 8884)
        if mqttPort == 8883 || mqttPort == 8884 {
            mqtt.enableSSL = true
            // Additional SSL settings for better compatibility
            mqtt.allowUntrustCACertificate = true
            if enableLogging {
                print("\(TAG): SSL enabled for port \(mqttPort)")
            }
        }
        
        mqttClient = mqtt
        
        if enableLogging {
            print("\(TAG): MQTT client initialized - Broker: \(mqttBroker):\(mqttPort), ClientID: \(clientID)")
        }
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
                print("\(TAG): Initializing with logging enabled")
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
                        print("\(TAG): Notification permission granted: \(granted)")
                    }
                }
            }
            
            if enableLogging {
                print("\(TAG): Initialized successfully")
            }
            
            result(nil)
            
        case "startTracking":
            guard CLLocationManager.locationServicesEnabled() else {
                result(FlutterError(code: "LOCATION_DISABLED", message: "Location services are disabled", details: nil))
                return
            }
            
            if enableLogging {
                print("\(TAG): Starting location tracking")
            }
            
            isTracking = true
            locationManager?.startUpdatingLocation()
            if #available(iOS 9.0, *) {
                locationManager?.startMonitoringSignificantLocationChanges()
            }
            
            startBackgroundTask()
            connectMqtt()
            
            // Save tracking state
            UserDefaults.standard.set(true, forKey: "tracking_enabled")
            
            if enableLogging {
                print("\(TAG): Location tracking started successfully")
            }
            
            result(nil)
            
        case "stopTracking":
            if enableLogging {
                print("\(TAG): Stopping location tracking")
            }
            
            isTracking = false
            locationManager?.stopUpdatingLocation()
            if #available(iOS 9.0, *) {
                locationManager?.stopMonitoringSignificantLocationChanges()
            }
            
            endBackgroundTask()
            disconnectMqtt()
            
            // Clear tracking state
            UserDefaults.standard.set(false, forKey: "tracking_enabled")
            
            if enableLogging {
                print("\(TAG): Location tracking stopped successfully")
            }
            
            result(nil)
            
        case "isTracking":
            result(isTracking)
            
        case "getCurrentLocation":
            if enableLogging {
                print("\(TAG): Getting current location")
            }
            
            if let location = currentLocation {
                if enableLogging {
                    print("\(TAG): Current location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
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
                print("\(TAG): Setting location accuracy to: \(accuracy)")
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
                print("\(TAG): Tracking stats: \(totalLocations) locations, \(String(format: "%.2f", totalDistance))m distance")
            }
            
            result(stats)
            
        case "clearTrackingData":
            if enableLogging {
                print("\(TAG): Clearing tracking data")
            }
            
            totalLocations = 0
            foregroundLocations = 0
            backgroundLocations = 0
            firstLocationTime = nil
            lastLocationTime = nil
            totalDistance = 0.0
            lastLocation = nil
            
            if enableLogging {
                print("\(TAG): Tracking data cleared successfully")
            }
            
            result(true)
            
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
            
        case "getMqttStatus":
            let status: [String: Any] = [
                "connected": isMqttConnected(),
                "connectionState": getMqttConnectionState(),
                "broker": mqttBroker,
                "port": mqttPort,
                "topic": mqttTopic,
                "userId": userId,
                "isConnecting": isConnecting
            ]
            result(status)
            
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
            
            saveMqttConfig()
            disconnectMqtt()
            setupMqttClient()
            if isTracking {
                connectMqtt()
            }
            
            if enableLogging {
                print("\(TAG): MQTT config updated - Broker: \(mqttBroker), Topic: \(mqttTopic)")
            }
            
            result(nil)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - MQTT Management
    
    private func connectMqtt() -> Bool {
        // Check if already connected
        if mqttClient?.connState == .connected {
            if enableLogging {
                print("\(TAG): Already connected to MQTT")
            }
            return true
        }
        
        // Check if already connecting
        if isConnecting {
            if enableLogging {
                print("\(TAG): Already attempting to connect to MQTT")
            }
            return false
        }
        
        // Validate parameters
        guard !mqttBroker.isEmpty, mqttPort > 0 else {
            if enableLogging {
                print("\(TAG): MQTT connection failed: Missing required parameters")
            }
            return false
        }
        
        isConnecting = true
        
        // Create new client
        let clientID = "nectar_ios_\(Int(Date().timeIntervalSince1970))"
        mqttClient?.disconnect()
        let mqtt = CocoaMQTT(clientID: clientID, host: mqttBroker, port: UInt16(mqttPort))
        mqtt.username = mqttUsername.isEmpty ? nil : mqttUsername
        mqtt.password = mqttPassword.isEmpty ? nil : mqttPassword
        mqtt.keepAlive = 60
        mqtt.delegate = self
        mqtt.autoReconnect = true
        mqtt.logLevel = enableLogging ? .debug : .off
        
        // Configure SSL correctly - only for SSL ports (8883, 8884)
        if mqttPort == 8883 || mqttPort == 8884 {
            mqtt.enableSSL = true
            // Additional SSL settings for better compatibility
            mqtt.allowUntrustCACertificate = true
            if enableLogging {
                print("\(TAG): SSL enabled for port \(mqttPort)")
            }
        }
        
        // Store reference before connecting
        mqttClient = mqtt
        
        // Single connection attempt
        let connected = mqtt.connect()
        if enableLogging {
            print("\(TAG): MQTT connection attempt result: \(connected)")
        }
        
        // Reset connecting flag if connection attempt failed immediately
        if !connected {
            isConnecting = false
        }
        
        return connected
    }
    
    private func disconnectMqtt() {
        if enableLogging {
            print("\(TAG): Disconnecting MQTT")
        }
        
        mqttClient?.disconnect()
        isConnecting = false
        mqttConnected = false
        
        if enableLogging {
            print("\(TAG): MQTT disconnected")
        }
    }
    
    private func publishToMqtt(location: CLLocation, isBackground: Bool) -> Bool {
        // Check if MQTT is connected
        guard let mqtt = mqttClient else {
            if enableLogging {
                print("\(TAG): MQTT client not initialized")
            }
            return false
        }
        
        // Check connection state
        guard mqtt.connState == .connected else {
            if enableLogging {
                print("\(TAG): MQTT not connected, current state: \(mqtt.connState)")
            }
            // Try to reconnect if not connected
            if isTracking {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.connectMqtt()
                }
            }
            return false
        }
        
        // Validate required fields
        guard !userId.isEmpty else {
            if enableLogging {
                print("\(TAG): MQTT publish failed: userId is empty")
            }
            return false
        }
        
        // Create JSON payload exactly like your working implementation
        let payload: [String: Any] = [
            "location": "POINT(\(location.coordinate.longitude) \(location.coordinate.latitude))",
            "id": userId,
            "batteryLevel": Int(UIDevice.current.batteryLevel * 100),
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
        
        let fullTopic = "\(mqttTopic)/\(userId)"
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                if enableLogging {
                    let status = isBackground ? "Background" : "Foreground"
                    print("\(TAG): Sending location to MQTT (\(status)): \(jsonString)")
                }
                mqtt.publish(fullTopic, withString: jsonString, qos: .qos1)
                return true
            } else {
                if enableLogging {
                    print("\(TAG): Failed to convert JSON data to string")
                }
            }
        } catch {
            if enableLogging {
                print("\(TAG): Failed to serialize JSON: \(error)")
            }
        }
        
        return false
    }
    
    // MARK: - Background Task Management
    
    private func startBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "NectarTrackerBackgroundTask") {
            self.endBackgroundTask()
        }
        
        if enableLogging {
            print("\(TAG): Background task started")
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
            
            if enableLogging {
                print("\(TAG): Background task ended")
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
                    print("\(TAG): Failed to show notification: \(error)")
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
            print("\(TAG): Location update: \(location.coordinate.latitude), \(location.coordinate.longitude) (Foreground)")
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
        
        // Publish to MQTT
        if !publishToMqtt(location: location, isBackground: false) {
            if enableLogging {
                print("\(TAG): Failed to publish location to MQTT")
            }
        }
        
        if enableBackgroundMode && isTracking {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self.isTracking {
                    self.updateTrackingStats(location: location, isBackground: true)
                    if self.enableLogging {
                        print("\(TAG): Location update: \(location.coordinate.latitude), \(location.coordinate.longitude) (Background)")
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
                    if !self.publishToMqtt(location: location, isBackground: true) {
                        if self.enableLogging {
                            print("\(TAG): Failed to publish background location to MQTT")
                        }
                    }
                }
            }
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if enableLogging {
            print("\(TAG): Location error: \(error.localizedDescription)")
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
                print("\(TAG): Location authorization: Always")
            case .authorizedWhenInUse:
                print("\(TAG): Location authorization: When in use")
            case .denied, .restricted:
                print("\(TAG): Location authorization: Denied")
            case .notDetermined:
                print("\(TAG): Location authorization: Not determined")
            @unknown default:
                print("\(TAG): Location authorization: Unknown")
            }
        }
    }
    
    public func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        if enableLogging {
            print("\(TAG): Location updates paused")
        }
    }
    
    public func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        if enableLogging {
            print("\(TAG): Location updates resumed")
        }
    }
    
    // MARK: - MQTT Status Methods
    
    private func isMqttConnected() -> Bool {
        return mqttClient?.connState == .connected
    }
    
    private func getMqttConnectionState() -> String {
        guard let mqtt = mqttClient else {
            return "Not Initialized"
        }
        
        switch mqtt.connState {
        case .initial:
            return "Initial"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        @unknown default:
            return "Unknown"
        }
    }
    
    // MARK: - CocoaMQTTDelegate
    
    public func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        isConnecting = false
        
        if enableLogging {
            print("\(TAG): MQTT Connected: \(ack)")
        }
        
        if ack == .accept {
            mqttConnected = true
            if enableLogging {
                print("\(TAG): MQTT connection successful")
            }
        } else {
            mqttConnected = false
            if enableLogging {
                print("\(TAG): MQTT connection failed with ACK: \(ack.rawValue)")
                switch ack {
                case .accept:
                    print("\(TAG): Connection accepted")
                case .unacceptableProtocolVersion:
                    print("\(TAG): Unacceptable protocol version")
                case .identifierRejected:
                    print("\(TAG): Identifier rejected")
                case .serverUnavailable:
                    print("\(TAG): Server unavailable")
                case .badUsernameOrPassword:
                    print("\(TAG): Bad username or password")
                case .notAuthorized:
                    print("\(TAG): Not authorized")
                case .reserved:
                    print("\(TAG): Reserved")
                @unknown default:
                    print("\(TAG): Unknown connection error")
                }
            }
        }
    }
    
    public func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        if enableLogging {
            print("\(TAG): Message published - ID: \(id), Topic: \(message.topic)")
        }
    }
    
    public func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        if enableLogging {
            print("\(TAG): Message publish acknowledged - ID: \(id)")
        }
    }
    
    public func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        if enableLogging {
            print("\(TAG): Received message - ID: \(id), Topic: \(message.topic), Payload: \(message.string ?? "")")
        }
    }
    
    public func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        if enableLogging {
            print("\(TAG): Subscribed to topics - Success: \(success), Failed: \(failed)")
        }
    }
    
    public func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        if enableLogging {
            print("\(TAG): Unsubscribed from topics: \(topics)")
        }
    }
    
    public func mqttDidPing(_ mqtt: CocoaMQTT) {
        if enableLogging {
            print("\(TAG): MQTT did ping")
        }
    }
    
    public func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        if enableLogging {
            print("\(TAG): MQTT did receive pong")
        }
    }
    
    public func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        mqttConnected = false
        isConnecting = false
        
        if enableLogging {
            print("\(TAG): MQTT did disconnect with error: \(String(describing: err))")
            print("\(TAG): MQTT Disconnected: \(err?.localizedDescription ?? "No error")")
        }
        
        // Try to reconnect if still tracking and not manually disconnected
        if isTracking && err != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.isTracking {
                    if self.enableLogging {
                        print("\(TAG): Attempting to reconnect MQTT after disconnect")
                    }
                    self.connectMqtt()
                }
            }
        }
    }
    
    public func _console(_ mqtt: CocoaMQTT, didConnect host: String, port: Int) {
        if enableLogging {
            print("\(TAG): MQTT Console - Connected to \(host):\(port)")
        }
    }
    
    public func _console(_ mqtt: CocoaMQTT, didSubscribeTopic topic: String) {
        if enableLogging {
            print("\(TAG): MQTT Console - Subscribed to topic: \(topic)")
        }
    }
    
    public func _console(_ mqtt: CocoaMQTT, didUnsubscribeTopic topic: String) {
        if enableLogging {
            print("\(TAG): MQTT Console - Unsubscribed from topic: \(topic)")
        }
    }
}