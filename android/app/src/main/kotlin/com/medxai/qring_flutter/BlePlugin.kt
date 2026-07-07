package com.medxai.qring_flutter

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.app.Application
import android.util.Log
import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.concurrent.atomic.AtomicBoolean
import com.google.gson.Gson
import com.oudmon.ble.base.bean.SleepDisplay
import com.oudmon.ble.base.bluetooth.BleOperateManager
import com.oudmon.ble.base.communication.CommandHandle
import com.oudmon.ble.base.communication.Constants
import com.oudmon.ble.base.communication.DfuHandle
import com.oudmon.ble.base.communication.ICommandResponse
import com.oudmon.ble.base.communication.ILargeDataLaunchSleepResponse
import com.oudmon.ble.base.communication.ILargeDataSleepResponse
import com.oudmon.ble.base.communication.LargeDataHandler
import com.oudmon.ble.base.communication.bigData.BloodOxygenEntity
import com.oudmon.ble.base.communication.bigData.IntervalBloodOxygenEntity
import com.oudmon.ble.base.communication.bigData.bean.IntervalHeartRateEntity
import com.oudmon.ble.base.communication.bigData.bean.IntervalTemperatureEntity
import com.oudmon.ble.base.communication.bigData.resp.IIntervalHeartRateCallback
import com.oudmon.ble.base.communication.dfu_temperature.TemperatureEntity
import com.oudmon.ble.base.communication.dfu_temperature.TemperatureOnceEntity
import com.oudmon.ble.base.communication.entity.BlePressure
import com.oudmon.ble.base.communication.entity.BleStepDetails
import com.oudmon.ble.base.communication.entity.StartEndTimeEntity
import com.oudmon.ble.base.communication.file.FileHandle
import com.oudmon.ble.base.communication.file.SimpleCallback
import com.oudmon.ble.base.communication.req.BloodOxygenSettingReq
import com.oudmon.ble.base.communication.req.BpSettingReq
import com.oudmon.ble.base.communication.req.DeviceSupportReq
import com.oudmon.ble.base.communication.req.DndReq
import com.oudmon.ble.base.communication.req.HRVReq
import com.oudmon.ble.base.communication.req.HeartRateSettingReq
import com.oudmon.ble.base.communication.req.HrvSettingReq
import com.oudmon.ble.base.communication.req.MusicSwitchReq
import com.oudmon.ble.base.communication.req.PressureReq
import com.oudmon.ble.base.communication.req.PressureSettingReq
import com.oudmon.ble.base.communication.req.ReadDetailSportDataReq
import com.oudmon.ble.base.communication.req.ReadDrinkAlarmReq
import com.oudmon.ble.base.communication.req.ReadHeartRateReq
import com.oudmon.ble.base.communication.req.SetANCSReq
import com.oudmon.ble.base.communication.req.SetTimeReq
import com.oudmon.ble.base.communication.req.SimpleKeyReq
import com.oudmon.ble.base.communication.req.TemperatureSettingReq
import com.oudmon.ble.base.communication.req.TouchControlReq
import com.oudmon.ble.base.communication.responseImpl.DeviceNotifyListener
import com.oudmon.ble.base.communication.rsp.BaseRspCmd
import com.oudmon.ble.base.communication.rsp.BatteryRsp
import com.oudmon.ble.base.communication.rsp.DeviceNotifyRsp
import com.oudmon.ble.base.communication.rsp.DeviceSupportFunctionRsp
import com.oudmon.ble.base.communication.rsp.HRVRsp
import com.oudmon.ble.base.communication.rsp.HeartRateSettingRsp
import com.oudmon.ble.base.communication.rsp.PressureRsp
import com.oudmon.ble.base.communication.rsp.ReadDetailSportDataRsp
import com.oudmon.ble.base.communication.rsp.ReadHeartRateRsp
import com.oudmon.ble.base.communication.rsp.SetTimeRsp
import com.oudmon.ble.base.communication.rsp.SleepNewProtoResp
import com.oudmon.ble.base.communication.rsp.StartHeartRateRsp
import com.oudmon.ble.base.communication.rsp.TouchControlResp
import com.oudmon.ble.base.communication.sport.SportPlusHandle
import com.oudmon.ble.base.scan.BleScannerHelper
import com.oudmon.ble.base.scan.ScanRecord
import com.oudmon.ble.base.scan.ScanWrapperCallback
import com.medxai.qring_flutter.analysis.FallAlertNotifier
import com.medxai.qring_flutter.data.FallEventEntity
import com.medxai.qring_flutter.data.MeasurementConfig
import com.medxai.qring_flutter.data.ReadingRepository
import com.medxai.qring_flutter.data.Vital
import com.medxai.qring_flutter.events.NewReadingEvent
import com.medxai.qring_flutter.sync.SupabaseConfig
import com.medxai.qring_flutter.sync.SupabaseSyncManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.launch
import org.greenrobot.eventbus.EventBus
import org.greenrobot.eventbus.Subscribe
import org.greenrobot.eventbus.ThreadMode
import java.time.LocalDate
import java.time.ZoneId

class BlePlugin(private val context: Context) {

    companion object {
        private const val TAG = "BlePlugin"
        private const val CONNECT_TIMEOUT_MS = 60_000L
        private const val INIT_COMMAND_DELAY_MS = 400L
        private const val INIT_RETRY_TIMEOUT_MS = 4_000L
        private const val INIT_MAX_ATTEMPTS = 3

        var instance: BlePlugin? = null
            private set
    }

    private val gson = Gson()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private val NOTIFY_KEY = 999
    private var _isConnected = false
    private var pendingConnectResult: MethodChannel.Result? = null
    private var deviceAddress: String? = null
    private var pendingBondFallback: Runnable? = null

    // Populated by QRingBluetoothReceiver.onCharacteristicRead once the SDK broadcasts them.
    var cachedFirmwareVersion: String = ""
    var cachedHardwareVersion: String = ""

    private val connectTimeoutRunnable = Runnable {
        val r = pendingConnectResult
        pendingConnectResult = null
        r?.let { mainHandler.post { it.error("TIMEOUT", "Connection timed out", null) } }
    }

    val eventStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
        }
        override fun onCancel(arguments: Any?) {
            eventSink = null
        }
    }

    init {
        try {
            BleOperateManager.getInstance(context.applicationContext as Application)
            BleOperateManager.getInstance().init()
        } catch (_: Exception) {}
        registerDeviceListener()
        MeasurementConfig.init(context.applicationContext)
        SupabaseConfig.init(context.applicationContext)
        EventBus.getDefault().register(this)
        instance = this
    }

    // Forwards native-side readings (persisted by MeasurementLoopManager) to Dart over the
    // existing ble_events EventChannel — no new channel needed.
    @Subscribe(threadMode = ThreadMode.MAIN)
    fun onNewReading(event: NewReadingEvent) {
        val data = mutableMapOf<String, Any>(
            "vital" to event.vital.name,
            "readingId" to event.readingId,
            "cycleId" to event.cycleId,
            "measuredAt" to event.measuredAt
        )
        event.primaryValue?.let { data["primaryValue"] = it }
        sendEvent("newReading", data)
    }

    private fun registerDeviceListener() {
        BleOperateManager.getInstance().addOutDeviceListener(
            NOTIFY_KEY,
            object : DeviceNotifyListener() {
                override fun onDataResponse(resultEntity: DeviceNotifyRsp?) {
                    resultEntity ?: return
                    sendEvent(
                        "deviceNotification",
                        mapOf(
                            "dataType" to resultEntity.dataType,
                            "status" to resultEntity.status,
                            "loadData" to (resultEntity.loadData?.map { it.toInt() and 0xFF } ?: emptyList<Int>())
                        )
                    )
                }
            }
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // Method call dispatcher
    // ─────────────────────────────────────────────────────────────────

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startScan"                  -> startScan(call, result)
            "stopScan"                   -> stopScan(result)
            "connect"                    -> connect(call, result)
            "disconnect"                 -> disconnect(result)
            "isConnected"                -> result.success(_isConnected)
            "getBattery"                 -> getBattery(result)
            "getFirmwareVersion"         -> getFirmwareVersion(result)
            "setTime"                    -> setTime(result)
            "getDeviceSupport"           -> getDeviceSupport(result)
            "getTodayHeartRate"          -> getTodayHeartRate(result)
            "getHeartRate"               -> getHeartRate(call, result)
            "getHeartRates"              -> getHeartRates(call, result)
            "getHeartRateSetting"        -> getHeartRateSetting(result)
            "setHeartRateSetting"        -> setHeartRateSetting(call, result)
            "manualModeHeart"            -> manualModeHeart(call, result)
            "readHeartRate"              -> readHeartRate(result)
            "syncIntervalHeartRate"      -> syncIntervalHeartRate(result)
            "syncHistoryHeartRate"       -> syncHistoryHeartRate(result)
            "getTodayBloodPressure"      -> getTodayBloodPressure(result)
            "getBloodPressure"           -> getBloodPressure(call, result)
            "getBloodPressures"          -> getBloodPressures(call, result)
            "getBloodPressureSetting"    -> getBloodPressureSetting(result)
            "setBloodPressureSetting"    -> setBloodPressureSetting(call, result)
            "manualModeBP"               -> manualModeBP(call, result)
            "syncBloodPressure"          -> syncBloodPressure(result)
            "getTodayBloodOxygen"        -> getTodayBloodOxygen(result)
            "getBloodOxygen"             -> getBloodOxygen(call, result)
            "getBloodOxygens"            -> getBloodOxygens(call, result)
            "getBloodOxygenSetting"      -> getBloodOxygenSetting(result)
            "setBloodOxygenSetting"      -> setBloodOxygenSetting(call, result)
            "manualModeBloodOxygen"      -> manualModeBloodOxygen(call, result)
            "syncIntervalBloodOxygen"    -> syncIntervalBloodOxygen(result)
            "getTodaySteps"              -> getTodaySteps(result)
            "getSteps"                   -> getSteps(call, result)
            "getStepsList"               -> getStepsList(call, result)
            "syncTodaySteps"             -> syncTodaySteps(result)
            "syncStepDetails"            -> syncStepDetails(result)
            "getTodaySleep"              -> getTodaySleep(result)
            "getSleep"                   -> getSleep(call, result)
            "getSleepList"               -> getSleepList(call, result)
            "syncSleep"                  -> syncSleep(result)
            "getTodayHrv"                -> getTodayHrv(result)
            "getHrv"                     -> getHrv(call, result)
            "getHrvList"                 -> getHrvList(call, result)
            "getHrvSetting"              -> getHrvSetting(result)
            "setHrvSetting"              -> setHrvSetting(call, result)
            "syncHrv"                    -> syncHrv(result)
            "manualModeHrv"              -> manualModeHrv(call, result)
            "getTodayPressure"           -> getTodayPressure(result)
            "getPressure"                -> getPressure(call, result)
            "getPressureList"            -> getPressureList(call, result)
            "getPressureSetting"         -> getPressureSetting(result)
            "setPressureSetting"         -> setPressureSetting(call, result)
            "syncPressure"               -> syncPressure(result)
            "manualModePressure"         -> manualModePressure(call, result)
            "getTodayTemperature"        -> getTodayTemperature(result)
            "getTemperature"             -> getTemperature(call, result)
            "getTemperatureList"         -> getTemperatureList(call, result)
            "getTemperatureSetting"      -> getTemperatureSetting(result)
            "setTemperatureSetting"      -> setTemperatureSetting(call, result)
            "syncAutoTemperature"        -> syncAutoTemperature(result)
            "syncManualTemperature"      -> syncManualTemperature(result)
            "syncSportRecords"           -> syncSportRecords(result)
            "getNotificationSettings"    -> getNotificationSettings(result)
            "setNotificationSetting"     -> setNotificationSetting(call, result)
            "getDndSetting"              -> getDndSetting(result)
            "setDndSetting"              -> setDndSetting(call, result)
            "getMusicSwitch"             -> getMusicSwitch(result)
            "setMusicSwitch"             -> setMusicSwitch(call, result)
            "getDisplaySettings"         -> result.success("{}")
            "setDisplaySetting"          -> result.success(true)
            "getTargetAndProfile"        -> result.success("{}")
            "setTargetAndProfile"        -> result.success(true)
            "getAdvancedSettings"        -> result.success("{}")
            "setAdvancedSetting"         -> result.success(true)
            "getTouchControlSetting"     -> getTouchControlSetting(result)
            "setTouchControlSetting"     -> setTouchControlSetting(call, result)
            "getDrinkReminder"           -> getDrinkReminder(result)
            "getSedentaryReminder"       -> getSedentaryReminder(result)
            "startOta"                   -> startOta(call, result)
            "sendNotification"           -> result.success(true)
            "startForegroundService"     -> {
                try {
                    BleOperateManager.getInstance(context.applicationContext as Application)
                    BleOperateManager.getInstance().init()
                } catch (_: Exception) {}
                BleConnectionService.start(context)
                result.success(true)
            }
            "startWorkout"               -> {
                WorkoutService.start(context)
                result.success(true)
            }
            "stopWorkout"                -> {
                WorkoutService.stop(context)
                result.success(true)
            }
            "getReadings"                -> getReadings(call, result)
            "getTodaySummary"            -> getTodaySummary(call, result)
            "getLatestReading"           -> getLatestReading(call, result)
            "getStepsToday"              -> getStepsToday(result)
            "getSyncStatus"              -> getSyncStatus(result)
            "getMeasurementCycleHistory" -> getMeasurementCycleHistory(call, result)
            "setVitalEnabled"            -> setVitalEnabled(call, result)
            "getVitalEnabled"            -> getVitalEnabled(call, result)
            "setMasterLoopEnabled"       -> {
                MeasurementConfig.setMasterEnabled(call.argument<Boolean>("enabled") ?: true)
                result.success(true)
            }
            "getMasterLoopEnabled"       -> result.success(MeasurementConfig.isMasterEnabled())
            "setSyncEnabled"             -> {
                MeasurementConfig.setSyncEnabled(call.argument<Boolean>("enabled") ?: true)
                result.success(true)
            }
            "getSyncEnabled"             -> result.success(MeasurementConfig.isSyncEnabled())
            "configureSync"              -> configureSync(call, result)
            "forceSyncNow"               -> result.success(SupabaseSyncManager.forceSyncNow())
            "seedDemoData"               -> seedDemoData(call, result)
            "getFallRiskScore"           -> getFallRiskScore(result)
            "getFallRiskLog"             -> getFallRiskLog(call, result)
            "getFallEvents"              -> getFallEvents(call, result)
            "simulateFallEvent"          -> simulateFallEvent(result)
            else                         -> result.notImplemented()
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // Scanning
    // ─────────────────────────────────────────────────────────────────

    private fun startScan(call: MethodCall, result: MethodChannel.Result) {
        val filterName = call.argument<String>("filterName") ?: ""

        // Emit already-bonded devices immediately — covers the case where the ring is
        // not advertising (e.g. after being used by another app that didn't close GATT).
        try {
            val btManager = context.getSystemService(Context.BLUETOOTH_SERVICE)
                    as? android.bluetooth.BluetoothManager
            btManager?.adapter?.bondedDevices?.forEach { device ->
                val name = try { device.name ?: "" } catch (_: SecurityException) { "" }
                if (filterName.isEmpty() || name.contains(filterName, ignoreCase = true)) {
                    sendEvent("scanResult", mapOf("name" to name, "address" to device.address, "rssi" to -80))
                }
            }
            // Also include any device already connected via GATT.
            btManager?.getConnectedDevices(android.bluetooth.BluetoothProfile.GATT)
                ?.forEach { device ->
                    val name = try { device.name ?: "" } catch (_: SecurityException) { "" }
                    if (filterName.isEmpty() || name.contains(filterName, ignoreCase = true)) {
                        sendEvent("scanResult", mapOf("name" to name, "address" to device.address, "rssi" to -60))
                    }
                }
        } catch (_: Exception) {}

        BleScannerHelper.getInstance().scanDevice(
            context,
            null,
            object : ScanWrapperCallback {
                override fun onStart() {}
                override fun onStop() {
                    sendEvent("scanFinished", emptyMap<String, Any>())
                }
                override fun onLeScan(device: BluetoothDevice?, rssi: Int, scanRecord: ByteArray?) {
                    val address = device?.address ?: return
                    val name = try { device.name ?: "" } catch (e: SecurityException) { "" }
                    if (filterName.isEmpty() || name.contains(filterName, ignoreCase = true)) {
                        sendEvent("scanResult", mapOf("name" to name, "address" to address, "rssi" to rssi))
                    }
                }
                override fun onScanFailed(errorCode: Int) {
                    sendEvent("scanError", mapOf("errorCode" to errorCode))
                }
                override fun onParsedData(device: BluetoothDevice?, scanRecord: ScanRecord?) {}
                override fun onBatchScanResults(results: MutableList<android.bluetooth.le.ScanResult>?) {}
            }
        )
        result.success(null)
    }

    private fun stopScan(result: MethodChannel.Result) {
        BleScannerHelper.getInstance().stopScan(context)
        result.success(null)
    }

    // ─────────────────────────────────────────────────────────────────
    // Connection
    // ─────────────────────────────────────────────────────────────────

    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        val address = call.argument<String>("address") ?: run {
            result.error("INVALID_ARG", "address required", null); return
        }
        deviceAddress = address
        BleScannerHelper.getInstance().stopScan(context)

        if (BleOperateManager.getInstance().isConnected) {
            // Already connected (e.g. reconnecting to a live session) — the SDK will not
            // re-fire onServiceDiscovered(), so resolve immediately instead of waiting for it.
            _isConnected = true
            mainHandler.post { result.success(true) }
            return
        }

        mainHandler.removeCallbacks(connectTimeoutRunnable)
        pendingConnectResult = result
        mainHandler.postDelayed(connectTimeoutRunnable, CONNECT_TIMEOUT_MS)
        BleOperateManager.getInstance().connectDirectly(address)
    }

    private fun disconnect(result: MethodChannel.Result) {
        mainHandler.removeCallbacks(connectTimeoutRunnable)
        pendingConnectResult = null
        BleOperateManager.getInstance().unBindDevice()
        _isConnected = false
        sendEvent("connectionState", mapOf("connected" to false))
        result.success(null)
    }

    // ─────────────────────────────────────────────────────────────────
    // Connection lifecycle callbacks (invoked by QRingBluetoothReceiver)
    // ─────────────────────────────────────────────────────────────────

    // The SDK requires waiting for onServiceDiscovered() before sending any commands —
    // sending them right off the raw GATT-connected state can be answered with no response.
    fun onServiceDiscovered() {
        mainHandler.removeCallbacks(connectTimeoutRunnable)
        _isConnected = true
        sendEvent("connectionState", mapOf("connected" to true))
        MeasurementLoopManager.onRingConnected()

        val result = pendingConnectResult
        pendingConnectResult = null
        result?.let { r -> mainHandler.post { r.success(true) } }

        // Give the phone/device GATT and notify state a moment to settle before sending
        // the bind-success command — sending immediately can receive no response.
        mainHandler.postDelayed({ readDeviceCapabilityAndPairIfNeeded() }, INIT_COMMAND_DELAY_MS)
    }

    fun onDeviceDisconnected() {
        mainHandler.removeCallbacks(connectTimeoutRunnable)
        pendingConnectResult = null
        _isConnected = false
        sendEvent("connectionState", mapOf("connected" to false))
        MeasurementLoopManager.onRingDisconnected()
    }

    // Fires for any successful connection, including ones BleConnectionService's background
    // reconnect loop initiates directly (bypassing connect()) — keeps isAlreadyBonded() working
    // regardless of who triggered the connection.
    fun onDeviceAddressKnown(address: String) {
        deviceAddress = address
    }

    // Called by QRingSystemBluetoothReceiver when a bond attempt ends in BOND_NONE
    // (rejected/cancelled/timed out) — unblocks whatever init command was waiting on it.
    fun onBondFailed() {
        val fallback = pendingBondFallback
        pendingBondFallback = null
        fallback?.let { mainHandler.post(it) }
    }

    private fun isAlreadyBonded(): Boolean {
        val address = deviceAddress ?: return false
        return try {
            BluetoothAdapter.getDefaultAdapter()?.getRemoteDevice(address)?.bondState == BluetoothDevice.BOND_BONDED
        } catch (_: Exception) {
            false
        }
    }

    // Devices with supportBlePair = true require the app to trigger system Bluetooth
    // pairing after connecting; until that bond exists, the ring's firmware silently
    // ignores every command (no error, just no response). If it's already bonded, skip
    // straight to sendBindSuccessWithRetry() — concurrent GATT writes during an in-flight
    // pairing handshake can starve the handshake itself, so the two must not overlap.
    private fun readDeviceCapabilityAndPairIfNeeded() {
        CommandHandle.getInstance().executeReqCmd(
            DeviceSupportReq.getReadInstance(),
            ICommandResponse<DeviceSupportFunctionRsp> { rsp ->
                Log.d(TAG, "DeviceSupportReq: supportBlePair=${rsp.supportBlePair}, alreadyBonded=${isAlreadyBonded()}")
                if (rsp.supportBlePair && !isAlreadyBonded()) {
                    Log.d(TAG, "Device requires BLE pairing — calling bleCreateBond(), deferring other init commands")
                    // If bonding succeeds, QRingSystemBluetoothReceiver reconnects the GATT
                    // link, which re-enters this whole flow fresh (and isAlreadyBonded() will
                    // then be true). If it fails, onBondFailed() runs this fallback so the app
                    // isn't stuck silently.
                    pendingBondFallback = Runnable { sendBindSuccessWithRetry() }
                    BleOperateManager.getInstance().bleCreateBond()
                } else {
                    sendBindSuccessWithRetry()
                }
            }
        )
    }

    private fun sendBindSuccessWithRetry(attempt: Int = 1) {
        var responded = false
        val timeoutRunnable = Runnable {
            if (!responded) {
                if (attempt < INIT_MAX_ATTEMPTS) {
                    Log.w(TAG, "CMD_BIND_SUCCESS attempt $attempt got no response, retrying")
                    sendBindSuccessWithRetry(attempt + 1)
                } else {
                    Log.e(TAG, "CMD_BIND_SUCCESS: no response after $INIT_MAX_ATTEMPTS attempts")
                }
            }
        }
        mainHandler.postDelayed(timeoutRunnable, INIT_RETRY_TIMEOUT_MS)
        CommandHandle.getInstance().executeReqCmd(
            SimpleKeyReq(Constants.CMD_BIND_SUCCESS),
            ICommandResponse<BaseRspCmd> {
                responded = true
                mainHandler.removeCallbacks(timeoutRunnable)
            }
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // Device Info
    // ─────────────────────────────────────────────────────────────────

    private fun getBattery(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            SimpleKeyReq(Constants.CMD_GET_DEVICE_ELECTRICITY_VALUE),
            ICommandResponse<BatteryRsp> { rsp ->
                mainHandler.post {
                    if (rsp.status == BaseRspCmd.RESULT_OK) {
                        result.success(rsp.batteryValue)
                    } else {
                        result.error("CMD_FAILED", "status=${rsp.status}", null)
                    }
                }
            }
        )
    }

    private fun getFirmwareVersion(result: MethodChannel.Result) {
        // Populated by QRingBluetoothReceiver.onCharacteristicRead once the SDK broadcasts it;
        // empty until the device has sent it (shortly after connect).
        mainHandler.post {
            result.success(mapOf("hardware" to cachedHardwareVersion, "firmware" to cachedFirmwareVersion, "model" to ""))
        }
    }

    private fun setTime(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            SetTimeReq(0),
            ICommandResponse<SetTimeRsp> { _ ->
                mainHandler.post { result.success(true) }
            }
        )
    }

    private fun getDeviceSupport(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            DeviceSupportReq.getReadInstance(),
            ICommandResponse<DeviceSupportFunctionRsp> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            }
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // Heart Rate
    // ─────────────────────────────────────────────────────────────────

    private fun getTodayHeartRate(result: MethodChannel.Result) {
        val done = java.util.concurrent.atomic.AtomicBoolean(false)
        try {
            BleOperateManager.getInstance().getTodayHeartRate(
                object : BleOperateManager.HealthDataCallback<ReadHeartRateRsp> {
                    override fun onSuccess(data: ReadHeartRateRsp?) {
                        if (done.compareAndSet(false, true))
                            mainHandler.post { result.success(if (data != null) gson.toJson(data) else "{}") }
                    }
                    override fun onError(code: Int, message: String?) {
                        if (done.compareAndSet(false, true))
                            mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                    }
                }
            )
        } catch (e: Exception) {
            if (done.compareAndSet(false, true)) {
                mainHandler.post { result.error("SDK_EXCEPTION", e.message, null) }
                return
            }
        }
        mainHandler.postDelayed({
            if (done.compareAndSet(false, true))
                result.error("TIMEOUT", "Heart rate data fetch timed out", null)
        }, 20_000L)
    }

    private fun getHeartRate(call: MethodCall, result: MethodChannel.Result) {
        val dayIndex = call.argument<Int>("dayIndex") ?: 0
        BleOperateManager.getInstance().getHeartRate(
            dayIndex,
            object : BleOperateManager.HealthDataCallback<ReadHeartRateRsp> {
                override fun onSuccess(data: ReadHeartRateRsp) {
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun getHeartRates(call: MethodCall, result: MethodChannel.Result) {
        val startDay = call.argument<Int>("startDay") ?: 0
        val count = call.argument<Int>("count") ?: 1
        BleOperateManager.getInstance().getHeartRates(
            startDay, count,
            object : BleOperateManager.HealthDataCallback<List<BleOperateManager.DayIndexedData<ReadHeartRateRsp>>> {
                override fun onSuccess(data: List<BleOperateManager.DayIndexedData<ReadHeartRateRsp>>) {
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun getHeartRateSetting(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            HeartRateSettingReq.getReadInstance(),
            ICommandResponse<HeartRateSettingRsp> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            }
        )
    }

    private fun setHeartRateSetting(call: MethodCall, result: MethodChannel.Result) {
        val enable = call.argument<Boolean>("enable") ?: true
        val interval = call.argument<Int>("interval") ?: 10
        CommandHandle.getInstance().executeReqCmd(
            HeartRateSettingReq.getWriteInstance(enable, interval, 10, 40, 110),
            ICommandResponse<HeartRateSettingRsp> { _ ->
                mainHandler.post { result.success(true) }
            }
        )
    }

    private fun manualModeHeart(call: MethodCall, result: MethodChannel.Result) {
        val start = call.argument<Boolean>("start") ?: true
        BleOperateManager.getInstance().manualModeHeart(
            ICommandResponse<StartHeartRateRsp> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            },
            !start
        )
    }

    // Single-call measurement: starts HR, waits for a valid (>0) reading,
    // auto-stops, then resolves. Mirrors the test_app RingSdkBridge.readHeartRate().
    private fun readHeartRate(result: MethodChannel.Result) {
        val done = AtomicBoolean(false)

        BleOperateManager.getInstance().manualModeHeart(
            ICommandResponse<StartHeartRateRsp> { rsp ->
                if (done.get()) return@ICommandResponse

                if (rsp.status == BaseRspCmd.RESULT_OK) {
                    val value = if (rsp.getHeartRate() > 0) rsp.getHeartRate() else rsp.getValue()
                    if (value > 0 && done.compareAndSet(false, true)) {
                        BleOperateManager.getInstance().manualModeHeart(null, true) // stop
                        mainHandler.post { result.success(value) }
                    }
                    // value == 0: measurement still warming up — wait for next callback
                } else {
                    if (done.compareAndSet(false, true)) {
                        mainHandler.post { result.success(null) }
                    }
                }
            },
            false // false = start measurement
        )

        // Stop and time out after 60 s so the Dart await never hangs forever
        mainHandler.postDelayed({
            if (done.compareAndSet(false, true)) {
                BleOperateManager.getInstance().manualModeHeart(null, true) // stop
                result.error("TIMEOUT", "Heart rate measurement timed out", null)
            }
        }, 60_000L)
    }

    private fun syncIntervalHeartRate(result: MethodChannel.Result) {
        LargeDataHandler.getInstance().syncIntervalHeartRateWithCallback(
            0,
            object : IIntervalHeartRateCallback {
                override fun readIntervalHeartRate(data: IntervalHeartRateEntity?) {
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
            }
        )
    }

    private fun syncHistoryHeartRate(result: MethodChannel.Result) {
        val nowUtc = System.currentTimeMillis() / 1000L
        CommandHandle.getInstance().executeReqCmd(
            ReadHeartRateReq(nowUtc),
            ICommandResponse<ReadHeartRateRsp> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            }
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // Blood Pressure
    // ─────────────────────────────────────────────────────────────────

    private fun getTodayBloodPressure(result: MethodChannel.Result) {
        val done = AtomicBoolean(false)
        BleOperateManager.getInstance().getTodayBloodPressure(
            object : BleOperateManager.HealthDataCallback<List<BlePressure>> {
                override fun onSuccess(data: List<BlePressure>?) {
                    if (done.compareAndSet(false, true)) {
                        val mapped = (data ?: emptyList()).map { p: BlePressure -> mapOf("sbp" to p.sbp, "dbp" to p.dbp, "time" to p.time) }
                        mainHandler.post { result.success(gson.toJson(mapped)) }
                    }
                }
                override fun onError(code: Int, message: String?) {
                    if (done.compareAndSet(false, true)) {
                        mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                    }
                }
            }
        )
        mainHandler.postDelayed({
            if (done.compareAndSet(false, true)) {
                result.error("TIMEOUT", "Blood pressure data fetch timed out", null)
            }
        }, 30000)
    }

    private fun getBloodPressure(call: MethodCall, result: MethodChannel.Result) {
        val dayIndex = call.argument<Int>("dayIndex") ?: 0
        BleOperateManager.getInstance().getBloodPressure(
            dayIndex,
            object : BleOperateManager.HealthDataCallback<List<BlePressure>> {
                override fun onSuccess(data: List<BlePressure>) {
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun getBloodPressures(call: MethodCall, result: MethodChannel.Result) {
        val startDay = call.argument<Int>("startDay") ?: 0
        val count = call.argument<Int>("count") ?: 1
        BleOperateManager.getInstance().getBloodPressures(
            startDay, count,
            object : BleOperateManager.HealthDataCallback<List<BleOperateManager.DayIndexedData<List<BlePressure>>>> {
                override fun onSuccess(data: List<BleOperateManager.DayIndexedData<List<BlePressure>>>) {
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun getBloodPressureSetting(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            BpSettingReq.getReadInstance(),
            ICommandResponse<BaseRspCmd> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            }
        )
    }

    private fun setBloodPressureSetting(call: MethodCall, result: MethodChannel.Result) {
        val enable = call.argument<Boolean>("enable") ?: true
        val interval = call.argument<Int>("interval") ?: 60
        CommandHandle.getInstance().executeReqCmd(
            BpSettingReq.getWriteInstance(enable, StartEndTimeEntity(9, 0, 18, 0), interval),
            ICommandResponse<BaseRspCmd> { _ ->
                mainHandler.post { result.success(true) }
            }
        )
    }

    private fun manualModeBP(call: MethodCall, result: MethodChannel.Result) {
        val start = call.argument<Boolean>("start") ?: true
        val done = AtomicBoolean(false)
        BleOperateManager.getInstance().manualModeBP(
            ICommandResponse<StartHeartRateRsp> { rsp ->
                val sbp = rsp.getSbp()
                val dbp = rsp.getDbp()
                val shouldRespond = if (start) (sbp > 0 && dbp > 0) else true
                if (shouldRespond && done.compareAndSet(false, true)) {
                    mainHandler.post {
                        result.success(gson.toJson(mapOf(
                            "sbp" to sbp,
                            "dbp" to dbp,
                            "status" to rsp.status
                        )))
                    }
                }
            },
            !start
        )
        if (start) {
            mainHandler.postDelayed({
                if (done.compareAndSet(false, true)) {
                    result.error("TIMEOUT", "Blood pressure measurement timed out", null)
                }
            }, 60000)
        }
    }

    private fun syncBloodPressure(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            SimpleKeyReq(Constants.CMD_BP_TIMING_MONITOR_DATA),
            ICommandResponse<BaseRspCmd> { _ ->
                mainHandler.post { result.success(true) }
            }
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // Blood Oxygen
    // ─────────────────────────────────────────────────────────────────

    private fun getTodayBloodOxygen(result: MethodChannel.Result) {
        val done = AtomicBoolean(false)
        try {
            BleOperateManager.getInstance().getTodayBloodOxygen(
                object : BleOperateManager.HealthDataCallback<BloodOxygenEntity> {
                    override fun onSuccess(data: BloodOxygenEntity?) {
                        if (done.compareAndSet(false, true)) {
                            if (data == null) { mainHandler.post { result.success("{}") }; return }
                            try {
                                val map = mapOf(
                                    "dateStr"   to (data.getDateStr() ?: ""),
                                    "maxArray"  to (data.getMaxArray()  ?: emptyList<Int>()),
                                    "minArray"  to (data.getMinArray()  ?: emptyList<Int>()),
                                    "unix_time" to data.getUnix_time()
                                )
                                mainHandler.post { result.success(gson.toJson(map)) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("PARSE_FAILED", e.message, null) }
                            }
                        }
                    }
                    override fun onError(code: Int, message: String?) {
                        if (done.compareAndSet(false, true)) {
                            mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                        }
                    }
                }
            )
        } catch (e: Exception) {
            if (done.compareAndSet(false, true)) {
                mainHandler.post { result.error("SDK_EXCEPTION", e.message, null) }
                return
            }
        }
        mainHandler.postDelayed({
            if (done.compareAndSet(false, true)) {
                result.error("TIMEOUT", "Blood oxygen data fetch timed out", null)
            }
        }, 30000)
    }

    private fun getBloodOxygen(call: MethodCall, result: MethodChannel.Result) {
        val dayIndex = call.argument<Int>("dayIndex") ?: 0
        BleOperateManager.getInstance().getBloodOxygen(
            dayIndex,
            object : BleOperateManager.HealthDataCallback<BloodOxygenEntity> {
                override fun onSuccess(data: BloodOxygenEntity) {
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun getBloodOxygens(call: MethodCall, result: MethodChannel.Result) {
        val startDay = call.argument<Int>("startDay") ?: 0
        val count = call.argument<Int>("count") ?: 1
        BleOperateManager.getInstance().getBloodOxygens(
            startDay, count,
            object : BleOperateManager.HealthDataCallback<List<BleOperateManager.DayIndexedData<BloodOxygenEntity>>> {
                override fun onSuccess(data: List<BleOperateManager.DayIndexedData<BloodOxygenEntity>>) {
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun getBloodOxygenSetting(result: MethodChannel.Result) {
        val done = AtomicBoolean(false)
        CommandHandle.getInstance().executeReqCmd(
            BloodOxygenSettingReq.getReadInstance(),
            ICommandResponse<BaseRspCmd> { rsp ->
                if (done.compareAndSet(false, true)) {
                    mainHandler.post { result.success(gson.toJson(rsp)) }
                }
            }
        )
        mainHandler.postDelayed({
            if (done.compareAndSet(false, true)) {
                result.error("TIMEOUT", "Blood oxygen setting read timed out", null)
            }
        }, 10000)
    }

    private fun setBloodOxygenSetting(call: MethodCall, result: MethodChannel.Result) {
        val enable = call.argument<Boolean>("enable") ?: true
        val interval = call.argument<Int>("interval") ?: 2
        CommandHandle.getInstance().executeReqCmd(
            BloodOxygenSettingReq.getWriteInstance(enable, interval.toByte()),
            ICommandResponse<BaseRspCmd> { _ ->
                mainHandler.post { result.success(true) }
            }
        )
    }

    private fun manualModeBloodOxygen(call: MethodCall, result: MethodChannel.Result) {
        val start = call.argument<Boolean>("start") ?: true
        val done = AtomicBoolean(false)
        BleOperateManager.getInstance().manualModeSpO2(
            ICommandResponse<StartHeartRateRsp> { rsp ->
                val spo2 = if (rsp.getBloodOxygen() > 0) rsp.getBloodOxygen() else rsp.getValue()
                // For start: skip zero ACK callbacks, wait for actual reading.
                // For stop: respond on first callback regardless.
                val shouldRespond = if (start) spo2 > 0 else true
                if (shouldRespond && done.compareAndSet(false, true)) {
                    mainHandler.post {
                        result.success(gson.toJson(mapOf("spo2" to spo2, "status" to rsp.status)))
                    }
                }
            },
            !start
        )
        // Timeout after 60 s so the Dart await doesn't hang forever
        if (start) {
            mainHandler.postDelayed({
                if (done.compareAndSet(false, true)) {
                    result.error("TIMEOUT", "SpO2 measurement timed out", null)
                }
            }, 60000)
        }
    }

    private fun syncIntervalBloodOxygen(result: MethodChannel.Result) {
        LargeDataHandler.getInstance().syncIntervalBloodOxygenWithCallback(0) { data ->
            mainHandler.post { result.success(gson.toJson(data)) }
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // Steps
    // ─────────────────────────────────────────────────────────────────

    private fun getTodaySteps(result: MethodChannel.Result) {
        val done = AtomicBoolean(false)
        try {
            BleOperateManager.getInstance().getTodayStepDetail(
                object : BleOperateManager.HealthDataCallback<List<BleStepDetails>> {
                    override fun onSuccess(data: List<BleStepDetails>) {
                        if (done.compareAndSet(false, true))
                            mainHandler.post { result.success(gson.toJson(data ?: emptyList<BleStepDetails>())) }
                    }
                    override fun onError(code: Int, message: String?) {
                        if (done.compareAndSet(false, true))
                            mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                    }
                }
            )
        } catch (e: Exception) {
            if (done.compareAndSet(false, true))
                mainHandler.post { result.error("SDK_EXCEPTION", e.message, null) }
        }
    }

    private fun getSteps(call: MethodCall, result: MethodChannel.Result) {
        val dayIndex = call.argument<Int>("dayIndex") ?: 0
        BleOperateManager.getInstance().getStepDetail(
            dayIndex,
            object : BleOperateManager.HealthDataCallback<List<BleStepDetails>> {
                override fun onSuccess(data: List<BleStepDetails>) {
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun getStepsList(call: MethodCall, result: MethodChannel.Result) {
        val startDay = call.argument<Int>("startDay") ?: 0
        val count = call.argument<Int>("count") ?: 1
        BleOperateManager.getInstance().getStepDetails(
            startDay, count,
            object : BleOperateManager.HealthDataCallback<List<BleOperateManager.DayIndexedData<List<BleStepDetails>>>> {
                override fun onSuccess(data: List<BleOperateManager.DayIndexedData<List<BleStepDetails>>>) {
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun syncTodaySteps(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            SimpleKeyReq(Constants.CMD_GET_STEP_TODAY),
            ICommandResponse<BaseRspCmd> { _ ->
                mainHandler.post { result.success(true) }
            }
        )
    }

    private fun syncStepDetails(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            ReadDetailSportDataReq(0, 0, 95),
            ICommandResponse<ReadDetailSportDataRsp> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            }
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // Sleep
    // ─────────────────────────────────────────────────────────────────

    // Serialise via getters so Gson reflection issues with obfuscated
    // inner-class fields (SleepDataBean showing as {}) are bypassed.
    private fun sleepDisplayToMap(data: SleepDisplay): Map<String, Any?> {
        val segments = data.list?.map { bean ->
            mapOf(
                "sleepStart" to bean.sleepStart,
                "sleepEnd"   to bean.sleepEnd,
                "type"       to bean.type
            )
        } ?: emptyList<Map<String, Any?>>()
        return mapOf(
            "totalSleepDuration" to data.totalSleepDuration,
            "deepDuration"       to data.deepSleepDuration,
            "lightDuration"      to data.shallowSleepDuration,
            "remDuration"        to data.rapidDuration,
            "awakeDuration"      to data.awakeDuration,
            "sleepTime"          to data.sleepTime,
            "wakeTime"           to data.wakeTime,
            "wakingCount"        to data.wakingCount,
            "fallSleepMin"       to data.fallSleepMin,
            "list"               to segments
        )
    }

    private fun sleepNewProtoToMap(data: SleepNewProtoResp): Map<String, Any?> {
        val segments = data.list?.map { bean ->
            mapOf("d" to bean.d, "t" to bean.t)
        } ?: emptyList<Map<String, Any?>>()
        return mapOf(
            "st"          to data.st,
            "et"          to data.et,
            "lunchBreak"  to data.isLunchBreak,
            "lunchSt"     to data.lunchSt,
            "lunchEt"     to data.lunchEt,
            "list"        to segments
        )
    }

    private fun getTodaySleep(result: MethodChannel.Result) {
        val done = AtomicBoolean(false)
        try {
            BleOperateManager.getInstance().getTodaySleep(
                object : BleOperateManager.HealthDataCallback<SleepDisplay> {
                    override fun onSuccess(data: SleepDisplay?) {
                        if (done.compareAndSet(false, true)) {
                            if (data == null) { mainHandler.post { result.success("{}") }; return }
                            try {
                                val json = gson.toJson(sleepDisplayToMap(data))
                                mainHandler.post { result.success(json) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("PARSE_FAILED", e.message, null) }
                            }
                        }
                    }
                    override fun onError(code: Int, message: String?) {
                        if (done.compareAndSet(false, true))
                            mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                    }
                }
            )
        } catch (e: Exception) {
            if (done.compareAndSet(false, true))
                mainHandler.post { result.error("SDK_EXCEPTION", e.message, null) }
            return
        }
        mainHandler.postDelayed({
            if (done.compareAndSet(false, true))
                result.error("TIMEOUT", "Sleep data fetch timed out", null)
        }, 20_000L)
    }

    private fun getSleep(call: MethodCall, result: MethodChannel.Result) {
        val dayIndex = call.argument<Int>("dayIndex") ?: 0
        BleOperateManager.getInstance().getSleep(
            dayIndex,
            object : BleOperateManager.HealthDataCallback<SleepDisplay> {
                override fun onSuccess(data: SleepDisplay) {
                    try {
                        val json = gson.toJson(sleepDisplayToMap(data))
                        mainHandler.post { result.success(json) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("PARSE_FAILED", e.message, null) }
                    }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun getSleepList(call: MethodCall, result: MethodChannel.Result) {
        val startDay = call.argument<Int>("startDay") ?: 0
        val count = call.argument<Int>("count") ?: 1
        BleOperateManager.getInstance().getSleeps(
            startDay, count,
            object : BleOperateManager.HealthDataCallback<List<BleOperateManager.DayIndexedData<SleepDisplay>>> {
                override fun onSuccess(data: List<BleOperateManager.DayIndexedData<SleepDisplay>>) {
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun syncSleep(result: MethodChannel.Result) {
        LargeDataHandler.getInstance().syncSleepList(
            0,
            object : ILargeDataSleepResponse {
                override fun sleepData(p0: SleepDisplay?) {
                    val json = if (p0 != null) gson.toJson(sleepDisplayToMap(p0)) else "{}"
                    mainHandler.post { result.success(json) }
                }
            },
            object : ILargeDataLaunchSleepResponse {
                override fun sleepData(p0: SleepNewProtoResp?) {
                    val json = if (p0 != null) gson.toJson(sleepNewProtoToMap(p0)) else "{}"
                    mainHandler.post { result.success(json) }
                }
            }
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // HRV
    // ─────────────────────────────────────────────────────────────────

    private fun getTodayHrv(result: MethodChannel.Result) {
        val done = java.util.concurrent.atomic.AtomicBoolean(false)
        try {
            BleOperateManager.getInstance().getTodayHrv(
                object : BleOperateManager.HealthDataCallback<HRVRsp> {
                    override fun onSuccess(data: HRVRsp?) {
                        if (done.compareAndSet(false, true))
                            mainHandler.post { result.success(if (data != null) gson.toJson(data) else "{}") }
                    }
                    override fun onError(code: Int, message: String?) {
                        if (done.compareAndSet(false, true))
                            mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                    }
                }
            )
        } catch (e: Exception) {
            if (done.compareAndSet(false, true)) {
                mainHandler.post { result.error("SDK_EXCEPTION", e.message, null) }
                return
            }
        }
        mainHandler.postDelayed({
            if (done.compareAndSet(false, true))
                result.error("TIMEOUT", "HRV data fetch timed out", null)
        }, 20_000L)
    }

    private fun getHrv(call: MethodCall, result: MethodChannel.Result) {
        val dayIndex = call.argument<Int>("dayIndex") ?: 0
        BleOperateManager.getInstance().getHrv(
            dayIndex,
            object : BleOperateManager.HealthDataCallback<HRVRsp> {
                override fun onSuccess(data: HRVRsp) {
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun getHrvList(call: MethodCall, result: MethodChannel.Result) {
        val startDay = call.argument<Int>("startDay") ?: 0
        val count = call.argument<Int>("count") ?: 1
        BleOperateManager.getInstance().getHrvs(
            startDay, count,
            object : BleOperateManager.HealthDataCallback<List<BleOperateManager.DayIndexedData<HRVRsp>>> {
                override fun onSuccess(data: List<BleOperateManager.DayIndexedData<HRVRsp>>) {
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun getHrvSetting(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            HrvSettingReq.getReadInstance(),
            ICommandResponse<BaseRspCmd> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            }
        )
    }

    private fun setHrvSetting(call: MethodCall, result: MethodChannel.Result) {
        val enable = call.argument<Boolean>("enable") ?: true
        CommandHandle.getInstance().executeReqCmd(
            HrvSettingReq.getWriteInstance(enable),
            ICommandResponse<BaseRspCmd> { _ ->
                mainHandler.post { result.success(true) }
            }
        )
    }

    private fun syncHrv(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            HRVReq(0),
            ICommandResponse<HRVRsp> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            }
        )
    }

    private fun manualModeHrv(call: MethodCall, result: MethodChannel.Result) {
        val start = call.argument<Boolean>("start") ?: true
        val done = AtomicBoolean(false)
        BleOperateManager.getInstance().manualModeHrv(
            ICommandResponse<StartHeartRateRsp> { rsp ->
                // HRV comes back through the dedicated getHrv() field, not the generic
                // getValue() field used by HR/SpO2/BP/Stress — confirmed against the SDK
                // sample (HrvActivity.kt) and the bundled SDK's StartHeartRateRsp class.
                val value = if (rsp.getHrv() > 0) rsp.getHrv() else rsp.getValue()
                val shouldRespond = if (start) value > 0 else true
                if (shouldRespond && done.compareAndSet(false, true)) {
                    mainHandler.post {
                        result.success(gson.toJson(mapOf("value" to value, "status" to rsp.status)))
                    }
                }
            },
            !start
        )
        if (start) {
            mainHandler.postDelayed({
                if (done.compareAndSet(false, true)) {
                    result.error("TIMEOUT", "HRV measurement timed out", null)
                }
            }, 60000)
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // Pressure (Stress)
    // ─────────────────────────────────────────────────────────────────

    private fun getTodayPressure(result: MethodChannel.Result) {
        val done = java.util.concurrent.atomic.AtomicBoolean(false)
        BleOperateManager.getInstance().getTodayPressure(
            object : BleOperateManager.HealthDataCallback<PressureRsp> {
                override fun onSuccess(data: PressureRsp?) {
                    if (done.compareAndSet(false, true))
                        mainHandler.post { result.success(if (data != null) gson.toJson(data) else "{}") }
                }
                override fun onError(code: Int, message: String?) {
                    if (done.compareAndSet(false, true))
                        mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
        mainHandler.postDelayed({
            if (done.compareAndSet(false, true))
                result.error("TIMEOUT", "Pressure data fetch timed out", null)
        }, 20_000L)
    }

    private fun getPressure(call: MethodCall, result: MethodChannel.Result) {
        val dayIndex = call.argument<Int>("dayIndex") ?: 0
        BleOperateManager.getInstance().getPressure(
            dayIndex,
            object : BleOperateManager.HealthDataCallback<PressureRsp> {
                override fun onSuccess(data: PressureRsp) {
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun getPressureList(call: MethodCall, result: MethodChannel.Result) {
        val startDay = call.argument<Int>("startDay") ?: 0
        val count = call.argument<Int>("count") ?: 1
        BleOperateManager.getInstance().getPressures(
            startDay, count,
            object : BleOperateManager.HealthDataCallback<List<BleOperateManager.DayIndexedData<PressureRsp>>> {
                override fun onSuccess(data: List<BleOperateManager.DayIndexedData<PressureRsp>>) {
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun getPressureSetting(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            PressureSettingReq.getReadInstance(),
            ICommandResponse<BaseRspCmd> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            }
        )
    }

    private fun setPressureSetting(call: MethodCall, result: MethodChannel.Result) {
        val enable = call.argument<Boolean>("enable") ?: true
        CommandHandle.getInstance().executeReqCmd(
            PressureSettingReq.getWriteInstance(enable),
            ICommandResponse<BaseRspCmd> { _ ->
                mainHandler.post { result.success(true) }
            }
        )
    }

    private fun syncPressure(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            PressureReq(0),
            ICommandResponse<PressureRsp> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            }
        )
    }

    private fun manualModePressure(call: MethodCall, result: MethodChannel.Result) {
        val start = call.argument<Boolean>("start") ?: true
        val done = AtomicBoolean(false)
        BleOperateManager.getInstance().manualModePressure(
            ICommandResponse<StartHeartRateRsp> { rsp ->
                val value = rsp.getValue()
                val shouldRespond = if (start) value > 0 else true
                if (shouldRespond && done.compareAndSet(false, true)) {
                    mainHandler.post {
                        result.success(gson.toJson(mapOf("value" to value, "status" to rsp.status)))
                    }
                }
            },
            !start
        )
        if (start) {
            mainHandler.postDelayed({
                if (done.compareAndSet(false, true)) {
                    result.error("TIMEOUT", "Pressure measurement timed out", null)
                }
            }, 60000)
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // Temperature
    // ─────────────────────────────────────────────────────────────────

    // Fetches today's interval temperature using BleOperateManager.getTemperatures (day 0, count 1)
    private fun getTodayTemperature(result: MethodChannel.Result) {
        BleOperateManager.getInstance().getTemperatures(
            0, 1,
            object : BleOperateManager.HealthDataCallback<List<BleOperateManager.DayIndexedData<IntervalTemperatureEntity>>> {
                override fun onSuccess(data: List<BleOperateManager.DayIndexedData<IntervalTemperatureEntity>>) {
                    val entity = data.firstOrNull()?.data
                    mainHandler.post { result.success(gson.toJson(entity)) }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun getTemperature(call: MethodCall, result: MethodChannel.Result) {
        val dayIndex = call.argument<Int>("dayIndex") ?: 0
        BleOperateManager.getInstance().getTemperatures(
            dayIndex, 1,
            object : BleOperateManager.HealthDataCallback<List<BleOperateManager.DayIndexedData<IntervalTemperatureEntity>>> {
                override fun onSuccess(data: List<BleOperateManager.DayIndexedData<IntervalTemperatureEntity>>) {
                    val entity = data.firstOrNull()?.data
                    mainHandler.post { result.success(gson.toJson(entity)) }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun getTemperatureList(call: MethodCall, result: MethodChannel.Result) {
        val startDay = call.argument<Int>("startDay") ?: 0
        val count = call.argument<Int>("count") ?: 1
        BleOperateManager.getInstance().getTemperatures(
            startDay, count,
            object : BleOperateManager.HealthDataCallback<List<BleOperateManager.DayIndexedData<IntervalTemperatureEntity>>> {
                override fun onSuccess(data: List<BleOperateManager.DayIndexedData<IntervalTemperatureEntity>>) {
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun getTemperatureSetting(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            TemperatureSettingReq.getReadInstance(),
            ICommandResponse<BaseRspCmd> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            }
        )
    }

    private fun setTemperatureSetting(call: MethodCall, result: MethodChannel.Result) {
        val enable = call.argument<Boolean>("enable") ?: true
        val interval = call.argument<Int>("interval") ?: 2
        CommandHandle.getInstance().executeReqCmd(
            TemperatureSettingReq.getWriteInstance(enable, interval.toByte()),
            ICommandResponse<BaseRspCmd> { _ ->
                mainHandler.post { result.success(true) }
            }
        )
    }

    // Syncs continuous body temperature via FileHandle; waits for onUpdateTemperature callback.
    private fun syncAutoTemperature(result: MethodChannel.Result) {
        val done = AtomicBoolean(false)
        Log.d("TempSync", "syncAutoTemperature: starting clearCallback+registerCallback+initRegister+startObtainTemperatureSeries(2)")
        val timeoutRunnable = Runnable {
            if (done.compareAndSet(false, true)) {
                Log.e("TempSync", "syncAutoTemperature: TIMED OUT after 30s — onUpdateTemperature never fired")
                FileHandle.getInstance().clearCallback()
                result.error("TIMEOUT", "Temperature auto sync timed out — ring did not send data", null)
            }
        }
        FileHandle.getInstance().clearCallback()
        FileHandle.getInstance().registerCallback(object : SimpleCallback() {
            override fun onUpdateTemperature(data: TemperatureEntity) {
                Log.d("TempSync", "syncAutoTemperature: onUpdateTemperature fired, data=${gson.toJson(data)}")
                if (done.compareAndSet(false, true)) {
                    mainHandler.removeCallbacks(timeoutRunnable)
                    FileHandle.getInstance().clearCallback()
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
            }
            override fun onUpdateTemperatureList(array: MutableList<TemperatureOnceEntity>?) {
                Log.d("TempSync", "syncAutoTemperature: onUpdateTemperatureList fired size=${array?.size ?: 0}")
                if (done.compareAndSet(false, true)) {
                    mainHandler.removeCallbacks(timeoutRunnable)
                    FileHandle.getInstance().clearCallback()
                    mainHandler.post { result.success(gson.toJson(array)) }
                }
            }
            override fun onActionResult(type: Int, errCode: Int) {
                Log.d("TempSync", "syncAutoTemperature: onActionResult type=$type errCode=$errCode")
                if (errCode != 0 && done.compareAndSet(false, true)) {
                    mainHandler.removeCallbacks(timeoutRunnable)
                    FileHandle.getInstance().clearCallback()
                    mainHandler.post {
                        result.error("ACTION_FAILED", "Ring rejected: type=$type errCode=$errCode", null)
                    }
                }
            }
        })
        // NOTE: initRegister() is for file UPLOAD (watch faces). Temperature sync does NOT use it —
        // calling it puts the ring in file-receive mode and blocks startObtainTemperatureSeries.
        Log.d("TempSync", "syncAutoTemperature: calling startObtainTemperatureSeries(2)")
        FileHandle.getInstance().startObtainTemperatureSeries(2)
        mainHandler.postDelayed(timeoutRunnable, 30_000L)
    }

    // Syncs manual/single temperature readings via FileHandle; waits for onUpdateTemperatureList.
    private fun syncManualTemperature(result: MethodChannel.Result) {
        val done = AtomicBoolean(false)
        Log.d("TempSync", "syncManualTemperature: starting clearCallback+registerCallback+initRegister+startObtainTemperatureOnce(0)")
        val timeoutRunnable = Runnable {
            if (done.compareAndSet(false, true)) {
                Log.e("TempSync", "syncManualTemperature: TIMED OUT after 30s — onUpdateTemperatureList never fired")
                FileHandle.getInstance().clearCallback()
                result.error("TIMEOUT", "Temperature manual sync timed out — ring did not send data", null)
            }
        }
        FileHandle.getInstance().clearCallback()
        FileHandle.getInstance().registerCallback(object : SimpleCallback() {
            override fun onUpdateTemperatureList(array: MutableList<TemperatureOnceEntity>?) {
                Log.d("TempSync", "syncManualTemperature: onUpdateTemperatureList fired size=${array?.size ?: 0}")
                if (done.compareAndSet(false, true)) {
                    mainHandler.removeCallbacks(timeoutRunnable)
                    FileHandle.getInstance().clearCallback()
                    mainHandler.post { result.success(gson.toJson(array)) }
                }
            }
            override fun onUpdateTemperature(data: TemperatureEntity) {
                Log.d("TempSync", "syncManualTemperature: onUpdateTemperature fired (unexpected for manual)")
                if (done.compareAndSet(false, true)) {
                    mainHandler.removeCallbacks(timeoutRunnable)
                    FileHandle.getInstance().clearCallback()
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
            }
            override fun onActionResult(type: Int, errCode: Int) {
                Log.d("TempSync", "syncManualTemperature: onActionResult type=$type errCode=$errCode")
                if (errCode != 0 && done.compareAndSet(false, true)) {
                    mainHandler.removeCallbacks(timeoutRunnable)
                    FileHandle.getInstance().clearCallback()
                    mainHandler.post {
                        result.error("ACTION_FAILED", "Ring rejected: type=$type errCode=$errCode", null)
                    }
                }
            }
        })
        Log.d("TempSync", "syncManualTemperature: calling startObtainTemperatureOnce(0)")
        FileHandle.getInstance().startObtainTemperatureOnce(0)
        mainHandler.postDelayed(timeoutRunnable, 30_000L)
    }

    // ─────────────────────────────────────────────────────────────────
    // Sport Records
    // ─────────────────────────────────────────────────────────────────

    private fun syncSportRecords(result: MethodChannel.Result) {
        val sportHandle = SportPlusHandle()
        sportHandle.timeFormat = "yyyy-MM-dd HH:mm"
        sportHandle.syncSportPlus { errorCode, _ ->
            mainHandler.post { result.success(errorCode == 0) }
        }
        sportHandle.cmdSummary(0)
    }

    // ─────────────────────────────────────────────────────────────────
    // Notification Settings
    // ─────────────────────────────────────────────────────────────────

    private fun getNotificationSettings(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            SimpleKeyReq(Constants.CMD_GET_ANCS_ON_OFF),
            ICommandResponse<BaseRspCmd> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            }
        )
    }

    private fun setNotificationSetting(call: MethodCall, result: MethodChannel.Result) {
        val req = SetANCSReq().apply {
            setCall(call.argument<Boolean>("call") ?: true)
            setSms(call.argument<Boolean>("sms") ?: true)
            setQq(call.argument<Boolean>("qq") ?: true)
            setWechat(call.argument<Boolean>("wechat") ?: true)
        }
        CommandHandle.getInstance().executeReqCmd(
            req,
            ICommandResponse<BaseRspCmd> { _ ->
                mainHandler.post { result.success(true) }
            }
        )
    }

    private fun getDndSetting(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            DndReq.getReadInstance(),
            ICommandResponse<BaseRspCmd> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            }
        )
    }

    private fun setDndSetting(call: MethodCall, result: MethodChannel.Result) {
        val enable = call.argument<Boolean>("enable") ?: false
        val startH = call.argument<Int>("startHour") ?: 22
        val startM = call.argument<Int>("startMinute") ?: 0
        val endH = call.argument<Int>("endHour") ?: 7
        val endM = call.argument<Int>("endMinute") ?: 0
        CommandHandle.getInstance().executeReqCmd(
            DndReq.getWriteInstance(enable, StartEndTimeEntity(startH, startM, endH, endM)),
            ICommandResponse<BaseRspCmd> { _ ->
                mainHandler.post { result.success(true) }
            }
        )
    }

    private fun getMusicSwitch(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            MusicSwitchReq.getReadInstance(),
            ICommandResponse<BaseRspCmd> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            }
        )
    }

    private fun setMusicSwitch(call: MethodCall, result: MethodChannel.Result) {
        val enable = call.argument<Boolean>("enable") ?: true
        CommandHandle.getInstance().executeReqCmd(
            MusicSwitchReq.getWriteInstance(enable),
            ICommandResponse<BaseRspCmd> { _ ->
                mainHandler.post { result.success(true) }
            }
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // Touch Control
    // ─────────────────────────────────────────────────────────────────

    // appType: 0=close 1=music 2=video 3=muslim 4=ebook 5=camera 6=phone call 7=game 8=heart 9=touch event
    private fun getTouchControlSetting(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            TouchControlReq.getReadInstance(true),
            ICommandResponse<TouchControlResp> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            }
        )
    }

    private fun setTouchControlSetting(call: MethodCall, result: MethodChannel.Result) {
        val enable = call.argument<Boolean>("enable") ?: true
        val strength = call.argument<Int>("strength") ?: 5
        val appType = if (enable) 9 else 0
        CommandHandle.getInstance().executeReqCmd(
            TouchControlReq.getWriteInstance(appType, true, strength),
            ICommandResponse<TouchControlResp> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            }
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // Reminders
    // ─────────────────────────────────────────────────────────────────

    private fun getDrinkReminder(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            ReadDrinkAlarmReq(1),
            ICommandResponse<BaseRspCmd> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            }
        )
    }

    private fun getSedentaryReminder(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            SimpleKeyReq(Constants.CMD_GET_SIT_LONG),
            ICommandResponse<BaseRspCmd> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            }
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // OTA
    // ─────────────────────────────────────────────────────────────────

    private fun startOta(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath") ?: run {
            result.error("INVALID_ARG", "filePath required", null); return
        }
        val dfuHandle = DfuHandle.getInstance()
        dfuHandle.initCallback()
        if (!dfuHandle.checkFile(filePath)) {
            result.error("INVALID_FILE", "Invalid firmware file: $filePath", null); return
        }
        dfuHandle.start(object : DfuHandle.IOpResult {
            override fun onActionResult(type: Int, errCode: Int) {
                if (errCode == DfuHandle.RSP_OK) {
                    when (type) {
                        1 -> dfuHandle.init()
                        2 -> dfuHandle.sendPacket()
                        3 -> dfuHandle.check()
                        4 -> {
                            dfuHandle.endAndRelease()
                            mainHandler.post { result.success(true) }
                        }
                    }
                } else {
                    mainHandler.post {
                        result.error("OTA_FAILED", "type=$type errCode=$errCode", null)
                    }
                }
            }
            override fun onProgress(percent: Int) {
                sendEvent("otaProgress", mapOf("progress" to percent))
            }
        })
    }

    // ─────────────────────────────────────────────────────────────────
    // Local readings (Room, via MeasurementLoopManager's local DB)
    // ─────────────────────────────────────────────────────────────────

    private fun repo() = ReadingRepository.getInstance(context)

    private fun todayBoundsMs(): Pair<Long, Long> {
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val start = today.atStartOfDay(zone).toInstant().toEpochMilli()
        val end = today.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli() - 1
        return start to end
    }

    private fun requireVital(call: MethodCall, result: MethodChannel.Result): Vital? {
        val key = call.argument<String>("vital")
        if (key == null) { result.error("INVALID_ARG", "vital required", null); return null }
        val vital = Vital.fromKey(key)
        if (vital == null) { result.error("INVALID_ARG", "unknown vital $key", null); return null }
        return vital
    }

    private fun getReadings(call: MethodCall, result: MethodChannel.Result) {
        val vital = requireVital(call, result) ?: return
        val fromMs = (call.argument<Number>("fromMs") ?: 0L).toLong()
        val toMs = (call.argument<Number>("toMs") ?: System.currentTimeMillis()).toLong()
        val limit = call.argument<Int>("limit") ?: 1000
        repo().ioScope.launch {
            val json = try {
                when (vital) {
                    Vital.HEART_RATE -> gson.toJson(repo().heartRateBetween(fromMs, toMs, limit))
                    Vital.SPO2 -> gson.toJson(repo().spo2Between(fromMs, toMs, limit))
                    Vital.STRESS -> gson.toJson(repo().stressBetween(fromMs, toMs, limit))
                    Vital.BLOOD_PRESSURE -> gson.toJson(repo().bpBetween(fromMs, toMs, limit))
                    Vital.HRV -> gson.toJson(repo().hrvBetween(fromMs, toMs, limit))
                    Vital.TEMPERATURE -> gson.toJson(repo().temperatureBetween(fromMs, toMs, limit))
                    Vital.STEPS -> gson.toJson(repo().stepsBetween(fromMs, toMs, limit))
                }
            } catch (e: Exception) {
                mainHandler.post { result.error("QUERY_FAILED", e.message, null) }
                return@launch
            }
            mainHandler.post { result.success(json) }
        }
    }

    private fun getTodaySummary(call: MethodCall, result: MethodChannel.Result) {
        val vital = requireVital(call, result) ?: return
        val (dayStart, dayEnd) = todayBoundsMs()
        repo().ioScope.launch {
            val map: Map<String, Any?> = try {
                when (vital) {
                    Vital.HEART_RATE -> {
                        val agg = repo().heartRateAggregate(dayStart, dayEnd)
                        val last = repo().latestHeartRate()
                        mapOf("avg" to agg.avg, "min" to agg.min, "max" to agg.max, "count" to agg.count,
                            "lastValue" to last?.valueBpm, "lastMeasuredAt" to last?.measuredAt)
                    }
                    Vital.SPO2 -> {
                        val agg = repo().spo2Aggregate(dayStart, dayEnd)
                        val last = repo().latestSpo2()
                        mapOf("avg" to agg.avg, "min" to agg.min, "max" to agg.max, "count" to agg.count,
                            "lastValue" to last?.valuePct, "lastMeasuredAt" to last?.measuredAt)
                    }
                    Vital.STRESS -> {
                        val agg = repo().stressAggregate(dayStart, dayEnd)
                        val last = repo().latestStress()
                        mapOf("avg" to agg.avg, "min" to agg.min, "max" to agg.max, "count" to agg.count,
                            "lastValue" to last?.value, "lastMeasuredAt" to last?.measuredAt)
                    }
                    Vital.BLOOD_PRESSURE -> {
                        val agg = repo().bpAggregate(dayStart, dayEnd)
                        val last = repo().latestBloodPressure()
                        mapOf(
                            "avgSbp" to agg.avgSbp, "minSbp" to agg.minSbp, "maxSbp" to agg.maxSbp,
                            "avgDbp" to agg.avgDbp, "minDbp" to agg.minDbp, "maxDbp" to agg.maxDbp,
                            "count" to agg.count,
                            "lastSbp" to last?.systolic, "lastDbp" to last?.diastolic, "lastMeasuredAt" to last?.measuredAt
                        )
                    }
                    Vital.HRV -> {
                        val agg = repo().hrvAggregate(dayStart, dayEnd)
                        val last = repo().latestHrv()
                        mapOf("avg" to agg.avg, "min" to agg.min, "max" to agg.max, "count" to agg.count,
                            "lastValue" to last?.valueMs, "lastMeasuredAt" to last?.measuredAt)
                    }
                    Vital.TEMPERATURE -> {
                        val agg = repo().temperatureAggregate(dayStart, dayEnd)
                        val last = repo().latestTemperature()
                        mapOf("avg" to agg.avg, "min" to agg.min, "max" to agg.max, "count" to agg.count,
                            "lastValue" to last?.valueC, "lastMeasuredAt" to last?.measuredAt)
                    }
                    Vital.STEPS -> {
                        val agg = repo().stepsAggregate(dayStart, dayEnd)
                        mapOf("steps" to agg?.steps, "caloriesKcal" to agg?.caloriesKcal,
                            "distanceM" to agg?.distanceM, "capturedAt" to agg?.capturedAt)
                    }
                }
            } catch (e: Exception) {
                mainHandler.post { result.error("QUERY_FAILED", e.message, null) }
                return@launch
            }
            mainHandler.post { result.success(gson.toJson(map)) }
        }
    }

    private fun getLatestReading(call: MethodCall, result: MethodChannel.Result) {
        val vital = requireVital(call, result) ?: return
        repo().ioScope.launch {
            val json = try {
                when (vital) {
                    Vital.HEART_RATE -> gson.toJson(repo().latestHeartRate())
                    Vital.SPO2 -> gson.toJson(repo().latestSpo2())
                    Vital.STRESS -> gson.toJson(repo().latestStress())
                    Vital.BLOOD_PRESSURE -> gson.toJson(repo().latestBloodPressure())
                    Vital.HRV -> gson.toJson(repo().latestHrv())
                    Vital.TEMPERATURE -> gson.toJson(repo().latestTemperature())
                    Vital.STEPS -> gson.toJson(repo().latestStepsSnapshot())
                }
            } catch (e: Exception) {
                mainHandler.post { result.error("QUERY_FAILED", e.message, null) }
                return@launch
            }
            mainHandler.post { result.success(json) }
        }
    }

    private fun seedDemoData(call: MethodCall, result: MethodChannel.Result) {
        val hoursBack = (call.argument<Number>("hoursBack") ?: 3L).toLong()
        repo().ioScope.launch {
            try {
                repo().seedDemoData(hoursBack)
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.error("SEED_FAILED", e.message, null) }
            }
        }
    }

    // Phase 1 fall-risk read surface — silent-logging only, see FallRiskAnalyzer.
    private fun getFallRiskScore(result: MethodChannel.Result) {
        repo().ioScope.launch {
            val json = try {
                gson.toJson(repo().latestFallRiskLog())
            } catch (e: Exception) {
                mainHandler.post { result.error("QUERY_FAILED", e.message, null) }
                return@launch
            }
            mainHandler.post { result.success(json) }
        }
    }

    private fun getFallRiskLog(call: MethodCall, result: MethodChannel.Result) {
        val fromMs = (call.argument<Number>("fromMs") ?: 0L).toLong()
        val toMs = (call.argument<Number>("toMs") ?: System.currentTimeMillis()).toLong()
        val limit = call.argument<Int>("limit") ?: 500
        repo().ioScope.launch {
            val json = try {
                gson.toJson(repo().fallRiskLogBetween(fromMs, toMs, limit))
            } catch (e: Exception) {
                mainHandler.post { result.error("QUERY_FAILED", e.message, null) }
                return@launch
            }
            mainHandler.post { result.success(json) }
        }
    }

    // Phase 2 fall-event read surface — silent-logging only, see FallMotionDetector.
    private fun getFallEvents(call: MethodCall, result: MethodChannel.Result) {
        val fromMs = (call.argument<Number>("fromMs") ?: 0L).toLong()
        val toMs = (call.argument<Number>("toMs") ?: System.currentTimeMillis()).toLong()
        val limit = call.argument<Int>("limit") ?: 200
        repo().ioScope.launch {
            val json = try {
                gson.toJson(repo().fallEventsBetween(fromMs, toMs, limit))
            } catch (e: Exception) {
                mainHandler.post { result.error("QUERY_FAILED", e.message, null) }
                return@launch
            }
            mainHandler.post { result.success(json) }
        }
    }

    // Dev/testing only — fires the real notification pipeline on demand so the fall-alert
    // flow can be demoed/tested without needing a genuine drop test + concurrent vitals spike.
    private fun simulateFallEvent(result: MethodChannel.Result) {
        val confidence = 0.82f
        val source = "hr_spike"
        repo().ioScope.launch {
            try {
                repo().insertFallEvent(
                    FallEventEntity(
                        confidence = confidence,
                        corroborated = true,
                        corroborationSource = source,
                        metadataJson = gson.toJson(mapOf("simulated" to true)),
                        detectedAt = System.currentTimeMillis(),
                    )
                )
                FallAlertNotifier.notifyFall(context, confidence, source)
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.error("SIMULATE_FAILED", e.message, null) }
            }
        }
    }

    private fun getStepsToday(result: MethodChannel.Result) {
        repo().ioScope.launch {
            val json = try {
                gson.toJson(repo().latestStepsSnapshot())
            } catch (e: Exception) {
                mainHandler.post { result.error("QUERY_FAILED", e.message, null) }
                return@launch
            }
            mainHandler.post { result.success(json) }
        }
    }

    private fun getSyncStatus(result: MethodChannel.Result) {
        repo().ioScope.launch {
            val pending = try { repo().pendingRowCount() } catch (_: Exception) { 0 }
            val status = SupabaseSyncManager.getSyncStatus() + mapOf("pendingRowCount" to pending)
            mainHandler.post { result.success(gson.toJson(status)) }
        }
    }

    private fun getMeasurementCycleHistory(call: MethodCall, result: MethodChannel.Result) {
        val fromMs = (call.argument<Number>("fromMs") ?: 0L).toLong()
        val toMs = (call.argument<Number>("toMs") ?: System.currentTimeMillis()).toLong()
        repo().ioScope.launch {
            val json = try {
                gson.toJson(repo().cyclesBetween(fromMs, toMs))
            } catch (e: Exception) {
                mainHandler.post { result.error("QUERY_FAILED", e.message, null) }
                return@launch
            }
            mainHandler.post { result.success(json) }
        }
    }

    private fun setVitalEnabled(call: MethodCall, result: MethodChannel.Result) {
        val vital = requireVital(call, result) ?: return
        MeasurementConfig.setEnabled(vital, call.argument<Boolean>("enabled") ?: true)
        result.success(true)
    }

    private fun getVitalEnabled(call: MethodCall, result: MethodChannel.Result) {
        val vital = requireVital(call, result) ?: return
        result.success(MeasurementConfig.isEnabled(vital))
    }

    private fun configureSync(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url") ?: run { result.error("INVALID_ARG", "url required", null); return }
        val anonKey = call.argument<String>("anonKey") ?: run { result.error("INVALID_ARG", "anonKey required", null); return }
        val userId = call.argument<String>("userId") ?: run { result.error("INVALID_ARG", "userId required", null); return }
        val accessToken = call.argument<String>("accessToken")
        SupabaseConfig.configure(url, anonKey, userId, accessToken)
        result.success(true)
    }

    // ─────────────────────────────────────────────────────────────────
    // Event helpers
    // ─────────────────────────────────────────────────────────────────

    private fun sendEvent(type: String, data: Map<String, Any>) {
        mainHandler.post {
            eventSink?.success(mapOf("type" to type, "data" to data))
        }
    }

    fun onDestroy() {
        mainHandler.removeCallbacks(connectTimeoutRunnable)
        BleScannerHelper.getInstance().stopScan(context)
        BleOperateManager.getInstance().removeNotifyListener(NOTIFY_KEY)
        EventBus.getDefault().unregister(this)
        if (instance === this) instance = null
    }
}
