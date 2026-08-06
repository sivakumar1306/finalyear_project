package com.medxai.sundr

import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.medxai.sundr.sdk.BleSdkLifecycle
import com.medxai.sundr.sdk.SdkGuard

private const val TAG = "QRingSystemBt"
private const val RECONNECT_DELAY_MS = 500L

/**
 * Logs system Bluetooth bond-state changes and cycles GATT after bonding completes.
 * See sdk_ring_external_access_en.pdf §3.2.
 */
class QRingSystemBluetoothReceiver : BroadcastReceiver() {
    private val handler = Handler(Looper.getMainLooper())

    override fun onReceive(context: Context, intent: Intent) {
        SdkGuard.run("systemBt.onReceive") {
            if (intent.action != BluetoothDevice.ACTION_BOND_STATE_CHANGED) return@run
            val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
            val bondState = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, -1)
            val prevBondState = intent.getIntExtra(BluetoothDevice.EXTRA_PREVIOUS_BOND_STATE, -1)
            val stateName = when (bondState) {
                BluetoothDevice.BOND_NONE -> "BOND_NONE"
                BluetoothDevice.BOND_BONDING -> "BOND_BONDING"
                BluetoothDevice.BOND_BONDED -> "BOND_BONDED"
                else -> "UNKNOWN($bondState)"
            }
            Log.d(TAG, "bondStateChanged: device=${device?.address} $prevBondState -> $stateName")

            if (bondState == BluetoothDevice.BOND_BONDED && prevBondState != BluetoothDevice.BOND_BONDED) {
                val address = device?.address ?: return@run
                Log.d(TAG, "Bond completed — cycling GATT connection")
                handler.postDelayed({
                    SdkGuard.run("systemBt.cycleDisconnect") {
                        BleSdkLifecycle.disconnect()
                    }
                    handler.postDelayed({
                        SdkGuard.run("systemBt.cycleConnect") {
                            BleSdkLifecycle.connectDirectly(address)
                        }
                    }, RECONNECT_DELAY_MS)
                }, RECONNECT_DELAY_MS)
            } else if (bondState == BluetoothDevice.BOND_NONE && prevBondState == BluetoothDevice.BOND_BONDING) {
                Log.w(TAG, "Bond attempt failed (BOND_BONDING -> BOND_NONE)")
                try {
                    BlePlugin.instance?.onBondFailed()
                } catch (e: Exception) {
                    Log.e(TAG, "onBondFailed failed", e)
                }
            }
        }
    }
}
