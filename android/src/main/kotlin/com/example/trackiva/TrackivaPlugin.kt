package com.example.trackiva

import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.location.Location
import android.net.Uri
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
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

class TrackivaPlugin : FlutterPlugin, MethodCallHandler {
    private companion object {
        const val CHANNEL_NAME = "trackiva"
        const val EVENT_CHANNEL_NAME = "trackiva/updates"
        const val TAG = "Trackiva"
        const val NOTIFICATION_ID = 12345678
        const val LOCATION_NOTIFICATION_ID = 12345679
        const val CHANNEL_ID = "trackiva_channel"
        const val LOCATION_CHANNEL_ID = "trackiva_location_channel"
        const val WAKE_LOCK_TAG = "Trackiva::LocationWakeLock"
        const val PREFS_NAME = "trackiva"
        const val ACTION_MQTT_CONFIG_UPDATED = "com.example.trackiva.MQTT_CONFIG_UPDATED"
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
    private var mqttTopic: String = "trackiva/location"
    // Flexible payload - stored as JSON string
    private var payloadJson: String = "{}"

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
                val chatHeadIcon = call.argument<String>("chatHeadIcon")
                enableLogging = call.argument<Boolean>("enableLogging") ?: true
                showLocationNotifications = call.argument<Boolean>("showLocationNotifications") ?: false

                if (enableLogging) {
                    Log.d(TAG, "Initializing Trackiva with logging enabled")
                }

                LocationForegroundService.setNotificationText(notificationTitle, notificationText)
                LocationForegroundService.setLocationSettings(
                    interval, fastestInterval, distanceFilter,
                    enableBackgroundMode, enableHighAccuracy, enableBatteryOptimization
                )
                LocationForegroundService.setChatHeadIcon(chatHeadIcon)
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
                
                // Check overlay permission for chat head
                val overlayPermissionGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    Settings.canDrawOverlays(context)
                } else {
                    true
                }
                
                if (!overlayPermissionGranted) {
                    if (enableLogging) {
                        Log.d(TAG, "Overlay permission not granted, requesting...")
                    }
                    try {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:${context.packageName}")
                        )
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(intent)
                        // Still start location tracking even without overlay permission
                        // Chat head will start automatically when permission is granted
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to open overlay permission settings: ${e.message}")
                    }
                }
                
                try {
                    val serviceIntent = Intent(context, LocationForegroundService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(serviceIntent)
                    } else {
                        context.startService(serviceIntent)
                    }
                    
                    // Chat head will be started by LocationForegroundService if permission is granted
                    // If permission is not granted yet, it will be started when permission is granted
                    
                    if (enableLogging) {
                        Log.d(TAG, "Location tracking started successfully")
                        if (!overlayPermissionGranted) {
                            Log.d(TAG, "Note: Chat head will appear after overlay permission is granted")
                        }
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
                
                // Stop chat head service
                val chatHeadStopIntent = Intent(context, ChatHeadService::class.java)
                context.stopService(chatHeadStopIntent)
                
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
                // Parse payload JSON to return it in status
                val payloadMap = try {
                    if (payloadJson.isNotEmpty() && payloadJson != "{}") {
                        Gson().fromJson(payloadJson, Map::class.java) as? Map<*, *>
                    } else {
                        null
                    }
                } catch (e: Exception) {
                    null
                }
                
                val status = mutableMapOf<String, Any>(
                    "connected" to (LocationForegroundService.mqttClient?.isConnected ?: false),
                    "connectionState" to if (LocationForegroundService.mqttClient?.isConnected == true) "Connected" else "Disconnected",
                    "broker" to mqttBroker,
                    "port" to mqttPort,
                    "topic" to mqttTopic,
                    "isConnecting" to false
                )
                
                // Add payload to status
                if (payloadMap != null) {
                    status["payload"] = payloadMap
                }
                
                result.success(status)
            }
            "canDrawOverlays" -> {
                result.success(canDrawOverlays())
            }
            "requestOverlayPermission" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    if (!Settings.canDrawOverlays(context)) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:${context.packageName}")
                        )
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(intent)
                        result.success(false)
                    } else {
                        result.success(true)
                    }
                } else {
                    result.success(true)
                }
            }
            "startChatHeadService" -> {
                // Manually start chat head service (useful after permission is granted)
                if (canDrawOverlays()) {
                    try {
                        val chatHeadIntent = Intent(context, ChatHeadService::class.java)
                        context.startService(chatHeadIntent)
                        if (enableLogging) {
                            Log.d(TAG, "Chat head service started manually")
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to start chat head service: ${e.message}")
                        result.error("CHAT_HEAD_START_FAILED", "Failed to start chat head: ${e.message}", null)
                    }
                } else {
                    result.error("OVERLAY_PERMISSION_NEEDED", "Overlay permission not granted", null)
                }
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
                
                // Store flexible payload as JSON
                val payload = args?.get("payload") as? Map<*, *>
                payloadJson = if (payload != null) {
                    try {
                        Gson().toJson(payload)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to serialize payload: ${e.message}")
                        "{}"
                    }
                } else {
                    "{}"
                }

                editor.putString("broker", mqttBroker)
                editor.putInt("port", mqttPort)
                editor.putString("username", mqttUsername)
                editor.putString("password", mqttPassword)
                editor.putString("topic", mqttTopic)
                editor.putString("payloadJson", payloadJson)
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
                    val sharedPrefs = context.getSharedPreferences("trackiva", Context.MODE_PRIVATE)
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
        private var mqttTopic: String = "trackiva/location"
        // Flexible payload stored as JSON string
        private var payloadJson: String = "{}"
        private var mqttConfigReceiver: BroadcastReceiver? = null

        companion object {
            private const val TAG = "LocationForegroundService"
            var isRunning = false
                private set
            var mqttClient: MqttAsyncClient? = null
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
            private var chatHeadIconName: String? = null

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

            fun setChatHeadIcon(iconName: String?) {
                chatHeadIconName = iconName
            }

            fun getChatHeadIconName(): String? = chatHeadIconName

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

            // Start chat head service if overlay permission is granted
            startChatHeadService()

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
            
            // Ensure chat head service is running (in case service was restarted)
            startChatHeadService()
            
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
                        // --- MQTT publish with flexible payload ---
                        val json = org.json.JSONObject().apply {
                            // Add location data
                            put("location", "POINT(${location.longitude} ${location.latitude})")
                            put("time", System.currentTimeMillis())
                            
                            // Merge flexible payload if available
                            if (payloadJson.isNotEmpty() && payloadJson != "{}") {
                                try {
                                    val payloadMap = Gson().fromJson(payloadJson, Map::class.java) as? Map<*, *>
                                    payloadMap?.forEach { (key, value) ->
                                        when (value) {
                                            is String -> put(key as String, value)
                                            is Number -> put(key as String, value)
                                            is Boolean -> put(key as String, value)
                                            is List<*> -> put(key as String, org.json.JSONArray(value))
                                            is Map<*, *> -> put(key as String, org.json.JSONObject(value as Map<*, *>))
                                            else -> put(key as String, value.toString())
                                        }
                                    }
                                } catch (e: Exception) {
                                    Log.e(TAG, "Failed to merge payload: ${e.message}")
                                }
                            }
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
            payloadJson = prefs.getString("payloadJson", payloadJson) ?: "{}"
        }

        private fun initMqttClient() {
            try {
                val scheme = if (mqttPort == 8883 || mqttPort == 8884) "ssl" else "tcp"
                val brokerUrl = "$scheme://$mqttBroker:$mqttPort"
                val clientId = "trackiva_android_" + System.currentTimeMillis()
                mqttClient = MqttAsyncClient(brokerUrl, clientId, MemoryPersistence())
                LocationForegroundService.mqttClient = mqttClient
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
                if (mqttClient?.isConnected == true) {
                    mqttClient?.disconnectForcibly(100)
                }
            } catch (e: Exception) {
                Log.d(TAG, "Error disconnecting MQTT during reconnect: ${e.message}")
            }
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
            
            // Stop chat head service
            stopChatHeadService()
            
            // Clear tracking state
            val sharedPrefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            sharedPrefs.edit().putBoolean("tracking_enabled", false).apply()
            // Disconnect MQTT safely
            try {
                if (mqttClient?.isConnected == true) {
                    mqttClient?.disconnect()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error disconnecting MQTT: ${e.message}")
            } finally {
                mqttClient = null
                LocationForegroundService.mqttClient = null
            }
            mqttConfigReceiver?.let {
                LocalBroadcastManager.getInstance(this).unregisterReceiver(it)
                mqttConfigReceiver = null
            }
        }

        private fun canDrawOverlays(): Boolean {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Settings.canDrawOverlays(this)
            } else {
                true
            }
        }

        private fun startChatHeadService() {
            if (canDrawOverlays()) {
                try {
                    // Check if chat head service is already running
                    val chatHeadRunning = try {
                        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        val runningServices = activityManager.getRunningServices(Integer.MAX_VALUE)
                        runningServices.any { 
                            it.service.className == ChatHeadService::class.java.name 
                        }
                    } catch (e: Exception) {
                        false
                    }
                    
                    if (!chatHeadRunning) {
                        val chatHeadIntent = Intent(this, ChatHeadService::class.java)
                        // Use startService instead of startForegroundService for chat head
                        // since it's not a foreground service itself
                        startService(chatHeadIntent)
                        Log.d(TAG, "Chat head service started from foreground service")
                    } else {
                        Log.d(TAG, "Chat head service already running")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start chat head service: ${e.message}")
                }
            } else {
                Log.d(TAG, "Overlay permission not granted, chat head will not be shown. Grant permission and restart tracking or call startChatHeadService()")
            }
        }

        private fun stopChatHeadService() {
            try {
                val chatHeadIntent = Intent(this, ChatHeadService::class.java)
                stopService(chatHeadIntent)
                Log.d(TAG, "Chat head service stopped")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to stop chat head service: ${e.message}")
            }
        }

        override fun onBind(intent: Intent?): IBinder? {
            return null
        }
    }

    // Helper method to check overlay permission
    private fun canDrawOverlays(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }
    }

    class ChatHeadService : Service() {
        private companion object {
            const val TAG = "ChatHeadService"
        }
        
        private var windowManager: WindowManager? = null
        private var chatHeadView: View? = null
        private var params: WindowManager.LayoutParams? = null
        private var initialX = 0
        private var initialY = 0
        private var initialTouchX = 0f
        private var initialTouchY = 0f

        override fun onCreate() {
            super.onCreate()
            createChatHeadView()
        }

        private fun createChatHeadView() {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                Log.e(TAG, "Overlay permission not granted")
                stopSelf()
                return
            }

            // Don't recreate if already exists
            if (chatHeadView != null) {
                return
            }

            windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

            // Create chat head view programmatically
            val size = (56 * resources.displayMetrics.density).toInt()
            chatHeadView = ImageView(this).apply {
                // Set icon from configuration or use default
                val iconName = LocationForegroundService.getChatHeadIconName()
                if (!iconName.isNullOrEmpty()) {
                    try {
                        // Try to get resource ID from name (e.g., "ic_launcher" or "drawable/ic_launcher")
                        val resourceName = if (iconName.contains("/")) {
                            iconName.split("/").last()
                        } else {
                            iconName
                        }
                        val resourceId = resources.getIdentifier(
                            resourceName,
                            "drawable",
                            packageName
                        )
                        if (resourceId != 0) {
                            setImageResource(resourceId)
                        } else {
                            // Fallback to default if resource not found
                            Log.w(TAG, "Chat head icon '$iconName' not found, using default")
                            setImageResource(android.R.drawable.ic_menu_mylocation)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error loading chat head icon: ${e.message}")
                        setImageResource(android.R.drawable.ic_menu_mylocation)
                    }
                } else {
                    // Use default icon
                    setImageResource(android.R.drawable.ic_menu_mylocation)
                }
                scaleType = ImageView.ScaleType.CENTER_INSIDE
                
                // Create circular background
                val drawable = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.parseColor("#4CAF50")) // Green color
                    setSize(size, size)
                }
                background = drawable
                
                // Add padding
                setPadding(
                    (8 * resources.displayMetrics.density).toInt(),
                    (8 * resources.displayMetrics.density).toInt(),
                    (8 * resources.displayMetrics.density).toInt(),
                    (8 * resources.displayMetrics.density).toInt()
                )
                
                // Set size
                layoutParams = android.view.ViewGroup.LayoutParams(size, size)
                
                var clickStartTime = 0L
                var isClick = false
                
                // Add touch listener for dragging and clicking
                setOnTouchListener(object : View.OnTouchListener {
                    override fun onTouch(v: View?, event: MotionEvent?): Boolean {
                        when (event?.action) {
                            MotionEvent.ACTION_DOWN -> {
                                initialX = params?.x ?: 0
                                initialY = params?.y ?: 0
                                initialTouchX = event.rawX
                                initialTouchY = event.rawY
                                clickStartTime = System.currentTimeMillis()
                                isClick = true
                                // Add visual feedback
                                alpha = 0.7f
                                return true
                            }
                            MotionEvent.ACTION_MOVE -> {
                                val deltaX = kotlin.math.abs(event.rawX - initialTouchX)
                                val deltaY = kotlin.math.abs(event.rawY - initialTouchY)
                                
                                // If moved more than 10 pixels, it's a drag, not a click
                                if (deltaX > 10 || deltaY > 10) {
                                    isClick = false
                                }
                                
                                params?.x = initialX + (event.rawX - initialTouchX).toInt()
                                params?.y = initialY + (event.rawY - initialTouchY).toInt()
                                
                                // Keep within screen bounds
                                val displayMetrics = resources.displayMetrics
                                params?.x = params?.x?.coerceIn(0, displayMetrics.widthPixels - size) ?: 0
                                params?.y = params?.y?.coerceIn(0, displayMetrics.heightPixels - size) ?: 0
                                
                                windowManager?.updateViewLayout(chatHeadView, params)
                                return true
                            }
                            MotionEvent.ACTION_UP -> {
                                alpha = 1.0f
                                val clickDuration = System.currentTimeMillis() - clickStartTime
                                
                                // If it was a click (short duration and minimal movement)
                                if (isClick && clickDuration < 200) {
                                    // Show a toast or perform action
                                    android.widget.Toast.makeText(
                                        this@ChatHeadService,
                                        "Trackiva Active",
                                        android.widget.Toast.LENGTH_SHORT
                                    ).show()
                                }
                                return true
                            }
                        }
                        return false
                    }
                })
            }

            // Set window parameters
            val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

            params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                layoutType,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = 0
                y = 100
            }

            try {
                windowManager?.addView(chatHeadView, params)
                Log.d(TAG, "Chat head added to window")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to add chat head: ${e.message}")
                stopSelf()
            }
        }

        override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
            // If view was removed (e.g., system killed it), recreate it
            if (chatHeadView == null) {
                createChatHeadView()
            } else {
                // Check if view is still attached to window manager
                try {
                    windowManager?.updateViewLayout(chatHeadView, params)
                } catch (e: Exception) {
                    // View was removed, recreate it
                    Log.d(TAG, "Chat head view was removed, recreating...")
                    chatHeadView = null
                    params = null
                    createChatHeadView()
                }
            }
            return START_STICKY
        }

        override fun onDestroy() {
            super.onDestroy()
            try {
                chatHeadView?.let {
                    windowManager?.removeView(it)
                }
                Log.d(TAG, "Chat head removed from window")
            } catch (e: Exception) {
                Log.e(TAG, "Error removing chat head: ${e.message}")
            }
        }

        override fun onBind(intent: Intent?): IBinder? {
            return null
        }
    }
}