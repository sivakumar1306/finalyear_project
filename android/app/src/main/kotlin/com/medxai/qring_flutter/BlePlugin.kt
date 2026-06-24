package com.medxai.qring_flutter

import android.bluetooth.BluetoothDevice
import android.app.Application
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
import com.oudmon.ble.base.communication.bigData.bean.IntervalHeartRateEntity
import com.oudmon.ble.base.communication.bigData.bean.IntervalTemperatureEntity
import com.oudmon.ble.base.communication.bigData.resp.IIntervalHeartRateCallback
import com.oudmon.ble.base.communication.entity.BlePressure
import com.oudmon.ble.base.communication.entity.BleStepDetails
import com.oudmon.ble.base.communication.entity.StartEndTimeEntity
import com.oudmon.ble.base.communication.file.FileHandle
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
import com.oudmon.ble.base.communication.sport.SportPlusHandle
import com.oudmon.ble.base.scan.BleScannerHelper
import com.oudmon.ble.base.scan.ScanRecord
import com.oudmon.ble.base.scan.ScanWrapperCallback
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class BlePlugin(private val context: Context) {

    private val gson = Gson()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private val NOTIFY_KEY = 999
    private var _isConnected = false

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
                            "status" to resultEntity.status
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
            else                         -> result.notImplemented()
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // Scanning
    // ─────────────────────────────────────────────────────────────────

    private fun startScan(call: MethodCall, result: MethodChannel.Result) {
        val filterName = call.argument<String>("filterName") ?: ""
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
        BleScannerHelper.getInstance().stopScan(context)
        BleOperateManager.getInstance().connectDirectly(address)

        var attempts = 0
        val maxAttempts = 60
        val pollRunnable = object : Runnable {
            override fun run() {
                attempts++
                val connected = BleOperateManager.getInstance().isConnected
                if (connected) {
                    _isConnected = true
                    sendEvent("connectionState", mapOf("connected" to true))
                    // Enable BLE notifications for large data (blood oxygen, sleep, etc.)
                    // Must be called after service discovery or large data callbacks never fire.
                    LargeDataHandler.getInstance().initEnable()
                    CommandHandle.getInstance().executeReqCmd(
                        SimpleKeyReq(Constants.CMD_BIND_SUCCESS), null
                    )
                    mainHandler.post { result.success(true) }
                } else if (attempts >= maxAttempts) {
                    mainHandler.post { result.error("TIMEOUT", "Connection timed out", null) }
                } else {
                    mainHandler.postDelayed(this, 1000L)
                }
            }
        }
        mainHandler.postDelayed(pollRunnable, 1000L)
    }

    private fun disconnect(result: MethodChannel.Result) {
        BleOperateManager.getInstance().unBindDevice()
        _isConnected = false
        sendEvent("connectionState", mapOf("connected" to false))
        result.success(null)
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
                        result.success(mapOf("battery" to rsp.batteryValue, "isCharging" to rsp.isCharging))
                    } else {
                        result.error("CMD_FAILED", "status=${rsp.status}", null)
                    }
                }
            }
        )
    }

    private fun getFirmwareVersion(result: MethodChannel.Result) {
        // Firmware version is broadcast by the SDK after connect; return empty until device sends it
        mainHandler.post {
            result.success(mapOf("hardware" to "", "firmware" to "", "model" to ""))
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
        BleOperateManager.getInstance().getTodayHeartRate(
            object : BleOperateManager.HealthDataCallback<ReadHeartRateRsp> {
                override fun onSuccess(data: ReadHeartRateRsp) {
                    if (done.compareAndSet(false, true))
                        mainHandler.post { result.success(gson.toJson(data)) }
                }
                override fun onError(code: Int, message: String?) {
                    if (done.compareAndSet(false, true))
                        mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
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
                override fun onSuccess(data: List<BlePressure>) {
                    if (done.compareAndSet(false, true)) {
                        val mapped = data.map { p: BlePressure -> mapOf("sbp" to p.sbp, "dbp" to p.dbp, "time" to p.time) }
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
        BleOperateManager.getInstance().getTodayBloodOxygen(
            object : BleOperateManager.HealthDataCallback<BloodOxygenEntity> {
                override fun onSuccess(data: BloodOxygenEntity) {
                    if (done.compareAndSet(false, true)) {
                        // Use getters so R8 renames call-site and definition consistently.
                        // Gson on the entity directly uses reflected field names (obfuscated).
                        val map = mapOf(
                            "dateStr"   to data.getDateStr(),
                            "maxArray"  to (data.getMaxArray()  ?: emptyList<Int>()),
                            "minArray"  to (data.getMinArray()  ?: emptyList<Int>()),
                            "unix_time" to data.getUnix_time()
                        )
                        mainHandler.post { result.success(gson.toJson(map)) }
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
        BleOperateManager.getInstance().getTodayStepDetail(
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

    private fun getTodaySleep(result: MethodChannel.Result) {
        BleOperateManager.getInstance().getTodaySleep(
            object : BleOperateManager.HealthDataCallback<SleepDisplay> {
                override fun onSuccess(data: SleepDisplay) {
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun getSleep(call: MethodCall, result: MethodChannel.Result) {
        val dayIndex = call.argument<Int>("dayIndex") ?: 0
        BleOperateManager.getInstance().getSleep(
            dayIndex,
            object : BleOperateManager.HealthDataCallback<SleepDisplay> {
                override fun onSuccess(data: SleepDisplay) {
                    mainHandler.post { result.success(gson.toJson(data)) }
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
                    mainHandler.post { result.success(gson.toJson(p0)) }
                }
            },
            object : ILargeDataLaunchSleepResponse {
                override fun sleepData(p0: SleepNewProtoResp?) {
                    mainHandler.post { result.success(gson.toJson(p0)) }
                }
            }
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // HRV
    // ─────────────────────────────────────────────────────────────────

    private fun getTodayHrv(result: MethodChannel.Result) {
        val done = java.util.concurrent.atomic.AtomicBoolean(false)
        BleOperateManager.getInstance().getTodayHrv(
            object : BleOperateManager.HealthDataCallback<HRVRsp> {
                override fun onSuccess(data: HRVRsp) {
                    if (done.compareAndSet(false, true))
                        mainHandler.post { result.success(gson.toJson(data)) }
                }
                override fun onError(code: Int, message: String?) {
                    if (done.compareAndSet(false, true))
                        mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
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
        BleOperateManager.getInstance().manualModeHrv(
            ICommandResponse<StartHeartRateRsp> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            },
            !start
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // Pressure (Stress)
    // ─────────────────────────────────────────────────────────────────

    private fun getTodayPressure(result: MethodChannel.Result) {
        BleOperateManager.getInstance().getTodayPressure(
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

    private fun getTodayTemperature(result: MethodChannel.Result) {
        BleOperateManager.getInstance().getTodayTemperature(
            object : BleOperateManager.HealthDataCallback<IntervalTemperatureEntity> {
                override fun onSuccess(data: IntervalTemperatureEntity) {
                    mainHandler.post { result.success(gson.toJson(data)) }
                }
                override fun onError(code: Int, message: String?) {
                    mainHandler.post { result.error("CMD_FAILED", message ?: "code=$code", null) }
                }
            }
        )
    }

    private fun getTemperature(call: MethodCall, result: MethodChannel.Result) {
        val dayIndex = call.argument<Int>("dayIndex") ?: 0
        BleOperateManager.getInstance().getTemperature(
            dayIndex,
            object : BleOperateManager.HealthDataCallback<IntervalTemperatureEntity> {
                override fun onSuccess(data: IntervalTemperatureEntity) {
                    mainHandler.post { result.success(gson.toJson(data)) }
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

    private fun syncAutoTemperature(result: MethodChannel.Result) {
        FileHandle.getInstance().startObtainTemperatureSeries(2)
        result.success(true)
    }

    private fun syncManualTemperature(result: MethodChannel.Result) {
        FileHandle.getInstance().startObtainTemperatureOnce(0)
        result.success(true)
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
    // Event helpers
    // ─────────────────────────────────────────────────────────────────

    private fun sendEvent(type: String, data: Map<String, Any>) {
        mainHandler.post {
            eventSink?.success(mapOf("type" to type, "data" to data))
        }
    }

    fun onDestroy() {
        BleScannerHelper.getInstance().stopScan(context)
        BleOperateManager.getInstance().removeNotifyListener(NOTIFY_KEY)
    }
}
