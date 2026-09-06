// package 相当于 PHP namespace，与 MainActivity 保持一致。
package com.example.my_english

// Context 提供 App 私有缓存目录。
import android.content.Context
// AudioManager 负责申请系统音频焦点，让 Android 在切换到蓝牙耳机时正确安排媒体输出。
import android.media.AudioFocusRequest
import android.media.AudioManager
// ConnectivityManager / NetworkCapabilities 用来判断当前设备是否明确没有网络。
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
// AudioAttributes 告诉系统当前媒体属于语音内容。
import android.media.AudioAttributes
// MediaPlayer 使用 Android 成熟的系统解码器播放本地 mp3。
import android.media.MediaPlayer
// TextToSpeech 调用用户设备当前选择的系统语音引擎。
import android.speech.tts.TextToSpeech
// UtteranceProgressListener 接收系统 TTS 的开始、完成和失败事件。
import android.speech.tts.UtteranceProgressListener
// Handler 与 Looper 用来把下载结果切回 Android 主线程操作播放器。
import android.os.Handler
import android.os.Looper
// Bundle 保存 TextToSpeech.speak 的参数。
import android.os.Bundle
// Base64 把任意拼写转换成不会破坏文件路径的缓存文件名。
import android.util.Base64
// Log 记录网络音频失败的时间窗口，便于真机排查网络兜底行为。
import android.util.Log
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
// ConcurrentHashMap 提供线程安全的“后台补缓存去重集合”。
import java.util.concurrent.ConcurrentHashMap
// CountDownLatch 让清空缓存等待主线程完成停止播放器。
import java.util.concurrent.CountDownLatch
// TimeUnit 为等待主线程停止动作提供明确的时间单位。
import java.util.concurrent.TimeUnit
// AtomicLong 让主线程与 I/O 线程递增批次/缓存纪元时不会发生丢更新。
import java.util.concurrent.atomic.AtomicLong

// androidx.media 提供媒体会话与 MediaStyle 通知（锁屏/蓝牙控制的标准机制）。
// 注意：这些兼容类在 androidx.media 库中仍保留历史包名 android.support.v4.media.*。
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.media.app.NotificationCompat.MediaStyle
// androidx.core 提供兼容的通知构造器。
import androidx.core.app.NotificationCompat
// 系统通知管理器与通知渠道所需。
import android.app.NotificationChannel
import android.app.NotificationManager
// 点击通知回到 App 主界面所需的意图。
import android.app.PendingIntent
// 复用本包内的 Activity 类，点击通知时回到随身听页面所在的主界面。
import android.content.Intent
// Android 8+ 创建通知渠道需要判断系统版本。
import android.os.Build

/**
 * 单词音频下载、缓存和播放服务。
 *
 * 4.5.0 起的主入口是 [playSmart]（智能轮转）：在“本周期未读且有本地缓存”的网络渠道
 * 间点名播放，缺缓存的渠道后台并发补齐并给短暂下载窗口，全部不可用才由系统 TTS 兜底。
 * [play] 与 [playChannel] 保留为历史固定顺序/点名播放路径，已不再被 Dart 调用。
 * 下载成功后先写临时文件，再原子替换正式缓存，避免网络中断留下一个看似存在但无法播放
 * 的残缺 mp3；TTS 只选择设备标记为不需要网络的英语声音。
 */
class WordAudioPlayer(
    context: Context,
    channel: MethodChannel,
    private val database: WordsDatabase,
) {
    // 保存 applicationContext，生命周期独立于单个 Activity 页面。
    private val appContext = context.applicationContext

    // 音频方法通道：既接收 Dart 的 play/stop，也用于把锁屏/蓝牙的媒体控制事件回传 Dart。
    private val mediaChannel = channel

    // 系统通知管理器：负责弹出/刷新/移除".media style"通知（锁屏与通知栏控制）。
    private val notificationManager =
        appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    // 媒体会话：Android 标准机制，把播放状态暴露给系统锁屏、通知栏与蓝牙耳机。
    // 懒创建，首次 showMediaSession 时才初始化，避免一启动就占用系统资源。
    private var mediaSession: MediaSessionCompat? = null

    // 当前通知标题（单词拼写）与副标题（首条释义），刷新通知时复用，避免回读控制器。
    private var currentTitle = ""
    private var currentSubtitle = ""

    // 单线程让缓存写入顺序稳定，也避免同一文件被并发覆盖。
    private val downloadExecutor = Executors.newSingleThreadExecutor()

    // 离线预缓存专用线程池：固定 4 并发，既利用带宽又避免一次性请求过多被音源限流。
    // 它与播放用的单线程池完全独立，因此批量缓存不会阻塞用户点单词时的即时播放。
    private val precacheExecutor = Executors.newFixedThreadPool(4)

    // 预缓存批次编号；每次新的一轮预缓存会让上一批尚未完成的任务主动退出，
    // 避免重复下载同一批单词。
    private val precacheGeneration = AtomicLong(0L)

    // 每次清空缓存都会递增纪元；清空前启动的下载不能在删除完成后重新写回正式文件。
    private val cacheEpoch = AtomicLong(0L)

    // 正式缓存文件替换与目录清空共用短临界区，避免 rename/delete 在同一瞬间交错。
    private val cacheMutationLock = Any()

    // MediaPlayer 的创建和回调都回到 Android 主线程。
    private val mainHandler = Handler(Looper.getMainLooper())

    // 所有单词发音统一按“媒体语音”申请音频焦点；蓝牙耳机通常就是通过这个媒体通道接收声音。
    private val speechAudioAttributes = AudioAttributes.Builder()
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .build()

    // 系统音频管理器：负责音频焦点，而不是直接控制蓝牙设备。
    private val audioManager =
        appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    // Android 8 及以上使用 AudioFocusRequest；旧版本走兼容的旧式申请接口。
    private var audioFocusRequest: AudioFocusRequest? = null

    // 标记当前是否持有音频焦点，避免重复申请或重复释放。
    private var hasAudioFocus = false

    // 音频焦点变化时回到主线程停止当前单词，避免其他应用或系统切换输出时静默失败。
    private val audioFocusChangeListener = AudioManager.OnAudioFocusChangeListener { change ->
        mainHandler.post {
            when (change) {
                // 允许其他短暂声音把本次单词音量压低，不打断用户正在听的发音。
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> Unit

                // 暂时或永久失去焦点时停止本次播放，并把原因回传给 Flutter 页面。
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
                AudioManager.AUDIOFOCUS_LOSS,
                -> {
                    if (hasAudioFocus || mediaPlayer != null || pendingTtsUtteranceId != null) {
                        // 智能轮转播放被打断：回滚记账，让该渠道下次还能重新点名。
                        clearActiveLedger(unmark = true)
                        releasePlayer()
                        textToSpeech?.stop()
                        pendingTtsRequest = null
                        pendingTtsUtteranceId = null
                        pendingResult?.error(
                            "AUDIO_FOCUS_LOST",
                            "系统音频输出暂时被其他应用占用，请重新点击发音",
                            null,
                        )
                        pendingResult = null
                    }
                }
            }
        }
    }

    // volatile 让下载线程总能看见最新请求编号。
    @Volatile
    private var requestGeneration = 0L

    // 当前真正准备或播放中的系统播放器。
    private var mediaPlayer: MediaPlayer? = null

    // 当前尚未返回 Dart 的 play 结果。
    private var pendingResult: MethodChannel.Result? = null

    // 内存中的失败截止时间；进程重启后从 settings 表恢复。
    //
    // 生活化解释：网络发音接口挂掉时，没必要每读一个词都去撞一次墙。
    // 这里记一个「几点之前别再试了」的时间点，期间直接用系统 TTS 发声。
    // 它是全项目唯一一处「非用户设置」也放进设置表的值——因为规矩是
    // 除了离线语音文件，任何需要跨进程留存的东西都只能进这一张表。
    @Volatile
    private var networkAudioUnavailableUntilMillis = readNetworkFailureDeadline()

    // 系统 TTS 实例；真正发声的引擎可能是 Google、厂商或用户安装的其他引擎。
    private var textToSpeech: TextToSpeech? = null

    // TTS 初始化成功后才能查询声音并调用 speak。
    private var ttsInitialized = false

    // 记录 TTS 初始化失败，避免每次网络失败都重复等待无效初始化。
    private var ttsInitializationFailed = false

    // TTS 初始化尚未完成时，暂存当前有效播放请求的兜底动作。
    private var pendingTtsRequest: (() -> Unit)? = null

    // 当前 TTS utterance 的唯一编号；用来过滤旧单词迟到的回调。
    private var pendingTtsUtteranceId: String? = null

    // 智能轮转播放（playSmart）的记账本：key=(拼写|口音)，value=本周期已经朗读过的
    // 网络渠道。每次点击只从「有缓存且本周期还没读过」的渠道里挑一个出声，全部读过
    // 一遍才清空进入下一周期。系统 TTS 不记账、不参与点名，永远只做最后兜底。
    private val rotationLedger = HashMap<String, MutableSet<String>>()

    // 当前正在出声的记账条目（账本 key 到渠道）。播放自然完成时保留记账（下轮换人）；
    // 播放失败、被打断或失去音频焦点时回滚记账，让该渠道下次还能被点名重读。
    @Volatile
    private var activeLedgerEntry: Pair<String, String>? = null

    // 后台补缓存的去重集合：同一个 (词,口音,渠道) 同时只允许一个下载任务在跑，
    // 手快连点或上一题刚触发过下载时，不会并发发起两个一模一样的下载。
    private val backgroundFetchKeys = ConcurrentHashMap.newKeySet<String>()

    init {
        // TTS 初始化是异步的，结果会在系统回调中返回。
        textToSpeech = TextToSpeech(appContext) { status ->
            // 即使厂商引擎回调线程不同，也统一切到 Android 主线程处理状态。
            mainHandler.post {
                if (status != TextToSpeech.SUCCESS) {
                    // 初始化失败通常表示设备没有可用的默认 TTS 引擎。
                    ttsInitializationFailed = true
                    ttsInitialized = false
                    // 初始化失败期间如果恰好有播放请求，立即结束并显示可读提示。
                    val hasPendingTtsRequest = pendingTtsRequest != null
                    pendingTtsRequest = null
                    if (hasPendingTtsRequest && pendingResult != null) {
                        finishWithError(
                            "AUDIO_TTS_UNAVAILABLE",
                            "当前设备没有可用的离线英语 TTS 引擎，请联网播放单词或安装英语语音包",
                        )
                    }
                    return@post
                }

                // 只有初始化成功后，系统才允许查询 Voice 和语言能力。
                ttsInitialized = true
                ttsInitializationFailed = false
                // 明确告诉 TTS 使用媒体语音通道，避免蓝牙连接后仍走听筒/通话通道。
                textToSpeech?.setAudioAttributes(speechAudioAttributes)
                textToSpeech?.setOnUtteranceProgressListener(ttsProgressListener)
                // 如果网络下载失败时 TTS 已经初始化，现在继续处理暂存的兜底请求。
                val request = pendingTtsRequest
                pendingTtsRequest = null
                request?.invoke()
            }
        }
    }

    // TTS 回调统一交给下面的函数处理，避免完成和失败逻辑散落在多个回调里。
    private val ttsProgressListener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String) {
            // 开始事件不需要额外更新 UI；Dart Future 仍保持等待直到 onDone。
        }

        override fun onDone(utteranceId: String) {
            mainHandler.post {
                finishTtsSuccessfully(utteranceId)
            }
        }

        @Suppress("DEPRECATION")
        override fun onError(utteranceId: String) {
            mainHandler.post {
                finishTtsWithError(utteranceId, null)
            }
        }

        override fun onError(utteranceId: String, errorCode: Int) {
            mainHandler.post {
                finishTtsWithError(utteranceId, errorCode)
            }
        }
    }

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
                // 先查本地 MP3；已有缓存不需要网络，也不受失败记录影响。
                val cachedAudioFile = findCachedAudioFile(normalizedSpelling, accent)
                if (cachedAudioFile != null) {
                    mainHandler.post {
                        if (generation != requestGeneration) return@post
                        startPlayer(cachedAudioFile, generation)
                    }
                    return@execute
                }

                // 明确没有网络，或最近 5 分钟网络音频已失败，直接走离线 TTS。
                if (shouldSkipNetworkAudio()) {
                    mainHandler.post {
                        if (generation != requestGeneration) return@post
                        startTtsFallback(normalizedSpelling, accent, generation)
                    }
                    return@execute
                }

                // 先查缓存，没有时依次请求两个来源。
                val audioFile = resolveAudioFile(normalizedSpelling, accent, generation)
                // 网络音频成功，说明之前的失败记录已经过时，允许后续继续尝试 MP3。
                clearNetworkAudioFailure()
                // MediaPlayer 必须回到主线程创建和启动。
                mainHandler.post {
                    // 若用户期间点击了其他单词，旧文件只保留缓存但绝不播放。
                    if (generation != requestGeneration) return@post
                    // 使用完整本地文件启动系统播放器。
                    startPlayer(audioFile, generation)
                }
            } catch (error: Throwable) {
                // 用户已切换单词时不记录旧请求的失败，避免污染新请求的网络状态。
                if (generation == requestGeneration && error is NetworkResolutionException) {
                    // 两个网络来源均失败，记录 5 分钟，后续单词直接使用 TTS。
                    recordNetworkAudioFailure(error)
                }
                // 两个网络音源都失败后，切回主线程尝试设备本地英语 TTS。
                mainHandler.post {
                    if (generation != requestGeneration) return@post
                    // 网络失败优先走离线 TTS；TTS 不可用时再返回明确的用户提示。
                    startTtsFallback(normalizedSpelling, accent, generation)
                }
            }
        }
    }

    /**
     * 按 Dart 指定的发音渠道播放当前单词。
     *
     * 与 [play]（固定顺序兜底）不同，这里只解析并播放 Dart 按轮转顺序选中的那一个
     * 来源，让反复重听的用户能听到不同发音。渠道下载失败或设备离线时，自动回退到
     * 口音级离线缓存，最后才轮到系统 TTS，保证每次点击都有声音。
     */
    fun playChannel(
        spelling: String,
        accent: String,
        channel: String,
        result: MethodChannel.Result,
    ) {
        // 清理首尾空格，防止生成无意义 URL。
        val normalizedSpelling = spelling.trim()
        // 空拼写无法请求发音。
        if (normalizedSpelling.isEmpty()) {
            result.error("AUDIO_ARGUMENT_ERROR", "单词拼写不能为空", null)
            return
        }
        // 缓存目录只接受两个已约定口音值。
        if (accent != AMERICAN && accent != BRITISH) {
            result.error("AUDIO_ARGUMENT_ERROR", "不支持的发音口音：$accent", null)
            return
        }
        // 渠道必须来自 Dart 约定的四个来源。
        if (channel != CHANNEL_BEINGFINE &&
            channel != CHANNEL_BAIDU &&
            channel != CHANNEL_YOUDAO &&
            channel != CHANNEL_TTS
        ) {
            result.error("AUDIO_ARGUMENT_ERROR", "不支持的发音渠道：$channel", null)
            return
        }

        // 递增编号会让仍在下载的旧任务失效。
        requestGeneration += 1
        // 保存当前请求编号供异步阶段逐次核验。
        val generation = requestGeneration
        // 停止旧播放器，并让旧 Dart Future 以“已被替换”结束。
        interruptCurrent("AUDIO_INTERRUPTED", "已开始播放另一个单词")
        // 当前调用要等到完成或失败时再回传。
        pendingResult = result

        // 下载和文件 IO 放入后台线程。
        downloadExecutor.execute {
            try {
                // 指定 TTS 渠道时不尝试网络，直接朗读。
                if (channel == CHANNEL_TTS) {
                    mainHandler.post {
                        if (generation == requestGeneration) {
                            startTtsFallback(normalizedSpelling, accent, generation)
                        }
                    }
                    return@execute
                }

                // 明确离线或最近 5 分钟网络音频已失败：先复用本渠道离线缓存，
                // 没有本渠道缓存再退回旧版口音级缓存，最后才轮到系统 TTS。
                if (shouldSkipNetworkAudio()) {
                    // 优先复用本次被选中渠道自己的缓存；只有渠道缓存缺失时才退回旧版口音级缓存。
                    val offlineCache = channelCacheFile(normalizedSpelling, accent, channel)
                        .takeIf { isLikelyMp3(it) }
                        ?: findCachedAudioFile(normalizedSpelling, accent)
                    mainHandler.post {
                        if (generation != requestGeneration) return@post
                        if (offlineCache != null) startPlayer(offlineCache, generation)
                        else startTtsFallback(normalizedSpelling, accent, generation)
                    }
                    return@execute
                }

                // 在线：只下载并播放被选中的这一个渠道。
                val audioFile =
                    resolveChannelFile(normalizedSpelling, accent, channel, generation)
                // 网络音频成功，说明上一段失败记录已过时，允许继续尝试 MP3。
                clearNetworkAudioFailure()
                // MediaPlayer 必须回到主线程创建和启动。
                mainHandler.post {
                    if (generation == requestGeneration) startPlayer(audioFile, generation)
                }
            } catch (error: Throwable) {
                // 指定渠道失败时记录 5 分钟网络失败，降低后续请求的重复等待。
                if (generation == requestGeneration && error is NetworkResolutionException) {
                    recordNetworkAudioFailure(error)
                }
                // 该渠道不可用时，先复用本渠道已有缓存，再退回旧版口音级缓存和系统 TTS。
                val offlineCache = channelCacheFile(normalizedSpelling, accent, channel)
                    .takeIf { isLikelyMp3(it) }
                    ?: findCachedAudioFile(normalizedSpelling, accent)
                mainHandler.post {
                    if (generation != requestGeneration) return@post
                    if (offlineCache != null) startPlayer(offlineCache, generation)
                    else startTtsFallback(normalizedSpelling, accent, generation)
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

    /**
     * 智能轮转播放：统一“正常播放”与“轮转重听”的入口。
     *
     * 生活化解释：每个单词都有一本小账本，记着“这一轮里哪些发音渠道已经读过”。
     * 每次点单词：只从「本地已有缓存、且这本账上还没读过」的网络渠道里挑第一个出声；
     * 没有缓存的渠道在后台并发补下载（不挡本次出声）；万一所有网络渠道都没就绪，
     * 就等一个短暂窗口让快的下载先完成；再不行，才轮到系统 TTS 做最后兜底。
     *
     * 好处：未就绪的渠道不会占用“点名机会”（旧轮转会点到没缓存的渠道而哑火）；
     * 缓存下载完成后渠道自动加入轮转；TTS 只出现在“网络真的无能为力”时。
     */
    fun playSmart(spelling: String, accent: String, result: MethodChannel.Result) {
        // 清理首尾空格，防止生成无意义 URL。
        val normalizedSpelling = spelling.trim()
        // 空拼写无法请求发音。
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
        // 当前调用要等到完成或失败时再回传。
        pendingResult = result

        // 挑选渠道与等待下载窗口都属于文件 IO，放入播放专用后台线程。
        downloadExecutor.execute {
            try {
                // 读一次账本快照：本周期已经朗读过的渠道（只发生在主线程与播放线程，快照安全）。
                val alreadyPlayed = synchronized(rotationLedger) {
                    rotationLedger[rotationKey(normalizedSpelling, accent)]?.toSet() ?: emptySet()
                }
                // 把网络渠道分成两拨：有缓存可点名（ready）与缺缓存需要补齐（missing）。
                // 已读过的渠道直接跳过，保证这一轮不会让同一家反复出声。
                val ready = mutableListOf<String>()
                val missing = mutableListOf<String>()
                for (channel in NETWORK_CHANNELS) {
                    if (channel in alreadyPlayed) continue
                    if (isLikelyMp3(channelCacheFile(normalizedSpelling, accent, channel))) {
                        ready.add(channel)
                    } else {
                        missing.add(channel)
                    }
                }

                // 只有明确离线或处于 5 分钟网络熔断期时才不发起网络请求。
                val tryNetwork = !shouldSkipNetworkAudio()
                // 缺缓存的渠道并发丢到后台线程池补下载（不阻塞本次点名、失败静默）。
                if (tryNetwork && missing.isNotEmpty()) {
                    submitBackgroundPrefetch(normalizedSpelling, accent, missing)
                }
                // 记录本次点播现场：哪些渠道有缓存可直接点名、哪些在后台补、本周期已读过谁。
                AppLog.i(
                    "audio",
                    "点播 拼写=$normalizedSpelling 口音=$accent 就绪=$ready 补缓存=$missing 本周期已读=$alreadyPlayed 跳过网络=${!tryNetwork}",
                )
                // 一个就绪渠道都没有时，等一个短暂窗口，让下载快的渠道能赶上本次出声，
                // 从而避免“第一次点某个单词必定是机器 TTS”的体验。
                if (tryNetwork && ready.isEmpty() && missing.isNotEmpty()) {
                    val waitStartedAt = System.currentTimeMillis()
                    waitForPrefetch(normalizedSpelling, accent, generation, ready, alreadyPlayed)
                    // 用户感觉「点了很久才出声」时先看这一行：无缓存首播最多要等 1 秒窗口。
                    AppLog.i(
                        "audio",
                        "无就绪缓存，等待下载窗口 ${System.currentTimeMillis() - waitStartedAt}ms 后就绪=$ready",
                    )
                    // 仅当请求仍然有效时才更新网络状态：等待期间若用户已切词（代次失效），
                    // 既不能误记 5 分钟熔断，也不该清掉真实的旧熔断记录。
                    if (generation == requestGeneration) {
                        if (ready.isEmpty()) {
                            // 窗口结束仍一个渠道都没补上 → 记 5 分钟熔断，避免之后每词白等窗口。
                            recordNetworkAudioFailure(
                                NetworkResolutionException("智能轮转预取未能在等待窗口内成功"),
                            )
                        } else {
                            // 有渠道补上了，说明网络已恢复，清掉旧熔断记录。
                            clearNetworkAudioFailure()
                        }
                    }
                }

                // 就绪池非空：按优先级点名第一个未读渠道，播放它自己的本地缓存文件。
                if (ready.isNotEmpty()) {
                    val channel = ready.first()
                    // 记录到底点名了哪家渠道：复查「为什么是它出声」时看这一行。
                    AppLog.i(
                        "audio",
                        "点名播放 渠道=$channel 拼写=$normalizedSpelling 口音=$accent",
                    )
                    // 记账：本周期已读过这一家（并发写用同一把锁保护）。
                    markLedgerRead(normalizedSpelling, accent, channel)
                    // 若就绪渠道这一轮已全部读过，清空账本进入下一周期。
                    clearLedgerIfCycleDone(normalizedSpelling, accent, ready)
                    // 记录正在出声的记账条目；播放失败/中断时按它回滚。
                    activeLedgerEntry =
                        rotationKey(normalizedSpelling, accent) to channel
                    // MediaPlayer 必须回到主线程创建和启动。
                    mainHandler.post {
                        // 若用户期间点击了其他单词，旧文件只保留缓存但绝不播放。
                        if (generation != requestGeneration) return@post
                        startPlayer(channelCacheFile(normalizedSpelling, accent, channel), generation)
                    }
                    return@execute
                }

                // 所有网络渠道都无能为力：切回主线程交给系统 TTS 最后兜底。
                mainHandler.post {
                    if (generation != requestGeneration) return@post
                    startTtsFallback(normalizedSpelling, accent, generation)
                }
            } catch (error: Throwable) {
                // 异常（如目录创建失败）也统一回到主线程走 TTS 兜底，不让用户干等。
                mainHandler.post {
                    if (generation != requestGeneration) return@post
                    startTtsFallback(normalizedSpelling, accent, generation)
                }
            }
        }
    }

    /**
     * 智能轮转的“短暂等待窗口”：最多等 [SMART_PREFETCH_WINDOW_MILLIS] 毫秒，
     * 每 100 毫秒醒来看一次后台补缓存有没有把新渠道文件写好；一旦有就提前退出。
     *
     * 注意：只“等结果”，绝不取消后台任务——窗口结束后没完成的下载继续在后台跑，
     * 用户下次再点这个词时它已经就绪，可以正常点名真人发音。
     */
    private fun waitForPrefetch(
        spelling: String,
        accent: String,
        generation: Long,
        ready: MutableList<String>,
        alreadyPlayed: Set<String>,
    ) {
        val deadline = System.currentTimeMillis() + SMART_PREFETCH_WINDOW_MILLIS
        while (System.currentTimeMillis() < deadline) {
            // 用户已点其他单词或退页面：旧请求不再出声，立即放弃等待。
            if (generation != requestGeneration) return
            // 把窗口内新出现有效缓存的渠道并入就绪池（仍跳过已读渠道）。
            collectNewlyReadyChannels(spelling, accent, ready, alreadyPlayed)
            if (ready.isNotEmpty()) return
            try {
                Thread.sleep(SMART_PREFETCH_POLL_MILLIS)
            } catch (_: InterruptedException) {
                // 线程被中断（如服务销毁）时直接放弃等待，由外层决定兜底。
                return
            }
        }
        // 最后再扫一次，让恰好赶在超时前完成下载的渠道也能被点名。
        collectNewlyReadyChannels(spelling, accent, ready, alreadyPlayed)
    }

    /** 把后台补缓存刚写好的渠道并入就绪池；只认文件头有效的 MP3。 */
    private fun collectNewlyReadyChannels(
        spelling: String,
        accent: String,
        ready: MutableList<String>,
        alreadyPlayed: Set<String>,
    ) {
        for (channel in NETWORK_CHANNELS) {
            // 已入池、已读或仍无有效文件的渠道都不处理。
            if (channel in ready || channel in alreadyPlayed) continue
            if (isLikelyMp3(channelCacheFile(spelling, accent, channel))) {
                ready.add(channel)
            }
        }
    }

    /**
     * 把缺缓存的渠道并发提交到预缓存线程池，让它们互不阻塞地补齐本地文件。
     *
     * 每个 (词,口音,渠道) 只允许一个任务在跑（backgroundFetchKeys 去重）；下载失败
     * 只静默跳过，绝不打扰正在进行的播放。任务只受「清空缓存」与「预缓存批次」约束，
     * 与用户播放请求的生命周期解耦——哪怕本次播放已经结束，补缓存也会继续完成。
     */
    private fun submitBackgroundPrefetch(
        spelling: String,
        accent: String,
        channels: List<String>,
    ) {
        for (channel in channels) {
            // 同一词同一渠道的补缓存任务去重；key 用词的小写形式避免大小写差异。
            val fetchKey = "$accent|$channel|${spelling.lowercase(Locale.ROOT)}"
            if (!backgroundFetchKeys.add(fetchKey)) continue
            try {
                // 跟随当前预缓存批次号：任务执行时若用户启动了新一轮全量预缓存，
                // 会被同一批次的“批次已失效”校验自然接管，不会重复下载。
                val batch = precacheGeneration.get()
                precacheExecutor.execute {
                    try {
                        // cancelEnabled=false：补缓存不响应播放请求的取消，只受批次/清空控制。
                        precacheResolveChannel(spelling, accent, channel, batch)
                    } catch (error: Throwable) {
                        // 音源缺词、断网、缓存被清空等都算正常失败，下次点击会再触发补齐。
                        // 每次失败都记渠道与原因，能看出是哪一家网络音源长期不通。
                        AppLog.i("audio", "后台补缓存失败 渠道=$channel 原因=${error.message}")
                    } finally {
                        // 无论成功失败都让出去重名额，允许未来重新补缓存。
                        backgroundFetchKeys.remove(fetchKey)
                    }
                }
            } catch (_: java.util.concurrent.RejectedExecutionException) {
                // 线程池已随 Activity 销毁关闭：本词本次放弃补缓存，释放去重名额。
                backgroundFetchKeys.remove(fetchKey)
            }
        }
    }

    /** 组装账本 key：拼写与口音都必须参与，避免美式/英式互相串账。 */
    private fun rotationKey(spelling: String, accent: String): String = "$spelling|$accent"

    /** 记账：把「本周期已读过该渠道」写入账本。 */
    private fun markLedgerRead(spelling: String, accent: String, channel: String) {
        synchronized(rotationLedger) {
            rotationLedger
                .getOrPut(rotationKey(spelling, accent)) { mutableSetOf() }
                .add(channel)
        }
    }

    /** 就绪池里的渠道这一轮已全部读过时，清空账本进入下一轮轮转。 */
    private fun clearLedgerIfCycleDone(
        spelling: String,
        accent: String,
        readyChannels: List<String>,
    ) {
        synchronized(rotationLedger) {
            val key = rotationKey(spelling, accent)
            val ledger = rotationLedger[key] ?: return
            // 只与“本轮就绪”的渠道比对：永远下载失败的渠道不参与计数，
            // 不会像旧“总数对比”那样让账本永远清不掉。
            if (readyChannels.all { it in ledger }) rotationLedger.remove(key)
        }
    }

    /**
     * 清掉“当前正在出声”的记账条目。
     *
     * [unmark] 为 true 时同时回滚账本（失败/被打断，该渠道下次可重新点名）；
     * 为 false 只清除活动条目、保留记账（自然播完，下一轮换别的渠道）。
     */
    private fun clearActiveLedger(unmark: Boolean) {
        // 取出当前条目并置空，避免并发回调重复回滚。
        val entry = activeLedgerEntry ?: return
        activeLedgerEntry = null
        if (!unmark) return
        // 回滚账本：key 直接取自条目本身，不需要再从字符串里反解拼写与口音。
        synchronized(rotationLedger) {
            rotationLedger[entry.first]?.remove(entry.second)
            // 账本变空就整体移除，避免无意义的空 key 越积越多。
            if (rotationLedger[entry.first].isNullOrEmpty()) rotationLedger.remove(entry.first)
        }
    }

    /** Activity 销毁时释放系统资源和下载线程。 */
    fun dispose() {
        // 使所有尚未回到主线程的任务失效。
        requestGeneration += 1
        // 销毁阶段不再向已经关闭的 Dart 引擎发送结果。
        pendingResult = null
        // 取消等待中的 TTS 兜底请求。
        pendingTtsRequest = null
        pendingTtsUtteranceId = null
        // 先停止并关闭系统 TTS，释放厂商引擎持有的资源。
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        ttsInitialized = false
        // 安全释放播放器。
        releasePlayer()
        // 顺手收起锁屏/通知栏媒体控制，避免退出后残留控制条。
        releaseMediaSession()
        // 不再接收新下载任务；队列中任务结束后线程自动退出。
        downloadExecutor.shutdown()
        // 同样让进行中的离线预缓存尽快退出，并释放其线程池。
        precacheGeneration.incrementAndGet()
        precacheExecutor.shutdown()
    }

    /** 先读取口音缓存；不存在时按来源顺序下载（供播放路径使用）。 */
    private fun resolveAudioFile(spelling: String, accent: String, generation: Long): File {
        // 播放路径需要响应用户切换单词的中断，因此开启请求取消检查。
        return resolveAudioFileInternal(spelling, accent, generation, cancelEnabled = true)
    }

    /** 查找有效的本地 MP3；只读检查，不创建目录，也不触发网络请求。 */
    private fun findCachedAudioFile(spelling: String, accent: String): File? {
        // expectedCacheFile 使用与下载完全相同的文件名规则。
        val file = expectedCacheFile(spelling, accent)
        // 文件头有效才交给 MediaPlayer，避免把残缺文件当作离线缓存。
        return file.takeIf { isLikelyMp3(it) }
    }

    /** 判断这一次播放是否应跳过网络，直接使用系统离线 TTS。 */
    private fun shouldSkipNetworkAudio(): Boolean {
        // 最近一次网络失败仍在有效期内，直接兜底，避免每个单词重复等待 1 秒 × 2。
        if (System.currentTimeMillis() < networkAudioUnavailableUntilMillis) return true
        // 过期记录只清掉，不影响本次对网络状态的重新判断。
        if (networkAudioUnavailableUntilMillis != 0L) clearNetworkAudioFailure()

        // 只有系统明确报告“没有活动网络”时才跳过网络；无法判断仍尝试一次。
        return when (readNetworkState()) {
            NetworkState.UNAVAILABLE -> true
            NetworkState.AVAILABLE,
            NetworkState.UNKNOWN,
            -> false
        }
    }

    /** 读取 Android 当前网络状态；UNKNOWN 表示不能自信地下结论。 */
    private fun readNetworkState(): NetworkState {
        val connectivityManager =
            appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return NetworkState.UNKNOWN
        return try {
            // 没有活动网络时可以明确判断为离线。
            val activeNetwork = connectivityManager.activeNetwork ?: return NetworkState.UNAVAILABLE
            // 能拿到网络但能力对象缺失，属于无法检测，仍应尝试一次网络。
            val capabilities = connectivityManager.getNetworkCapabilities(activeNetwork)
                ?: return NetworkState.UNKNOWN
            // 没有 INTERNET 能力时明确不可联网。
            if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                return NetworkState.UNAVAILABLE
            }
            // VALIDATED 表示系统已验证能访问互联网；未验证时保守视为未知。
            if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) {
                NetworkState.AVAILABLE
            } else {
                NetworkState.UNKNOWN
            }
        } catch (_: Throwable) {
            // 厂商 ROM 查询网络能力异常时不能误判离线，交给网络请求自行验证。
            NetworkState.UNKNOWN
        }
    }

    /** 记录网络音频失败，并把相同判断暂存 5 分钟。 */
    private fun recordNetworkAudioFailure(error: Throwable) {
        // 熔断一旦建立，之后每个词都直接走 TTS：它是「听不到网络发音」的最重要解释。
        AppLog.e("audio", "网络音源不可用，进入 5 分钟熔断：${error.message}")
        // 使用墙上时钟便于跨进程重启后恢复同一条 5 分钟记录。
        val unavailableUntil = System.currentTimeMillis() + NETWORK_FAILURE_TTL_MILLIS
        // 内存值立即生效，磁盘写入失败也不影响本次判断。
        networkAudioUnavailableUntilMillis = unavailableUntil
        writeNetworkFailureDeadline(unavailableUntil)
        Log.i(
            LOG_TAG,
            "网络音频失败，${NETWORK_FAILURE_TTL_MILLIS / 60_000} 分钟内使用系统 TTS：" +
                (error.message ?: error.javaClass.simpleName),
        )
    }

    /** 清除已经恢复的网络音频失败记录。 */
    private fun clearNetworkAudioFailure() {
        AppLog.i("audio", "网络音源恢复可用，解除 5 分钟熔断")
        networkAudioUnavailableUntilMillis = 0L
        writeNetworkFailureDeadline(0L)
    }

    /**
     * 从设置表读回上次记录的失败截止时间；没有记录或读失败时按 0 处理。
     *
     * 这一步在构造函数里跑，读失败绝不能让整个音频服务起不来——
     * 最坏结果只是多撞一次网络墙，不影响发声。
     */
    private fun readNetworkFailureDeadline(): Long = try {
        val entry = database.getSettings()[NETWORK_AUDIO_UNAVAILABLE_UNTIL_KEY] as? Map<*, *>
        (entry?.get("value") as? String)?.toLongOrNull() ?: 0L
    } catch (error: Throwable) {
        Log.w(LOG_TAG, "读取网络音频熔断时间失败，按未熔断处理：${error.message}")
        0L
    }

    /** 把失败截止时间写回设置表；写失败只记日志，不影响播放。 */
    private fun writeNetworkFailureDeadline(millis: Long) {
        try {
            database.setSetting(NETWORK_AUDIO_UNAVAILABLE_UNTIL_KEY, millis.toString(), "int")
        } catch (error: Throwable) {
            Log.w(LOG_TAG, "保存网络音频熔断时间失败：${error.message}")
        }
    }

    /** 网络状态枚举：只有 UNAVAILABLE 才表示可以确信当前没有网络。 */
    private enum class NetworkState {
        AVAILABLE,
        UNAVAILABLE,
        UNKNOWN,
    }

    /** 仅下载并缓存某个网络渠道、不触发播放；复用渠道播放相同的来源与校验。 */
    private fun precacheResolveChannel(
        spelling: String,
        accent: String,
        channel: String,
        generation: Long,
    ) {
        val normalized = spelling.trim()
        // 空拼写不值得请求。
        if (normalized.isEmpty()) return
        // 只接受约定的两种口音。
        if (accent != AMERICAN && accent != BRITISH) return
        // 离线预缓存只处理真正会产生文件的网络渠道；TTS 没有可缓存内容。
        if (channel !in NETWORK_CHANNELS) return
        // 预缓存任务不能被播放/停止的 requestGeneration 取消，因此关闭取消检查；
        // 用 precacheGeneration 作为临时文件命名空间即可避免并发写冲突。
        resolveChannelFileInternal(
            normalized,
            accent,
            channel,
            generation,
            cancelEnabled = false,
        )
    }

    /** 计算某个 (spelling, accent) 的预期缓存文件位置，不触发下载。 */
    private fun expectedCacheFile(spelling: String, accent: String): File {
        // 与 resolveAudioFileInternal 完全一致的目录与文件名算法，保证判定准确。
        val accentDirectory = File(appContext.cacheDir, "word_audio/$accent")
        val cacheKey = Base64.encodeToString(
            spelling.lowercase(Locale.ROOT).toByteArray(StandardCharsets.UTF_8),
            Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING,
        )
        return File(accentDirectory, "$cacheKey.mp3")
    }

    /**
     * 统一的缓存解析实现：先查本地缓存，没有时按"不背单词 -> 百度翻译 -> 有道"顺序下载。
     *
     * [cancelEnabled] 为 true 时（播放路径）会在下载过程中校验 requestGeneration，
     * 用户点其它单词可立即中断；为 false 时（离线预缓存）跳过校验，任务只受
     * 新一轮预缓存的 precacheGeneration 控制，互不干扰。
     */
    private fun resolveAudioFileInternal(
        spelling: String,
        accent: String,
        generation: Long,
        cancelEnabled: Boolean,
    ): File {
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
        // 记录下载开始时的缓存纪元；清空动作会改变它，使旧下载不能重新落正式文件。
        val initialCacheEpoch = cacheEpoch.get()
        // 保存每个来源的简短失败原因，最终一起提供给用户排查。
        val failures = mutableListOf<String>()
        // 从不背单词开始逐个尝试。
        for ((sourceName, url) in sources) {
            try {
                // 用户已点击其他单词时立即停止当前旧任务，不继续占用下载队列。
                if (cancelEnabled) ensureRequestIsActive(generation)
                // 任一来源下载成功便立即返回缓存文件。
                downloadToCache(url, target, generation, cancelEnabled, initialCacheEpoch)
                return target
            } catch (error: Throwable) {
                // 被新请求替换时直接结束旧任务，不再尝试第二来源。
                if (cancelEnabled && generation != requestGeneration) throw error
                // 记录来源名，避免最终只看到模糊的“网络错误”。
                failures += "$sourceName：${error.message ?: error.javaClass.simpleName}"
            }
        }
        // 两个网络来源都失败才抛出专用异常，外层据此记录 5 分钟网络失败状态。
        throw NetworkResolutionException(failures.joinToString("；"))
    }

    /** 标记两个网络音源均已实际请求但都不可用。 */
    private class NetworkResolutionException(message: String) : RuntimeException(message)

    /**
     * 解析单个发音渠道的缓存文件（播放路径），缺失时才请求该渠道自己的 URL。
     *
     * 每个渠道使用独立子目录缓存：这样同一单词反复重听时能命中不同来源的文件，
     * 而不是永远只听到第一次成功下载的那一份声音。
     */
    private fun resolveChannelFile(
        spelling: String,
        accent: String,
        channel: String,
        generation: Long,
    ): File {
        return resolveChannelFileInternal(
            spelling,
            accent,
            channel,
            generation,
            cancelEnabled = true,
        )
    }

    /**
     * 渠道级缓存解析实现：先查该渠道本地缓存，缺失时才请求该渠道 URL。
     *
     * [cancelEnabled] 为 true 时供播放路径在下载过程中响应 requestGeneration；
     * 为 false 时供离线预缓存使用，任务只受 precacheGeneration 控制。
     */
    private fun resolveChannelFileInternal(
        spelling: String,
        accent: String,
        channel: String,
        generation: Long,
        cancelEnabled: Boolean,
    ): File {
        // 计算该渠道专属缓存位置。
        val target = channelCacheFile(spelling, accent, channel)
        // 已有该渠道的有效缓存直接返回。
        if (isLikelyMp3(target)) return target
        // 残缺旧缓存不能反复交给 MediaPlayer。
        if (target.exists()) target.delete()
        // 确保渠道子目录存在。
        val parent = target.parentFile
        check(parent != null && (parent.exists() || parent.mkdirs())) {
            "无法创建音频渠道缓存目录"
        }
        // 记录下载开始时的缓存纪元；清空动作会改变它，使旧下载不能重新落正式文件。
        val initialCacheEpoch = cacheEpoch.get()
        // 只请求被选中渠道这一个来源；失败抛 NetworkResolutionException。
        downloadToCache(
            channelUrl(spelling, accent, channel),
            target,
            generation,
            cancelEnabled,
            initialCacheEpoch,
        )
        return target
    }

    /** 计算某个 (spelling, accent, channel) 的渠道级缓存文件位置，不触发下载。 */
    private fun channelCacheFile(
        spelling: String,
        accent: String,
        channel: String,
    ): File {
        // 渠道目录与口音目录嵌套，复用与小写 URL-safe Base64 相同的单层文件规则。
        val channelDirectory = File(appContext.cacheDir, "word_audio/$accent/$channel")
        val cacheKey = Base64.encodeToString(
            spelling.lowercase(Locale.ROOT).toByteArray(StandardCharsets.UTF_8),
            Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING,
        )
        // mp3 后缀帮助 MediaPlayer 判断文件容器格式。
        return File(channelDirectory, "$cacheKey.mp3")
    }

    /** 根据口音与指定渠道生成准确 HTTPS URL；支持不背单词、百度翻译与有道三个网络渠道。 */
    private fun channelUrl(spelling: String, accent: String, channel: String): String {
        // URLEncoder 默认把空格写成 +，路径中改用标准 %20；
        // 撇号会被编码成 %27，百度翻译接口两种写法都接受。
        val encodedSpelling = URLEncoder.encode(
            spelling,
            StandardCharsets.UTF_8.toString(),
        ).replace("+", "%20")
        // 不背单词使用 US 或 UK 路径。
        val beingFineAccent = if (accent == AMERICAN) "US" else "UK"
        // 有道 type=2 是美式，type=1 是英式。
        val youdaoType = if (accent == AMERICAN) "2" else "1"
        // 百度翻译 lan=en 是美式，lan=uk 是英式；spd=3 是正常语速（可调 1-5）。
        val baiduLan = if (accent == AMERICAN) "en" else "uk"
        return when (channel) {
            CHANNEL_BEINGFINE ->
                "https://audio.beingfine.cn/speeches/$beingFineAccent/" +
                    "$beingFineAccent-speech/$encodedSpelling.mp3"
            CHANNEL_BAIDU ->
                "https://fanyi.baidu.com/gettts" +
                    "?lan=$baiduLan&text=$encodedSpelling&spd=3&source=web"
            CHANNEL_YOUDAO ->
                "https://dict.youdao.com/dictvoice?audio=$encodedSpelling&type=$youdaoType"
            else -> error("不支持的发音渠道：$channel")
        }
    }

    /**
     * 根据口音生成“不背单词 -> 百度翻译 -> 有道”的准确 HTTPS URL，
     * 供普通固定顺序播放使用；顺序即优先级（数字越大越优先）。
     */
    private fun buildSources(spelling: String, accent: String): List<Pair<String, String>> {
        // List 保持明确优先级。
        return listOf(
            // 第一优先：不背单词（100）。
            "不背单词" to channelUrl(spelling, accent, CHANNEL_BEINGFINE),
            // 第二优先：百度翻译（50）。
            "百度翻译" to channelUrl(spelling, accent, CHANNEL_BAIDU),
            // 第三优先：有道（10）。
            "有道" to channelUrl(spelling, accent, CHANNEL_YOUDAO),
        )
    }

    /** 下载到临时文件，确认响应有效后再替换正式缓存。 */
    private fun downloadToCache(
        url: String,
        target: File,
        generation: Long,
        cancelEnabled: Boolean,
        initialCacheEpoch: Long,
    ) {
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
                        // 每一块之前确认用户没有切换到另一个单词（仅播放路径检查）。
                        if (cancelEnabled) ensureRequestIsActive(generation)
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
            // 只锁住最终替换这段短操作，四个线程的网络下载仍可并发进行。
            synchronized(cacheMutationLock) {
                // 播放请求或预缓存批次失效后，旧下载不得生成正式缓存。
                if (cancelEnabled) {
                    ensureRequestIsActive(generation)
                } else {
                    check(generation == precacheGeneration.get()) { "预缓存批次已失效" }
                }
                // 清空动作发生过时，即使下载内容有效也只能丢弃临时文件。
                check(initialCacheEpoch == cacheEpoch.get()) { "音频缓存已被清空" }
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

    /**
     * 离线预缓存全部单词的全渠道音频：每个网络渠道、每种口音都会尝试下载。
     *
     * 任务数虽为“单词 × 美/英 × 网络渠道”，但上报给 Dart 的进度以单词为单位：
     * 某个单词只要存在任意一家渠道同时缓存了美式和英式，就计为已缓存一个单词。
     *
     * 该任务只依赖 applicationContext 与独立的线程池，不持有任何 Flutter Widget，
     * 因此用户关闭抽屉或返回首页后仍在后台继续，直到全部完成或启动新一轮预缓存。
     */
    fun precacheAll(
        spellings: List<String>,
        onProgress: (batch: Long, cached: Int, total: Int, done: Boolean) -> Unit,
    ) {
        // 新一轮预缓存让上一批尚未执行的任务立即退出，避免重复下载。
        val myGeneration = precacheGeneration.incrementAndGet()
        // 清洗空拼写并保持原有顺序；重复单词仍按调用方传入的条数统计。
        val words = spellings.map { it.trim() }.filter { it.isNotEmpty() }
        val totalWords = words.size
        // 没有单词时直接回报“已完成”，让 Dart 收起进度条。
        if (totalWords == 0) {
            onProgress(myGeneration, 0, 0, true)
            return
        }

        // 先在线程池里扫描一次磁盘已有缓存，避免第一次进度事件把初始百分比打回 0。
        try {
            precacheExecutor.execute {
                if (myGeneration != precacheGeneration.get()) return@execute
                val initialStates = buildPrecacheStates(words)
                if (myGeneration != precacheGeneration.get()) return@execute
                val progress = PrecacheWordProgress(
                    total = totalWords,
                    taskCount = totalWords * NETWORK_CHANNELS.size * 2,
                    initialStates = initialStates,
                )
                submitPrecacheTasks(words, progress, myGeneration, onProgress)
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            // 执行器已关闭：本批只能立即结束，不伪造任何缓存成功数。
            onProgress(myGeneration, 0, totalWords, true)
        }
    }

    /**
     * 把所有“单词 × 口音 × 网络渠道”任务提交到预缓存线程池。
     *
     * [progress] 负责把并发任务的渠道/口音成功信息合并成“单词是否完整缓存”的进度。
     */
    private fun submitPrecacheTasks(
        words: List<String>,
        progress: PrecacheWordProgress,
        myGeneration: Long,
        onProgress: (batch: Long, cached: Int, total: Int, done: Boolean) -> Unit,
    ) {
        for ((wordIndex, spelling) in words.withIndex()) {
            for (accent in listOf(AMERICAN, BRITISH)) {
                for (channel in NETWORK_CHANNELS) {
                    // 线程池若已随 Activity 销毁被关闭，提交会被拒绝；此处静默吞掉，
                    // 避免 RejectedExecutionException 冒泡到调用方导致无任何进度回调。
                    try {
                        precacheExecutor.execute {
                            // 已有新一轮预缓存或用户重复点击时，旧任务直接退出。
                            if (myGeneration != precacheGeneration.get()) return@execute
                            // 先假定本任务失败；只有解析得到有效缓存后才切换为成功。
                            var cacheSucceeded = false
                            // 单个任务失败（音源缺失 / 网络错误）只跳过，不影响其他任务。
                            try {
                                precacheResolveChannel(spelling, accent, channel, myGeneration)
                                // 正常返回说明磁盘上已有或刚写入了有效 MP3。
                                cacheSucceeded = true
                            } catch (_: Throwable) {
                                // 离线预缓存以“尽量填满”为目标，单个失败无需中断整体。
                            }
                            // 下载期间若已清空缓存或启动新批次，旧任务结果不再回写界面。
                            if (myGeneration != precacheGeneration.get()) return@execute
                            // 无论成功或失败都记录任务结束，但只有形成完整单词才增加 cached。
                            val snapshot = progress.finish(
                                wordIndex,
                                channel,
                                accent,
                                cacheSucceeded,
                            )
                            onProgress(
                                myGeneration,
                                snapshot.cached,
                                snapshot.total,
                                snapshot.done,
                            )
                        }
                    } catch (_: java.util.concurrent.RejectedExecutionException) {
                        // 线程池已关闭：保留真实成功数，并把本批标记结束，绝不伪造 100%。
                        val snapshot = progress.stopped()
                        onProgress(myGeneration, snapshot.cached, snapshot.total, snapshot.done)
                        return
                    }
                }
            }
        }
    }

    /**
     * 扫描磁盘，把当前已经存在的渠道级缓存整理成进度计数器的初始状态。
     *
     * 旧版本的口音级缓存虽然不知道当初来自哪一家渠道，但既然美式和英式都有，
     * 就足以让该单词先计为“已缓存”；后续全渠道任务仍会继续补齐各渠道文件。
     */
    private fun buildPrecacheStates(
        words: List<String>,
    ): Map<Int, Map<String, Set<String>>> {
        val result = HashMap<Int, Map<String, Set<String>>>()
        for ((wordIndex, spelling) in words.withIndex()) {
            val channelStates = HashMap<String, MutableSet<String>>()
            for (channel in NETWORK_CHANNELS) {
                val accents = mutableSetOf<String>()
                if (isLikelyMp3(channelCacheFile(spelling, AMERICAN, channel))) {
                    accents += AMERICAN
                }
                if (isLikelyMp3(channelCacheFile(spelling, BRITISH, channel))) {
                    accents += BRITISH
                }
                if (accents.isNotEmpty()) channelStates[channel] = accents
            }
            if (isLikelyMp3(expectedCacheFile(spelling, AMERICAN)) &&
                isLikelyMp3(expectedCacheFile(spelling, BRITISH))
            ) {
                channelStates[LEGACY_CACHE_CHANNEL] =
                    mutableSetOf(AMERICAN, BRITISH)
            }
            if (channelStates.isNotEmpty()) result[wordIndex] = channelStates
        }
        return result
    }

    /** 判断准备发送到 Dart 的预缓存事件是否仍属于当前有效批次。 */
    fun isCurrentPrecacheBatch(batch: Long): Boolean {
        // clearAudioCache 与下一次 precacheAll 都会递增编号，使旧事件立即失效。
        return batch == precacheGeneration.get()
    }

    /** 统计当前词库中已完整缓存发音的单词数，用于在抽屉里显示初始百分比。 */
    fun getCacheProgress(spellings: List<String>): Pair<Int, Int> {
        // 总数 = 词库单词数。
        val total = spellings.size
        // 没有任何单词时返回空进度。
        if (total == 0) return 0 to 0
        // 逐个检查该单词是否已有任意一家渠道同时缓存美式和英式。
        var cached = 0
        for (spelling in spellings) {
            if (hasAnyChannelForBothAccents(spelling)) cached += 1
        }
        return cached to total
    }

    /** 判断某个单词是否至少有一家渠道同时拥有美式和英式有效 MP3。 */
    private fun hasAnyChannelForBothAccents(spelling: String): Boolean {
        // 兼容旧版本口音级缓存：两份都在，就相当于曾经有一家渠道下载成功。
        if (isLikelyMp3(expectedCacheFile(spelling, AMERICAN)) &&
            isLikelyMp3(expectedCacheFile(spelling, BRITISH))
        ) {
            return true
        }
        // 新版本口径：任意一个网络渠道的美式、英式渠道级缓存都存在即可。
        return NETWORK_CHANNELS.any { channel ->
            isLikelyMp3(channelCacheFile(spelling, AMERICAN, channel)) &&
                isLikelyMp3(channelCacheFile(spelling, BRITISH, channel))
        }
    }

    /**
     * 清空全部离线语音缓存：删除 word_audio 目录（含美式/英式子目录与所有 mp3）。
     *
     * 先让进行中的预缓存批次退出，再在 Android 主线程停止 MediaPlayer/TTS，避免
     * 文件虽被删除但已经打开的播放器仍继续发声。删除失败必须抛异常，让 Dart 不会
     * 把未真正清空的缓存错误显示成 0%。
     */
    fun clearAudioCache(): Boolean {
        // 让尚未执行的预缓存任务直接退出，不再往目录里写新文件。
        precacheGeneration.incrementAndGet()
        // 让所有已开始下载的任务在最终替换前发现缓存已被清空。
        cacheEpoch.incrementAndGet()
        // 播放器资源由 Android 主线程管理；这里等待它完成停止后再删文件。
        stopPlaybackOnMainThread()
        // 与正式文件替换互斥，保证清空返回后没有旧下载重新写回。
        synchronized(cacheMutationLock) {
            // 仅清空本服务负责的 word_audio 目录；其余缓存（如图片）不受影响。
            val root = File(appContext.cacheDir, "word_audio")
            // 防御：路径必须位于 cacheDir 之内，防止任何意外越界删除。
            val cacheRoot = appContext.cacheDir
            if (!root.absolutePath.startsWith(cacheRoot.absolutePath + File.separator)) {
                error("离线语音缓存路径不安全")
            }
            // 目录本来不存在也代表已经清空；存在时必须确认递归删除成功。
            if (root.exists()) {
                check(root.deleteRecursively() && !root.exists()) {
                    "无法完整删除离线语音缓存目录"
                }
            }
        }
        // 缓存文件已全部删除：轮转账本随之清空，让下载重建后的渠道能被重新点名；
        // 并放行仍在排队的后台补缓存任务（它们落盘时会因缓存纪元不符而自动放弃）。
        synchronized(rotationLedger) {
            rotationLedger.clear()
        }
        activeLedgerEntry = null
        backgroundFetchKeys.clear()
        // true 表示目录已经不存在，Dart 才可以把界面进度重置为 0%。
        return true
    }

    /** 在 Android 主线程停止当前 MP3/TTS，保证清空缓存时没有旧声音继续播放。 */
    private fun stopPlaybackOnMainThread() {
        // 当前已经在主线程时直接停止，避免等待自己造成死锁。
        if (Looper.myLooper() == Looper.getMainLooper()) {
            interruptCurrent("AUDIO_STOPPED", "播放已停止")
            return
        }
        // 清空动作运行在 MainActivity 的 I/O 线程，需要同步等待主线程处理完成。
        val latch = CountDownLatch(1)
        mainHandler.post {
            try {
                interruptCurrent("AUDIO_STOPPED", "播放已停止")
            } finally {
                // 无论播放器是否已有异常，都必须释放等待中的清空线程。
                latch.countDown()
            }
        }
        // 主线程异常卡死时也不能让清空请求永久等待；后续删除会继续由文件系统负责。
        check(latch.await(2, TimeUnit.SECONDS)) {
            "停止当前音频超时，无法安全清空离线语音缓存"
        }
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
            // 记下开始解码的时刻：onPrepared / onCompletion 用它算「出声快不快」。
            val decodeStartedAtMillis = System.currentTimeMillis()
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
                // 只有真正开始发声前才申请焦点，下载和解码阶段不会打断其他媒体。
                if (!requestAudioFocus()) {
                    finishWithError(
                        "AUDIO_FOCUS_UNAVAILABLE",
                        "系统暂时无法取得音频输出，请稍后重试",
                    )
                    return@setOnPreparedListener
                }
                preparedPlayer.start()
                // 记录从「开始解码」到「真正开播」的耗时：直接回答「点击后是不是等了很久」。
                AppLog.i("audio", "MP3 开播 解码耗时=${System.currentTimeMillis() - decodeStartedAtMillis}ms")
            }
            // 播放自然结束时完成 Dart Future，页面会隐藏动画喇叭。
            player.setOnCompletionListener { completedPlayer ->
                // 只结束仍属于当前请求的结果。
                if (generation == requestGeneration && mediaPlayer === completedPlayer) {
                    // 先释放播放器。
                    releasePlayer()
                    // 自然播完：保留“本周期已读”的记账（下一轮换别的渠道），只清活动条目。
                    clearActiveLedger(unmark = false)
                    // 自然播完：全程耗时可看出文件时长与是否被提前截断。
                    AppLog.i("audio", "MP3 自然播完 全程=${System.currentTimeMillis() - decodeStartedAtMillis}ms")
                    // 再向 Dart 返回成功。
                    // false 表示本次使用的是本地或远程 MP3，而不是 TTS。
                    pendingResult?.success(false)
                    // 清空结果避免重复回传。
                    pendingResult = null
                }
            }
            // 解码或播放错误转成用户可见失败。
            player.setOnErrorListener { failedPlayer, what, extra ->
                // 只处理当前播放器。
                if (generation == requestGeneration && mediaPlayer === failedPlayer) {
                    // 文件头通过但解码仍失败时，缓存内容已经不可信；删除后下次会重新下载。
                    synchronized(cacheMutationLock) {
                        if (audioFile.exists()) audioFile.delete()
                    }
                    // 返回可恢复错误；Dart 听音辨义页收到后会自动重试一次远程下载。
                    finishWithError(
                        "AUDIO_PLAYBACK_FAILED",
                        "音频文件无法解码，已清除缓存，请点击重试（$what/$extra）",
                    )
                }
                // true 表示错误已经由这里处理。
                true
            }
            // prepareAsync 不阻塞 Flutter 主线程。
            player.prepareAsync()
        } catch (error: Throwable) {
            // 同步准备失败也说明这份缓存不可播放，删除后允许下一次重新下载。
            synchronized(cacheMutationLock) {
                if (audioFile.exists()) audioFile.delete()
            }
            // setDataSource 等同步错误也走统一错误出口。
            finishWithError(
                "AUDIO_PLAYBACK_FAILED",
                error.message ?: error.javaClass.simpleName,
            )
        }
    }

    /** 网络音频失败后，选择设备上不需要网络的英语 TTS 声音并开始朗读。 */
    private fun startTtsFallback(spelling: String, accent: String, generation: Long) {
        // 新单词已经替换当前请求时，不能让旧请求突然开始朗读。
        if (generation != requestGeneration) return

        // 记录进入 TTS 兜底时的引擎状态：回答「本地 TTS 为什么没声」这类问题。
        val ttsState = when {
            ttsInitialized -> "已就绪"
            ttsInitializationFailed -> "初始化失败"
            else -> "仍在初始化"
        }
        AppLog.i("audio", "进入 TTS 兜底 拼写=$spelling 口音=$accent 引擎状态=$ttsState")

        // TTS 初始化尚未结束时，先保存动作；初始化回调完成后会继续执行它。
        if (!ttsInitialized) {
            if (ttsInitializationFailed) {
                finishWithError(
                    "AUDIO_TTS_UNAVAILABLE",
                    "当前设备没有可用的离线英语 TTS 引擎，请联网播放单词或安装英语语音包",
                )
                return
            }
            pendingTtsRequest = {
                if (generation == requestGeneration) {
                    startTtsFallback(spelling, accent, generation)
                }
            }
            return
        }

        // 根据当前设置选择美式或英式英语区域。
        val targetLocale = if (accent == AMERICAN) Locale.US else Locale.UK
        // 只接受引擎明确标记为“不需要网络”的英语声音，避免离线时再次卡住。
        val localVoices = textToSpeech?.voices
            ?.filter { candidate ->
                // 只接受英语且明确不依赖网络的声音。
                !candidate.isNetworkConnectionRequired &&
                    candidate.locale.language == targetLocale.language
            }
            .orEmpty()
        // 优先使用当前口音对应的国家/地区；部分国产引擎只提供通用 en，因此允许降级。
        val voice = localVoices.firstOrNull { candidate ->
            candidate.locale.country == targetLocale.country
        } ?: localVoices.firstOrNull()

        // 没有本地英语声音时，不调用可能依赖网络的 speak，直接给用户明确提示。
        if (voice == null) {
            finishWithError(
                "AUDIO_TTS_UNAVAILABLE",
                "当前设备没有可用的离线英语 TTS 引擎，请联网播放单词或安装英语语音包",
            )
            return
        }

        try {
            // 切换到检测到的具体声音，口音由 Voice 的 Locale 决定。
            textToSpeech?.voice = voice
            // TTS 也必须使用媒体语音通道，确保与 MP3 播放走同一条蓝牙输出路径。
            textToSpeech?.setAudioAttributes(speechAudioAttributes)
            // 与 MP3 保持一致：真正开始合成前申请短时媒体焦点。
            if (!requestAudioFocus()) {
                finishWithError(
                    "AUDIO_FOCUS_UNAVAILABLE",
                    "系统暂时无法取得音频输出，请稍后重试",
                )
                return
            }
            // 每次朗读使用唯一编号，过滤旧单词的迟到回调。
            val utteranceId = "my_english_tts_${generation}_${System.nanoTime()}"
            pendingTtsUtteranceId = utteranceId
            // QUEUE_FLUSH 确保新单词不会排在旧 TTS 后面等待。
            val result = textToSpeech?.speak(
                spelling,
                TextToSpeech.QUEUE_FLUSH,
                Bundle(),
                utteranceId,
            ) ?: TextToSpeech.ERROR
            // 引擎拒绝朗读时立即返回统一的 TTS 失败错误，避免 Future 永久等待。
            if (result != TextToSpeech.SUCCESS) {
                pendingTtsUtteranceId = null
                finishWithError(
                    "AUDIO_TTS_FAILED",
                    "设备 TTS 引擎无法朗读当前单词",
                )
            }
            // 引擎接受本次朗读请求；真正出声或出错由后续回调决定并记录。
            AppLog.i("audio", "TTS 已受理朗读 utterance=$utteranceId")
        } catch (error: Throwable) {
            // 厂商引擎异常也转换成用户可理解的错误。
            pendingTtsUtteranceId = null
            finishWithError(
                "AUDIO_TTS_FAILED",
                error.message ?: "设备 TTS 引擎无法朗读当前单词",
            )
        }
    }

    /** TTS 成功完成时结束 Dart 的播放 Future。 */
    private fun finishTtsSuccessfully(utteranceId: String) {
        // 旧单词回调到达时不能结束新单词的 Future。
        if (pendingTtsUtteranceId != utteranceId) return
        // TTS 最终成功出声并读完，记录完成（配合「进入 TTS 兜底」行可算出总等待）。
        AppLog.i("audio", "TTS 朗读完成 utterance=$utteranceId")
        // 清除当前 TTS 状态，防止重复回调重复完成结果。
        pendingTtsUtteranceId = null
        // 单词已经读完，释放焦点，避免蓝牙耳机或其他 App 后续仍认为本应用占用媒体输出。
        abandonAudioFocus()
        // 朗读完成后通知 Flutter 页面收起播放动画。
        // true 告诉 Flutter 本次实际由本地英语 TTS 完成朗读。
        pendingResult?.success(true)
        pendingResult = null
    }

    /** TTS 失败时结束 Dart 的播放 Future。 */
    private fun finishTtsWithError(utteranceId: String, errorCode: Int?) {
        // 旧单词回调到达时直接忽略。
        if (pendingTtsUtteranceId != utteranceId) return
        // 厂商引擎的错误码是排查「某台设备 TTS 不发声」的第一手线索，先留痕。
        AppLog.e("audio", "TTS 朗读失败 utterance=$utteranceId 错误码=${errorCode ?: "未知"}")
        // 清除当前 TTS 状态，避免后续错误回调重复返回。
        pendingTtsUtteranceId = null
        abandonAudioFocus()
        // 保留系统错误码，方便真机排查厂商引擎差异。
        val suffix = errorCode?.let { "（错误码 $it）" }.orEmpty()
        finishWithError(
            "AUDIO_TTS_FAILED",
            "设备 TTS 引擎无法朗读当前单词$suffix",
        )
    }

    /** 停掉旧播放器并结束旧的 Dart play Future。 */
    private fun interruptCurrent(code: String, message: String) {
        // 智能轮转播放被打断（换词/停止/清空）：这次没听完，回滚“本周期已读”记账。
        clearActiveLedger(unmark = true)
        // 先释放系统音频资源。
        releasePlayer()
        // 同时停止系统 TTS，避免旧单词在新请求后继续出声。
        textToSpeech?.stop()
        pendingTtsRequest = null
        pendingTtsUtteranceId = null
        // 如果旧请求仍在等待，明确告诉它已被替换或停止。
        pendingResult?.error(code, message, null)
        // MethodChannel.Result 只能回传一次，因此立即清空引用。
        pendingResult = null
    }

    /** 当前请求以错误结束。 */
    private fun finishWithError(code: String, message: String) {
        // 所有用户可见的播放失败都汇总到这里统一留痕，一处不漏。
        AppLog.e("audio", "播放失败 code=$code message=$message")
        // 播放器自身失败（坏缓存、抢不到音频焦点）时，点名播放没成功，回滚记账，
        // 让该渠道下次还能重新点名；TTS 类错误发生时没有点名播放，无需回滚。
        if (code == "AUDIO_PLAYBACK_FAILED" || code == "AUDIO_FOCUS_UNAVAILABLE") {
            clearActiveLedger(unmark = true)
        }
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
        // 播放结束、被替换或报错后都释放焦点，避免焦点状态残留。
        abandonAudioFocus()
    }

    /**
     * 申请媒体音频焦点。
     *
     * 音频焦点不是蓝牙配对权限，而是告诉 Android“这一次是媒体语音播放”。
     * 申请成功后，系统会把 MediaPlayer/TTS 与当前蓝牙媒体输出保持在同一路径。
     */
    private fun requestAudioFocus(): Boolean {
        if (hasAudioFocus) return true

        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = audioFocusRequest ?: AudioFocusRequest.Builder(
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
            )
                .setAudioAttributes(speechAudioAttributes)
                .setOnAudioFocusChangeListener(audioFocusChangeListener)
                .setWillPauseWhenDucked(false)
                .build()
                .also { audioFocusRequest = it }
            audioManager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                audioFocusChangeListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
            )
        }

        hasAudioFocus = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return hasAudioFocus
    }

    /** 释放本次短语音播放申请的音频焦点。 */
    private fun abandonAudioFocus() {
        if (!hasAudioFocus) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(audioFocusChangeListener)
        }
        hasAudioFocus = false
    }

    /**
     * 显示或刷新锁屏/通知栏的媒体控制卡片。
     *
     * 首次调用会创建 Android MediaSession 并通过 MediaStyle 通知把它挂到系统；
     * 之后每次切歌都只更新元数据（标题=拼写、副标题=首条释义）与播放状态。
     * 「媒体控制」类似音乐 App 在锁屏/下拉通知栏显示的播放条，蓝牙耳机也能直接操控。
     *
     * @param spelling 当前单词拼写（通知标题）。
     * @param subtitle 首条释义（通知副标题）。
     * @param isPlaying 当前是否正在播放，决定通知显示播放还是暂停图标。
     */
    fun showMediaSession(spelling: String, subtitle: String, isPlaying: Boolean) {
        // 缓存标题与副标题，后续刷新通知时直接复用，不必回读 MediaController。
        currentTitle = spelling
        currentSubtitle = subtitle
        // 首次进入时创建媒体会话并登记按键回调（仅一次）。
        ensureMediaSession()
        // 会话为空说明创建失败，直接放弃本次刷新避免空指针。
        val session = mediaSession ?: return
        // 组装媒体元数据：标题=拼写，专辑字段借放副标题，便于锁屏折行展示。
        val metadata = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, spelling)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, "MyEnglish")
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, subtitle)
            .build()
        // 写入元数据，锁屏卡片立即显示新单词。
        session.setMetadata(metadata)
        // 根据播放状态刷新 PlaybackState（系统据此决定显示播放/暂停按钮）。
        updatePlaybackState(isPlaying)
        // 弹出或更新通知栏媒体控制。
        postNotification(session, isPlaying)
    }

    /**
     * 仅切换播放/暂停状态（通知图标与锁屏按钮），不重建元数据。
     *
     * @param isPlaying 当前是否正在播放。
     */
    fun setMediaPlaying(isPlaying: Boolean) {
        // 会话不存在（用户还没播过歌）时无需操作。
        val session = mediaSession ?: return
        // 更新播放状态并刷新通知图标。
        updatePlaybackState(isPlaying)
        postNotification(session, isPlaying)
    }

    /**
     * 收起媒体控制并停用会话：移除通知、释放 MediaSession，避免锁屏残留控制条。
     */
    fun releaseMediaSession() {
        // 取出当前会话并置空，防止后续回调命中已释放对象。
        val session = mediaSession
        mediaSession = null
        // 会话存在才需要停用与释放，避免重复操作。
        if (session != null) {
            // 先取消激活，锁屏卡片随之消失。
            session.isActive = false
            // 再释放底层资源。
            session.release()
        }
        // 移除通知，彻底清掉通知栏媒体控制。
        notificationManager.cancel(MEDIA_NOTIFICATION_ID)
    }

    /** 懒创建媒体会话并登记回调（只初始化一次）。 */
    private fun ensureMediaSession() {
        // 已存在则直接复用，不做重复创建。
        if (mediaSession != null) return
        // MediaSessionCompat 是 Android 媒体控制的统一入口，第二个参数是调试标签。
        val session = MediaSessionCompat(appContext, "MyEnglishAudio")
        // 绑定回调：锁屏/通知栏/蓝牙的播放、暂停、上下首都会进入这里。
        session.setCallback(mediaSessionCallback)
        // 可用媒体动作已在 PlaybackState 中声明；新版兼容库不再需要旧式 flags。
        // 把会话置于激活态，锁屏才会显示媒体卡片。
        session.isActive = true
        // 保存引用供后续刷新与释放。
        mediaSession = session
    }

    /** 媒体会话回调：把系统/蓝牙的按键事件回传给 Dart（再交给随身听页）。 */
    private val mediaSessionCallback = object : MediaSessionCompat.Callback() {
        // 锁屏/蓝牙“播放”键。
        override fun onPlay() {
            sendMediaControl("play")
        }

        // 锁屏/蓝牙“暂停”键。
        override fun onPause() {
            sendMediaControl("pause")
        }

        // 锁屏/蓝牙“下一首”键。
        override fun onSkipToNext() {
            sendMediaControl("next")
        }

        // 锁屏/蓝牙“上一首”键。
        override fun onSkipToPrevious() {
            sendMediaControl("previous")
        }

        // 锁屏/蓝牙“停止”键。
        override fun onStop() {
            sendMediaControl("stop")
        }
    }

    /** 把媒体控制动作通过音频通道回传给 Dart；MethodChannel 会把它投递到随身听页。 */
    private fun sendMediaControl(action: String) {
        // invokeMethod 在任意线程调用都会被引擎安全地转交给 Dart 的接收器。
        mediaChannel.invokeMethod("mediaControl", mapOf("action" to action))
    }

    /** 构建并设置 PlaybackState（含可用动作与当前播放/暂停）。 */
    private fun updatePlaybackState(isPlaying: Boolean) {
        // 会话为空说明尚未创建，直接返回。
        val session = mediaSession ?: return
        // 声明通知栏与锁屏将要展示的动作集合（播放/暂停/上下首/停止）。
        val actions = PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
            PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
            PlaybackStateCompat.ACTION_STOP
        // 当前状态：播放中或已暂停，系统据此渲染对应按钮高亮。
        val state = if (isPlaying) {
            PlaybackStateCompat.STATE_PLAYING
        } else {
            PlaybackStateCompat.STATE_PAUSED
        }
        // 构建并写入状态；位置未知（我们不显示进度条），播放速度固定 1.0。
        session.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(state, PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN, 1.0f)
                .build(),
        )
    }

    /**
     * 构建并弹出 ".media style" 通知（锁屏/通知栏媒体控制）。
     *
     * 通过 MediaStyle 把媒体会话令牌挂到通知上，系统据此自动渲染播放/暂停/上下首控件，
     * 无需我们手写每个按钮的 PendingIntent。
     */
    private fun postNotification(session: MediaSessionCompat, isPlaying: Boolean) {
        // Android 8+ 必须先创建通知渠道，否则通知不会显示。
        createNotificationChannelIfNeeded()
        // 内容点击意图：回到 App 主界面（复用既有任务栈，不叠加新 Activity）。
        val contentIntent = PendingIntent.getActivity(
            appContext,
            0,
            Intent(appContext, MainActivity::class.java).apply {
                // SINGLE_TOP 复用栈顶 Activity，避免从通知多次进入开堆叠页面。
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            // 现代 Android 强制 PendingIntent 不可变，避免被其他 App 篡改意图。
            PendingIntent.FLAG_IMMUTABLE,
        )
        // MediaStyle 是音乐类通知的标准样式；挂上会话令牌后系统接管控件渲染。
        val style = MediaStyle()
            .setMediaSession(session.sessionToken)
            // 锁屏折叠后只保留前两枚控件（播放/暂停、上一首）。
            .setShowActionsInCompactView(0, 1)
        // 构建通知：标题=拼写，副标题=释义，小图标用专用通知图标。
        val notification = NotificationCompat.Builder(appContext, MEDIA_CHANNEL_ID)
            .setContentTitle(currentTitle)
            .setContentText(currentSubtitle)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(contentIntent)
            .setStyle(style)
            // PUBLIC 让锁屏也完整显示内容（单词本身非敏感）。
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            // 播放中设为常驻（滑动不消失），暂停后允许清除。
            .setOngoing(isPlaying)
            // 标记为媒体传输类通知，部分系统据此着色与分组。
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            // 刷新时不重复响铃/震动。
            .setOnlyAlertOnce(true)
            .build()
        // 用固定 id 弹出或更新通知，多次调用只更新同一张卡片。
        notificationManager.notify(MEDIA_NOTIFICATION_ID, notification)
    }

    /** 在 Android 8+ 创建媒体通知渠道（只需一次，低版本无需）。 */
    private fun createNotificationChannelIfNeeded() {
        // 低于 Android 8（API 26）不存在通知渠道概念，直接跳过。
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        // 创建一个低重要级渠道：有通知但不响铃、不弹窗，适合媒体控制。
        val channel = NotificationChannel(
            MEDIA_CHANNEL_ID,
            "单词播放控制",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            // 补充说明，用户长按通知可见。
            description = "锁屏与通知栏的单词播放控制"
            // 媒体控制不需要角标数字。
            setShowBadge(false)
        }
        // 把渠道注册进系统；重复创建会自动忽略。
        notificationManager.createNotificationChannel(channel)
    }

    /** 稳定协议值和超时集中定义。 */
    private companion object {
        // 美式缓存目录名与 Dart storageValue 一致。
        const val AMERICAN = "american"

        // 英式缓存目录名与 Dart storageValue 一致。
        const val BRITISH = "british"

        // 发音渠道：稳定协议值（历史版本与 Dart 侧 PronunciationChannel.storageValue
        // 一一对应；4.5.0 起渠道挑选与轮转记账整体下沉到原生，Dart 不再参与挑选）。
        // 优先级约定（数字越大越优先）：不背单词=100、百度翻译=50（新增渠道默认值）、
        // 有道=10、系统 TTS=0。
        const val CHANNEL_BEINGFINE = "beingfine"

        // 百度翻译网络 TTS 渠道（fanyi.baidu.com/gettts）。
        const val CHANNEL_BAIDU = "baidu"

        // 有道网络音频渠道。
        const val CHANNEL_YOUDAO = "youdao"

        // 系统离线英语 TTS 渠道：不做网络请求，直接朗读。
        const val CHANNEL_TTS = "tts"

        // 离线预缓存会尝试下载的网络渠道；系统 TTS 是设备实时合成，没有文件可缓存。
        // 顺序即优先级：与 buildSources 的兜底顺序保持一致。
        val NETWORK_CHANNELS = listOf(CHANNEL_BEINGFINE, CHANNEL_BAIDU, CHANNEL_YOUDAO)

        // 旧版本的口音级缓存只保留一份“任意网络渠道成功”的结果；进度统计时把它
        // 当作一个虚拟渠道，避免升级后明明已有离线发音却显示成 0%。
        const val LEGACY_CACHE_CHANNEL = "_legacy"

        // 每个网络来源最多等待 1 秒；超时后立即尝试下一个音源或后续 TTS 兜底。
        const val NETWORK_TIMEOUT_MILLIS = 1_000

        // 网络音频失败记录有效 5 分钟，避免每个单词重复请求三个网络音源。
        const val NETWORK_FAILURE_TTL_MILLIS = 5 * 60 * 1_000L

        // 智能轮转的无缓存等待窗口：第一次点某词时，最多等这么久让快的下载赶上发声，
        // 避免首次播放必定是机器 TTS。窗口结束未完成的下载继续在后台跑，不会被取消。
        const val SMART_PREFETCH_WINDOW_MILLIS = 1_000L

        // 等待窗口内的轮询粒度：每 100 毫秒看一次后台补缓存是否已写好新文件。
        const val SMART_PREFETCH_POLL_MILLIS = 100L

        // settings 表中保存网络音频失败截止时间的键名。
        const val NETWORK_AUDIO_UNAVAILABLE_UNTIL_KEY = "networkAudioUnavailableUntilMillis"

        // 便于从 adb logcat 中筛选本功能的网络兜底日志。
        const val LOG_TAG = "MyEnglishAudio"

        // 下载时每次读取 8KB，兼顾内存与 IO 次数。
        const val DOWNLOAD_BUFFER_BYTES = 8 * 1024

        // 媒体通知固定 id：多次弹出只更新同一张通知卡片。
        const val MEDIA_NOTIFICATION_ID = 1001

        // 媒体通知渠道 id：Android 8+ 必须先在系统注册该渠道。
        const val MEDIA_CHANNEL_ID = "my_english_media_session"
    }
}
