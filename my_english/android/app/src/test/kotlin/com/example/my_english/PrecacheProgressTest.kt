// package 与被测内部类一致，因此测试无需把生产实现暴露为 public。
package com.example.my_english

// JUnit 提供基础测试注解和断言。
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
// Executors 用并发任务验证 AtomicInteger 计数不会丢失。
import java.util.concurrent.Executors
// TimeUnit 为测试线程池设置明确超时，失败时不会永久卡住 Gradle。
import java.util.concurrent.TimeUnit

/** 验证失败任务、批次结束和并发计数的真实语义。 */
class PrecacheProgressTest {
    /** 失败任务只推进完成数，不能被算成已缓存文件。 */
    @Test
    fun failedTaskDoesNotIncreaseCachedCount() {
        // 本批共两个任务。
        val progress = PrecacheProgress(total = 2)
        // 第一个任务下载失败。
        val first = progress.finish(cacheSucceeded = false)
        // 缓存数必须保持 0，并且整批尚未结束。
        assertEquals(0, first.cached)
        assertFalse(first.done)

        // 第二个任务成功后整批结束。
        val second = progress.finish(cacheSucceeded = true)
        // 两个任务只成功一个，所以百分比口径是 1/2，而不是错误的 2/2。
        assertEquals(1, second.cached)
        assertEquals(2, second.total)
        assertTrue(second.done)
    }

    /** 多线程同时结束任务时不能丢失成功计数。 */
    @Test
    fun concurrentTasksKeepExactSuccessfulCount() {
        // 200 个任务中偶数编号成功，预期恰好 100 个缓存。
        val progress = PrecacheProgress(total = 200)
        // 使用与真实播放器相同的四线程并发规模。
        val executor = Executors.newFixedThreadPool(4)
        // 投递全部任务。
        repeat(200) { index ->
            executor.execute { progress.finish(cacheSucceeded = index % 2 == 0) }
        }
        // 不再接收新任务，并等待现有任务结束。
        executor.shutdown()
        assertTrue(executor.awaitTermination(5, TimeUnit.SECONDS))

        // stopped 只读取真实缓存数，不会把失败的一半补成成功。
        val snapshot = progress.stopped()
        assertEquals(100, snapshot.cached)
        assertEquals(200, snapshot.total)
        assertTrue(snapshot.done)
    }
}
