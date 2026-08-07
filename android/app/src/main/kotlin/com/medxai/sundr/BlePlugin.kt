package com.medxai.sundr

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.app.Application
import android.util.Log
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.annotation.SuppressLint
import android.telecom.TelecomManager
import android.media.AudioManager
import android.view.KeyEvent
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
import com.oudmon.ble.base.communication.req.AgpsReq
import com.oudmon.ble.base.communication.req.BaseReqCmd
import com.oudmon.ble.base.communication.req.BatterySavingReq
import com.oudmon.ble.base.communication.req.BloodOxygenSettingReq
import com.oudmon.ble.base.communication.req.BpSettingReq
import com.oudmon.ble.base.communication.req.BrightnessSettingsReq
import com.oudmon.ble.base.communication.req.CameraReq
import com.oudmon.ble.base.communication.req.DeviceSupportReq
import com.oudmon.ble.base.communication.req.DisplayOrientationReq
import com.oudmon.ble.base.communication.req.DisplayStyleReq
import com.oudmon.ble.base.communication.req.DisplayTimeReq
import com.oudmon.ble.base.communication.req.DndReq
import com.oudmon.ble.base.communication.req.FindDeviceReq
import com.oudmon.ble.base.communication.req.HRVReq
import com.oudmon.ble.base.communication.req.HeartRateSettingReq
import com.oudmon.ble.base.communication.req.HrvSettingReq
import com.oudmon.ble.base.communication.req.IntellReq
import com.oudmon.ble.base.communication.req.MusicSwitchReq
import com.oudmon.ble.base.communication.req.MuslimReq
import com.oudmon.ble.base.communication.req.NotificationEventNotifyReq
import com.oudmon.ble.base.communication.req.PalmScreenReq
import com.oudmon.ble.base.communication.req.PressureReq
import com.oudmon.ble.base.communication.req.PressureSettingReq
import com.oudmon.ble.base.communication.req.ReadDetailSportDataReq
import com.oudmon.ble.base.communication.req.ReadDrinkAlarmReq
import com.oudmon.ble.base.communication.req.ReadHeartRateReq
import com.oudmon.ble.base.communication.req.RestoreKeyReq
import com.oudmon.ble.base.communication.req.SetANCSReq
import com.oudmon.ble.base.communication.req.SetTimeReq
import com.oudmon.ble.base.communication.req.SimpleKeyPowerOffReq
import com.oudmon.ble.base.communication.req.SimpleKeyReq
import com.oudmon.ble.base.communication.req.SugarLipidsSettingReq
import com.oudmon.ble.base.communication.req.TargetSettingReq
import com.oudmon.ble.base.communication.req.TimeFormatReq
import com.oudmon.ble.base.communication.req.TouchControlReq
import com.oudmon.ble.base.communication.responseImpl.DeviceNotifyListener
import com.oudmon.ble.base.communication.rsp.AgpsRsp
import com.oudmon.ble.base.communication.rsp.BaseRspCmd
import com.oudmon.ble.base.communication.rsp.BatteryRsp
import com.oudmon.ble.base.communication.rsp.BatterySavingRsp
import com.oudmon.ble.base.communication.rsp.BloodSugarLipidsSettingRsp
import com.oudmon.ble.base.communication.rsp.BrightnessSettingsRsp
import com.oudmon.ble.base.communication.rsp.CameraNotifyRsp
import com.oudmon.ble.base.communication.rsp.DeviceNotifyRsp
import com.oudmon.ble.base.communication.rsp.DeviceSupportFunctionRsp
import com.oudmon.ble.base.communication.rsp.DisplayOrientationRsp
import com.oudmon.ble.base.communication.rsp.DisplayStyleRsp
import com.oudmon.ble.base.communication.rsp.DisplayTimeRsp
import com.oudmon.ble.base.communication.rsp.HRVRsp
import com.oudmon.ble.base.communication.rsp.HeartRateSettingRsp
import com.oudmon.ble.base.communication.rsp.IntellRsp
import com.oudmon.ble.base.communication.rsp.PalmScreenRsp
import com.oudmon.ble.base.communication.rsp.PressureRsp
import com.oudmon.ble.base.communication.rsp.ReadDetailSportDataRsp
import com.oudmon.ble.base.communication.rsp.ReadHeartRateRsp
import com.oudmon.ble.base.communication.rsp.SetTimeRsp
import com.oudmon.ble.base.communication.rsp.SleepNewProtoResp
import com.oudmon.ble.base.communication.rsp.StartHeartRateRsp
import com.oudmon.ble.base.communication.rsp.TargetSettingRsp
import com.oudmon.ble.base.communication.rsp.TimeFormatRsp
import com.oudmon.ble.base.communication.rsp.TouchControlResp
import com.oudmon.ble.base.communication.sport.SportPlusHandle
import com.oudmon.ble.base.scan.BleScannerHelper
import com.oudmon.ble.base.scan.ScanRecord
import com.oudmon.ble.base.scan.ScanWrapperCallback
import com.medxai.sundr.analysis.EmergencyAutoCaller
import com.medxai.sundr.analysis.EmergencySmsSender
import com.medxai.sundr.analysis.FallAlertNotifier
import com.medxai.sundr.analysis.FallMotionDetector
import com.medxai.sundr.analysis.FallPredictionNotifier
import com.medxai.sundr.analysis.SafetyLiveUpdate
import com.medxai.sundr.data.FallEventEntity
import com.medxai.sundr.data.MeasurementConfig
import com.medxai.sundr.data.ReadingRepository
import com.medxai.sundr.data.Vital
import com.medxai.sundr.events.NewReadingEvent
import com.medxai.sundr.sync.SupabaseConfig
import com.medxai.sundr.sync.SupabaseSyncManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.launch
import org.greenrobot.eventbus.EventBus
import org.greenrobot.eventbus.Subscribe
import org.greenrobot.eventbus.ThreadMode
import java.time.LocalDate
import java.time.ZoneId
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.content.ContextCompat
import androidx.core.app.NotificationManagerCompat

class BlePlugin(private val context: Context) {

    companion object {
        private const val TAG = "BlePlugin"
        private const val CONNECT_TIMEOUT_MS = 60_000L
        private const val INIT_COMMAND_DELAY_MS = 400L
        private const val INIT_RETRY_TIMEOUT_MS = 4_000L
        private const val INIT_MAX_ATTEMPTS = 3
        private const val MANUAL_ACQUIRE_POLL_MS = 300L
        private const val MANUAL_ACQUIRE_TIMEOUT_MS = 4_000L
        // How often to re-send ACTION_KEEP_SCREEN_ON while the ring camera UI is active —
        // per the SDK docs, the ring's screen would otherwise dim/sleep on its own.
        private const val CAMERA_KEEP_ALIVE_MS = 2_000L
        // Raw device-notify dataType for the ring's proactive battery/charging push
        // (see SDK section "2.3.9 Changes in Ring measurement data are proactively
        // reported to the APP" — 0x0c carries [reserved, batteryPercent, charging, ...]).
        private const val DATA_TYPE_BATTERY_PUSH = 0x0c

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
    private var pendingBindConfirmation: Runnable? = null
    private val bindConfirmed = AtomicBoolean(false)

    // Populated by QRingBluetoothReceiver.onCharacteristicRead once the SDK broadcasts them.
    var cachedFirmwareVersion: String = ""
    var cachedHardwareVersion: String = ""

    // ── Ring camera / photo control state ──────────────────────────────
    private var cameraKeepAliveRunnable: Runnable? = null
    private var cameraModeActive = false

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
        com.medxai.sundr.sdk.CrashStore.init(context.applicationContext)
        com.medxai.sundr.sdk.BleSdkLifecycle.ensureInitialized(context.applicationContext)
        try {
            registerDeviceListener()
        } catch (e: Exception) {
            Log.e(TAG, "registerDeviceListener failed", e)
        }
        try {
            MeasurementConfig.init(context.applicationContext)
            SupabaseConfig.init(context.applicationContext)
        } catch (e: Exception) {
            Log.e(TAG, "config init failed", e)
        }
        try {
            if (!EventBus.getDefault().isRegistered(this)) {
                EventBus.getDefault().register(this)
            }
        } catch (e: Exception) {
            Log.e(TAG, "EventBus register failed", e)
        }
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
                    try {
                        resultEntity ?: return

                        if (resultEntity.dataType == (Constants.CMD_BIND_SUCCESS.toInt() and 0xFF)) {
                            if (bindConfirmed.compareAndSet(false, true)) {
                                Log.d(TAG, "CMD_BIND_SUCCESS confirmed via raw notify echo")
                                val confirm = pendingBindConfirmation
                                pendingBindConfirmation = null
                                confirm?.let { mainHandler.post(it) }
                            }
                        }

                        if (resultEntity.dataType == DATA_TYPE_BATTERY_PUSH) {
                            val loadData = resultEntity.loadData
                            if (loadData != null && loadData.size >= 3) {
                                val batteryPercent = loadData[1].toInt() and 0xFF
                                val charging = (loadData[2].toInt() and 0xFF) > 0
                                sendEvent(
                                    "batteryPush",
                                    mapOf("batteryPercent" to batteryPercent, "charging" to charging)
                                )
                            }
                        }

                        sendEvent(
                            "deviceNotification",
                            mapOf(
                                "dataType" to resultEntity.dataType,
                                "status" to resultEntity.status,
                                "loadData" to (resultEntity.loadData?.map { it.toInt() and 0xFF } ?: emptyList<Int>())
                            )
                        )
                    } catch (e: Exception) {
                        Log.e(TAG, "onDataResponse failed", e)
                    }
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
            "findDevice"                 -> findDevice(call, result)
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
            "testManualTemperature"      -> testManualTemperature(result)
            "syncSportRecords"           -> syncSportRecords(result)
            "getHealthSettings"          -> getHealthSettings(result)
            "setHealthSettings"          -> setHealthSettings(call, result)
            "getNotificationSettings"    -> getNotificationSettings(result)
            "setNotificationSetting"     -> setNotificationSetting(call, result)
            "getDndSetting"              -> getDndSetting(result)
            "setDndSetting"              -> setDndSetting(call, result)
            "getMusicSwitch"             -> getMusicSwitch(result)
            "setMusicSwitch"             -> setMusicSwitch(call, result)
            "getDisplaySettings"         -> getDisplaySettings(result)
            "setDisplaySetting"          -> setDisplaySetting(call, result)
            "getTargetAndProfile"        -> getTargetAndProfile(result)
            "setTargetAndProfile"        -> setTargetAndProfile(call, result)
            "getAdvancedSettings"        -> getAdvancedSettings(result)
            "setAdvancedSetting"         -> setAdvancedSetting(call, result)
            "getGestureSetting"          -> getGestureSetting(result)
            "setGestureSetting"          -> setGestureSetting(call, result)
            "getTouchControlSetting"     -> getTouchControlSetting(result)
            "setTouchControlSetting"     -> setTouchControlSetting(call, result)
            "answerPhoneCall"            -> answerPhoneCall(result)
            "endOrDeclinePhoneCall"      -> endOrDeclinePhoneCall(result)
            "toggleMediaPlayPause"       -> toggleMediaPlayPause(result)
            "getDrinkReminder"           -> getDrinkReminder(result)
            "getSedentaryReminder"       -> getSedentaryReminder(result)
            "startOta"                   -> startOta(call, result)
            "sendNotification"           -> sendRingNotification(call, result)
            "takePicture"                -> takePicture(result)
            "exitCameraMode"             -> exitCameraMode(result)
            "factoryReset"               -> factoryReset(result)
            "shutDownRing"               -> shutDownRing(result)
            "startForegroundService"     -> {
                com.medxai.sundr.sdk.BleSdkLifecycle.ensureInitialized(context.applicationContext)
                BleConnectionService.start(context)
                result.success(true)
            }
            "getLastNativeCrash"         -> {
                result.success(com.medxai.sundr.sdk.CrashStore.peek())
            }
            "clearLastNativeCrash"       -> {
                com.medxai.sundr.sdk.CrashStore.clear()
                result.success(true)
            }
            "softResetBleSdk"            -> {
                com.medxai.sundr.sdk.BleSdkLifecycle.requestSoftReset("flutter_request")
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
            "getDaySummary"              -> getDaySummary(call, result)
            "getLocalHistory"            -> getLocalHistory(call, result)
            "cacheCloudDaySummary"       -> cacheCloudDaySummary(call, result)
            "getLocalDbStats"            -> getLocalDbStats(result)
            "getLatestReading"           -> getLatestReading(call, result)
            "getStepsToday"              -> getStepsToday(result)
            "saveStepsSnapshot"          -> saveStepsSnapshot(call, result)
            "getSyncStatus"              -> getSyncStatus(result)
            "getMeasurementCycleHistory" -> getMeasurementCycleHistory(call, result)
            "setVitalEnabled"            -> setVitalEnabled(call, result)
            "getVitalEnabled"            -> getVitalEnabled(call, result)
            "setMasterLoopEnabled"       -> {
                MeasurementConfig.setMasterEnabled(call.argument<Boolean>("enabled") ?: true)
                result.success(true)
            }
            "getMasterLoopEnabled"       -> result.success(MeasurementConfig.isMasterEnabled())
            "setCycleCooldownMs"         -> {
                val ms = (call.argument<Number>("ms") ?: 180_000L).toLong()
                MeasurementConfig.setCycleCooldownMs(ms)
                result.success(true)
            }
            "getCycleCooldownMs"         -> result.success(MeasurementConfig.getCycleCooldownMs())
            "setSyncEnabled"             -> {
                MeasurementConfig.setSyncEnabled(call.argument<Boolean>("enabled") ?: true)
                result.success(true)
            }
            "getSyncEnabled"             -> result.success(MeasurementConfig.isSyncEnabled())
            "configureSync"              -> configureSync(call, result)
            "forceSyncNow"               -> result.success(SupabaseSyncManager.forceSyncNow())
            "clearPersonalData"          -> clearPersonalData(result)
            "seedDemoData"               -> seedDemoData(call, result)
            "getFallRiskScore"           -> getFallRiskScore(result)
            "getFallRiskLog"             -> getFallRiskLog(call, result)
            "getFallEvents"              -> getFallEvents(call, result)
            "getPhoneModeSessions"       -> getPhoneModeSessions(call, result)
            "simulateFallEvent"          -> simulateFallEvent(result)
            "postHealthAlert"            -> postHealthAlert(call, result)
            "getEmergencyContacts"       -> getEmergencyContacts(result)
            "addEmergencyContact"        -> addEmergencyContact(call, result)
            "updateEmergencyContact"     -> updateEmergencyContact(call, result)
            "deleteEmergencyContact"     -> deleteEmergencyContact(call, result)
            "simulateFallRiskTrigger"    -> simulateFallRiskTrigger(result)
            "simulateFallPrediction"     -> simulateFallPrediction(result)
            "consumeFallPredictionFlag"  -> consumeFallPredictionFlag(result)
            "clearFallPredictionFlag"    -> clearFallPredictionFlag(result)
            "getEmergencySmsStatus"      -> getEmergencySmsStatus(result)
            "cancelEmergencySms"         -> cancelEmergencySms(result)
            "sendEmergencySms"           -> sendEmergencySms(call, result)
            "getAutoCallOnFallEnabled"   -> getAutoCallOnFallEnabled(result)
            "setAutoCallOnFallEnabled"   -> setAutoCallOnFallEnabled(call, result)
            "placeEmergencyCall"         -> placeEmergencyCall(call, result)
            else                         -> result.notImplemented()
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // Gesture control (PalmScreenReq — wrist-flip / palm-screen wake)
    // ─────────────────────────────────────────────────────────────────

    private fun getGestureSetting(result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            PalmScreenReq.getRingReadInstance(),
            ICommandResponse<PalmScreenRsp> { rsp ->
                mainHandler.post {
                    result.success(
                        gson.toJson(
                            mapOf(
                                "enabled" to rsp.isEnable,
                                "isLeft" to rsp.isLeft
                            )
                        )
                    )
                }
            }
        )
    }

    private fun setGestureSetting(call: MethodCall, result: MethodChannel.Result) {
        val enable = call.argument<Boolean>("enable") ?: true
        val isLeft = call.argument<Boolean>("isLeft") ?: true
        CommandHandle.getInstance().executeReqCmd(
            PalmScreenReq.getWriteInstance(enable, isLeft),
            null
        )
        result.success(true)
    }

    // ─────────────────────────────────────────────────────────────────
    // Ring photo control (camera mode)
    // ─────────────────────────────────────────────────────────────────
    //
    // Flow (per QC Wireless SDK "Ring photo control" section):
    //  1. Tell the ring to enter its camera UI (ACTION_INTO_CAMARA_UI).
    //  2. Keep re-sending ACTION_KEEP_SCREEN_ON every ~2s so the ring's display
    //     stays lit while the phone shows a live camera preview.
    //  3. Listen for CMD_TAKING_PICTURE notifications — the ring reports
    //     ACTION_TAKE_PHOTO when its physical button/gesture is used as a shutter,
    //     and ACTION_FINISH when the ring itself exits the camera UI.
    //  4. On screen close (or ACTION_FINISH from the ring), stop the keep-alive
    //     loop, remove the listener, and tell the ring to exit (ACTION_FINISH).
    //
    // Dart side: BleService.takePicture() enters this mode; BleProvider listens for
    // the "cameraShutter" event (action: "capture" | "exit") to trigger the phone's
    // own camera capture or close the screen; BleService.exitCameraMode() tears it down.

    private val cameraNotifyListener = ICommandResponse<CameraNotifyRsp> { resultEntity ->
        when (resultEntity.action) {
            CameraNotifyRsp.ACTION_TAKE_PHOTO -> sendEvent("cameraShutter", mapOf("action" to "capture"))
            CameraNotifyRsp.ACTION_FINISH -> {
                sendEvent("cameraShutter", mapOf("action" to "exit"))
                stopCameraKeepAlive()
            }
        }
    }

    private fun startCameraKeepAlive() {
        stopCameraKeepAlive()
        val runnable = object : Runnable {
            override fun run() {
                CommandHandle.getInstance().executeReqCmd(CameraReq(CameraReq.ACTION_KEEP_SCREEN_ON), null)
                mainHandler.postDelayed(this, CAMERA_KEEP_ALIVE_MS)
            }
        }
        cameraKeepAliveRunnable = runnable
        mainHandler.post(runnable)
    }

    private fun stopCameraKeepAlive() {
        cameraKeepAliveRunnable?.let { mainHandler.removeCallbacks(it) }
        cameraKeepAliveRunnable = null
    }

    private fun takePicture(result: MethodChannel.Result) {
        if (!cameraModeActive) {
            cameraModeActive = true
            BleOperateManager.getInstance().addNotifyListener(
                Constants.CMD_TAKING_PICTURE.toInt(),
                cameraNotifyListener
            )
        }
        CommandHandle.getInstance().executeReqCmd(CameraReq(CameraReq.ACTION_INTO_CAMARA_UI), null)
        startCameraKeepAlive()
        result.success(true)
    }

    private fun exitCameraMode(result: MethodChannel.Result) {
        stopCameraKeepAlive()
        if (cameraModeActive) {
            BleOperateManager.getInstance().removeNotifyListener(Constants.CMD_TAKING_PICTURE.toInt())
            cameraModeActive = false
        }
        CommandHandle.getInstance().executeReqCmd(CameraReq(CameraReq.ACTION_FINISH), null)
        result.success(true)
    }

    // ─────────────────────────────────────────────────────────────────
    // Scanning
    // ─────────────────────────────────────────────────────────────────

    private fun startScan(call: MethodCall, result: MethodChannel.Result) {
        val filterName = call.argument<String>("filterName") ?: ""

        try {
            val btManager = context.getSystemService(Context.BLUETOOTH_SERVICE)
                    as? android.bluetooth.BluetoothManager
            btManager?.adapter?.bondedDevices?.forEach { device ->
                val name = try { device.name ?: "" } catch (_: SecurityException) { "" }
                if (filterName.isEmpty() || name.contains(filterName, ignoreCase = true)) {
                    sendEvent("scanResult", mapOf("name" to name, "address" to device.address, "rssi" to -80))
                }
            }
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
        try {
            BleScannerHelper.getInstance().stopScan(context)
        } catch (_: Exception) {
        }

        if (com.medxai.sundr.sdk.BleSdkLifecycle.isConnected()) {
            _isConnected = true
            mainHandler.post { result.success(true) }
            return
        }

        mainHandler.removeCallbacks(connectTimeoutRunnable)
        pendingConnectResult = result
        mainHandler.postDelayed(connectTimeoutRunnable, CONNECT_TIMEOUT_MS)
        com.medxai.sundr.sdk.BleSdkLifecycle.connectDirectly(address)
    }

    private fun disconnect(result: MethodChannel.Result) {
        mainHandler.removeCallbacks(connectTimeoutRunnable)
        pendingConnectResult = null
        com.medxai.sundr.sdk.BleSdkLifecycle.unBindDevice()
        _isConnected = false
        sendEvent("connectionState", mapOf("connected" to false))
        result.success(null)
    }

    // ─────────────────────────────────────────────────────────────────
    // Connection lifecycle callbacks (invoked by QRingBluetoothReceiver)
    // ─────────────────────────────────────────────────────────────────

    fun onServiceDiscovered() {
        mainHandler.removeCallbacks(connectTimeoutRunnable)
        _isConnected = true
        sendEvent("connectionState", mapOf("connected" to true))
        MeasurementLoopManager.onRingConnected()

        val result = pendingConnectResult
        pendingConnectResult = null
        result?.let { r -> mainHandler.post { r.success(true) } }

        mainHandler.postDelayed({ readDeviceCapabilityAndPairIfNeeded() }, INIT_COMMAND_DELAY_MS)
    }

    fun onDeviceDisconnected() {
        mainHandler.removeCallbacks(connectTimeoutRunnable)
        pendingConnectResult = null
        _isConnected = false
        sendEvent("connectionState", mapOf("connected" to false))
        MeasurementLoopManager.onRingDisconnected()
    }

    fun onDeviceAddressKnown(address: String) {
        deviceAddress = address
    }

    fun onBondFailed() {
        val fallback = pendingBondFallback
        pendingBondFallback = null
        fallback?.let { mainHandler.post(it) }
    }

    private val prefs by lazy {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    }

    private fun isAlreadyBonded(): Boolean {
        val address = deviceAddress
            ?: prefs.getString("flutter.device_address", "")?.takeIf { it.isNotEmpty() }
            ?: return false
        return try {
            BluetoothAdapter.getDefaultAdapter()?.getRemoteDevice(address)?.bondState == BluetoothDevice.BOND_BONDED
        } catch (_: Exception) {
            false
        }
    }

    private fun readDeviceCapabilityAndPairIfNeeded() {
        CommandHandle.getInstance().executeReqCmd(
            DeviceSupportReq.getReadInstance(),
            ICommandResponse<DeviceSupportFunctionRsp> { rsp ->
                Log.d(TAG, "DeviceSupportReq: supportBlePair=${rsp.supportBlePair}, alreadyBonded=${isAlreadyBonded()}")
                if (rsp.supportBlePair && !isAlreadyBonded()) {
                    Log.d(TAG, "Device requires BLE pairing — calling bleCreateBond(), deferring other init commands")
                    pendingBondFallback = Runnable { sendBindSuccessWithRetry() }
                    BleOperateManager.getInstance().bleCreateBond()
                } else {
                    sendBindSuccessWithRetry()
                }
            }
        )
    }

    private fun sendBindSuccessWithRetry(attempt: Int = 1) {
        bindConfirmed.set(false)

        val timeoutRunnable = Runnable {
            if (!bindConfirmed.get()) {
                pendingBindConfirmation = null
                if (attempt < INIT_MAX_ATTEMPTS) {
                    Log.w(TAG, "CMD_BIND_SUCCESS attempt $attempt: no raw-echo confirmation, retrying")
                    sendBindSuccessWithRetry(attempt + 1)
                } else {
                    Log.e(TAG, "CMD_BIND_SUCCESS: no raw-echo confirmation after $INIT_MAX_ATTEMPTS attempts — proceeding anyway")
                }
            }
        }

        pendingBindConfirmation = Runnable {
            mainHandler.removeCallbacks(timeoutRunnable)
        }
        mainHandler.postDelayed(timeoutRunnable, INIT_RETRY_TIMEOUT_MS)

        CommandHandle.getInstance().executeReqCmd(
            SimpleKeyReq(Constants.CMD_BIND_SUCCESS),
            ICommandResponse<BaseRspCmd> {
                if (bindConfirmed.compareAndSet(false, true)) {
                    Log.d(TAG, "CMD_BIND_SUCCESS confirmed via ICommandResponse (unexpected but fine)")
                    val confirm = pendingBindConfirmation
                    pendingBindConfirmation = null
                    confirm?.let { mainHandler.post(it) }
                }
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

    private fun findDevice(call: MethodCall, result: MethodChannel.Result) {
        CommandHandle.getInstance().executeReqCmd(
            FindDeviceReq(),
            ICommandResponse<BaseRspCmd> { rsp ->
                mainHandler.post {
                    if (rsp.status == BaseRspCmd.RESULT_OK) {
                        result.success(true)
                    } else {
                        result.error("CMD_FAILED", "status=${rsp.status}", null)
                    }
                }
            }
        )
    }

    private fun getFirmwareVersion(result: MethodChannel.Result) {
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
                Log.d("DeviceSupport", gson.toJson(rsp))
                mainHandler.post {
                    result.success(gson.toJson(rsp))
                }
            }
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // Manual measurement coordination
    // ─────────────────────────────────────────────────────────────────

    private fun acquireManualSlot(owner: String, result: MethodChannel.Result, onAcquired: () -> Unit) {
        if (MeasurementCoordinator.tryAcquire(owner)) {
            onAcquired()
            return
        }
        MeasurementCoordinator.manualRequestPending = true
        val deadline = System.currentTimeMillis() + MANUAL_ACQUIRE_TIMEOUT_MS
        fun poll() {
            if (MeasurementCoordinator.tryAcquire(owner)) {
                MeasurementCoordinator.manualRequestPending = false
                onAcquired()
                return
            }
            if (System.currentTimeMillis() >= deadline) {
                MeasurementCoordinator.manualRequestPending = false
                result.error("BUSY", "Another measurement is already in progress. Please try again.", null)
                return
            }
            mainHandler.postDelayed({ poll() }, MANUAL_ACQUIRE_POLL_MS)
        }
        mainHandler.postDelayed({ poll() }, MANUAL_ACQUIRE_POLL_MS)
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
        val owner = "manual"
        fun proceed() {
            try {
                BleOperateManager.getInstance().manualModeHeart(
                    ICommandResponse<StartHeartRateRsp> { rsp ->
                        if (!start) {
                            MeasurementCoordinator.release(owner)
                        }
                        mainHandler.post { result.success(gson.toJson(rsp)) }
                    },
                    !start
                )
            } catch (e: Exception) {
                if (start) {
                    MeasurementCoordinator.release(owner)
                }
                mainHandler.post { result.error("SDK_EXCEPTION", e.message, null) }
            }
        }
        if (start) acquireManualSlot(owner, result) { proceed() } else proceed()
    }

    private fun readHeartRate(result: MethodChannel.Result) {
        val owner = "manual"
        acquireManualSlot(owner, result) {
            val done = AtomicBoolean(false)

            try {
                BleOperateManager.getInstance().manualModeHeart(
                    ICommandResponse<StartHeartRateRsp> { rsp ->
                        if (done.get()) return@ICommandResponse

                        if (rsp.status == BaseRspCmd.RESULT_OK) {
                            val value = if (rsp.getHeartRate() > 0) rsp.getHeartRate() else rsp.getValue()
                            if (value > 0 && done.compareAndSet(false, true)) {
                                try { BleOperateManager.getInstance().manualModeHeart(null, true) } catch (_: Exception) {}
                                MeasurementCoordinator.release(owner)
                                mainHandler.post { result.success(value) }
                            }
                        } else {
                            if (done.compareAndSet(false, true)) {
                                try { BleOperateManager.getInstance().manualModeHeart(null, true) } catch (_: Exception) {}
                                MeasurementCoordinator.release(owner)
                                mainHandler.post { result.success(null) }
                            }
                        }
                    },
                    false
                )
            } catch (e: Exception) {
                if (done.compareAndSet(false, true)) {
                    MeasurementCoordinator.release(owner)
                    mainHandler.post { result.error("SDK_EXCEPTION", e.message, null) }
                }
                return@acquireManualSlot
            }

            mainHandler.postDelayed({
                if (done.compareAndSet(false, true)) {
                    try { BleOperateManager.getInstance().manualModeHeart(null, true) } catch (_: Exception) {}
                    MeasurementCoordinator.release(owner)
                    result.error("TIMEOUT", "Heart rate measurement timed out", null)
                }
            }, 60_000L)
        }
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
        val owner = "manual"
        fun proceed() {
            val done = AtomicBoolean(false)
            try {
                BleOperateManager.getInstance().manualModeBP(
                    ICommandResponse<StartHeartRateRsp> { rsp ->
                        val sbp = rsp.getSbp()
                        val dbp = rsp.getDbp()
                        val shouldRespond = if (start) (sbp > 0 && dbp > 0) else true
                        if (shouldRespond && done.compareAndSet(false, true)) {
                            if (start) MeasurementCoordinator.release(owner)
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
            } catch (e: Exception) {
                if (done.compareAndSet(false, true)) {
                    if (start) MeasurementCoordinator.release(owner)
                    mainHandler.post { result.error("SDK_EXCEPTION", e.message, null) }
                }
                return
            }
            if (start) {
                mainHandler.postDelayed({
                    if (done.compareAndSet(false, true)) {
                        MeasurementCoordinator.release(owner)
                        result.error("TIMEOUT", "Blood pressure measurement timed out", null)
                    }
                }, 60000)
            }
        }
        if (start) acquireManualSlot(owner, result) { proceed() } else proceed()
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
        val owner = "manual"
        fun proceed() {
            val done = AtomicBoolean(false)
            try {
                BleOperateManager.getInstance().manualModeSpO2(
                    ICommandResponse<StartHeartRateRsp> { rsp ->
                        val spo2 = if (rsp.getBloodOxygen() > 0) rsp.getBloodOxygen() else rsp.getValue()
                        val shouldRespond = if (start) spo2 > 0 else true
                        if (shouldRespond && done.compareAndSet(false, true)) {
                            if (start) MeasurementCoordinator.release(owner)
                            mainHandler.post {
                                result.success(gson.toJson(mapOf("spo2" to spo2, "status" to rsp.status)))
                            }
                        }
                    },
                    !start
                )
            } catch (e: Exception) {
                if (done.compareAndSet(false, true)) {
                    if (start) MeasurementCoordinator.release(owner)
                    mainHandler.post { result.error("SDK_EXCEPTION", e.message, null) }
                }
                return
            }
            if (start) {
                mainHandler.postDelayed({
                    if (done.compareAndSet(false, true)) {
                        MeasurementCoordinator.release(owner)
                        result.error("TIMEOUT", "SpO2 measurement timed out", null)
                    }
                }, 60000)
            }
        }
        if (start) acquireManualSlot(owner, result) { proceed() } else proceed()
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
        val owner = "manual"
        fun proceed() {
            val done = AtomicBoolean(false)
            var callbackCount = 0
            try {
                BleOperateManager.getInstance().manualModeHrv(
                    ICommandResponse<StartHeartRateRsp> { rsp ->
                        val value = if (rsp.getHrv() > 0) rsp.getHrv() else rsp.getValue()
                        callbackCount++
                        Log.d(TAG, "manualModeHrv callback #$callbackCount: value=$value status=${rsp.status}")
                        val shouldRespond = if (start) value > 0 else true
                        if (shouldRespond && done.compareAndSet(false, true)) {
                            if (start) MeasurementCoordinator.release(owner)
                            mainHandler.post {
                                result.success(gson.toJson(mapOf("value" to value, "status" to rsp.status)))
                            }
                        }
                    },
                    !start
                )
            } catch (e: Exception) {
                if (done.compareAndSet(false, true)) {
                    if (start) MeasurementCoordinator.release(owner)
                    mainHandler.post { result.error("SDK_EXCEPTION", e.message, null) }
                }
                return
            }
            if (start) {
                mainHandler.postDelayed({
                    if (done.compareAndSet(false, true)) {
                        Log.e(TAG, "manualModeHrv timed out after $callbackCount callback(s), none with a valid value")
                        MeasurementCoordinator.release(owner)
                        result.error("TIMEOUT", "HRV measurement timed out", null)
                    }
                }, 90000)
            }
        }
        if (start) acquireManualSlot(owner, result) { proceed() } else proceed()
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
        val owner = "manual"
        fun proceed() {
            val done = AtomicBoolean(false)
            try {
                BleOperateManager.getInstance().manualModePressure(
                    ICommandResponse<StartHeartRateRsp> { rsp ->
                        val value = rsp.getValue()
                        val shouldRespond = if (start) value > 0 else true
                        if (shouldRespond && done.compareAndSet(false, true)) {
                            if (start) MeasurementCoordinator.release(owner)
                            mainHandler.post {
                                result.success(gson.toJson(mapOf("value" to value, "status" to rsp.status)))
                            }
                        }
                    },
                    !start
                )
            } catch (e: Exception) {
                if (done.compareAndSet(false, true)) {
                    if (start) MeasurementCoordinator.release(owner)
                    mainHandler.post { result.error("SDK_EXCEPTION", e.message, null) }
                }
                return
            }
            if (start) {
                mainHandler.postDelayed({
                    if (done.compareAndSet(false, true)) {
                        MeasurementCoordinator.release(owner)
                        result.error("TIMEOUT", "Pressure measurement timed out", null)
                    }
                }, 60000)
            }
        }
        if (start) acquireManualSlot(owner, result) { proceed() } else proceed()
    }

    // ─────────────────────────────────────────────────────────────────
    // Temperature
    // ─────────────────────────────────────────────────────────────────

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
            SugarLipidsSettingReq.getReadTemperatureInstance(),
            ICommandResponse<BaseRspCmd> { rsp ->
                mainHandler.post { result.success(gson.toJson(rsp)) }
            }
        )
    }

    private fun setTemperatureSetting(call: MethodCall, result: MethodChannel.Result) {
        val enable = call.argument<Boolean>("enable") ?: true
        val interval = call.argument<Int>("interval") ?: 2
        CommandHandle.getInstance().executeReqCmd(
            SugarLipidsSettingReq.getWriteTemperatureInstance(enable, interval),
            ICommandResponse<BaseRspCmd> { _ ->
                mainHandler.post { result.success(true) }
            }
        )
    }

    private fun syncAutoTemperature(result: MethodChannel.Result) {
        val owner = "temperature"
        val MAX_ATTEMPTS = 4
        val ATTEMPT_TIMEOUT_MS = 8_000L

        fun acquireWithRetry(elapsedMs: Long = 0L, onAcquired: () -> Unit) {
            MeasurementCoordinator.manualRequestPending = true
            if (MeasurementCoordinator.tryAcquire(owner)) {
                MeasurementCoordinator.manualRequestPending = false
                onAcquired()
                return
            }
            if (elapsedMs >= 20_000L) {
                MeasurementCoordinator.manualRequestPending = false
                Log.w("TempSync", "syncAutoTemperature: still busy after ${elapsedMs}ms, giving up")
                result.error(
                    "BUSY",
                    "A measurement is already in progress. Please wait a moment and try again.",
                    null
                )
                return
            }
            mainHandler.postDelayed({ acquireWithRetry(elapsedMs + 1000L, onAcquired) }, 1000L)
        }

        fun attempt(attemptNum: Int) {
            acquireWithRetry {
                val done = AtomicBoolean(false)
                Log.d("TempSync", "syncAutoTemperature: attempt $attemptNum/$MAX_ATTEMPTS — clearCallback+registerCallback+startObtainTemperatureSeries(2)")

                fun releaseAndRun(block: () -> Unit) {
                    MeasurementCoordinator.release(owner)
                    block()
                }

                val timeoutRunnable = Runnable {
                    if (done.compareAndSet(false, true)) {
                        FileHandle.getInstance().clearCallback()
                        if (attemptNum < MAX_ATTEMPTS) {
                            Log.w("TempSync", "syncAutoTemperature: attempt $attemptNum timed out after ${ATTEMPT_TIMEOUT_MS}ms — retrying")
                            releaseAndRun { attempt(attemptNum + 1) }
                        } else {
                            Log.e("TempSync", "syncAutoTemperature: TIMED OUT after $MAX_ATTEMPTS attempts — onUpdateTemperature never fired")
                            releaseAndRun { result.error("TIMEOUT", "Temperature auto sync timed out — ring did not send data", null) }
                        }
                    }
                }

                FileHandle.getInstance().clearCallback()
                FileHandle.getInstance().registerCallback(object : SimpleCallback() {
                    override fun onUpdateTemperature(data: TemperatureEntity) {
                        Log.d("TempSync", "syncAutoTemperature: onUpdateTemperature fired on attempt $attemptNum, data=${gson.toJson(data)}")
                        if (done.compareAndSet(false, true)) {
                            mainHandler.removeCallbacks(timeoutRunnable)
                            FileHandle.getInstance().clearCallback()
                            mainHandler.post { releaseAndRun { result.success(gson.toJson(data)) } }
                        }
                    }
                    override fun onUpdateTemperatureList(array: MutableList<TemperatureOnceEntity>?) {
                        Log.d("TempSync", "syncAutoTemperature: onUpdateTemperatureList fired on attempt $attemptNum size=${array?.size ?: 0}")
                        if (done.compareAndSet(false, true)) {
                            mainHandler.removeCallbacks(timeoutRunnable)
                            FileHandle.getInstance().clearCallback()
                            mainHandler.post { releaseAndRun { result.success(gson.toJson(array)) } }
                        }
                    }
                    override fun onActionResult(type: Int, errCode: Int) {
                        Log.d("TempSync", "syncAutoTemperature: onActionResult attempt $attemptNum type=$type errCode=$errCode")
                        if (errCode != 0 && done.compareAndSet(false, true)) {
                            mainHandler.removeCallbacks(timeoutRunnable)
                            FileHandle.getInstance().clearCallback()
                            if (attemptNum < MAX_ATTEMPTS) {
                                Log.w("TempSync", "syncAutoTemperature: attempt $attemptNum rejected (errCode=$errCode) — retrying")
                                releaseAndRun { attempt(attemptNum + 1) }
                            } else {
                                releaseAndRun {
                                    result.error("ACTION_FAILED", "Ring rejected: type=$type errCode=$errCode", null)
                                }
                            }
                        }
                    }
                })

                FileHandle.getInstance().initRegister()
                FileHandle.getInstance().startObtainTemperatureSeries(2)
                mainHandler.postDelayed(timeoutRunnable, ATTEMPT_TIMEOUT_MS)
            }
        }

        attempt(1)
    }

    private fun syncManualTemperature(result: MethodChannel.Result) {
        // Live single temperature measurement. The old implementation used the
        // file-pull path (startObtainTemperatureOnce), which only downloads readings
        // the ring already recorded and produced the "onUpdateTemperatureList never
        // fired" timeouts. The SDK's dedicated live API is
        // BleOperateManager.manualTemperature() — raw value is degrees Celsius × 10
        // (365 → 36.5 °C), same scaling the file-pull TemperatureOnceEntity used.
        // Mirrors readHeartRate()'s wait-for-value + stop pattern, including the
        // coordinator acquire/release so it can't collide with the auto loop.
        val owner = "temperature"
        acquireManualSlot(owner, result) {
            val done = AtomicBoolean(false)

            try {
                BleOperateManager.getInstance().manualTemperature(
                    ICommandResponse<StartHeartRateRsp> { rsp ->
                        if (done.get()) return@ICommandResponse

                        val tempRaw = rsp.getTemperature()
                        val valueRaw = rsp.getValue()
                        Log.d("TempSync", "syncManualTemperature: status=${rsp.status} tempRaw=$tempRaw valueRaw=$valueRaw")

                        val raw = if (tempRaw > 0) tempRaw else valueRaw
                        if (raw > 0 && done.compareAndSet(false, true)) {
                            try { BleOperateManager.getInstance().manualTemperature(null, true) } catch (_: Exception) {}
                            MeasurementCoordinator.release(owner)

                            val tempC = raw / 10.0
                            // Persist to Room and broadcast NewReadingEvent so the Dart
                            // side refreshes today's summary and pushes the reading to
                            // Health Connect — mirrors MeasurementLoopManager.persist().
                            repo().ioScope.launch {
                                val cycleId = repo().startCycle()
                                val id = repo().insertTemperature(tempC, cycleId, "manual")
                                repo().completeCycle(cycleId, "COMPLETED", null)
                                EventBus.getDefault().post(
                                    NewReadingEvent(Vital.TEMPERATURE, id, cycleId, System.currentTimeMillis(), tempC)
                                )
                            }

                            val json = gson.toJson(
                                listOf(
                                    mapOf(
                                        "mTime" to System.currentTimeMillis() / 1000L,
                                        "mValue" to raw
                                    )
                                )
                            )
                            mainHandler.post { result.success(json) }
                        }
                    },
                    false
                )
            } catch (e: Exception) {
                Log.e("TempSync", "syncManualTemperature threw", e)
                if (done.compareAndSet(false, true)) {
                    try { BleOperateManager.getInstance().manualTemperature(null, true) } catch (_: Exception) {}
                    MeasurementCoordinator.release(owner)
                    mainHandler.post { result.error("SDK_EXCEPTION", e.message, null) }
                }
                return@acquireManualSlot
            }

            mainHandler.postDelayed({
                if (done.compareAndSet(false, true)) {
                    Log.w("TempSync", "syncManualTemperature: timed out after 60s")
                    try { BleOperateManager.getInstance().manualTemperature(null, true) } catch (_: Exception) {}
                    MeasurementCoordinator.release(owner)
                    result.error("TIMEOUT", "Temperature measurement timed out — keep the ring on your finger", null)
                }
            }, 60_000L)
        }
    }

    private fun testManualTemperature(result: MethodChannel.Result) {
        val done = AtomicBoolean(false)
        var callbackCount = 0

        Log.d("TempPOC", "testManualTemperature: calling BleOperateManager.manualTemperature(cb, false)")

        try {
            BleOperateManager.getInstance().manualTemperature(
                ICommandResponse<StartHeartRateRsp> { rsp ->
                    if (done.get()) return@ICommandResponse
                    callbackCount++

                    val tempRaw = rsp.getTemperature()
                    val valueRaw = rsp.getValue()
                    val status = rsp.status

                    Log.d("TempPOC", "testManualTemperature callback #$callbackCount: " +
                            "status=$status, getTemperature()=$tempRaw, getValue()=$valueRaw")

                    val rawValue = if (tempRaw > 0) tempRaw else valueRaw

                    if (rawValue > 0 && done.compareAndSet(false, true)) {
                        val tempC = rawValue / 10.0
                        Log.d("TempPOC", "testManualTemperature: SUCCESS rawValue=$rawValue tempC=$tempC — stopping sensor")

                        try {
                            BleOperateManager.getInstance().manualTemperature(null, true)
                        } catch (_: Exception) {}

                        val json = gson.toJson(mapOf(
                            "temperature" to tempC,
                            "rawValue" to rawValue,
                            "getTemperature" to tempRaw,
                            "getValue" to valueRaw,
                            "status" to status,
                            "source" to "manualTemperature_POC",
                            "callbackCount" to callbackCount
                        ))
                        mainHandler.post { result.success(json) }
                    }
                },
                false
            )
        } catch (e: Exception) {
            Log.e("TempPOC", "testManualTemperature: SDK call threw exception", e)
            if (done.compareAndSet(false, true)) {
                mainHandler.post {
                    result.error("SDK_EXCEPTION", "manualTemperature() threw: ${e.message}", e.stackTraceToString())
                }
            }
            return
        }

        mainHandler.postDelayed({
            if (done.compareAndSet(false, true)) {
                Log.e("TempPOC", "testManualTemperature: TIMED OUT after 60s ($callbackCount callbacks, none with value > 0)")
                try {
                    BleOperateManager.getInstance().manualTemperature(null, true)
                } catch (_: Exception) {}
                mainHandler.post {
                    result.error("TIMEOUT", "manualTemperature timed out after 60s ($callbackCount callbacks received, none with value > 0)", null)
                }
            }
        }, 60_000L)
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
    // Ring display settings (brightness / clock style / time format /
    // orientation / screen-on duration) — real SDK reads & writes
    // ─────────────────────────────────────────────────────────────────

    private fun <T : BaseRspCmd> readSetting(
        req: BaseReqCmd,
        rspClass: Class<T>,
        onDone: (T?) -> Unit
    ) {
        try {
            CommandHandle.getInstance().executeReqCmd(
                req,
                ICommandResponse<T> { rsp ->
                    mainHandler.post { onDone(rsp) }
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "readSetting error: ${e.message}")
            mainHandler.post { onDone(null) }
        }
    }

    private fun getDisplaySettings(result: MethodChannel.Result) {
        val out = HashMap<String, Any?>()
        readSetting(BrightnessSettingsReq.getReadInstance(), BrightnessSettingsRsp::class.java) { b ->
            if (b != null) out["brightness"] = b.level
            readSetting(DisplayStyleReq.getReadInstance(), DisplayStyleRsp::class.java) { s ->
                if (s != null) out["clockStyle"] = s.styleIndex
                readSetting(DisplayTimeReq.getReadInstance(), DisplayTimeRsp::class.java) { t ->
                    if (t != null) out["screenOnDuration"] = t.displayTime
                    readSetting(DisplayOrientationReq.getReadInstance(), DisplayOrientationRsp::class.java) { o ->
                        if (o != null) out["orientation"] = if (o.isLeft) 0 else 1
                        readSetting(TimeFormatReq.getReadInstance(), TimeFormatRsp::class.java) { f ->
                            if (f != null) out["is24h"] = f.is24
                            mainHandler.post { result.success(gson.toJson(out)) }
                        }
                    }
                }
            }
        }
    }

    private fun setDisplaySetting(call: MethodCall, result: MethodChannel.Result) {
        val m = try {
            gson.fromJson(call.argument<String>("data"), Map::class.java)
        } catch (e: Exception) {
            Log.e(TAG, "setDisplaySetting parse error: ${e.message}")
            null
        } ?: run { result.success(false); return }
        (m["brightness"] as? Number)?.let { v ->
            CommandHandle.getInstance().executeReqCmd(BrightnessSettingsReq.getWriteInstance(v.toInt()), null)
        }
        (m["clockStyle"] as? Number)?.let { v ->
            CommandHandle.getInstance().executeReqCmd(DisplayStyleReq.getWriteInstance(v.toInt()), null)
        }
        (m["is24h"] as? Boolean)?.let { v ->
            CommandHandle.getInstance().executeReqCmd(TimeFormatReq.getWriteInstance(v, 1), null)
        }
        (m["orientation"] as? Number)?.let { v ->
            CommandHandle.getInstance().executeReqCmd(
                DisplayOrientationReq.getWriteInstance(true, v.toInt() == 0),
                null
            )
        }
        (m["screenOnDuration"] as? Number)?.let { v ->
            readSetting(DisplayTimeReq.getReadInstance(), DisplayTimeRsp::class.java) { cur ->
                CommandHandle.getInstance().executeReqCmd(
                    DisplayTimeReq.getWriteInstanceNew(
                        v.toInt(),
                        cur?.displayType ?: 1,
                        cur?.alpha ?: 5,
                        cur?.total ?: 5,
                        cur?.alwaysOn ?: 5,
                        true
                    ),
                    null
                )
                mainHandler.post { result.success(true) }
            }
            return
        }
        result.success(true)
    }

    // ─────────────────────────────────────────────────────────────────
    // Targets & user profile (read-only on this ring model)
    // ─────────────────────────────────────────────────────────────────

    private fun getTargetAndProfile(result: MethodChannel.Result) {
        readSetting(TargetSettingReq.getReadInstance(), TargetSettingRsp::class.java) { r ->
            val out = HashMap<String, Any?>()
            if (r != null) {
                out["stepTarget"] = r.step
                out["calorieTarget"] = r.calorie
                out["distanceTargetM"] = r.distance
                out["sleepTargetMin"] = r.getmSleep()
                out["sportTargetMin"] = r.getmSport()
            }
            out["profileSupported"] = false
            mainHandler.post { result.success(gson.toJson(out)) }
        }
    }

    private fun setTargetAndProfile(call: MethodCall, result: MethodChannel.Result) {
        val m = try {
            gson.fromJson(call.argument<String>("data"), Map::class.java)
        } catch (e: Exception) {
            Log.e(TAG, "setTargetAndProfile parse error: ${e.message}")
            null
        } ?: run { result.success(false); return }
        val step = (m["stepTarget"] as? Number)?.toInt() ?: 8000
        val calorie = (m["calorieTarget"] as? Number)?.toInt() ?: 500
        val distanceM = ((m["distanceTarget"] as? Number)?.toDouble() ?: 5.0).let { (it * 1000).toInt() }
        val sportMin = (m["sportTargetMin"] as? Number)?.toInt() ?: 60
        val sleepMin = ((m["sleepTarget"] as? Number)?.toDouble() ?: 8.0).let { (it * 60).toInt() }
        CommandHandle.getInstance().executeReqCmd(
            TargetSettingReq.getWriteInstance(step, calorie, distanceM, sportMin, sleepMin),
            ICommandResponse<BaseRspCmd> { _ ->
                mainHandler.post { result.success(true) }
            }
        )
    }

    // ─────────────────────────────────────────────────────────────────
    // Advanced settings (battery saving / AGPS / intelligent / touch)
    // ─────────────────────────────────────────────────────────────────

    private fun getAdvancedSettings(result: MethodChannel.Result) {
        val out = HashMap<String, Any?>()
        readSetting(BatterySavingReq.getReadInstance(), BatterySavingRsp::class.java) { b ->
            if (b != null) out["batterySaving"] = b.isOpen
            readSetting(AgpsReq.getReadInstance(), AgpsRsp::class.java) { a ->
                if (a != null) out["agpsEnable"] = a.isEnable
                readSetting(IntellReq.getReadInstance(), IntellRsp::class.java) { i ->
                    if (i != null) out["intellSettings"] = i.isEnable
                    readSetting(TouchControlReq.getReadInstance(true), TouchControlResp::class.java) { t ->
                        if (t != null) out["touchControl"] = t.isTouch
                        mainHandler.post { result.success(gson.toJson(out)) }
                    }
                }
            }
        }
    }

    private fun setAdvancedSetting(call: MethodCall, result: MethodChannel.Result) {
        val m = try {
            gson.fromJson(call.argument<String>("data"), Map::class.java)
        } catch (e: Exception) {
            Log.e(TAG, "setAdvancedSetting parse error: ${e.message}")
            null
        } ?: run { result.success(false); return }
        (m["batterySaving"] as? Boolean)?.let { v ->
            CommandHandle.getInstance().executeReqCmd(BatterySavingReq.getWriteInstance(v), null)
        }
        (m["agpsEnable"] as? Boolean)?.let { v ->
            CommandHandle.getInstance().executeReqCmd(AgpsReq.getWriteInstance(v), null)
        }
        (m["intellSettings"] as? Boolean)?.let { v ->
            CommandHandle.getInstance().executeReqCmd(IntellReq.getWriteInstance(v, 0), null)
        }
        (m["touchControl"] as? Boolean)?.let { v ->
            CommandHandle.getInstance().executeReqCmd(
                TouchControlReq.getWriteInstance(if (v) 9 else 0, true, 5),
                null
            )
        }
        (m["muslimMode"] as? Boolean)?.let { v ->
            CommandHandle.getInstance().executeReqCmd(MuslimReq.getWriteInstance(v), null)
        }
        result.success(true)
    }

    // ─────────────────────────────────────────────────────────────────
    // Ring event notification (fixed ring-side events; title/content
    // are accepted for API compatibility but not part of the protocol)
    // ─────────────────────────────────────────────────────────────────

    private fun sendRingNotification(call: MethodCall, result: MethodChannel.Result) {
        val type = call.argument<Int>("type") ?: NotificationEventNotifyReq.EVENT_NONE
        val event = when (type) {
            1 -> NotificationEventNotifyReq.EVENT_DOUBLE_CLICK_BUTTON
            2 -> NotificationEventNotifyReq.EVENT_PAIRING
            3 -> NotificationEventNotifyReq.EVENT_MISS_YOU
            4 -> NotificationEventNotifyReq.EVENT_LOVE_YOU
            5 -> NotificationEventNotifyReq.EVENT_NEED_YOU
            6 -> NotificationEventNotifyReq.EVENT_SAD
            7 -> NotificationEventNotifyReq.EVENT_LOVE_LETTER
            else -> NotificationEventNotifyReq.EVENT_NONE
        }
        CommandHandle.getInstance().executeReqCmd(NotificationEventNotifyReq.getEventInstance(event), null)
        result.success(true)
    }

    // ─────────────────────────────────────────────────────────────────
    // Health settings — sugar/lipids measurement state on the ring
    // (temperature / RRI / emotion auto-measure toggles)
    // ─────────────────────────────────────────────────────────────────

    private fun getHealthSettings(result: MethodChannel.Result) {
        readSetting(
            SugarLipidsSettingReq.getReadTemperatureInstance(),
            BloodSugarLipidsSettingRsp::class.java
        ) { t ->
            readSetting(
                SugarLipidsSettingReq.getReadRriInstance(),
                BloodSugarLipidsSettingRsp::class.java
            ) { rri ->
                readSetting(
                    SugarLipidsSettingReq.getReadEmotionInstance(),
                    BloodSugarLipidsSettingRsp::class.java
                ) { em ->
                    fun toMap(r: BloodSugarLipidsSettingRsp?) = r?.let {
                        mapOf(
                            "enabled" to it.isEnable,
                            "value" to it.value,
                            "type" to it.type,
                            "read" to it.isRead,
                            "startInterval" to it.startInterval,
                            "interval" to it.interval,
                            "rriAutoMeasureEnable" to it.isRriAutoMeasureEnable
                        )
                    }
                    mainHandler.post {
                        result.success(
                            gson.toJson(
                                mapOf(
                                    "sugarLipids" to mapOf(
                                        "temperature" to toMap(t),
                                        "rri" to toMap(rri),
                                        "emotion" to toMap(em)
                                    )
                                )
                            )
                        )
                    }
                }
            }
        }
    }

    private fun setHealthSettings(call: MethodCall, result: MethodChannel.Result) {
        val m = try {
            gson.fromJson(call.argument<String>("data"), Map::class.java)
        } catch (e: Exception) {
            Log.e(TAG, "setHealthSettings parse error: ${e.message}")
            null
        } ?: run { result.success(false); return }
        val sugarLipids = m["sugarLipids"] as? Map<*, *>
        (sugarLipids?.get("temperature") as? Map<*, *>)?.let { t ->
            (t["enabled"] as? Boolean)?.let { en ->
                val interval = (t["interval"] as? Number)?.toInt() ?: 60
                CommandHandle.getInstance().executeReqCmd(
                    SugarLipidsSettingReq.getWriteTemperatureInstance(en, interval),
                    null
                )
            }
        }
        (sugarLipids?.get("rri") as? Map<*, *>)?.let { r ->
            (r["enabled"] as? Boolean)?.let { en ->
                CommandHandle.getInstance().executeReqCmd(
                    SugarLipidsSettingReq.getWriteRriInstance(en),
                    null
                )
            }
        }
        (sugarLipids?.get("emotion") as? Map<*, *>)?.let { e ->
            (e["enabled"] as? Boolean)?.let { en ->
                CommandHandle.getInstance().executeReqCmd(
                    SugarLipidsSettingReq.getWriteEmotionInstance(en),
                    null
                )
            }
        }
        result.success(true)
    }

    // ─────────────────────────────────────────────────────────────────
    // Touch Control
    // ─────────────────────────────────────────────────────────────────

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

    @SuppressLint("MissingPermission")
    private fun answerPhoneCall(result: MethodChannel.Result) {
        try {
            val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                telecomManager.acceptRingingCall()
            } else {
                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_HEADSETHOOK))
                audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_HEADSETHOOK))
            }
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "answerPhoneCall error: ${e.message}")
            // Fallback via headset key event
            try {
                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_HEADSETHOOK))
                audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_HEADSETHOOK))
                result.success(true)
            } catch (ex: Exception) {
                result.success(false)
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun endOrDeclinePhoneCall(result: MethodChannel.Result) {
        try {
            val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                telecomManager.endCall()
            } else {
                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_HEADSETHOOK))
                audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_HEADSETHOOK))
            }
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "endOrDeclinePhoneCall error: ${e.message}")
            try {
                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_HEADSETHOOK))
                audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_HEADSETHOOK))
                result.success(true)
            } catch (ex: Exception) {
                result.success(false)
            }
        }
    }

    private fun toggleMediaPlayPause(result: MethodChannel.Result) {
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
            audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "toggleMediaPlayPause error: ${e.message}")
            result.success(false)
        }
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
                // Unified path: daySummary prefers raw Room then daily_vital_summary cache.
                repo().daySummary(vitalChannelKey(vital), dayStart, dayEnd)
            } catch (e: Exception) {
                mainHandler.post { result.error("QUERY_FAILED", e.message, null) }
                return@launch
            }
            mainHandler.post { result.success(gson.toJson(map)) }
        }
    }

    private fun vitalChannelKey(vital: Vital): String = when (vital) {
        Vital.HEART_RATE -> "heart_rate"
        Vital.SPO2 -> "spo2"
        Vital.STRESS -> "stress"
        Vital.BLOOD_PRESSURE -> "blood_pressure"
        Vital.HRV -> "hrv"
        Vital.TEMPERATURE -> "temperature"
        Vital.STEPS -> "steps"
    }

    private fun getDaySummary(call: MethodCall, result: MethodChannel.Result) {
        val vitalKey = call.argument<String>("vital")
        if (vitalKey.isNullOrBlank()) {
            result.error("BAD_ARGS", "vital is required", null)
            return
        }
        val dayStartMs = (call.argument<Number>("dayStartMs") ?: 0L).toLong()
        val dayEndMs = (call.argument<Number>("dayEndMs")
            ?: (dayStartMs + ReadingRepository.DAY_MS - 1)).toLong()
        if (dayStartMs <= 0L) {
            result.error("BAD_ARGS", "dayStartMs is required", null)
            return
        }
        repo().ioScope.launch {
            val map = try {
                repo().daySummary(vitalKey, dayStartMs, dayEndMs)
            } catch (e: Exception) {
                mainHandler.post { result.error("QUERY_FAILED", e.message, null) }
                return@launch
            }
            mainHandler.post { result.success(gson.toJson(map)) }
        }
    }

    private fun getLocalHistory(call: MethodCall, result: MethodChannel.Result) {
        val vitalKey = call.argument<String>("vital")
        if (vitalKey.isNullOrBlank()) {
            result.error("BAD_ARGS", "vital is required", null)
            return
        }
        val fromDayStartMs = (call.argument<Number>("fromDayStartMs") ?: 0L).toLong()
        val toDayStartMs = (call.argument<Number>("toDayStartMs")
            ?: System.currentTimeMillis()).toLong()
        repo().ioScope.launch {
            val list = try {
                repo().localHistory(vitalKey, fromDayStartMs, toDayStartMs)
            } catch (e: Exception) {
                mainHandler.post { result.error("QUERY_FAILED", e.message, null) }
                return@launch
            }
            mainHandler.post { result.success(gson.toJson(list)) }
        }
    }

    private fun cacheCloudDaySummary(call: MethodCall, result: MethodChannel.Result) {
        val vitalKey = call.argument<String>("vital")
        val dayStartMs = (call.argument<Number>("dayStartMs") ?: 0L).toLong()
        if (vitalKey.isNullOrBlank() || dayStartMs <= 0L) {
            result.error("BAD_ARGS", "vital and dayStartMs are required", null)
            return
        }
        val avg = call.argument<Number>("avg")?.toDouble()
        val min = call.argument<Number>("min")?.toDouble()
        val max = call.argument<Number>("max")?.toDouble()
        val count = call.argument<Number>("count")?.toInt() ?: 0
        val avgSecondary = call.argument<Number>("avgSecondary")?.toDouble()
        val minSecondary = call.argument<Number>("minSecondary")?.toDouble()
        val maxSecondary = call.argument<Number>("maxSecondary")?.toDouble()
        val steps = call.argument<Number>("steps")?.toInt()
        val caloriesKcal = call.argument<Number>("caloriesKcal")?.toInt()
        val distanceM = call.argument<Number>("distanceM")?.toDouble()
        repo().ioScope.launch {
            try {
                repo().cacheCloudDaySummary(
                    vital = vitalKey,
                    dayStartMs = dayStartMs,
                    avg = avg,
                    min = min,
                    max = max,
                    count = count,
                    avgSecondary = avgSecondary,
                    minSecondary = minSecondary,
                    maxSecondary = maxSecondary,
                    steps = steps,
                    caloriesKcal = caloriesKcal,
                    distanceM = distanceM
                )
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.error("CACHE_FAILED", e.message, null) }
            }
        }
    }

    private fun getLocalDbStats(result: MethodChannel.Result) {
        repo().ioScope.launch {
            val map = try {
                repo().localDbStats()
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

    private fun getPhoneModeSessions(call: MethodCall, result: MethodChannel.Result) {
        val fromMs = (call.argument<Number>("fromMs") ?: 0L).toLong()
        val toMs = (call.argument<Number>("toMs") ?: System.currentTimeMillis()).toLong()
        val limit = call.argument<Int>("limit") ?: 200
        repo().ioScope.launch {
            val json = try {
                gson.toJson(repo().phoneModeSessionsBetween(fromMs, toMs, limit))
            } catch (e: Exception) {
                mainHandler.post { result.error("QUERY_FAILED", e.message, null) }
                return@launch
            }
            mainHandler.post { result.success(json) }
        }
    }

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
                // Demo only — never schedule SMS or place a call from a simulation.
                FallAlertNotifier.notifyFall(context, confidence, source, simulated = true)
                SafetyLiveUpdate.showFall(
                    context,
                    (confidence * 100).toInt(),
                    EmergencySmsSender.COUNTDOWN_SECONDS,
                    EmergencyAutoCaller.isEnabled(context),
                    simulated = true,
                )
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.error("SIMULATE_FAILED", e.message, null) }
            }
        }
    }

    private fun postHealthAlert(call: MethodCall, result: MethodChannel.Result) {
        val title = call.argument<String>("title")
        if (title == null) { result.error("INVALID_ARG", "title required", null); return }
        val message = call.argument<String>("message") ?: ""
        val vital = call.argument<String>("vital")?.let { Vital.fromKey(it) } ?: Vital.HEART_RATE
        AlertNotifier.notifyAnomaly(context, title, message, vital)
        result.success(true)
    }

    private fun simulateFallRiskTrigger(result: MethodChannel.Result) {
        repo().ioScope.launch {
            try {
                val cycleId = repo().startCycle()
                val bpm = 135
                val id = repo().insertHeartRate(bpm, cycleId, "demo_seed")
                EventBus.getDefault().post(
                    NewReadingEvent(
                        Vital.HEART_RATE, id, cycleId, System.currentTimeMillis(),
                        bpm.toDouble(), simulated = true,
                    )
                )
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.error("SIMULATE_FAILED", e.message, null) }
            }
        }
    }

    private fun simulateFallPrediction(result: MethodChannel.Result) {
        repo().ioScope.launch {
            try {
                val cycleId = repo().startCycle()
                val bpm = 122
                val id = repo().insertHeartRate(bpm, cycleId, "demo_seed")
                EventBus.getDefault().post(
                    NewReadingEvent(
                        Vital.HEART_RATE, id, cycleId, System.currentTimeMillis(),
                        bpm.toDouble(), simulated = true,
                    )
                )
                // Demo only — never schedule SMS from a simulation.
                FallPredictionNotifier.notifyPrediction(context, bpm, simulated = true)

                // Persist so it shows up in Fall History, same as the real
                // FallRiskAnalyzer.maybeAlert() path.
                repo().insertFallEvent(
                    FallEventEntity(
                        confidence = 0.7f,
                        corroborated = false,
                        corroborationSource = "prediction",
                        metadataJson = gson.toJson(mapOf("hr" to bpm, "simulated" to true)),
                        detectedAt = System.currentTimeMillis(),
                        eventType = "PREDICTED",
                    )
                )

                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.error("SIMULATE_FAILED", e.message, null) }
            }
        }
    }

    private fun getEmergencySmsStatus(result: MethodChannel.Result) {
        result.success(gson.toJson(EmergencySmsSender.status(context)))
    }

    private fun getAutoCallOnFallEnabled(result: MethodChannel.Result) {
        result.success(gson.toJson(EmergencyAutoCaller.status(context)))
    }

    private fun setAutoCallOnFallEnabled(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        EmergencyAutoCaller.setEnabled(context, enabled)
        result.success(gson.toJson(EmergencyAutoCaller.status(context)))
    }

    private fun cancelEmergencySms(result: MethodChannel.Result) {
        EmergencySmsSender.cancel(context)
        FallPredictionNotifier.clearPending(context)
        result.success(true)
    }

    /**
     * Full logout wipe, called from Dart's SupabaseService.logoutAndClearLocalData().
     * Stops every background loop, drops the Room database (vitals, fall events,
     * emergency contacts, phone-mode sessions), clears the native SharedPreferences
     * that carry session/credential/personal data (Dart's own prefs.clear() covers the
     * FlutterSharedPreferences keys), and dismisses all outstanding notifications.
     */
    private fun clearPersonalData(result: MethodChannel.Result) {
        try {
            val app = context.applicationContext

            // 1. Stop everything that could write mid-wipe.
            MeasurementLoopManager.stop()
            SupabaseSyncManager.stop()
            WorkoutService.stop(app)
            FallMotionDetector.stop()
            EmergencySmsSender.cancel(app)
            FallPredictionNotifier.clearPending(app)
            SafetyLiveUpdate.clear(app)
            try { BleOperateManager.getInstance().disconnect() } catch (_: Exception) {}
            BleConnectionService.stop(app)

            // 2. Drop the Room database; next getInstance() rebuilds an empty one.
            ReadingRepository.destroy()
            app.deleteDatabase("qring_local.db")

            // 3. Wipe native SharedPreferences that hold personal/session data.
            //    qring_supabase_sync_config holds the JWT copy — clearing it also makes
            //    SupabaseSyncManager no-op (isConfigured=false) until the next login.
            SupabaseConfig.clear()
            MeasurementConfig.clear()
            listOf(
                "qring_supabase_sync_state",
                "qring_emergency_sms",
                "qring_fall_settings",
                "qring_fall_prediction"
            ).forEach { name ->
                app.getSharedPreferences(name, Context.MODE_PRIVATE).edit().clear().apply()
            }

            // 4. Dismiss any residual notifications (fall alerts, anomaly alerts, …).
            NotificationManagerCompat.from(app).cancelAll()

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "clearPersonalData failed", e)
            result.error("CLEAR_FAILED", e.message, null)
        }
    }

    private fun sendEmergencySms(call: MethodCall, result: MethodChannel.Result) {
        val message = call.argument<String>("message")
            ?: EmergencySmsSender.DEFAULT_MESSAGE
        repo().ioScope.launch {
            val status = try {
                EmergencySmsSender.sendNow(context, message)
            } catch (e: Exception) {
                mainHandler.post { result.error("SMS_FAILED", e.message, null) }
                return@launch
            }
            mainHandler.post { result.success(gson.toJson(status)) }
        }
    }

    private fun placeEmergencyCall(call: MethodCall, result: MethodChannel.Result) {
        val phone = call.argument<String>("phone")
        if (phone.isNullOrBlank()) {
            result.error("NO_PHONE", "No phone number provided", null)
            return
        }
        val ok = EmergencyAutoCaller.placeCall(context, phone)
        if (ok) {
            result.success(true)
        } else {
            val hasPermission = ContextCompat.checkSelfPermission(
                context, Manifest.permission.CALL_PHONE
            ) == PackageManager.PERMISSION_GRANTED
            if (!hasPermission) {
                result.error("NO_PERMISSION", "CALL_PHONE permission not granted", null)
            } else {
                result.error("CALL_FAILED", "Could not place call", null)
            }
        }
    }

    private fun consumeFallPredictionFlag(result: MethodChannel.Result) {
        FallPredictionNotifier.restorePending(context)
        val pending = MainActivity.pendingFallPrediction
        val hr = MainActivity.pendingFallPredictionHr
        result.success(gson.toJson(mapOf("pending" to pending, "hr" to hr)))
    }

    private fun clearFallPredictionFlag(result: MethodChannel.Result) {
        FallPredictionNotifier.clearPending(context)
        result.success(true)
    }

    private fun getEmergencyContacts(result: MethodChannel.Result) {
        repo().ioScope.launch {
            val json = try {
                gson.toJson(repo().allEmergencyContacts())
            } catch (e: Exception) {
                mainHandler.post { result.error("QUERY_FAILED", e.message, null) }
                return@launch
            }
            mainHandler.post { result.success(json) }
        }
    }

    private fun updateEmergencyContact(call: MethodCall, result: MethodChannel.Result) {
        val id = (call.argument<Number>("id") ?: run {
            result.error("INVALID_ARG", "id required", null); return
        }).toLong()
        val name = call.argument<String>("name") ?: run {
            result.error("INVALID_ARG", "name required", null); return
        }
        val phone = call.argument<String>("phone") ?: ""
        repo().ioScope.launch {
            try {
                repo().updateEmergencyContact(id, name, phone)
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.error("UPDATE_FAILED", e.message, null) }
            }
        }
    }

    private fun addEmergencyContact(call: MethodCall, result: MethodChannel.Result) {
        val name = call.argument<String>("name") ?: run {
            result.error("INVALID_ARG", "name required", null); return
        }
        val phone = call.argument<String>("phone") ?: ""
        repo().ioScope.launch {
            try {
                repo().insertEmergencyContact(name, phone)
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.error("INSERT_FAILED", e.message, null) }
            }
        }
    }

    private fun deleteEmergencyContact(call: MethodCall, result: MethodChannel.Result) {
        val id = (call.argument<Number>("id") ?: run {
            result.error("INVALID_ARG", "id required", null); return
        }).toLong()
        repo().ioScope.launch {
            try {
                repo().deleteEmergencyContact(id)
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.error("DELETE_FAILED", e.message, null) }
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

    private fun saveStepsSnapshot(call: MethodCall, result: MethodChannel.Result) {
        val steps = call.argument<Int>("steps") ?: 0
        val calories = call.argument<Int>("calories") ?: 0
        val distanceM = (call.argument<Number>("distanceM") ?: 0.0).toDouble()
        if (steps > 0 || calories > 0) {
            repo().ioScope.launch {
                try {
                    repo().insertStepsSnapshot(steps, calories, distanceM, 0, "flutter_push")
                    SupabaseSyncManager.forceSyncNow()
                } catch (e: Exception) {
                    Log.e(TAG, "saveStepsSnapshot failed", e)
                }
            }
        }
        mainHandler.post { result.success(true) }
    }

    private fun getSyncStatus(result: MethodChannel.Result) {
        // Enriched below with pending queue + local DB stats for offline diagnostics.
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
            try {
                eventSink?.success(mapOf("type" to type, "data" to data))
            } catch (e: Exception) {
                // Channel already closed / engine detaching — drop the event rather than crash.
                Log.w(TAG, "sendEvent($type) dropped: ${e.message}")
                eventSink = null
            }
        }
    }

    private fun factoryReset(result: MethodChannel.Result) {
        if (!_isConnected) {
            result.success(false)
            return
        }
        try {
            var handled = false
            CommandHandle.getInstance().executeReqCmd(
                RestoreKeyReq(Constants.CMD_RE_STORE),
                ICommandResponse<BaseRspCmd> { _ ->
                    if (!handled) {
                        handled = true
                        mainHandler.post { result.success(true) }
                    }
                }
            )
            // Fallback response in case device resets immediately without ACK
            mainHandler.postDelayed({
                if (!handled) {
                    handled = true
                    result.success(true)
                }
            }, 1200)
        } catch (e: Exception) {
            Log.e(TAG, "factoryReset failed", e)
            result.success(false)
        }
    }

    private fun shutDownRing(result: MethodChannel.Result) {
        if (!_isConnected) {
            result.success(false)
            return
        }
        try {
            var handled = false
            CommandHandle.getInstance().executeReqCmd(
                SimpleKeyPowerOffReq(),
                ICommandResponse<BaseRspCmd> { _ ->
                    if (!handled) {
                        handled = true
                        mainHandler.post { result.success(true) }
                    }
                }
            )
            // Fallback response in case device shuts down immediately without ACK
            mainHandler.postDelayed({
                if (!handled) {
                    handled = true
                    result.success(true)
                }
            }, 1200)
        } catch (e: Exception) {
            Log.e(TAG, "shutDownRing failed", e)
            result.success(false)
        }
    }

    fun onDestroy() {
        try {
            mainHandler.removeCallbacks(connectTimeoutRunnable)
            stopCameraKeepAlive()
        } catch (_: Exception) {
        }
        try {
            BleScannerHelper.getInstance().stopScan(context)
        } catch (_: Exception) {
        }
        try {
            BleOperateManager.getInstance().removeNotifyListener(NOTIFY_KEY)
        } catch (_: Exception) {
        }
        try {
            if (EventBus.getDefault().isRegistered(this)) {
                EventBus.getDefault().unregister(this)
            }
        } catch (_: Exception) {
        }
        eventSink = null
        if (instance === this) instance = null
    }
}