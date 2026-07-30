# Native Android Architecture

The native Android layer handles the heavy lifting of hardware communication, continuous health analysis, and persistent background tasks.

## Core Services

### `BleConnectionService`
A **Foreground Service** that ensures the app remains active in the background. It owns the BLE connection life cycle and orchestrates several sub-managers.
- **Auto-Reconnect**: Automatically attempts to reconnect to the bonded ring if the connection is lost.
- **Persistence**: Runs independently of the Flutter UI process.

### `MeasurementLoopManager` & `MeasurementCoordinator`
These components manage the "Measurement Loop":
- Periodically triggers the ring to take readings for different vitals (Heart Rate, SpO2, etc.).
- Collects raw data from the ring and saves it to the local Room database.
- Handles timing and priority between different vital measurements.

## Health Analysis Engine

Located in the `analysis` package, these components work on raw data:

- **`FallMotionDetector`**: Analyzes accelerometer/gyroscope data (if available) or movement patterns to detect potential falls.
- **`FallRiskAnalyzer`**: Uses historical vital trends and recent readings to compute a "Fall Risk Score".
- **`FallPredictionNotifier`**: Alerts the user and prepares emergency protocols if a high-risk state is detected.

## Emergency Response System

- **`EmergencySmsSender`**: Sends automated SMS messages to designated emergency contacts.
- **`EmergencyAutoCaller`**: Initiates phone calls to emergency services or contacts upon corroborated fall detection.
- **Countdown Mechanism**: Provides a user-facing countdown (via `BleProvider` and UI) to allow canceling an emergency alert if it's a false positive.

## System Integration

- **`BootReceiver`**: Ensures the `BleConnectionService` restarts automatically after a device reboot.
- **`QRingBluetoothReceiver`**: Monitors system Bluetooth state changes to manage the ring connection gracefully.
- **`AlertNotifier`**: Handles posting system-level notifications for health alerts and service status.

## Data Flow (Native)

1. **Hardware (Ring)** -> **BLE SDK** -> **`BleConnectionService`**
2. **`BleConnectionService`** -> **`MeasurementLoopManager`** -> **`QRingDatabase` (Room)**
3. **`QRingDatabase`** -> **`SupabaseSyncManager`** -> **Supabase Cloud**
4. **`QRingDatabase`** -> **`FallRiskAnalyzer`** -> **`FallAlertNotifier`**
