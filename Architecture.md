# The Vital Monitoring: Architecture Documentation

This project is a sophisticated health monitoring platform utilizing a Flutter mobile application and a native Android background service to interface with a QRing Smart Ring.

## Architecture Documentation index

For a detailed breakdown of each component, please refer to the following documents:

1.  **[Overview](architecture/Overview.md)**: High-level system architecture, technology stack, and project goals.
2.  **[Flutter Application](architecture/Flutter_App.md)**: UI structure, state management (Provider), and Flutter services.
3.  **[Native Android Service](architecture/Native_Android.md)**: Foreground service, background loops, and system integration.
4.  **[Data & Synchronization](architecture/Data_Layer.md)**: Local Room database, Supabase cloud sync, and "Offline-First" strategy.
5.  **[Health Analysis & Safety](architecture/Health_Analysis.md)**: Fall detection, risk assessment, and emergency response logic.
6.  **[Flutter-Native Interoperability](architecture/InterOp.md)**: Communication channels (MethodChannel/EventChannel) and shared state.

## Core Design Principles

-   **Offline-First**: All health data is captured and stored locally on the device (Room DB) before being synced to the cloud.
-   **Hardware-Native Focus**: Critical BLE and health analysis logic resides in the native Kotlin layer to ensure performance and reliability.
-   **Reactive UI**: The Flutter layer uses a reactive state management pattern (Provider) to reflect real-time changes from both the cloud and local hardware.
-   **Safety-Centric**: The architecture prioritizes the emergency response pipeline, ensuring it can operate even if the app UI is not in the foreground.
