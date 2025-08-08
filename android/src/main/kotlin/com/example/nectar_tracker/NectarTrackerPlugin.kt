package com.example.nectar_tracker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.Location
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.google.android.gms.location.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.atomic.AtomicInteger
import com.google.gson.Gson
import org.eclipse.paho.client.mqttv3.*
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence

class NectarTrackerPlugin : FlutterPlugin, MethodCallHandler {
    private companion object {
        const val CHANNEL_NAME = "nectar_tracker"
        const val EVENT_CHANNEL_NAME = "nectar_tracker/updates"
        const val TAG = "NectarTracker"
        const val NOTIFICATION_ID = 12345678
        const val LOCATION_NOTIFICATION_ID = 12345679
        const val CHANNEL_ID = "nectar_tracker_channel"
        const val LOCATION_CHANNEL_ID = "nectar_tracker_location_channel"
        const val WAKE_LOCK_TAG = "NectarTracker::LocationWakeLock"
        const val PREFS_NAME = "nectar_tracker"
        const val ACTION_MQTT_CONFIG_UPDATED = "com.example.nectar_tracker.MQTT_CONFIG_UPDATED"
    }

    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    // Tracking statistics
    private val totalLocations = AtomicInteger(0)
    private val foregroundLocations = AtomicInteger(0)
    private val backgroundLocations = AtomicInteger(0)
    private var firstLocationTime: Long = 0
    private var lastLocationTime: Long = 0
    private var totalDistance: Double = 0.0
    private var lastLocation: Location? = null

    // Settings
    private var enableLogging = true
    private var showLocationNotifications = false

    // MQTT config fields
    private var mqttBroker: String = "broker.hivemq.com"
    private var mqttPort: Int = 1883
    private var mqttUsername: String? = null
    private var mqttPassword: String? = null
    private var mqttTopic: String = "nectar/location"
    // User/device/job info fields
    private var userId: String = ""
    private var batteryLevel: Int = 0
    private var userType: String = ""
    private var deviceId: String = ""
    private var domain: String = ""
    private var usernameField: String = ""
    private var identifier: String = ""
    private var skillsJson: String = "[]"
    private var status: String = ""
    private var name: String = ""
    private var geofence: String = ""
    private var emailid: String = ""
    private var mobile: String = ""
    private var jobId: String = ""

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)

        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, EVENT_CHANNEL_NAME)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                eventSink = events
                LocalBroadcastManager.getInstance(context).registerReceiver(
                    locationUpdateReceiver,
                    IntentFilter("location_update")
                )
            }

            override fun onCancel(arguments: Any?) {
                LocalBroadcastManager.getInstance(context).unregisterReceiver(locationUpdateReceiver)
                eventSink = null
            }
        })
    }

    private val locationUpdateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            eventSink?.let { sink ->
                val location = intent.getParcelableExtra<Location>("location")
                val isBackground = intent.getBooleanExtra("isBackground", false)
                location?.let {
                    updateTrackingStats(it, isBackground)
                    
                    // Log location update
                    if (enableLogging) {
                        Log.d(TAG, "Location update: ${it.latitude}, ${it.longitude} (${if (isBackground) "Background" else "Foreground"})")
                    }
                    
                    // Show location notification if enabled
                    if (showLocationNotifications) {
                        showLocationNotification(it, isBackground)
                    }
                    
                    val locationMap = mapOf(
                        "latitude" to it.latitude,
                        "longitude" to it.longitude,
                        "accuracy" to it.accuracy,
                        "altitude" to it.altitude,
                        "speed" to it.speed,
                        "bearing" to it.bearing,
                        "timestamp" to it.time,
                        "isBackground" to isBackground,
                        "provider" to it.provider
                    )
                    sink.success(locationMap)
                }
            }
        }
    }

    private fun updateTrackingStats(location: Location, isBackground: Boolean) {
        totalLocations.incrementAndGet()
        if (isBackground) {
            backgroundLocations.incrementAndGet()
        } else {
            foregroundLocations.incrementAndGet()
        }

        if (firstLocationTime == 0L) {
            firstLocationTime = location.time
        }
        lastLocationTime = location.time

        // Calculate distance
        lastLocation?.let { last ->
            val distance = last.distanceTo(location)
            totalDistance += distance
        }
        lastLocation = location
    }

    private fun showLocationNotification(location: Location, isBackground: Boolean) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        // Create location notification channel
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                LOCATION_CHANNEL_ID,
                "Location Updates",
                NotificationManager.IMPORTANCE_LOW
            )
            notificationManager.createNotificationChannel(channel)
        }

        val status = if (isBackground) "Background" else "Foreground"
        val notification = NotificationCompat.Builder(context, LOCATION_CHANNEL_ID)
            .setContentTitle("Location Update")
            .setContentText("${location.latitude}, ${location.longitude} ($status)")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setAutoCancel(true)
            .build()

        notificationManager.notify(LOCATION_NOTIFICATION_ID, notification)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "initialize" -> {
                val notificationTitle = call.argument<String>("notificationTitle") ?: ""
                val notificationText = call.argument<String>("notificationText") ?: ""
                val interval = call.argument<Int>("interval") ?: 5000
                val fastestInterval = call.argument<Int>("fastestInterval") ?: 3000
                val distanceFilter = call.argument<Double>("distanceFilter")?.toFloat() ?: 10f
                val enableBackgroundMode = call.argument<Boolean>("enableBackgroundMode") ?: true
                val enableHighAccuracy = call.argument<Boolean>("enableHighAccuracy") ?: true
                val enableBatteryOptimization = call.argument<Boolean>("enableBatteryOptimization") ?: false
                val notificationIcon = call.argument<String>("notificationIcon")
                val notificationColor = call.argument<String>("notificationColor")
                enableLogging = call.argument<Boolean>("enableLogging") ?: true
                showLocationNotifications = call.argument<Boolean>("showLocationNotifications") ?: false

                if (enableLogging) {
                    Log.d(TAG, "Initializing NectarTracker with logging enabled")
                }

                LocationForegroundService.setNotificationText(notificationTitle, notificationText)
                LocationForegroundService.setLocationSettings(
                    interval, fastestInterval, distanceFilter,
                    enableBackgroundMode, enableHighAccuracy, enableBatteryOptimization
                )
                result.success(null)
            }
            "startTracking" -> {
                if (enableLogging) {
                    Log.d(TAG, "Starting location tracking")
                }
                
                // Check permissions before starting service
                if (ActivityCompat.checkSelfPermission(
                        context,
                        android.Manifest.permission.ACCESS_FINE_LOCATION
                    ) != PackageManager.PERMISSION_GRANTED && ActivityCompat.checkSelfPermission(
                        context,
                        android.Manifest.permission.ACCESS_COARSE_LOCATION
                    ) != PackageManager.PERMISSION_GRANTED
                ) {
                    Log.e(TAG, "Location permission not granted")
                    result.error("PERMISSION_DENIED", "Location permission not granted", null)
                    return
                }
                
                try {
                    val serviceIntent = Intent(context, LocationForegroundService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(serviceIntent)
                    } else {
                        context.startService(serviceIntent)
                    }
                    
                    if (enableLogging) {
                        Log.d(TAG, "Location tracking started successfully")
                    }
                    
                    result.success(null)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start location tracking: ${e.message}")
                    result.error("SERVICE_START_FAILED", "Failed to start location service: ${e.message}", null)
                }
            }
            "stopTracking" -> {
                if (enableLogging) {
                    Log.d(TAG, "Stopping location tracking")
                }
                
                val stopIntent = Intent(context, LocationForegroundService::class.java)
                context.stopService(stopIntent)
                
                if (enableLogging) {
                    Log.d(TAG, "Location tracking stopped successfully")
                }
                
                result.success(null)
            }
            "isTracking" -> {
                result.success(LocationForegroundService.isRunning)
            }
            "getCurrentLocation" -> {
                if (enableLogging) {
                    Log.d(TAG, "Getting current location")
                }
                
                LocationForegroundService.getCurrentLocation { location ->
                    location?.let {
                        if (enableLogging) {
                            Log.d(TAG, "Current location: ${it.latitude}, ${it.longitude}")
                        }
                        
                        val locationMap = mapOf(
                            "latitude" to it.latitude,
                            "longitude" to it.longitude,
                            "accuracy" to it.accuracy,
                            "altitude" to it.altitude,
                            "speed" to it.speed,
                            "bearing" to it.bearing,
                            "timestamp" to it.time,
                            "isBackground" to false,
                            "provider" to it.provider
                        )
                        result.success(locationMap)
                    } ?: result.success(null)
                }
            }
            "isLocationServiceEnabled" -> {
                val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
                result.success(locationManager.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER) ||
                        locationManager.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER))
            }
            "getLocationAccuracy" -> {
                result.success(LocationForegroundService.getCurrentAccuracy())
            }
            "setLocationAccuracy" -> {
                val accuracy = call.argument<String>("accuracy") ?: "medium"
                if (enableLogging) {
                    Log.d(TAG, "Setting location accuracy to: $accuracy")
                }
                
                val success = LocationForegroundService.setAccuracy(accuracy)
                result.success(success)
            }
            "getTrackingStats" -> {
                val stats = mapOf(
                    "totalLocations" to totalLocations.get(),
                    "foregroundLocations" to foregroundLocations.get(),
                    "backgroundLocations" to backgroundLocations.get(),
                    "firstLocationTime" to firstLocationTime,
                    "lastLocationTime" to lastLocationTime,
                    "totalDistance" to totalDistance,
                    "averageSpeed" to if (totalLocations.get() > 0) totalDistance / totalLocations.get() else 0.0
                )
                
                if (enableLogging) {
                    Log.d(TAG, "Tracking stats: ${totalLocations.get()} locations, ${String.format("%.2f", totalDistance)}m distance")
                }
                
                result.success(stats)
            }
            "clearTrackingData" -> {
                if (enableLogging) {
                    Log.d(TAG, "Clearing tracking data")
                }
                
                totalLocations.set(0)
                foregroundLocations.set(0)
                backgroundLocations.set(0)
                firstLocationTime = 0
                lastLocationTime = 0
                totalDistance = 0.0
                lastLocation = null
                
                if (enableLogging) {
                    Log.d(TAG, "Tracking data cleared successfully")
                }
                
                result.success(true)
            }
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }
            "getMqttStatus" -> {
                val status = mapOf(
                    "connected" to (LocationForegroundService.mqttClient?.isConnected ?: false),
                    "connectionState" to if (LocationForegroundService.mqttClient?.isConnected == true) "Connected" else "Disconnected",
                    "broker" to mqttBroker,
                    "port" to mqttPort,
                    "topic" to mqttTopic,
                    "userId" to userId,
                    "isConnecting" to false
                )
                result.success(status)
            }
            "setMqttConfigAndDetails" -> {
                val args = call.arguments as? Map<String, Any>
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val editor = prefs.edit()

                mqttBroker = args?.get("broker") as? String ?: mqttBroker
                mqttPort = (args?.get("port") as? Int) ?: mqttPort
                mqttUsername = args?.get("username") as? String
                mqttPassword = args?.get("password") as? String
                mqttTopic = args?.get("topic") as? String ?: mqttTopic
                userId = args?.get("userId") as? String ?: ""
                batteryLevel = (args?.get("batteryLevel") as? Int) ?: 0
                userType = args?.get("userType") as? String ?: ""
                deviceId = args?.get("deviceId") as? String ?: ""
                domain = args?.get("domain") as? String ?: ""
                usernameField = args?.get("usernameField") as? String ?: ""
                identifier = args?.get("identifier") as? String ?: ""
                skillsJson = (args?.get("skills") as? List<*>)?.let { Gson().toJson(it) } ?: "[]"
                status = args?.get("status") as? String ?: ""
                name = args?.get("name") as? String ?: ""
                geofence = args?.get("geofence") as? String ?: ""
                emailid = args?.get("emailid") as? String ?: ""
                mobile = args?.get("mobile") as? String ?: ""
                jobId = args?.get("jobId") as? String ?: ""

                editor.putString("broker", mqttBroker)
                editor.putInt("port", mqttPort)
                editor.putString("username", mqttUsername)
                editor.putString("password", mqttPassword)
                editor.putString("topic", mqttTopic)
                editor.putString("userId", userId)
                editor.putInt("batteryLevel", batteryLevel)
                editor.putString("userType", userType)
                editor.putString("deviceId", deviceId)
                editor.putString("domain", domain)
                editor.putString("usernameField", usernameField)
                editor.putString("identifier", identifier)
                editor.putString("skillsJson", skillsJson)
                editor.putString("status", status)
                editor.putString("name", name)
                editor.putString("geofence", geofence)
                editor.putString("emailid", emailid)
                editor.putString("mobile", mobile)
                editor.putString("jobId", jobId)
                editor.apply()

                // Notify running service to reload config
                val intent = Intent(ACTION_MQTT_CONFIG_UPDATED)
                LocalBroadcastManager.getInstance(context).sendBroadcast(intent)

                result.success(null)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    class BootReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_PACKAGE_REPLACED -> {
                    // Check if we should restart location tracking
                    val sharedPrefs = context.getSharedPreferences("nectar_tracker", Context.MODE_PRIVATE)
                    val shouldRestart = sharedPrefs.getBoolean("tracking_enabled", false)
                    
                    if (shouldRestart) {
                        Log.d(TAG, "Restarting location tracking after boot")
                        val serviceIntent = Intent(context, LocationForegroundService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            context.startForegroundService(serviceIntent)
                        } else {
                            context.startService(serviceIntent)
                        }
                    }
                }
            }
        }
    }

    class LocationForegroundService : Service() {
        private lateinit var fusedLocationClient: FusedLocationProviderClient
        private lateinit var locationCallback: LocationCallback
        private var wakeLock: PowerManager.WakeLock? = null
        private var mqttClient: MqttAsyncClient? = null
        private var mqttBroker: String = "broker.hivemq.com"
        private var mqttPort: Int = 1883
        private var mqttUsername: String? = null
        private var mqttPassword: String? = null
        private var mqttTopic: String = "nectar/location"
        private var userId: String = ""
        private var batteryLevel: Int = 0
        private var userType: String = ""
        private var deviceId: String = ""
        private var domain: String = ""
        private var usernameField: String = ""
        private var identifier: String = ""
        private var skillsJson: String = "[]"
        private var status: String = ""
        private var name: String = ""
        private var geofence: String = ""
        private var emailid: String = ""
        private var mobile: String = ""
        private var jobId: String = ""
        private var mqttConfigReceiver: BroadcastReceiver? = null

        companion object {
            private const val TAG = "LocationForegroundService"
            var isRunning = false
                private set
            private var notificationTitle = "Location Tracking"
            private var notificationText = "Tracking your location in background"
            private var interval = 5000L
            private var fastestInterval = 3000L
            private var distanceFilter = 10f
            private var enableBackgroundMode = true
            private var enableHighAccuracy = true
            private var enableBatteryOptimization = false
            private var currentAccuracy = "medium"
            private var currentLocation: Location? = null

            fun setNotificationText(title: String, text: String) {
                notificationTitle = title
                notificationText = text
            }

            fun setLocationSettings(
                intervalMs: Int, fastestIntervalMs: Int, distanceFilterMeters: Float,
                backgroundMode: Boolean, highAccuracy: Boolean, batteryOptimization: Boolean
            ) {
                interval = intervalMs.toLong()
                fastestInterval = fastestIntervalMs.toLong()
                distanceFilter = distanceFilterMeters
                enableBackgroundMode = backgroundMode
                enableHighAccuracy = highAccuracy
                enableBatteryOptimization = batteryOptimization
            }

            fun getCurrentLocation(callback: (Location?) -> Unit) {
                if (isRunning) {
                    callback(currentLocation)
                } else {
                    callback(null)
                }
            }

            fun getCurrentAccuracy(): String = currentAccuracy

            fun setAccuracy(accuracy: String): Boolean {
                currentAccuracy = accuracy
                return true
            }
        }

        override fun onCreate() {
            super.onCreate()
            isRunning = true
            fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
            createLocationCallback()
            acquireWakeLock()
            
            // Save tracking state
            val sharedPrefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            sharedPrefs.edit().putBoolean("tracking_enabled", true).apply()
            // Load MQTT config and initialize client
            loadMqttConfig()
            initMqttClient()

            // Listen for runtime config updates
            mqttConfigReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action == ACTION_MQTT_CONFIG_UPDATED) {
                        loadMqttConfig()
                        reconnectMqttClient()
                    }
                }
            }
            LocalBroadcastManager.getInstance(this).registerReceiver(
                mqttConfigReceiver!!, IntentFilter(ACTION_MQTT_CONFIG_UPDATED)
            )
        }

        override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
            createNotificationChannel()
            val notification = createNotification()
            startForeground(NOTIFICATION_ID, notification)
            startLocationUpdates()
            return START_STICKY
        }

        private fun acquireWakeLock() {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                WAKE_LOCK_TAG
            )
            wakeLock?.acquire()
        }

        private fun releaseWakeLock() {
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                }
            }
            wakeLock = null
        }

        private fun createLocationCallback() {
            locationCallback = object : LocationCallback() {
                override fun onLocationResult(locationResult: LocationResult) {
                    locationResult ?: return
                    for (location in locationResult.locations) {
                        currentLocation = location
                        
                        // Always broadcast as foreground first
                        broadcastLocation(location, false)
                        
                        // If background mode is enabled, also broadcast as background
                        if (enableBackgroundMode) {
                            // Small delay to simulate background processing
                            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                                broadcastLocation(location, true)
                            }, 1000)
                        }
                        // --- MQTT publish (proper JSON encoding) ---
                        val json = org.json.JSONObject().apply {
                            put("location", "POINT(${location.longitude} ${location.latitude})")
                            put("id", userId)
                            put("batteryLevel", batteryLevel)
                            put("type", userType)
                            put("time", System.currentTimeMillis())
                            put("deviceId", deviceId)
                            put("domain", domain)
                            put("username", usernameField)
                            put("identifier", identifier)
                            val skillsArray = try { org.json.JSONArray(skillsJson) } catch (_: Exception) { org.json.JSONArray() }
                            put("skills", skillsArray)
                            put("status", status)
                            put("name", name)
                            put("geofence", geofence)
                            put("emailid", emailid)
                            put("mobile", mobile)
                            put("jobId", jobId)
                        }
                        val payload = json.toString()
                        try {
                            if (mqttClient?.isConnected == true) {
                                val message = MqttMessage(payload.toByteArray()).apply {
                                    qos = 0
                                    isRetained = false
                                }
                                mqttClient?.publish(mqttTopic, message)
                            } else {
                                Log.w(TAG, "MQTT not connected, skipping publish")
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "MQTT publish failed: ${e.message}")
                        }
                    }
                }
            }
        }

        private fun loadMqttConfig() {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            mqttBroker = prefs.getString("broker", mqttBroker) ?: mqttBroker
            mqttPort = prefs.getInt("port", mqttPort)
            mqttUsername = prefs.getString("username", mqttUsername)
            mqttPassword = prefs.getString("password", mqttPassword)
            mqttTopic = prefs.getString("topic", mqttTopic) ?: mqttTopic
            userId = prefs.getString("userId", userId) ?: userId
            batteryLevel = prefs.getInt("batteryLevel", batteryLevel)
            userType = prefs.getString("userType", userType) ?: userType
            deviceId = prefs.getString("deviceId", deviceId) ?: deviceId
            domain = prefs.getString("domain", domain) ?: domain
            usernameField = prefs.getString("usernameField", usernameField) ?: usernameField
            identifier = prefs.getString("identifier", identifier) ?: identifier
            skillsJson = prefs.getString("skillsJson", skillsJson) ?: skillsJson
            status = prefs.getString("status", status) ?: status
            name = prefs.getString("name", name) ?: name
            geofence = prefs.getString("geofence", geofence) ?: geofence
            emailid = prefs.getString("emailid", emailid) ?: emailid
            mobile = prefs.getString("mobile", mobile) ?: mobile
            jobId = prefs.getString("jobId", jobId) ?: jobId
        }

        private fun initMqttClient() {
            try {
                val scheme = if (mqttPort == 8883 || mqttPort == 8884) "ssl" else "tcp"
                val brokerUrl = "$scheme://$mqttBroker:$mqttPort"
                val clientId = "nectar_android_" + System.currentTimeMillis()
                mqttClient = MqttAsyncClient(brokerUrl, clientId, MemoryPersistence())
                mqttClient?.setCallback(object : MqttCallback {
                    override fun connectionLost(cause: Throwable?) {
                        Log.e(TAG, "MQTT connection lost: ${cause?.message}")
                    }
                    override fun messageArrived(topic: String?, message: MqttMessage?) {}
                    override fun deliveryComplete(token: IMqttDeliveryToken?) {}
                })
                val options = MqttConnectOptions().apply {
                    isAutomaticReconnect = true
                    isCleanSession = true
                    mqttUsername?.let { userName = it }
                    mqttPassword?.let { password = it.toCharArray() }
                }
                Thread {
                    try {
                        mqttClient?.connect(options)?.waitForCompletion()
                        Log.d(TAG, "MQTT connected to $brokerUrl")
                    } catch (e: Exception) {
                        Log.e(TAG, "MQTT connect failed: ${e.message}")
                    }
                }.start()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to init MQTT: ${e.message}")
            }
        }

        private fun reconnectMqttClient() {
            try {
                mqttClient?.disconnectForcibly(100)
            } catch (_: Exception) {}
            initMqttClient()
        }

        private fun broadcastLocation(location: Location, isBackground: Boolean) {
            val intent = Intent("location_update")
            intent.putExtra("location", location)
            intent.putExtra("isBackground", isBackground)
            LocalBroadcastManager.getInstance(this).sendBroadcast(intent)
        }

        private fun startLocationUpdates() {
            val priority = when {
                enableHighAccuracy -> Priority.PRIORITY_HIGH_ACCURACY
                else -> Priority.PRIORITY_BALANCED_POWER_ACCURACY
            }

            val locationRequest = LocationRequest.Builder(priority, interval)
                .setMinUpdateIntervalMillis(fastestInterval)
                .setMinUpdateDistanceMeters(distanceFilter)
                .build()

            if (ActivityCompat.checkSelfPermission(
                    this,
                    android.Manifest.permission.ACCESS_FINE_LOCATION
                ) != PackageManager.PERMISSION_GRANTED && ActivityCompat.checkSelfPermission(
                    this,
                    android.Manifest.permission.ACCESS_COARSE_LOCATION
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                Log.e(TAG, "Location permission not granted")
                return
            }

            fusedLocationClient.requestLocationUpdates(
                locationRequest,
                locationCallback,
                Looper.getMainLooper()
            )
        }

        private fun createNotificationChannel() {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Location Tracker",
                    NotificationManager.IMPORTANCE_LOW
                )
                val manager = getSystemService(NotificationManager::class.java)
                manager.createNotificationChannel(channel)
            }
        }

        private fun createNotification(): Notification {
            return NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle(notificationTitle)
                .setContentText(notificationText)
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(true)
                .build()
        }

        override fun onDestroy() {
            super.onDestroy()
            isRunning = false
            fusedLocationClient.removeLocationUpdates(locationCallback)
            releaseWakeLock()
            
            // Clear tracking state
            val sharedPrefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            sharedPrefs.edit().putBoolean("tracking_enabled", false).apply()
            // Disconnect MQTT
            mqttClient?.disconnect()
            mqttConfigReceiver?.let {
                LocalBroadcastManager.getInstance(this).unregisterReceiver(it)
                mqttConfigReceiver = null
            }
        }

        override fun onBind(intent: Intent?): IBinder? {
            return null
        }
    }
}