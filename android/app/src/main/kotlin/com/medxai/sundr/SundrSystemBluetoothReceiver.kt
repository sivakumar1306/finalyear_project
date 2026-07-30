package com.medxai.qring_flutter

import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.oudmon.ble.base.bluetooth.BleOperateManager

private const val TAG = "QRingSystemBt"
private const val RECONNECT_DELAY_MS = 500L

/**
 * Logs system Bluetooth bond-state changes so we can see whether bleCreateBond()
 * actually results in a completed pairing (BOND_BONDED), a rejection (BOND_NONE), or
 * nothing at all. Registered EXPORTED in QRingApplication since these are system
 * broadcasts, not app-scoped SDK ones — see sdk_ring_external_access_en.pdf §3.2.
 *
 * Also cycles the GATT connection once bonding completes: a GATT link opened before
 * bonding is not automatically upgraded to the new encrypted/bonded session, so commands
 * can keep getting silently ignored even after BOND_BONDED unless the app reconnects.
 */
class QRingSystemBluetoothReceiver : BroadcastReceiver() {
    private val handler = Handler(Looper.getMainLooper())

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != BluetoothDevice.ACTION_BOND_STATE_CHANGED) return
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
            val address = device?.address ?: return
            Log.d(TAG, "Bond completed — cycling GATT connection to pick up the encrypted link")
            handler.postDelayed({
                BleOperateManager.getInstance().disconnect()
                handler.postDelayed({
                    BleOperateManager.getInstance().connectDirectly(address)
                }, RECONNECT_DELAY_MS)
            }, RECONNECT_DELAY_MS)
        } else if (bondState == BluetoothDevice.BOND_NONE && prevBondState == BluetoothDevice.BOND_BONDING) {
            // Pairing was rejected/cancelled/timed out — unblock whatever BlePlugin deferred
            // waiting on this bond instead of leaving it hanging silently.
            Log.w(TAG, "Bond attempt failed (BOND_BONDING -> BOND_NONE)")
            BlePlugin.instance?.onBondFailed()
        }
    }
}
