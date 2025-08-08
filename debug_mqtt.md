# MQTT Debugging Guide for iOS

## Issues Fixed

### 1. SSL Configuration

**Problem**: The iOS code was enabling SSL for any port other than 1883, but port 8884 specifically requires SSL.
**Fix**: Changed the condition to only enable SSL for ports 8883 and 8884.

```swift
// Before (incorrect)
if mqttPort != 1883 {
    mqtt.enableSSL = true
}

// After (correct)
if mqttPort == 8883 || mqttPort == 8884 {
    mqtt.enableSSL = true
}
```

### 2. Connection State Management

**Problem**: The `isConnecting` flag was not properly managed, leading to connection attempts being blocked.
**Fix**: Added proper state management and reset the flag when connection attempts fail.

### 3. Error Handling

**Problem**: Insufficient error handling and logging for MQTT connection issues.
**Fix**: Added detailed error logging and connection state reporting.

### 4. Background Task Handling

**Problem**: MQTT connections may be terminated when the app goes to background.
**Fix**: Added reconnection logic for unexpected disconnections.

## Testing Steps

1. **Check MQTT Status**: Use the "Check MQTT" button in the app to verify connection status.

2. **Enable Debug Logging**: Make sure debug mode is enabled to see detailed logs.

3. **Verify Configuration**: Check that the MQTT configuration matches your broker settings:

   - Broker: messages.nectarit.com
   - Port: 8884 (SSL)
   - Username: mobile-ui
   - Password: NecAws@123

4. **Monitor Logs**: Look for these log messages:
   - "SSL enabled for port 8884"
   - "MQTT client initialized"
   - "MQTT connection attempt result: true"
   - "MQTT Connected: accept"

## Common Issues

### SSL Certificate Issues

If you see SSL-related errors, the broker may have a self-signed certificate. You may need to add certificate handling.

### Network Connectivity

Ensure the device has a stable internet connection and can reach the MQTT broker.

### Authentication Issues

Verify the username and password are correct for the MQTT broker.

### Port Blocking

Some networks may block port 8884. Try using port 8883 or 1883 if available.

## Debugging Commands

You can use these commands to test MQTT connectivity:

```bash
# Test connection to the broker
mosquitto_pub -h messages.nectarit.com -p 8884 -u mobile-ui -P NecAws@123 -t test/topic -m "test message" --cafile /path/to/ca.crt
```

## Additional Notes

- The iOS implementation now has better error reporting
- Connection state is properly tracked
- Reconnection logic is improved
- SSL configuration is corrected for port 8884
