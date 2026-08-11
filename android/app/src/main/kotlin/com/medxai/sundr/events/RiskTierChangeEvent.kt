package com.medxai.sundr.events

/**
 * Broadcasts the latest vitals-based Fall Risk tier computed by FallRiskAnalyzer.
 * Used to conditionally wake up high-power sensors like the IMU only during elevated risk windows.
 */
data class RiskTierChangeEvent(val tier: String)
