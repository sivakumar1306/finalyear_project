package com.sundr.myapp

import android.bluetooth.BluetoothDevice
import android.util.Log
import com.sundr.myapp.sdk.SdkGuard
import com.oudmon.ble.base.bluetooth.QCBluetoothCallbackCloneReceiver
import com.oudmon.ble.base.communication.Constants
import com.oudmon.ble.base.communication.LargeDataHandler

private const val TAG = "QRingBleReceiver"

/**
 * Required by the SDK: receives connection, service-discovery, and characteristic
 * callbacks as app-scoped broadcasts. Registered dynamically in
 * QRingApplication.onCreate(). Without this receiver, onServiceDiscovered() never
 * fires, LargeDataHandler is never enabled, and large-data/file syncs silently never
 * start — see sdk_ring_external_access_en.pdf §3.1.
 */
class QRingBluetoothReceiver : QCBluetoothCallbackCloneReceiver() {

    override fun connectStatue(device: BluetoothDevice?, connected: Boolean) {
        SdkGuard.run("receiver.connectStatue") {
            if (connected) {
                device?.address?.let { BlePlugin.instance?.onDeviceAddressKnown(it) }
            } else {
                BlePlugin.instance?.onDeviceDisconnected()
            }
        }
    }

    override fun onServiceDiscovered() {
        SdkGuard.run("receiver.onServiceDiscovered") {
            Log.d(TAG, "onServiceDiscovered")
            try {
                LargeDataHandler.getInstance().initEnable()
            } catch (e: Exception) {
                Log.e(TAG, "LargeDataHandler.initEnable failed", e)
            }
            BlePlugin.instance?.onServiceDiscovered()
        }
    }

    override fun onCharacteristicRead(uuid: String?, data: ByteArray?) {
        SdkGuard.run("receiver.onCharacteristicRead") {
            if (uuid == null || data == null) return@run
            val value = String(data, Charsets.UTF_8)
            when (uuid) {
                Constants.CHAR_FIRMWARE_REVISION.toString() ->
                    BlePlugin.instance?.cachedFirmwareVersion = value
                Constants.CHAR_HW_REVISION.toString() ->
                    BlePlugin.instance?.cachedHardwareVersion = value
            }
        }
    }

    override fun onCharacteristicChange(address: String?, uuid: String?, data: ByteArray?) {
        // Not currently needed by any Flutter-facing feature.
    }
}
