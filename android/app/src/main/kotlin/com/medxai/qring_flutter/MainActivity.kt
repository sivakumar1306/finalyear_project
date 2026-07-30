package com.medxai.qring_flutter

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.medxai.qring_flutter.analysis.EmergencySmsSender
import com.medxai.qring_flutter.analysis.FallPredictionNotifier
import com.medxai.qring_flutter.ui.navigation.MainScreen
import com.medxai.qring_flutter.ui.theme.AppColors
import com.medxai.qring_flutter.ui.theme.QRingTheme

class MainActivity : ComponentActivity() {

    companion object {
        var pendingFallPrediction = false
        var pendingFallPredictionHr = 0
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        requestBlePermissions()

        if (hasBlePermission()) {
            BleConnectionService.start(this)
        }

        FallPredictionNotifier.restorePending(this)
        EmergencySmsSender.restoreIfNeeded(this)
        handleIntent(intent)

        setContent {
            QRingTheme {
                Surface(
                    color = AppColors.bg,
                    modifier = androidx.compose.ui.Modifier.fillMaxSize(),
                ) {
                    MainScreen()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(FallPredictionNotifier.EXTRA_FALL_PREDICTION, false) == true) {
            val hr = intent.getIntExtra(FallPredictionNotifier.EXTRA_FALL_PREDICTION_HR, 0)
            FallPredictionNotifier.markPending(this, hr)
        }
    }

    private fun requestBlePermissions() {
        val perms = mutableListOf(
            Manifest.permission.BLUETOOTH,
            Manifest.permission.BLUETOOTH_ADMIN,
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.POST_NOTIFICATIONS,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            perms.add(Manifest.permission.BLUETOOTH_SCAN)
            perms.add(Manifest.permission.BLUETOOTH_CONNECT)
            perms.add(Manifest.permission.BLUETOOTH_ADVERTISE)
        }
        val needed = perms.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (needed.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, needed.toTypedArray(), 100)
        }
    }

    private fun hasBlePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }
}
