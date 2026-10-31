package io.github.zalexei.app_diagnostics

import android.content.Context
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin

/** Bridges ApplicationExitInfo and ProfilingManager to Dart. */
class AppDiagnosticsPlugin : FlutterPlugin {
    private var profiler: Profiler? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        val profiler = Profiler(context)
        AndroidDiagnosticsHostApi.setUp(
            binding.binaryMessenger,
            HostApi(context, ExitReasons(context), profiler),
        )
        ProfilingResultsStreamHandler.register(binding.binaryMessenger, profiler.resultsStream)
        this.profiler = profiler
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        AndroidDiagnosticsHostApi.setUp(binding.binaryMessenger, null)
        profiler?.dispose()
        profiler = null
    }

    private class HostApi(
        private val context: Context,
        private val exitReasons: ExitReasons,
        private val profiler: Profiler,
    ) : AndroidDiagnosticsHostApi {
        override fun getSupport(): SupportMessage {
            val sdk = Build.VERSION.SDK_INT
            val sdkFull = ApiLevels.sdkIntFull()
            return SupportMessage(
                sdkInt = sdk.toLong(),
                sdkIntFull = sdkFull.toLong(),
                exitReasons = sdk >= Build.VERSION_CODES.R,
                nativeTombstones = sdk >= Build.VERSION_CODES.S,
                anrInfo = sdk >= ApiLevels.API_37,
                profiling = sdk >= Build.VERSION_CODES.VANILLA_ICE_CREAM,
                profilingTriggers = sdk >= ApiLevels.BAKLAVA,
                runningTraceSnapshot = sdkFull >= ApiLevels.BAKLAVA_1_FULL,
            )
        }

        override fun getExitReasons(pid: Long, maxNum: Long) =
            exitReasons.list(pid.toInt(), maxNum.toInt())

        override fun takeNewExitReasons() = exitReasons.takeNew()

        override fun getTrace(pid: Long, timestamp: Long) = exitReasons.trace(pid.toInt(), timestamp)

        override fun setProcessStateSummary(summary: ByteArray?) = exitReasons.setSummary(summary)

        override fun requestProfiling(
            requestId: String,
            request: ProfilingRequestMessage,
            callback: (Result<ProfilingResultMessage>) -> Unit,
        ) = profiler.request(requestId, request) { callback(Result.success(it)) }

        override fun cancelProfiling(requestId: String) = profiler.cancel(requestId)

        override fun addProfilingTriggers(triggers: List<ProfilingTriggerMessage>) =
            profiler.addTriggers(triggers).map { it.toLong() }

        override fun removeProfilingTriggers(triggerTypes: List<Long>) =
            profiler.removeTriggers(triggerTypes.map { it.toInt() })

        override fun clearProfilingTriggers() = profiler.clearTriggers()

        override fun requestRunningSystemTrace(tag: String?) = profiler.requestRunningSystemTrace(tag)

        override fun listProfilingFiles(): List<String> =
            context.filesDir.resolve("profiling").listFiles()
                ?.filter { it.isFile }
                ?.sortedByDescending { it.lastModified() }
                ?.map { it.absolutePath }
                ?: emptyList()
    }
}
