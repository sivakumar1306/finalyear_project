# Interoperability: Flutter and Native Bridge

The communication between the Flutter UI and the Native Android background service is facilitated by `MethodChannel` and `EventChannel`.

## MethodChannels (Flutter to Native)

Used for one-off commands and data requests. Defined primarily in `BlePlugin.kt` and `PhoneModePlugin.kt`.

### Common Commands:
- `startScan` / `stopScan`: Trigger BLE scanning.
- `connect` / `disconnect`: Manage ring connection.
- `setTime`: Sync phone time to the ring.
- `getTodaySummary`: Fetch aggregated health data from the local Room DB.
- `configureSync`: Pass Supabase credentials to the native sync manager.
- `sendEmergencySms`: Manually trigger an emergency message.

## EventChannels (Native to Flutter)

Used for real-time streams of data and status updates.

### Streams:
- **`bleEvents`**: Broadcasts connection state changes, scan results, and battery updates.
- **`newReading`**: Notifies Flutter whenever the background loop saves a new vital reading to the local DB, allowing the UI to refresh instantly.
- **`cameraShutter`**: Forwards ring button presses to the Flutter camera UI.
- **`emergencyStatus`**: Streams the countdown state during an emergency alert.

## Data Serialization

Communication happens via JSON-encoded strings or Map objects.
- **Flutter**: Uses `jsonEncode` and `jsonDecode`.
- **Native**: Uses `Gson` or `JSONObject` for parsing and constructing responses.

## Shared Persistence (SharedPreferences)

Both layers access Android `SharedPreferences` to stay in sync on critical settings:
- `device_address`: The MAC address of the bonded ring.
- `user_logged_in`: Boolean flag to gate background sync logic.
- `low_battery_prompt_enabled`: User preference for battery alerts.

## Lifecycle Management

- **Flutter side**: The `BleProvider` initializes the channels and subscribes to events.
- **Native side**: `BlePlugin` is registered in `MainActivity` but interacts with the long-running `BleConnectionService` via intents or a shared repository to ensure that background data is accessible to the UI when it's alive.
