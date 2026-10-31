package io.github.zalexei.android_diagnostics

import android.os.Build

/** API levels newer than the plugin's compileSdk (36), and per-feature gates. */
internal object ApiLevels {
    const val BAKLAVA = 36
    const val API_37 = 37

    /** Build.VERSION_CODES_FULL.BAKLAVA_1 (Android 16 QPR2). */
    const val BAKLAVA_1_FULL = 3_600_001

    /** Build.VERSION.SDK_INT_FULL, synthesized as major * 100000 before API 36. */
    fun sdkIntFull(): Int =
        if (Build.VERSION.SDK_INT >= BAKLAVA) Build.VERSION.SDK_INT_FULL
        else Build.VERSION.SDK_INT * 100_000

    /** Minimum SDK_INT_FULL for a ProfilingTrigger.TRIGGER_TYPE_* value, null if unknown. */
    fun triggerMinSdkFull(triggerType: Int): Int? = when (triggerType) {
        1, 2 -> BAKLAVA * 100_000 // APP_FULLY_DRAWN, ANR
        3, 4, 5, 6 -> BAKLAVA_1_FULL // APP_REQUEST_RUNNING_TRACE, KILL_*
        in 7..11 -> API_37 * 100_000 // OOM, ANOMALY, KILL_EXCESSIVE_CPU_USAGE, COLD_START, APP_COMPAT
        else -> null
    }

    fun isTriggerSupported(triggerType: Int, sdkIntFull: Int): Boolean =
        triggerMinSdkFull(triggerType)?.let { sdkIntFull >= it } ?: false
}
