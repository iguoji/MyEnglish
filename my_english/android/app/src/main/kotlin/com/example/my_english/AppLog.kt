// package 相当于 PHP namespace，必须与 Android application namespace 对应。
package com.example.my_english

// Context 提供 App 私有目录（filesDir），日志文件就放在这里。
import android.content.Context
// ContentResolver 负责把日志内容写到用户通过系统保存框选中的位置。
import android.content.ContentResolver
// Uri 是系统保存框返回的文件定位符。
import android.net.Uri
// 文件读写：追加写入日志、跨天清空、按字节拷贝导出。
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.OutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 全 App 唯一的运行日志内核（Kotlin 侧）。
 *
 * 设计目标就三条，和用户约定一一对应：
 * 1. **只有一个文件**：固定叫 `my_english.log`，放在 App 私有目录 filesDir 下；
 * 2. **只保留当天**：每次写入前检查文件第一行横幅里的日期，发现不是今天就整份清空重记；
 *    另外设一道 4MB 的保险，单日日志异常暴涨时也只留最新一段；
 * 3. **谁都能写**：Dart、数据库线程、音频下载线程都会调用，因此内部全部
 *    `@Synchronized` 串行化，行与行绝不会互相插队。
 *
 * 日志绝不允许影响主流程：写文件失败只静默吞掉，不抛异常、不阻塞调用方。
 * 导出走系统保存框（SAF）：由 MainActivity 发起，最后调用 [copyTo] 流式拷贝。
 */
object AppLog {
    // 固定文件名：全 App 只有这一个日志文件。
    private const val FILE_NAME = "my_english.log"

    // 单日容量保险：超过 4MB 就只保留横幅后重记，防止异常循环把磁盘写满。
    private const val MAX_FILE_BYTES = 4L * 1024 * 1024

    // 行内时间戳格式：精确到毫秒，复查时能看清两次操作的先后。
    private val timeFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)

    // 跨天判断用的日期键格式（yyyy-MM-dd）。
    private val dayFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)

    // applicationContext：生命周期比任何页面都长，导出时要用它拿 ContentResolver。
    @Volatile
    private var appContext: Context? = null

    // 当前日志文件对象；setup 之后才非空。
    private var logFile: File? = null

    // 上次写入时文件横幅里的日期；为空表示尚未初始化（下次写入时检查）。
    private var cachedDayKey: String? = null

    /** 初始化日志文件位置；MainActivity 创建数据库前调用一次即可。 */
    fun setup(context: Context) {
        // 只保留 applicationContext，避免把整个 Activity 长期攥在手里。
        appContext = context.applicationContext
        // 日志放在 App 私有目录 filesDir 下，无需任何存储权限。
        logFile = File(appContext?.filesDir, FILE_NAME)
        // 置空缓存日期：第一次写入时会检查横幅并决定要不要清空昨天的内容。
        cachedDayKey = null
    }

    /** 记一条 info 级日志。 */
    fun i(tag: String, message: String) = write("I", tag, message)

    /** 记一条 error 级日志。 */
    fun e(tag: String, message: String) = write("E", tag, message)

    /** 统一入口：拼行、跨天检查、追加写盘，全程串行且绝不抛出。 */
    @Synchronized
    private fun write(level: String, tag: String, message: String) {
        // 尚未 setup（例如单元测试直接引用）时静默跳过。
        val file = logFile ?: return
        try {
            // 先处理「新的一天」：横幅日期不是今天就把昨天的内容整份清掉。
            rolloverIfNeededLocked(file)
            // 再处理超限：文件超过 4MB 时同样只留横幅重新开始。
            if (file.length() > MAX_FILE_BYTES) file.writeText("")
            // 拼一行并追加；消息里的换行统一压成空格，保证一行一条记录。
            val line = buildString {
                append(timeFormat.format(Date()))
                append(' ')
                append(level)
                append(' ')
                append(tag)
                append(' ')
                append(message.replace('\n', ' ').replace('\r', ' '))
            }
            // 追加写：FileWriter(append=true) 不会覆盖前面已经记下的内容。
            FileOutputStream(file, true).use { stream ->
                stream.write(line.toByteArray(Charsets.UTF_8))
                stream.write('\n'.code)
            }
        } catch (_: Throwable) {
            // 日志失败绝不能反过来影响业务（磁盘满、目录被删等一律静默）。
        }
    }

    /** 跨天检查：横幅第一行以 `# yyyy-MM-dd` 开头，日期不是今天就清空重记。 */
    private fun rolloverIfNeededLocked(file: File) {
        // 今天的日期键。
        val today = dayFormat.format(Date())
        // 缓存键相同说明今天已经检查过，直接跳过读文件。
        if (today == cachedDayKey) return
        // 读文件第一行非空内容，判断横幅里记的是哪一天。
        val firstLine = file.takeIf { it.exists() }?.useLines { lines ->
            lines.firstOrNull { it.isNotBlank() }
        }
        val bannerDay = firstLine
            ?.takeIf { it.startsWith("# ") && it.length >= 12 }
            ?.substring(2, 12)
        // 横幅日期不是今天（或还没有横幅）→ 重写为今天的横幅。
        if (bannerDay != today) {
            file.writeText("# $today MyEnglish 运行日志（仅保留当天，次日启动自动清空）")
        }
        // 记下今天，本次会话内不再重复读文件判断。
        cachedDayKey = today
    }

    /** 读取当前日志全文（导出与调试用）；文件不存在时返回空串。 */
    @Synchronized
    fun readText(): String {
        val file = logFile ?: return ""
        return try {
            // 文件不存在时 readText 会抛异常，先判存在再读。
            if (file.exists()) file.readText(Charsets.UTF_8) else ""
        } catch (_: Throwable) {
            ""
        }
    }

    /** 把日志文件流式拷贝到系统保存框选中的 Uri；找不到文件时抛 IOException。 */
    fun copyTo(uri: Uri) {
        // 拷贝全程不加锁：写日志侧只是追加小行，读到哪算哪即可。
        val file = logFile ?: throw IOException("日志文件尚未初始化")
        if (!file.exists()) throw IOException("日志文件不存在")
        val resolver = appContext?.contentResolver ?: throw IOException("日志系统未初始化")
        copyStream(FileInputStream(file), resolver, uri)
    }

    /** 拷贝字节流：边读边写，2MB 量级也不占大内存。 */
    private fun copyStream(input: java.io.InputStream, resolver: ContentResolver, uri: Uri) {
        // use 类似 PHP 的 try/finally，离开作用域自动关闭流。
        input.use { source ->
            val output: OutputStream = resolver.openOutputStream(uri)
                ?: throw IOException("无法打开文件输出流：$uri")
            output.use { sink ->
                // 8KB 缓冲往返拷贝。
                val buffer = ByteArray(8 * 1024)
                while (true) {
                    val count = source.read(buffer)
                    // -1 表示读到了文件末尾。
                    if (count < 0) break
                    sink.write(buffer, 0, count)
                }
                // 显式 flush 确保全部落盘再返回。
                sink.flush()
            }
        }
    }
}
