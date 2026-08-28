// package 与播放器一致，使内部类不需要扩大为公共 API。
package com.example.my_english

// AtomicInteger 让四个下载线程可以安全更新计数。
import java.util.concurrent.atomic.AtomicInteger

/** 一次离线缓存进度快照，字段会直接映射到 Dart 的进度事件。 */
internal data class PrecacheProgressSnapshot(
    // 当前进度条分子；对于单词级计数器是完整缓存单词数，对于任务级计数器是成功任务数。
    val cached: Int,
    // 当前进度条分母；由创建该快照的计数器决定是单词数还是任务数。
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

// 与 WordAudioPlayer 中 AMERICAN/BRITISH 协议值一致；独立成文件后避免重复魔法字符串。
private const val AMERICAN = "american"
private const val BRITISH = "british"

/**
 * 全渠道离线缓存专用的单词级进度计数器。
 *
 * 任务会按“单词 × 口音 × 网络渠道”并发执行，但 Dart 界面只需要知道：
 * “还有多少个单词没凑齐同一家渠道的美式 + 英式”。因此这里保存每个单词、每个渠道
 * 已成功缓存的口音集合，只有某个渠道第一次同时拥有美式和英式时，才增加 cached。
 */
internal class PrecacheWordProgress(
    // Dart 进度条的分母：词库单词数。
    private val total: Int,
    // 判断整批是否结束所需的任务数：单词数 × 美/英 × 网络渠道数。
    private val taskCount: Int,
    // 启动本批前磁盘上已经存在的部分/完整缓存状态。
    initialStates: Map<Int, Map<String, Set<String>>> = emptyMap(),
) {
    // 所有状态读写都放进同一把锁，避免四个下载线程把“判断是否完整”和“写入口音”拆成两步。
    private val lock = Any()

    // wordIndex -> channel -> 已成功缓存的口音集合。
    private val states = HashMap<Int, MutableMap<String, MutableSet<String>>>()

    // 已完整缓存的单词数：任意渠道同时拥有美式和英式即计为 1。
    private val cached = AtomicInteger(0)

    // 已经结束的任务数，用来判断 done。
    private val completed = AtomicInteger(0)

    init {
        // 把调用方传来的不可变初始状态复制成本类可继续修改的结构。
        for ((wordIndex, channels) in initialStates) {
            val mutableChannels = HashMap<String, MutableSet<String>>()
            for ((channel, accents) in channels) {
                mutableChannels[channel] = accents.toMutableSet()
            }
            states[wordIndex] = mutableChannels
            if (isWordCompleteLocked(wordIndex)) cached.incrementAndGet()
        }
    }

    /**
     * 记录一个渠道/口音任务的结果，并返回这一时刻的一致快照。
     *
     * [cacheSucceeded] 为 false 时只推进任务结束数；为 true 时把该口音写入对应渠道，
     * 若这个单词因此第一次凑齐同一渠道的美式 + 英式，才增加 cached。
     */
    fun finish(
        wordIndex: Int,
        channel: String,
        accent: String,
        cacheSucceeded: Boolean,
    ): PrecacheProgressSnapshot {
        if (cacheSucceeded) {
            synchronized(lock) {
                val channels = states.getOrPut(wordIndex) { HashMap() }
                val accents = channels.getOrPut(channel) { mutableSetOf() }
                // 必须在写入前先记住是否已经完整，避免同一渠道第二次口音成功时重复计数。
                val wasComplete = isWordCompleteLocked(wordIndex)
                accents += accent
                if (!wasComplete && isWordCompleteLocked(wordIndex)) {
                    cached.incrementAndGet()
                }
            }
        }
        val finished = completed.incrementAndGet()
        return PrecacheProgressSnapshot(
            cached = cached.get(),
            total = total,
            done = finished >= taskCount,
        )
    }

    /** 执行器关闭时读取真实成功数，并显式结束本批界面状态。 */
    fun stopped(): PrecacheProgressSnapshot {
        return PrecacheProgressSnapshot(cached = cached.get(), total = total, done = true)
    }

    /** 仅在持有 [lock] 时调用，判断某个单词是否已有渠道同时拥有美式和英式。 */
    private fun isWordCompleteLocked(wordIndex: Int): Boolean {
        val channels = states[wordIndex] ?: return false
        return channels.values.any { accents ->
            AMERICAN in accents && BRITISH in accents
        }
    }
}
