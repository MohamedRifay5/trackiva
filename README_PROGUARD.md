# ProGuard Configuration for Trackiva Plugin

## Overview

When building your app in release mode with ProGuard enabled, you need to ensure that the Trackiva plugin classes are not obfuscated or removed. The plugin includes ProGuard rules that are automatically applied when you use the plugin.

## Automatic Configuration

The Trackiva plugin includes a `proguard-rules.pro` file that is automatically included when you add the plugin to your project. **You don't need to do anything additional** - the rules are automatically merged into your app's ProGuard configuration.

## What the Rules Protect

The ProGuard rules ensure the following are preserved:

1. **Trackiva Plugin Classes** - All plugin classes and methods
2. **MQTT Client (Eclipse Paho)** - Required for MQTT functionality
3. **Gson** - JSON serialization for flexible payloads
4. **Location Services** - Google Play Services Location APIs
5. **Notifications** - Android notification classes
6. **Services & Broadcast Receivers** - Background services and receivers
7. **Kotlin Metadata** - Required for Kotlin reflection

## Manual Configuration (If Needed)

If you need to add additional rules in your main app, you can add them to your app's `proguard-rules.pro` file:

```proguard
# Additional Trackiva rules (if needed)
-keep class com.example.trackiva.** { *; }
```

## Testing with ProGuard

To test your app with ProGuard enabled:

1. Build a release APK:

   ```bash
   flutter build apk --release
   ```

2. Or build an App Bundle:

   ```bash
   flutter build appbundle --release
   ```

3. Test all Trackiva features:
   - Location tracking
   - MQTT publishing
   - Notifications
   - Background services

## Troubleshooting

If you encounter issues after enabling ProGuard:

1. **Check Logcat** - Look for `ClassNotFoundException` or `NoSuchMethodError`
2. **Verify Rules** - Ensure `proguard-rules.pro` is included in your app's build
3. **Add Specific Rules** - If a specific class is missing, add a keep rule for it

## Common Issues

### MQTT Connection Fails

- **Solution**: The rules already include Eclipse Paho MQTT classes. If issues persist, verify your network permissions.

### JSON Serialization Errors

- **Solution**: Gson rules are included. Ensure your payload classes are not being obfuscated.

### Location Services Not Working

- **Solution**: Google Play Services Location rules are included. Check location permissions.

## Notes

- The ProGuard rules are automatically included via `consumerProguardFiles` in the plugin's build.gradle
- No manual configuration is required in your main app
- The rules are optimized to keep only necessary classes to minimize app size impact
