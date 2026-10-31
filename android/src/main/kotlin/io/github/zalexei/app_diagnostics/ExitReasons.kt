package io.github.zalexei.app_diagnostics

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import java.io.IOException

/** ApplicationExitInfo access. Every call degrades to an empty answer below API 30. */
internal class ExitReasons(private val context: Context) {
    private val activityManager: ActivityManager
        get() = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager

    private val prefs by lazy { context.getSharedPreferences(PREFS, Context.MODE_PRIVATE) }

    fun list(pid: Int, maxNum: Int): List<ExitInfoMessage> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        return records(pid, maxNum).map { it.toMessage() }
    }

    fun takeNew(): List<ExitInfoMessage> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val lastSeen = prefs.getLong(KEY_LAST_SEEN, 0L)
        val fresh = records(0, 0).filter { it.timestamp > lastSeen }
        val messages = fresh.map { it.toMessage() }
        // Move the marker only once the records are ready, and synchronously
        // (this runs on a background queue) so a crash right after keeps it.
        fresh.maxOfOrNull { it.timestamp }?.let { prefs.edit().putLong(KEY_LAST_SEEN, it).commit() }
        return messages
    }

    fun trace(pid: Int, timestamp: Long): ByteArray? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val record = records(pid, 0).firstOrNull { it.timestamp == timestamp } ?: return null
        return try {
            record.traceInputStream?.use { it.readBytes() }
        } catch (e: IOException) {
            Log.w(TAG, "Cannot read trace of pid $pid", e)
            null
        }
    }

    fun setSummary(summary: ByteArray?): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false
        return try {
            activityManager.setProcessStateSummary(summary)
            true
        } catch (e: RuntimeException) {
            // The system throttles frequent calls with a RuntimeException.
            Log.w(TAG, "setProcessStateSummary rejected", e)
            false
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun records(pid: Int, maxNum: Int): List<ApplicationExitInfo> =
        activityManager.getHistoricalProcessExitReasons(null, pid, maxNum)

    @RequiresApi(Build.VERSION_CODES.R)
    private fun ApplicationExitInfo.toMessage() = ExitInfoMessage(
        reason = reason.toLong(),
        status = status.toLong(),
        importance = importance.toLong(),
        timestamp = timestamp,
        pid = pid.toLong(),
        processName = processName,
        description = description,
        pss = pss,
        rss = rss,
        processStateSummary = processStateSummary,
        hasTrace = hasTrace(),
        anrInfo = anrInfo(),
    )

    @RequiresApi(Build.VERSION_CODES.R)
    private fun ApplicationExitInfo.hasTrace(): Boolean = try {
        traceInputStream?.use { true } ?: false
    } catch (e: IOException) {
        false
    }

    /** ApplicationExitInfo.getAnrInfo() is API 37, above compileSdk, hence reflection. */
    @RequiresApi(Build.VERSION_CODES.R)
    private fun ApplicationExitInfo.anrInfo(): AnrInfoMessage? {
        if (Build.VERSION.SDK_INT < ApiLevels.API_37 || reason != ApplicationExitInfo.REASON_ANR) return null
        return try {
            val info = javaClass.getMethod("getAnrInfo").invoke(this) ?: return null
            fun call(name: String) = info.javaClass.getMethod(name).invoke(info)
            AnrInfoMessage(
                anrType = (call("getAnrType") as Int).toLong(),
                anrId = (call("getAnrId") as Int).toLong(),
                timeoutMillis = call("getTimeoutMillis") as Long,
                userPerceptible = call("isUserPerceptible") as Boolean,
            )
        } catch (e: Exception) {
            // Reflection failures, or unexpected types on an OEM build.
            Log.w(TAG, "getAnrInfo unavailable", e)
            null
        }
    }

    private companion object {
        const val TAG = "AndroidDiagnostics"
        const val PREFS = "io.github.zalexei.app_diagnostics"
        const val KEY_LAST_SEEN = "last_seen_exit_timestamp"
    }
}
