# 02 — Device Pairing & BLE Connection

| Field | Value |
|-------|-------|
| **Status** | Shipped |
| **Primary platform** | Android (vendor SDK required) |
| **Key code** | `BlePlugin.kt`, `BleConnectionService.kt`, `lib/services/ble_service.dart`, `lib/providers/ble_provider.dart`, `ring_scan_sheet.dart`, `device_bind_screen.dart` |

---

## 1. Purpose

Discover, bond, and maintain a connection to a SUNDR/QRing smart ring so vitals, settings, OTA, and workouts can operate.

---

## 2. Constraints

- All BLE traffic goes through the **closed-source vendor AAR** (`android/app/libs/qring_sdk_*.aar`, `com.oudmon.ble.*`).
- Flutter never opens GATT directly; it uses MethodChannel / EventChannel (`com.sundr.myapp/ble`, `.../ble_events`).
- Real BLE testing requires a **physical Android device**; emulator has no usable BLE stack for this product.
- Foreground service owns connection lifecycle independent of Flutter UI process.

---

## 3. User-facing entry points

| Entry | UI | When |
|-------|-----|------|
| Home device pill | `ring_scan_sheet.dart` (modal) | Primary everyday path |
| Onboarding / Settings | `device_bind_screen.dart` (full screen) | First-time or explicit rebind |
| Auto-reconnect | Native service | Last known address + logged-in user |

---

## 4. Pairing flow

```
Idle → Scanning → Connecting → Service discovery → Bond check
  → (bond if needed) → Bind success (CMD_BIND_SUCCESS, retry ≤3)
  → Connected
```

### Requirements

| ID | Requirement |
|----|-------------|
| BLE-01 | Start/stop BLE scan on user action; auto-stop scan after ~20s if no selection. |
| BLE-02 | Filter advertisements to product name prefixes (e.g. `R08_`, `R02_` / SUNDR naming). |
| BLE-03 | Show discovered devices with signal strength (RSSI) indication. |
| BLE-04 | On select, connect GATT, complete service discovery, ensure bond if required. |
| BLE-05 | On bind success, persist device address for reconnect (`SharedPreferences` / native). |
| BLE-06 | Provide “connect to last known device” when advertising stopped but device still bondable. |
| BLE-07 | Disconnect path clears or marks connection state; UI reflects disconnected. |
| BLE-08 | Auto-reconnect when logged in, Bluetooth on, and address known — including after reboot (`BootReceiver`). |
| BLE-09 | Do not start intrusive pairing prompts on the login screen (gate on `user_logged_in`). |
| BLE-10 | Emit connection, battery, and scan events to Flutter via EventChannel. |

---

## 5. Connection states (UI)

UI should expose at least:

- Disconnected / Idle  
- Scanning  
- Connecting  
- Connected (with optional battery %)  
- Error / timeout (non-fatal; allow retry)

`BleProvider` is the Flutter source of truth for connection fields consumed by Home and Settings.

---

## 6. Background service

| ID | Requirement |
|----|-------------|
| BLE-11 | `BleConnectionService` runs as a foreground service with a persistent notification while monitoring is active. |
| BLE-12 | Service starts early in app launch (`main.dart`) but reconnect loop respects login flag. |
| BLE-13 | System Bluetooth off/on handled via receivers without crashing the process. |
| BLE-14 | After device reboot, service can restart and attempt reconnect when appropriate. |

---

## 7. Commands surface (product-level)

The bridge exposes (non-exhaustive) capabilities used by features:

- Scan / connect / disconnect  
- Time sync to ring  
- Today summary & reading queries from Room  
- Manual and settings measurements  
- Drink / sedentary reminders  
- Display / health / notification / advanced settings  
- OTA start + progress events  
- Camera shutter / gesture-related events  
- Fall-related configure / simulate / emergency contacts  

Full method inventory: `KNOWLEDGE_TRANSFER.md` §6 and `architecture/InterOp.md`.

---

## 8. Acceptance criteria

- [ ] User can scan, see only relevant rings, and connect successfully.
- [ ] After force-stop of UI, service can still hold or restore connection when process allowed.
- [ ] After reboot (with permissions), service restarts and reconnects if user was logged in.
- [ ] Disconnect from Settings/UI updates Home device pill.
- [ ] Scan timeout does not leave UI stuck in scanning forever.
- [ ] Last-device connect works when advertising is silent.

---

## 9. Known limitations

- Vendor SDK does **not** expose continuous raw accelerometer/gyro streams for fall IMU (see fall spec).
- Temperature one-click paths may be unreliable (vital often disabled by default).
- iOS BLE integration is not the active product path.

---

## 10. Related

- [03-vitals-monitoring.md](./03-vitals-monitoring.md)  
- [10-settings-device.md](./10-settings-device.md)  
- `architecture/Native_Android.md`, `architecture/InterOp.md`  
