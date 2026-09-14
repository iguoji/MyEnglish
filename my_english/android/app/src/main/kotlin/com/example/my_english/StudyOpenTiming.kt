package com.example.my_english

import android.os.SystemClock

/**
 * 只响应 Flutter 显式附带的诊断编号，普通调用不创建计时对象。
 * 各阶段仅采样时钟，最后一次写日志；阶段是前后相邻节点的差，单位微秒。
 * channel 中的总工作时间包含 repository 的各阶段，分析时不能重复相加。
 */
internal class StudyOpenTiming private constructor(
    private val traceId: String,
    private val scope: String,
) {
    companion object {
        fun from(arguments: Any?, scope: String): StudyOpenTiming? {
            val id = (arguments as? Map<*, *>)?.get("_open_trace_id") as? String
            return id?.let { StudyOpenTiming(it, scope) }
        }
    }

    private val started = SystemClock.elapsedRealtimeNanos()
    private val marks = linkedMapOf<String, Long>("start" to 0L)

    fun mark(name: String) {
        marks[name] = (SystemClock.elapsedRealtimeNanos() - started) / 1000
    }

    fun write() {
        AppLog.i("study_open_native", encode(mapOf(
            "trace_id" to traceId, "scope" to scope, "marks_us" to marks,
        )))
    }
}
