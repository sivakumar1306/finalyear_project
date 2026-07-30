# Flutter Application Architecture

The Flutter layer serves as the user interface and the primary management interface for the QRing system. It is designed to be highly reactive and consistent across the application.

## State Management: Provider

The app uses the `provider` package to manage state. Key providers include:

- **BleProvider**: The core of the application. It manages the connection state with the ring, exposes vitals data (either from the native local DB or Supabase fallback), and handles commands to the ring (e.g., sync, camera control).
- **WorkoutProvider**: Manages active workout sessions and history.
- **AlarmModeProvider**: Handles configuration for ring-based reminders and alarms.
- **MainTabProvider**: Manages navigation state within the main app shell.

## Directory Structure

- `lib/screens/`: Organizes UI by feature.
    - `auth/`: Login, Signup, Splash.
    - `health/`: Detailed vitals screens (Heart Rate, SpO2, Sleep, etc.).
    - `settings/`: Device, Health, and Account configurations.
    - `workouts/`: Active exercise tracking.
- `lib/providers/`: Contains business logic and state using `ChangeNotifier`.
- `lib/services/`:
    - `supabase_service.dart`: Encapsulates all cloud database operations.
    - `ble_service.dart`: A wrapper around the `MethodChannel` calls to the native side.
- `lib/models/`: Dart classes representing the data entities (mirrored from native and cloud).
- `lib/widgets/`: Reusable UI components (Custom charts, status cards, etc.).

## Routing and Navigation

The app uses static named routes defined in `app.dart`.
- `/`: Splash screen handles initial auth and initialization check.
- `/home`: The `MainShell` containing the dashboard.
- Feature routes: `/heart-rate`, `/sleep`, `/device-settings`, etc.

## Theming

A dark-centric theme is applied globally using `AppTheme.darkTheme()`, defined in `lib/theme/app_theme.dart`. It uses Google Fonts and custom color palettes tailored for a health-monitoring experience.

## Initialization Workflow (`main.dart`)

1. **Native Bindings**: `WidgetsFlutterBinding.ensureInitialized()`.
2. **Permissions**: Request Bluetooth, Location, Notification, SMS, and Phone permissions.
3. **Foreground Service**: Signal the native side to start the `BleConnectionService`.
4. **Supabase**: Initialize the Supabase client.
5. **Native Config**: Configure the native `SupabaseSyncManager` with the current user's session and credentials to enable background syncing.
6. **Auth Listening**: Subscribe to auth state changes to re-configure native sync upon login/logout.
