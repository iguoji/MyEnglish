// package 与播放器一致，使内部类不需要扩大为公共 API。
package com.example.my_english

// AtomicInteger 让四个下载线程可以安全更新计数。
import java.util.concurrent.atomic.AtomicInteger

/** 一次离线缓存进度快照，字段会直接映射到 Dart 的进度事件。 */
internal data class PrecacheProgressSnapshot(
    // 真正在磁盘形成有效 MP3 的任务数。
    val cached: Int,
    // 本批需要处理的美式与英式任务总数。
    val total: Int,
    // true 表示全部任务都已结束，而不是表示全部下载成功。
    val done: Boolean,
)

/**
 * 线程安全的预缓存计数器。
 *
 * “任务结束”和“缓存成功”是两套不同计数：网络失败也会让整批最终结束，
 * 但绝不能让界面百分比增加。独立成纯 Kotlin 类后可用 JVM 测试直接验证。
 */
internal class PrecacheProgress(private val total: Int) {
    // completed 只记录已有多少任务结束，用来判断 done。
    private val completed = AtomicInteger(0)

    // cached 只记录成功命中或写入有效 MP3 的任务数。
    private val cached = AtomicInteger(0)

    /** 记录一个任务的结果，并返回这一时刻的一致快照。 */
    fun finish(cacheSucceeded: Boolean): PrecacheProgressSnapshot {
        // 只有成功任务才推进用户看到的缓存数。
        if (cacheSucceeded) cached.incrementAndGet()
        // 成功和失败都会结束任务，保证失败不会让进度条永久悬挂。
        val finished = completed.incrementAndGet()
        // cached.get 在所有自增之后读取，可能包含其他线程刚完成的更多成功，属于合法最新进度。
        return PrecacheProgressSnapshot(
            cached = cached.get(),
            total = total,
            done = finished >= total,
        )
    }

    /** 执行器关闭时读取真实成功数，并显式结束本批界面状态。 */
    fun stopped(): PrecacheProgressSnapshot {
        // 不伪造剩余任务成功，仅把 done 设为 true 让界面停止等待。
        return PrecacheProgressSnapshot(cached = cached.get(), total = total, done = true)
    }
}
