package com.medxai.sundr

import android.bluetooth.BluetoothDevice
import android.util.Log
import com.oudmon.ble.base.bluetooth.QCBluetoothCallbackCloneReceiver
import com.oudmon.ble.base.communication.Constants
import com.oudmon.ble.base.communication.LargeDataHandler

private const val TAG = "QRingBleReceiver"

/**
 * Required by the SDK: receives connection, service-discovery, and characteristic
 * callbacks as app-scoped broadcasts. Registered dynamically in
 * QRingApplication.onCreate(). Without this receiver, onServiceDiscovered() never
 * fires, LargeDataHandler is never enabled, and large-data/file syncs (temperature,
 * sleep, blood oxygen, ...) silently never start — see sdk_ring_external_access_en.pdf §3.1.
 */
class QRingBluetoothReceiver : QCBluetoothCallbackCloneReceiver() {

    override fun connectStatue(device: BluetoothDevice?, connected: Boolean) {
        if (connected) {
            device?.address?.let { BlePlugin.instance?.onDeviceAddressKnown(it) }
        } else {
            BlePlugin.instance?.onDeviceDisconnected()
        }
    }

    override fun onServiceDiscovered() {
        Log.d(TAG, "onServiceDiscovered")
        // Required before any large-data (file/big-data) sync will produce callbacks.
        LargeDataHandler.getInstance().initEnable()
        BlePlugin.instance?.onServiceDiscovered()
    }

    override fun onCharacteristicRead(uuid: String?, data: ByteArray?) {
        if (uuid == null || data == null) return
        val value = String(data, Charsets.UTF_8)
        when (uuid) {
            Constants.CHAR_FIRMWARE_REVISION.toString() -> BlePlugin.instance?.cachedFirmwareVersion = value
            Constants.CHAR_HW_REVISION.toString() -> BlePlugin.instance?.cachedHardwareVersion = value
        }
    }

    override fun onCharacteristicChange(address: String?, uuid: String?, data: ByteArray?) {
        // Not currently needed by any Flutter-facing feature.
    }
}
