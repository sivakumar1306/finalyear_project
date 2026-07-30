# Health Analysis and Safety Logic

One of the project's unique strengths is its proactive health analysis and safety features, implemented largely in the native Kotlin layer.

## Fall Detection Pipeline

The system uses a multi-stage process to detect and respond to falls.

### 1. Motion Detection (`FallMotionDetector`)
- Monitors real-time movement data.
- Uses threshold-based triggers to identify sudden impacts or orientation changes consistent with a fall.

### 2. Risk Assessment (`FallRiskAnalyzer`)
- Not all impacts are falls. The analyzer looks at the user's vitals (HR, SpO2) immediately after a detected motion.
- High heart rate combined with a sudden drop in movement increases the confidence score of a fall.

### 3. Verification and Notification
- **Alerting**: The `FallAlertNotifier` triggers a loud alarm on the phone and a full-screen notification.
- **User Confirmation**: The user is given a window (e.g., 30 seconds) to dismiss the alert if they are okay.

### 4. Automated Response
- If the user doesn't respond, `EmergencySmsSender` and `EmergencyAutoCaller` take over to get help.

## Vitals Monitoring Loop

The `MeasurementLoopManager` operates on a scheduled cycle:
- **Prioritization**: High-priority vitals (Heart Rate) are measured more frequently.
- **Battery Optimization**: The loop adjusts its frequency based on the ring's battery level.
- **Interoperability**: If the user manually triggers a measurement in the Flutter UI, the background loop pauses to avoid SDK conflicts.

## Fall Risk Prediction

Beyond detection, the app *predicts* risk:
- Analyzes patterns in vitals over the last few hours/days.
- If trends (e.g., consistently decreasing SpO2 and increasing resting heart rate) suggest a higher probability of an accident, a "High Fall Risk" banner is displayed to the user in the Flutter dashboard.
