package io.github.zalexei.app_diagnostics

import android.content.Context
import android.os.Build
import android.os.CancellationSignal
import android.os.ProfilingManager
import android.os.ProfilingResult
import android.os.ProfilingTrigger
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import androidx.core.os.BufferFillPolicy
import androidx.core.os.HeapProfileRequestBuilder
import androidx.core.os.JavaHeapDumpRequestBuilder
import androidx.core.os.ProfilingRequest
import androidx.core.os.ProfilingRequestBuilder
import androidx.core.os.StackSamplingRequestBuilder
import androidx.core.os.SystemTraceRequestBuilder
import androidx.core.os.requestProfiling
import java.util.concurrent.Executor
import java.util.function.Consumer

/**
 * ProfilingManager access. Requests answer with [ERROR_UNSUPPORTED] below API 35,
 * trigger calls are no-ops below API 36. All state is touched on the main thread.
 */
internal class Profiler(private val context: Context) {
    private val mainExecutor: Executor = ContextCompat.getMainExecutor(context)
    private val pending = HashMap<String, CancellationSignal>()
    val resultsStream = ResultsStream()

    fun request(
        requestId: String,
        message: ProfilingRequestMessage,
        onResult: (ProfilingResultMessage) -> Unit,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            onResult(failure(ERROR_UNSUPPORTED, "ProfilingManager requires Android 15 (API 35)", message.tag))
            return
        }
        val signal = CancellationSignal()
        // Pigeon does not catch exceptions of async handlers and a second reply
        // throws: answer exactly once, or Dart waits forever.
        var answered = false
        val answer = { result: ProfilingResultMessage ->
            if (!answered) {
                answered = true
                if (pending[requestId] === signal) pending.remove(requestId)
                onResult(result)
            }
        }
        val request = try {
            Api35.buildRequest(message, signal)
        } catch (e: IllegalArgumentException) {
            answer(failure(ERROR_FAILED_INVALID_REQUEST, e.message, message.tag))
            return
        } catch (e: Exception) {
            answer(failure(ERROR_UNKNOWN, e.toString(), message.tag))
            return
        } catch (e: LinkageError) {
            answer(failure(ERROR_UNKNOWN, e.toString(), message.tag))
            return
        }
        pending[requestId] = signal
        try {
            Api35.request(context, request, mainExecutor, answer)
        } catch (e: Exception) {
            Log.w(TAG, "requestProfiling failed", e)
            answer(failure(ERROR_UNKNOWN, e.toString(), message.tag))
        } catch (e: LinkageError) {
            // A ProfilingManager trimmed by the device maker.
            Log.w(TAG, "requestProfiling unavailable", e)
            answer(failure(ERROR_UNKNOWN, e.toString(), message.tag))
        }
    }

    fun cancel(requestId: String): Boolean {
        val signal = pending[requestId] ?: return false
        signal.cancel()
        return true
    }

    fun addTriggers(triggers: List<ProfilingTriggerMessage>): List<Int> {
        if (Build.VERSION.SDK_INT < ApiLevels.BAKLAVA) return emptyList()
        val sdkFull = ApiLevels.sdkIntFull()
        val supported = triggers.filter { ApiLevels.isTriggerSupported(it.triggerType.toInt(), sdkFull) }
        if (supported.isEmpty()) return emptyList()
        return try {
            Api36.addTriggers(context, supported)
            supported.map { it.triggerType.toInt() }
        } catch (e: RuntimeException) {
            Log.w(TAG, "addProfilingTriggers failed", e)
            emptyList()
        }
    }

    fun removeTriggers(triggerTypes: List<Int>) {
        if (Build.VERSION.SDK_INT >= ApiLevels.BAKLAVA) Api36.removeTriggers(context, triggerTypes.toIntArray())
    }

    fun clearTriggers() {
        if (Build.VERSION.SDK_INT >= ApiLevels.BAKLAVA) Api36.clearTriggers(context)
    }

    /** ProfilingManager.requestRunningSystemTrace is Android 16 QPR2, above compileSdk, hence reflection. */
    fun requestRunningSystemTrace(tag: String?): Boolean {
        if (ApiLevels.sdkIntFull() < ApiLevels.BAKLAVA_1_FULL) return false
        return try {
            val manager = context.getSystemService(ProfilingManager::class.java)
            manager.javaClass.getMethod("requestRunningSystemTrace", String::class.java).invoke(manager, tag)
            true
        } catch (e: ReflectiveOperationException) {
            Log.w(TAG, "requestRunningSystemTrace unavailable", e)
            false
        }
    }

    fun dispose() {
        pending.values.forEach { it.cancel() }
        pending.clear()
        resultsStream.stop()
    }

    /** Forwards ProfilingManager.registerForAllProfilingResults while Dart listens. */
    inner class ResultsStream : ProfilingResultsStreamHandler() {
        // Consumer<ProfilingResult>, kept untyped so this class loads below API 35.
        private var listener: Any? = null

        override fun onListen(p0: Any?, sink: PigeonEventSink<ProfilingResultMessage>) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) return
            stop()
            listener = Api35.registerForAll(context, mainExecutor) { sink.success(it) }
        }

        override fun onCancel(p0: Any?) = stop()

        fun stop() {
            val current = listener ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
                Api35.unregister(context, current)
            }
            listener = null
        }
    }

    @RequiresApi(Build.VERSION_CODES.VANILLA_ICE_CREAM)
    private object Api35 {
        fun buildRequest(m: ProfilingRequestMessage, signal: CancellationSignal): ProfilingRequest =
            when (m.type.toInt()) {
                ProfilingManager.PROFILING_TYPE_JAVA_HEAP_DUMP -> JavaHeapDumpRequestBuilder().apply {
                    m.bufferSizeKb?.let { setBufferSizeKb(it.toInt()) }
                }.finish(m, signal)

                ProfilingManager.PROFILING_TYPE_HEAP_PROFILE -> HeapProfileRequestBuilder().apply {
                    m.bufferSizeKb?.let { setBufferSizeKb(it.toInt()) }
                    m.durationMs?.let { setDurationMs(it.toInt()) }
                    m.samplingIntervalBytes?.let { setSamplingIntervalBytes(it) }
                    m.trackJavaAllocations?.let { setTrackJavaAllocations(it) }
                }.finish(m, signal)

                ProfilingManager.PROFILING_TYPE_STACK_SAMPLING -> StackSamplingRequestBuilder().apply {
                    m.bufferSizeKb?.let { setBufferSizeKb(it.toInt()) }
                    m.durationMs?.let { setDurationMs(it.toInt()) }
                    m.samplingFrequencyHz?.let { setSamplingFrequencyHz(it.toInt()) }
                }.finish(m, signal)

                ProfilingManager.PROFILING_TYPE_SYSTEM_TRACE -> SystemTraceRequestBuilder().apply {
                    m.bufferSizeKb?.let { setBufferSizeKb(it.toInt()) }
                    m.durationMs?.let { setDurationMs(it.toInt()) }
                    m.ringBuffer?.let {
                        setBufferFillPolicy(if (it) BufferFillPolicy.RING_BUFFER else BufferFillPolicy.DISCARD)
                    }
                }.finish(m, signal)

                else -> throw IllegalArgumentException("Unknown profiling type ${m.type}")
            }

        private fun <T : ProfilingRequestBuilder<T>> T.finish(
            m: ProfilingRequestMessage,
            signal: CancellationSignal,
        ): ProfilingRequest {
            m.tag?.let { setTag(it) }
            setCancellationSignal(signal)
            return build()
        }

        fun request(
            context: Context,
            request: ProfilingRequest,
            executor: Executor,
            onResult: (ProfilingResultMessage) -> Unit,
        ) = requestProfiling(context, request, executor) { onResult(it.toMessage()) }

        fun registerForAll(
            context: Context,
            executor: Executor,
            onResult: (ProfilingResultMessage) -> Unit,
        ): Any {
            val consumer = Consumer<ProfilingResult> { onResult(it.toMessage()) }
            context.getSystemService(ProfilingManager::class.java)
                .registerForAllProfilingResults(executor, consumer)
            return consumer
        }

        @Suppress("UNCHECKED_CAST")
        fun unregister(context: Context, listener: Any) =
            context.getSystemService(ProfilingManager::class.java)
                .unregisterForAllProfilingResults(listener as Consumer<ProfilingResult>)

        private fun ProfilingResult.toMessage() = ProfilingResultMessage(
            errorCode = errorCode.toLong(),
            errorMessage = errorMessage,
            resultFilePath = resultFilePath,
            tag = tag,
            triggerType = if (Build.VERSION.SDK_INT >= ApiLevels.BAKLAVA) triggerType.toLong() else 0L,
        )
    }

    @RequiresApi(ApiLevels.BAKLAVA)
    private object Api36 {
        fun addTriggers(context: Context, triggers: List<ProfilingTriggerMessage>) =
            context.getSystemService(ProfilingManager::class.java).addProfilingTriggers(
                triggers.map { t ->
                    ProfilingTrigger.Builder(t.triggerType.toInt()).apply {
                        t.rateLimitingPeriodHours?.let { setRateLimitingPeriodHours(it.toInt()) }
                    }.build()
                },
            )

        fun removeTriggers(context: Context, types: IntArray) =
            context.getSystemService(ProfilingManager::class.java).removeProfilingTriggersByType(types)

        fun clearTriggers(context: Context) =
            context.getSystemService(ProfilingManager::class.java).clearProfilingTriggers()
    }

    private companion object {
        const val TAG = "AndroidDiagnostics"

        /** Plugin-defined: the device has no ProfilingManager. */
        const val ERROR_UNSUPPORTED = -1L
        const val ERROR_FAILED_INVALID_REQUEST = 7L
        const val ERROR_UNKNOWN = 8L

        fun failure(code: Long, message: String?, tag: String?) =
            ProfilingResultMessage(errorCode = code, errorMessage = message, tag = tag, triggerType = 0L)
    }
}
