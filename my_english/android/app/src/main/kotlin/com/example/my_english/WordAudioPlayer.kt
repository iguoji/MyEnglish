// package 相当于 PHP namespace，与 MainActivity 保持一致。
package com.example.my_english

// Context 提供 App 私有缓存目录。
import android.content.Context
// AudioAttributes 告诉系统当前媒体属于语音内容。
import android.media.AudioAttributes
// MediaPlayer 使用 Android 成熟的系统解码器播放本地 mp3。
import android.media.MediaPlayer
// Handler 与 Looper 用来把下载结果切回 Android 主线程操作播放器。
import android.os.Handler
import android.os.Looper
// Base64 把任意拼写转换成不会破坏文件路径的缓存文件名。
import android.util.Base64
// MethodChannel.Result 保存 Dart 这次 play 调用，直到播放完成才返回。
import io.flutter.plugin.common.MethodChannel
// File 管理 App 私有音频缓存。
import java.io.File
// HttpURLConnection 负责按 README 地址下载网络音频。
import java.net.HttpURLConnection
// URLEncoder 安全编码空格、斜线等特殊字符。
import java.net.URLEncoder
// UTF-8 保证拼写编码在不同设备上一致。
import java.nio.charset.StandardCharsets
// Locale.ROOT 避免土耳其语等系统区域影响英文小写缓存键。
import java.util.Locale
// Executors 提供单独下载线程，避免阻塞 Flutter 页面。
import java.util.concurrent.Executors

/**
 * 单词音频下载、缓存和播放服务。
 *
 * 查找顺序固定为：口音对应的本地缓存 -> 不背单词 -> 有道。下载成功后先写临时文件，
 * 再原子替换正式缓存，避免网络中断留下一个看似存在但无法播放的残缺 mp3。
 */
class WordAudioPlayer(context: Context) {
    // 保存 applicationContext，生命周期独立于单个 Activity 页面。
    private val appContext = context.applicationContext

    // 单线程让缓存写入顺序稳定，也避免同一文件被并发覆盖。
    private val downloadExecutor = Executors.newSingleThreadExecutor()

    // MediaPlayer 的创建和回调都回到 Android 主线程。
    private val mainHandler = Handler(Looper.getMainLooper())

    // volatile 让下载线程总能看见最新请求编号。
    @Volatile
    private var requestGeneration = 0L

    // 当前真正准备或播放中的系统播放器。
    private var mediaPlayer: MediaPlayer? = null

    // 当前尚未返回 Dart 的 play 结果。
    private var pendingResult: MethodChannel.Result? = null

    /** 开始播放；同一个页面后来的请求会立即替换先前请求。 */
    fun play(spelling: String, accent: String, result: MethodChannel.Result) {
        // 清理首尾空格，防止生成无意义 URL。
        val normalizedSpelling = spelling.trim()
        // 空拼写无法请求发音，直接返回清晰参数错误。
        if (normalizedSpelling.isEmpty()) {
            result.error("AUDIO_ARGUMENT_ERROR", "单词拼写不能为空", null)
            return
        }
        // 缓存目录只接受两个已约定口音值。
        if (accent != AMERICAN && accent != BRITISH) {
            result.error("AUDIO_ARGUMENT_ERROR", "不支持的发音口音：$accent", null)
            return
        }

        // 递增编号会让仍在下载的旧任务失效。
        requestGeneration += 1
        // 保存当前请求编号供异步阶段逐次核验。
        val generation = requestGeneration
        // 停止旧播放器，并让旧 Dart Future 以“已被替换”结束。
        interruptCurrent("AUDIO_INTERRUPTED", "已开始播放另一个单词")
        // 当前 play 调用要等到完成或失败时再回传。
        pendingResult = result

        // 下载和文件 IO 放入后台线程。
        downloadExecutor.execute {
            try {
                // 先查缓存，没有时依次请求两个来源。
                val audioFile = resolveAudioFile(normalizedSpelling, accent, generation)
                // MediaPlayer 必须回到主线程创建和启动。
                mainHandler.post {
                    // 若用户期间点击了其他单词，旧文件只保留缓存但绝不播放。
                    if (generation != requestGeneration) return@post
                    // 使用完整本地文件启动系统播放器。
                    startPlayer(audioFile, generation)
                }
            } catch (error: Throwable) {
                // 下载异常同样切回主线程，只结束仍属于当前编号的请求。
                mainHandler.post {
                    if (generation != requestGeneration) return@post
                    // 把两个音源最终失败原因返回 Dart SnackBar。
                    finishWithError(
                        "AUDIO_DOWNLOAD_FAILED",
                        error.message ?: error.javaClass.simpleName,
                    )
                }
            }
        }
    }

    /** 页面销毁或 App 进入后台时主动停止。 */
    fun stop(result: MethodChannel.Result) {
        // 让后台中的旧下载完成后不能再启动播放器。
        requestGeneration += 1
        // 释放播放器并结束尚未完成的旧 play Future。
        interruptCurrent("AUDIO_STOPPED", "播放已停止")
        // 当前 stop 调用本身正常完成。
        result.success(null)
    }

    /** Activity 销毁时释放系统资源和下载线程。 */
    fun dispose() {
        // 使所有尚未回到主线程的任务失效。
        requestGeneration += 1
        // 销毁阶段不再向已经关闭的 Dart 引擎发送结果。
        pendingResult = null
        // 安全释放播放器。
        releasePlayer()
        // 不再接收新下载任务；队列中任务结束后线程自动退出。
        downloadExecutor.shutdown()
    }

    /** 先读取口音缓存；不存在时按来源顺序下载。 */
    private fun resolveAudioFile(spelling: String, accent: String, generation: Long): File {
        // 美式与英式使用独立子目录，绝不会命中另一种口音文件。
        val accentDirectory = File(appContext.cacheDir, "word_audio/$accent")
        // 第一次使用时递归创建目录。
        check(accentDirectory.exists() || accentDirectory.mkdirs()) {
            "无法创建音频缓存目录"
        }
        // 小写后做 URL-safe Base64，既复用大小写相同单词又不引入斜线。
        val cacheKey = Base64.encodeToString(
            spelling.lowercase(Locale.ROOT).toByteArray(StandardCharsets.UTF_8),
            Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING,
        )
        // mp3 后缀帮助 MediaPlayer 判断文件容器格式。
        val target = File(accentDirectory, "$cacheKey.mp3")
        // 只有带有效 MP3 文件头的文件才算缓存，旧残缺文件会先删除。
        if (isLikelyMp3(target)) return target
        // 无效旧缓存不能反复交给 MediaPlayer。
        if (target.exists()) target.delete()

        // README 的两个来源已按业务优先级生成。
        val sources = buildSources(spelling, accent)
        // 保存每个来源的简短失败原因，最终一起提供给用户排查。
        val failures = mutableListOf<String>()
        // 从不背单词开始逐个尝试。
        for ((sourceName, url) in sources) {
            try {
                // 用户已点击其他单词时立即停止当前旧任务，不继续占用下载队列。
                ensureRequestIsActive(generation)
                // 任一来源下载成功便立即返回缓存文件。
                downloadToCache(url, target, generation)
                return target
            } catch (error: Throwable) {
                // 被新请求替换时直接结束旧任务，不再尝试第二来源。
                if (generation != requestGeneration) throw error
                // 记录来源名，避免最终只看到模糊的“网络错误”。
                failures += "$sourceName：${error.message ?: error.javaClass.simpleName}"
            }
        }
        // 两个来源都失败才抛出汇总错误。
        error(failures.joinToString("；"))
    }

    /** 根据口音生成“不背单词 -> 有道”的准确 HTTPS URL。 */
    private fun buildSources(spelling: String, accent: String): List<Pair<String, String>> {
        // URLEncoder 默认把空格写成 +，路径中改用标准 %20。
        val encodedSpelling = URLEncoder.encode(
            spelling,
            StandardCharsets.UTF_8.toString(),
        ).replace("+", "%20")
        // 不背单词使用 US 或 UK 路径。
        val beingFineAccent = if (accent == AMERICAN) "US" else "UK"
        // 有道 type=2 是美式，type=1 是英式。
        val youdaoType = if (accent == AMERICAN) "2" else "1"
        // List 保持明确优先级。
        return listOf(
            // 第一优先：不背单词。
            "不背单词" to
                "https://audio.beingfine.cn/speeches/$beingFineAccent/" +
                "$beingFineAccent-speech/$encodedSpelling.mp3",
            // 第二优先：有道。
            "有道" to
                "https://dict.youdao.com/dictvoice?audio=$encodedSpelling&type=$youdaoType",
        )
    }

    /** 下载到临时文件，确认响应有效后再替换正式缓存。 */
    private fun downloadToCache(url: String, target: File, generation: Long) {
        // openConnection 返回通用连接，这里明确收窄为 HTTPS 所属的 HTTP API。
        val connection = java.net.URL(url).openConnection() as HttpURLConnection
        // 连接超时避免无网络时长时间卡住“播放中”状态。
        connection.connectTimeout = NETWORK_TIMEOUT_MILLIS
        // 读取超时同样限制单个来源等待时间。
        connection.readTimeout = NETWORK_TIMEOUT_MILLIS
        // 服务端跳转时继续跟随最终音频地址。
        connection.instanceFollowRedirects = true
        // 提供普通移动端标识，减少部分 CDN 拒绝空 User-Agent。
        connection.setRequestProperty("User-Agent", "MyEnglish/1.0 Android")
        // 当前请求独立的临时文件。
        val temporary = File(target.parentFile, "${target.name}.$generation.download")

        try {
            // 发起连接并取得状态码。
            val statusCode = connection.responseCode
            // 只有 2xx 才可能是有效音频。
            check(statusCode in 200..299) { "HTTP $statusCode" }
            // HTML 错误页即使返回 200 也不能保存成 mp3。
            val contentType = connection.contentType?.lowercase(Locale.ROOT).orEmpty()
            // 接受标准 audio、通用二进制和缺失类型；JSON/HTML 等响应一律拒绝。
            val acceptedContentType = contentType.isEmpty() ||
                contentType.startsWith("audio/") ||
                contentType.contains("octet-stream") ||
                contentType.contains("binary") ||
                contentType.contains("mpeg") ||
                contentType.contains("mp3")
            // 非音频响应不能伪装成缓存 mp3。
            check(acceptedContentType) {
                "返回内容不是音频（$contentType）"
            }
            // 清理同编号可能遗留的临时文件。
            if (temporary.exists()) temporary.delete()
            // use 类似 PHP finally，会自动关闭输入流。
            connection.inputStream.use { input ->
                // outputStream 同样自动关闭并刷新磁盘缓冲。
                temporary.outputStream().use { output ->
                    // 8KB 缓冲分块读取，避免把整个 mp3 一次装入内存。
                    val buffer = ByteArray(DOWNLOAD_BUFFER_BYTES)
                    // 循环直到输入流结束。
                    while (true) {
                        // 每一块之前确认用户没有切换到另一个单词。
                        ensureRequestIsActive(generation)
                        // 读取下一块；-1 表示下载结束。
                        val bytesRead = input.read(buffer)
                        // 没有更多数据时退出循环。
                        if (bytesRead == -1) break
                        // 只写入本次真正读取到的字节数。
                        output.write(buffer, 0, bytesRead)
                    }
                }
            }
            // 响应必须具有标准 ID3 或 MPEG frame sync 文件头。
            check(isLikelyMp3(temporary)) { "返回内容没有有效 MP3 文件头" }
            // 若其他任务已经生成正式文件，保留那个有效结果。
            if (isLikelyMp3(target)) {
                temporary.delete()
                return
            }
            // 同目录 rename 通常是原子操作，不会暴露半文件。
            if (!temporary.renameTo(target)) {
                // 极少数文件系统不支持 rename 时使用覆盖复制兜底。
                temporary.copyTo(target, overwrite = true)
                // 复制成功后删除临时文件。
                temporary.delete()
            }
        } finally {
            // 失败或成功都删除残留临时文件。
            if (temporary.exists()) temporary.delete()
            // 释放底层 HTTP socket。
            connection.disconnect()
        }
    }

    /** 确认后台任务仍属于当前点击请求。 */
    private fun ensureRequestIsActive(generation: Long) {
        // check 失败会抛出异常并进入 finally 清理临时文件和连接。
        check(generation == requestGeneration) { "播放请求已被新单词替换" }
    }

    /** 读取文件开头，快速排除 HTML、JSON、空文件和残缺缓存。 */
    private fun isLikelyMp3(file: File): Boolean {
        // 至少需要三个字节才能识别 ID3 标记。
        if (!file.isFile || file.length() < 3L) return false
        // inputStream.use 确保检查后立即关闭文件句柄。
        return file.inputStream().use { input ->
            // 读取前三个无符号字节。
            val first = input.read()
            val second = input.read()
            val third = input.read()
            // 带元数据的 MP3 通常以 ASCII "ID3" 开始。
            val hasId3Header = first == 'I'.code && second == 'D'.code && third == '3'.code
            // 无 ID3 的 MP3 通常直接以 11 位 MPEG frame sync 开始。
            val hasFrameSync = first == 0xFF && (second and 0xE0) == 0xE0
            // 任一合法开头即可交给 MediaPlayer。
            hasId3Header || hasFrameSync
        }
    }

    /** 用 Android MediaPlayer 播放已经完整缓存的本地文件。 */
    private fun startPlayer(audioFile: File, generation: Long) {
        try {
            // 创建本次独立播放器，旧实例已经在 play 开头释放。
            val player = MediaPlayer()
            // 保存引用，stop 与 dispose 才能立即释放它。
            mediaPlayer = player
            // 声明这是语音媒体，系统会按媒体音量处理。
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .build(),
            )
            // 只把本地缓存路径交给播放器，播放阶段不再依赖网络。
            player.setDataSource(audioFile.absolutePath)
            // 异步准备完成后再开始，避免主线程解码阻塞。
            player.setOnPreparedListener { preparedPlayer ->
                // 请求被替换时直接释放，不允许旧单词突然出声。
                if (generation != requestGeneration || mediaPlayer !== preparedPlayer) {
                    preparedPlayer.release()
                    return@setOnPreparedListener
                }
                // 当前请求仍有效，开始播放。
                preparedPlayer.start()
            }
            // 播放自然结束时完成 Dart Future，页面会隐藏动画喇叭。
            player.setOnCompletionListener { completedPlayer ->
                // 只结束仍属于当前请求的结果。
                if (generation == requestGeneration && mediaPlayer === completedPlayer) {
                    // 先释放播放器。
                    releasePlayer()
                    // 再向 Dart 返回成功。
                    pendingResult?.success(null)
                    // 清空结果避免重复回传。
                    pendingResult = null
                }
            }
            // 解码或播放错误转成用户可见失败。
            player.setOnErrorListener { failedPlayer, what, extra ->
                // 只处理当前播放器。
                if (generation == requestGeneration && mediaPlayer === failedPlayer) {
                    // 返回系统错误编号，便于真机定位格式问题。
                    finishWithError("AUDIO_PLAYBACK_FAILED", "播放器错误 what=$what extra=$extra")
                }
                // true 表示错误已经由这里处理。
                true
            }
            // prepareAsync 不阻塞 Flutter 主线程。
            player.prepareAsync()
        } catch (error: Throwable) {
            // setDataSource 等同步错误也走统一错误出口。
            finishWithError(
                "AUDIO_PLAYBACK_FAILED",
                error.message ?: error.javaClass.simpleName,
            )
        }
    }

    /** 停掉旧播放器并结束旧的 Dart play Future。 */
    private fun interruptCurrent(code: String, message: String) {
        // 先释放系统音频资源。
        releasePlayer()
        // 如果旧请求仍在等待，明确告诉它已被替换或停止。
        pendingResult?.error(code, message, null)
        // MethodChannel.Result 只能回传一次，因此立即清空引用。
        pendingResult = null
    }

    /** 当前请求以错误结束。 */
    private fun finishWithError(code: String, message: String) {
        // 错误后必须释放可能处于 prepare 状态的播放器。
        releasePlayer()
        // 把具体错误返回 Dart。
        pendingResult?.error(code, message, null)
        // 防止后续回调重复返回。
        pendingResult = null
    }

    /** 对 MediaPlayer 做幂等释放。 */
    private fun releasePlayer() {
        // 先保存局部引用并清空字段，避免释放过程中的回调再次命中当前对象。
        val player = mediaPlayer
        // 页面状态立即视为没有播放器。
        mediaPlayer = null
        // release 对任何准备/播放阶段都有效；没有实例时安全跳过。
        player?.release()
    }

    /** 稳定协议值和超时集中定义。 */
    private companion object {
        // 美式缓存目录名与 Dart storageValue 一致。
        const val AMERICAN = "american"

        // 英式缓存目录名与 Dart storageValue 一致。
        const val BRITISH = "british"

        // 每个网络来源最多等待 8 秒。
        const val NETWORK_TIMEOUT_MILLIS = 8_000

        // 下载时每次读取 8KB，兼顾内存与 IO 次数。
        const val DOWNLOAD_BUFFER_BYTES = 8 * 1024
    }
}
