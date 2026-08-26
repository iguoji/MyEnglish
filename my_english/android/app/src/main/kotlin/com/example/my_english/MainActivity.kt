// package 相当于 PHP namespace，必须与 Android application namespace 对应。
package com.example.my_english

// FlutterActivity 是 Android 承载 Flutter 页面所需的原生 Activity 基类。
import io.flutter.embedding.android.FlutterActivity
// FlutterEngine 提供 Dart 与 Android 原生层之间的运行引擎。
import io.flutter.embedding.engine.FlutterEngine
// MethodChannel 类似小程序 JS 调用原生插件时使用的桥接 API。
import io.flutter.plugin.common.MethodChannel
// EventChannel 用于把离线预缓存的实时进度持续推回 Dart。
import io.flutter.plugin.common.EventChannel
// ExecutorService/Executors 提供数据库与普通文件 I/O 队列，避免阻塞 Flutter UI。
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

// Activity 提供 RESULT_OK 等标准返回码，用于判断 SAF 选择结果。
import android.app.Activity
// Intent 用来启动系统文件选择器（打开/保存文档）。
import android.content.Intent
// Uri 是 SAF 返回的文件定位符，类似小程序临时文件路径但由系统托管。
import android.net.Uri
// IO 与字符集工具：把 Uri 读成文本、把文本写进 Uri。
import java.io.BufferedReader
import java.io.IOException
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.nio.charset.StandardCharsets

/**
 * Android 原生入口，相当于 Flutter 页面背后的原生 Controller。
 *
 * Dart Store 通过 MethodChannel 调用这里访问 SQLite。数据库与普通文件 I/O 分别在
 * 独立单线程队列中顺序执行，避免事务、缓存扫描或大文件读写阻塞 Android 主线程。
 */
class MainActivity : FlutterActivity() {
    // 通道名相当于接口路由，必须与 Dart LocalWordStore 中的字符串完全一致。
    private val channelName = "my_english/word_store"

    // 设置通道负责 SharedPreferences 读取和写入。
    private val settingsChannelName = "my_english/settings"

    // 音频通道负责缓存、双来源下载和 MediaPlayer 播放。
    private val audioChannelName = "my_english/word_audio"

    // 音节划分通道负责把每个单词的音节切分读写到原生 SQLite。
    private val syllableChannelName = "my_english/syllable"

    // 离线预缓存进度事件通道：Kotlin 在后台批量缓存时持续推送 {cached,total,done}。
    private val audioCacheChannelName = "my_english/audio_cache"

    // 当前 Dart 端对进度流的订阅接收器；null 表示还没有任何页面在监听。
    private var audioCacheSink: EventChannel.EventSink? = null

    // 后台任务只在 FlutterEngine 仍绑定时回传 MethodChannel 结果。
    @Volatile
    private var acceptsChannelResults = false

    // 文件通道负责 SAF 选 JSON 与导出写文件，与 word_store 同风格的原生桥接。
    private val fileIoChannelName = "my_english/file_io"

    // 单线程执行器保证导入、读取、写入不会并发破坏事务顺序。
    private val databaseExecutor = Executors.newSingleThreadExecutor()

    // 独立 I/O 队列处理缓存扫描、SharedPreferences 和 SAF 文件，避免占用数据库队列。
    private val ioExecutor = Executors.newSingleThreadExecutor()

    // lateinit 表示 Activity 创建后再初始化，类似 PHP 类中稍后注入 Store 属性。
    private lateinit var wordsDatabase: WordsDatabase

    // 原生设置 Store 与 Dart SettingsStore 一一对应。
    private lateinit var appSettingsStore: AppSettingsStore

    // 原生音频服务可以跨 Flutter Widget 重建持续工作。
    private lateinit var wordAudioPlayer: WordAudioPlayer

    // 音频方法通道：既接收 Dart 的 play/stop，也用于把锁屏/蓝牙的媒体控制事件回传 Dart。
    private lateinit var audioChannel: MethodChannel

    // SAF 请求码：导入选文件与导出写文件共用，结果里再用 pendingFileAction 区分。
    private companion object {
        const val REQUEST_CODE_FILE_IO = 1001
    }

    // 当前正在等待系统选择器结果的 Dart 调用；同一时刻只允许一个文件操作。
    private var pendingFileResult: MethodChannel.Result? = null

    // 区分本次 SAF 是「选文件」还是「写文件」。
    private var pendingFileAction: String? = null

    // 写文件时暂存要落盘的 JSON 文本。
    private var pendingExportText: String? = null

    // 写文件时暂存预填文件名（结果回调里不再需要，仅用于防御性校验）。
    private var pendingExportName: String? = null

    // FlutterEngine 准备完成后会调用本方法，对应在小程序插件中注册可调用的方法。
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // 先保留 FlutterActivity 自己的标准初始化流程。
        super.configureFlutterEngine(flutterEngine)
        // 从这里开始当前引擎可以安全接收异步通道结果。
        acceptsChannelResults = true
        // 创建 SQLite helper；applicationContext 可避免持有 Activity 导致内存泄漏。
        wordsDatabase = WordsDatabase(applicationContext)
        // 创建 App 私有设置 Store。
        appSettingsStore = AppSettingsStore(applicationContext)
        // 先创建音频通道：Dart 调用播放/停止，也用于把媒体按键回传给 Dart。
        audioChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioChannelName)
        // 创建下载与播放服务，把音频通道交给它用于回传锁屏/蓝牙的媒体控制事件。
        wordAudioPlayer = WordAudioPlayer(applicationContext, audioChannel)

        // 在当前 FlutterEngine 上注册 Dart ↔ Android 方法通道。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            // 每次 Dart invokeMethod 都会进入这个处理器。
            .setMethodCallHandler { call, result ->
                // when 类似 PHP 8 match，根据方法名路由到不同数据库操作。
                when (call.method) {
                    // Dart Store 调用这里读取全部 SQLite Word/Meaning。
                    "getAllWords" -> runDatabaseCall(result) {
                        // 只查询 SQLite，不读取 JSON，也不会执行任何导入或写入。
                        wordsDatabase.getAllWords()
                    }

                    // 新增单词接口。
                    "createWord" -> runDatabaseCall(result) {
                        // arguments 对应 Dart 传来的 Map；类型不符时主动抛出清晰错误。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("createWord 缺少单词参数")
                        // 在事务内创建 Word 和 Meanings，并返回自增主键。
                        wordsDatabase.createWord(payload)
                    }

                    // 编辑单词接口。
                    "updateWord" -> runDatabaseCall(result) {
                        // 读取 Dart Word.toMap 生成的数据。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("updateWord 缺少单词参数")
                        // 更新完成后返回 null，对应 Dart Future<void>。
                        wordsDatabase.updateWord(payload)
                        null
                    }

                    // 删除操作使用软删除接口。
                    "deleteWord" -> runDatabaseCall(result) {
                        // 删除参数使用 Map，便于以后扩展其他字段。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("deleteWord 缺少删除参数")
                        // id 必须为数字。
                        val id = (payload["id"] as? Number)?.toLong()
                            ?: error("deleteWord 缺少有效 id")
                        // 写入 deleted_at 而不是物理删除。
                        wordsDatabase.softDeleteWord(id)
                        null
                    }

                    // 批量导入：先清空旧数据再整库替换写入。
                    "importWords" -> runDatabaseCall(result) {
                        // 参数必须是 Dart 传来的单词 Map 列表。
                        val payload = call.arguments as? List<*>
                            ?: error("importWords 缺少单词列表")
                        // 在事务内批量写入，返回 null 对应 Dart Future<void>。
                        wordsDatabase.importWords(payload)
                        null
                    }

                    // 清空全部 SQLite 业务数据与听音辨义候选缓存，对应「清空数据」入口。
                    "clearAllWords" -> runDatabaseCall(result) {
                        // 原生事务会删除词库、分组、记录及候选缓存。
                        wordsDatabase.clearAllWords()
                        null
                    }

                    // 读取全部未删除分组，供首页与分组管理面板使用。
                    "getAllGroups" -> runDatabaseCall(result) {
                        // 直接返回分组列表，Dart GroupStore 负责加载。
                        wordsDatabase.getAllGroups()
                    }

                    // 新建分组并返回自增主键。
                    "createGroup" -> runDatabaseCall(result) {
                        // 读取 Dart 传来的名称与排序值。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("createGroup 缺少参数")
                        // 名称必填。
                        val name = payload["name"]?.toString()
                            ?: error("createGroup 缺少 name")
                        // 排序值缺省为 0。
                        val sortOrder = (payload["sortOrder"] as? Number)?.toInt() ?: 0
                        // 插入并返回新主键。
                        wordsDatabase.createGroup(name, sortOrder)
                    }

                    // 重命名分组。
                    "renameGroup" -> runDatabaseCall(result) {
                        // 读取分组 id 与名称。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("renameGroup 缺少参数")
                        // id 必须为数字。
                        val id = (payload["id"] as? Number)?.toLong()
                            ?: error("renameGroup 缺少有效 id")
                        // 名称必填。
                        val name = payload["name"]?.toString()
                            ?: error("renameGroup 缺少 name")
                        // 更新并返回 null 对应 Dart Future<void>。
                        wordsDatabase.renameGroup(id, name)
                        null
                    }

                    // 调整分组排序。
                    "setGroupOrder" -> runDatabaseCall(result) {
                        // 读取分组 id 与排序值。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("setGroupOrder 缺少参数")
                        // id 必须为数字。
                        val id = (payload["id"] as? Number)?.toLong()
                            ?: error("setGroupOrder 缺少有效 id")
                        // 排序值必填。
                        val sortOrder = (payload["sortOrder"] as? Number)?.toInt()
                            ?: error("setGroupOrder 缺少 sortOrder")
                        // 更新并返回 null。
                        wordsDatabase.setGroupOrder(id, sortOrder)
                        null
                    }

                    // 软删除分组并清理其成员。
                    "deleteGroup" -> runDatabaseCall(result) {
                        // 读取分组 id。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("deleteGroup 缺少参数")
                        // id 必须为数字。
                        val id = (payload["id"] as? Number)?.toLong()
                            ?: error("deleteGroup 缺少有效 id")
                        // 删除并返回 null。
                        wordsDatabase.deleteGroup(id)
                        null
                    }

                    // 把单词加入某分组（复制语义）。
                    "addGroupMember" -> runDatabaseCall(result) {
                        // 读取分组与单词主键。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("addGroupMember 缺少参数")
                        // 两个外键都必须为数字。
                        val groupId = (payload["groupId"] as? Number)?.toLong()
                            ?: error("addGroupMember 缺少有效 groupId")
                        val wordId = (payload["wordId"] as? Number)?.toLong()
                            ?: error("addGroupMember 缺少有效 wordId")
                        // 加入并返回 null。
                        wordsDatabase.addGroupMember(groupId, wordId)
                        null
                    }

                    // 把单词从某分组移除。
                    "removeGroupMember" -> runDatabaseCall(result) {
                        // 读取分组与单词主键。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("removeGroupMember 缺少参数")
                        // 两个外键都必须为数字。
                        val groupId = (payload["groupId"] as? Number)?.toLong()
                            ?: error("removeGroupMember 缺少有效 groupId")
                        val wordId = (payload["wordId"] as? Number)?.toLong()
                            ?: error("removeGroupMember 缺少有效 wordId")
                        // 移除并返回 null。
                        wordsDatabase.removeGroupMember(groupId, wordId)
                        null
                    }

                    // 设置单词的全部所属分组（移动语义）。
                    "setWordGroups" -> runDatabaseCall(result) {
                        // 读取单词主键与分组 id 列表。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("setWordGroups 缺少参数")
                        // 单词 id 必须为数字。
                        val wordId = (payload["wordId"] as? Number)?.toLong()
                            ?: error("setWordGroups 缺少有效 wordId")
                        // 分组 id 列表可为空（移回未分组）。
                        val groupIds = payload["groupIds"] as? List<*> ?: emptyList<Any?>()
                        // 替换关系并返回 null。
                        wordsDatabase.setWordGroups(wordId, groupIds)
                        null
                    }

                    // 导入 words 数组，以及文件中可选的 groups/members。
                    "importData" -> runDatabaseCall(result) {
                        // 参数必须是 Dart 规范化后的导入 Map。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("importData 缺少导入数据")
                        // 在事务内替换词库并按需重建分组，返回 null 对应 Dart Future<void>。
                        wordsDatabase.importData(payload)
                        null
                    }

                    // 直接从 SQLite 实际业务字段生成单词与分组导出数据。
                    "exportData" -> runDatabaseCall(result) {
                        // 日期和数组已在数据库层转为人类可读的 MethodChannel 值。
                        wordsDatabase.exportData()
                    }

                    // 读取随身听和听音辨义尚未完成的学习会话。
                    "getLearningSessions" -> runDatabaseCall(result) {
                        // 最多返回两条结构化记录，Dart 首页据此显示“继续”按钮。
                        wordsDatabase.getLearningSessions()
                    }

                    // 新增或覆盖一种学习方式的进度与单词列表。
                    "saveLearningSession" -> runDatabaseCall(result) {
                        // Dart 已把数组和页面状态编码为 JSON 字符串，原生只负责可靠落盘。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("saveLearningSession 缺少参数")
                        val sessionType = payload["session_type"]?.toString()?.trim()
                            ?.takeIf { it.isNotEmpty() }
                            ?: error("saveLearningSession 缺少有效 session_type")
                        val wordIdsJson = payload["word_ids_json"]?.toString()
                            ?: error("saveLearningSession 缺少 word_ids_json")
                        val stateJson = payload["state_json"]?.toString()
                            ?: error("saveLearningSession 缺少 state_json")
                        // 主键冲突时覆盖，返回 null 对应 Dart Future<void>。
                        wordsDatabase.saveLearningSession(sessionType, wordIdsJson, stateJson)
                        null
                    }

                    // 删除已经完成或无法恢复的一种学习会话。
                    "deleteLearningSession" -> runDatabaseCall(result) {
                        // 参数只需要稳定类型键。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("deleteLearningSession 缺少参数")
                        val sessionType = payload["session_type"]?.toString()?.trim()
                            ?.takeIf { it.isNotEmpty() }
                            ?: error("deleteLearningSession 缺少有效 session_type")
                        wordsDatabase.deleteLearningSession(sessionType)
                        null
                    }

                    // ── 复习模块：每日词库 ──────────────────────────────
                    // 读取设备本地今天的每日词库；四个模块共用同一批单词。
                    "getTodayWordSet" -> runDatabaseCall(result) {
                        wordsDatabase.getTodayWordSet()
                    }

                    // 保存（覆盖）今天的每日词库；日期由原生按设备时区生成。
                    "saveTodayWordSet" -> runDatabaseCall(result) {
                        val payload = call.arguments as? Map<*, *>
                            ?: error("saveTodayWordSet 缺少参数")
                        val wordIds = readLongList(payload["wordIds"], "saveTodayWordSet.wordIds")
                        wordsDatabase.saveTodayWordSet(wordIds)
                    }

                    // ── 复习模块：模块会话 ──────────────────────────────
                    // 读取某模块今天最新的一条会话（不论状态）。
                    "getLatestReviewSession" -> runDatabaseCall(result) {
                        wordsDatabase.getLatestReviewSession(
                            readModule(call.arguments, "getLatestReviewSession"),
                        )
                    }

                    // 读取某模块今天已完成的主线会话；有它才说明今日任务过关。
                    "getCompletedDailyReviewSession" -> runDatabaseCall(result) {
                        wordsDatabase.getCompletedDailyReviewSession(
                            readModule(call.arguments, "getCompletedDailyReviewSession"),
                        )
                    }

                    // 首页四张卡片的三态数据：今天每个模块最新一条会话的状态。
                    "getTodayReviewSessionStates" -> runDatabaseCall(result) {
                        wordsDatabase.getTodayReviewSessionStates()
                    }

                    // 新建一局会话（主线或巩固），返回完整行供页面直接使用。
                    "createReviewSession" -> runDatabaseCall(result) {
                        val payload = call.arguments as? Map<*, *>
                            ?: error("createReviewSession 缺少参数")
                        val module = payload["module"]?.toString()?.trim()
                            ?.takeIf { it.isNotEmpty() }
                            ?: error("createReviewSession 缺少有效 module")
                        val kind = (payload["kind"] as? Number)?.toInt()
                            ?: error("createReviewSession 缺少有效 kind")
                        // 词库 id 可空：巩固局的单词跨越今明两天，不属于单一词库。
                        val wordSetId = (payload["wordSetId"] as? Number)?.toLong()
                        val wordIds = readLongList(payload["wordIds"], "createReviewSession.wordIds")
                        val stateJson = payload["stateJson"]?.toString() ?: "{}"
                        wordsDatabase.createReviewSession(module, kind, wordSetId, wordIds, stateJson)
                    }

                    // 更新一局进行中会话的页面进度与累计错误数。
                    "updateReviewSessionProgress" -> runDatabaseCall(result) {
                        val payload = call.arguments as? Map<*, *>
                            ?: error("updateReviewSessionProgress 缺少参数")
                        val sessionId = (payload["sessionId"] as? Number)?.toLong()
                            ?: error("updateReviewSessionProgress 缺少有效 sessionId")
                        val stateJson = payload["stateJson"]?.toString()
                            ?: error("updateReviewSessionProgress 缺少 stateJson")
                        val wrongTotal = (payload["wrongTotal"] as? Number)?.toInt() ?: 0
                        wordsDatabase.updateReviewSessionProgress(sessionId, stateJson, wrongTotal)
                        null
                    }

                    // 给一局会话结算：完成 / 中断 / 失败。
                    "finishReviewSession" -> runDatabaseCall(result) {
                        val payload = call.arguments as? Map<*, *>
                            ?: error("finishReviewSession 缺少参数")
                        val sessionId = (payload["sessionId"] as? Number)?.toLong()
                            ?: error("finishReviewSession 缺少有效 sessionId")
                        val status = (payload["status"] as? Number)?.toInt()
                            ?: error("finishReviewSession 缺少有效 status")
                        // 两个可空参数表示「保持数据库现值」，页面可只改状态。
                        val stateJson = payload["stateJson"]?.toString()
                        val wrongTotal = (payload["wrongTotal"] as? Number)?.toInt()
                        wordsDatabase.finishReviewSession(sessionId, status, stateJson, wrongTotal)
                    }

                    // 批量中断进行中的会话：改设置时全部中断，跨天时只收非今日的。
                    "abortActiveReviewSessions" -> runDatabaseCall(result) {
                        val onlyStale = (call.arguments as? Map<*, *>)
                            ?.get("onlyStale") as? Boolean ?: false
                        wordsDatabase.abortActiveReviewSessions(onlyStale)
                    }

                    // ── 复习模块：复习记录 ──────────────────────────────
                    // 记录一次单词复习结果，并在事务内更新连对次数、难度与复习时间。
                    "addReviewRecord" -> runDatabaseCall(result) {
                        val payload = call.arguments as? Map<*, *>
                            ?: error("addReviewRecord 缺少参数")
                        val wordId = (payload["wordId"] as? Number)?.toLong()
                            ?: error("addReviewRecord 缺少有效 wordId")
                        val module = payload["module"]?.toString()?.trim()
                            ?.takeIf { it.isNotEmpty() }
                            ?: error("addReviewRecord 缺少有效 module")
                        // 会话 id 可空：词库底部的普通听音辨义不属于任何复习会话。
                        val sessionId = (payload["sessionId"] as? Number)?.toLong()
                        val wrongCount = (payload["wrongCount"] as? Number)?.toInt() ?: 0
                        val hintCount = (payload["hintCount"] as? Number)?.toInt() ?: 0
                        // 只有每日主线会话才推进单词的复习时间；巩固局传 false。
                        val updateReviewedAt = payload["updateReviewedAt"] as? Boolean ?: true
                        val extraJson = payload["extraJson"]?.toString() ?: "{}"
                        wordsDatabase.addReviewRecord(
                            wordId,
                            module,
                            sessionId,
                            wrongCount,
                            hintCount,
                            updateReviewedAt,
                            extraJson,
                        )
                    }

                    // 读取今日全部复习记录，供"今日复习"明细展示。
                    "getTodayReviewRecords" -> runDatabaseCall(result) {
                        wordsDatabase.getTodayReviewRecords()
                    }

                    // 今日复习数量：今天「一次做对」过的不同单词数。
                    "getTodayReviewWordCount" -> runDatabaseCall(result) {
                        wordsDatabase.getTodayReviewWordCount()
                    }

                    // 读取一道听音辨义题已经持久化的三个干扰项和正确答案位置。
                    "getListeningMeaningOptionCache" -> runDatabaseCall(result) {
                        // 缓存 key 必须是非空字符串。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("getListeningMeaningOptionCache 缺少参数")
                        val cacheKey = payload["cacheKey"]?.toString()?.trim()
                            ?.takeIf { it.isNotEmpty() }
                            ?: error("getListeningMeaningOptionCache 缺少有效 cacheKey")
                        // null 表示首次生成，Map 表示命中可还原完整四选一的缓存。
                        wordsDatabase.getListeningMeaningOptionCache(cacheKey)
                    }

                    // 新增或覆盖一道听音辨义题的干扰项与正确答案位置缓存。
                    "saveListeningMeaningOptionCache" -> runDatabaseCall(result) {
                        // 读取 Dart Store 提交的 key、可空单词外键与文本数组。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("saveListeningMeaningOptionCache 缺少参数")
                        val cacheKey = payload["cacheKey"]?.toString()?.trim()
                            ?.takeIf { it.isNotEmpty() }
                            ?: error("saveListeningMeaningOptionCache 缺少有效 cacheKey")
                        val wordId = (payload["wordId"] as? Number)?.toLong()
                        val distractors = (payload["distractors"] as? List<*>)
                            ?.mapNotNull { it?.toString()?.trim()?.takeIf(String::isNotEmpty) }
                            ?: error("saveListeningMeaningOptionCache 缺少 distractors")
                        // 标准四选一只能有三个干扰项，原生入口也拒绝不完整数据。
                        if (distractors.size != 3) {
                            error("saveListeningMeaningOptionCache 的 distractors 必须恰好三项")
                        }
                        // correctIndex 表示正确答案所在的 A/B/C/D 位置。
                        val correctIndex = (payload["correctIndex"] as? Number)?.toInt()
                            ?.takeIf { it in 0..3 }
                            ?: error("saveListeningMeaningOptionCache 缺少有效 correctIndex")
                        wordsDatabase.saveListeningMeaningOptionCache(
                            cacheKey,
                            wordId,
                            distractors,
                            correctIndex,
                        )
                        null
                    }

                    // 按天统计复习单词数（每天去重），供趋势曲线与打卡质量卡使用。
                    "getDailyReviewCounts" -> runDatabaseCall(result) {
                        // 可选参数：起始日期 yyyy-MM-dd；null 表示统计全部历史。
                        val since = (call.arguments as? Map<*, *>)?.get("since") as? String
                        wordsDatabase.getDailyReviewCounts(since)
                    }

                    // 按月统计复习单词数（每月去重），供趋势曲线"半年/一年"档使用。
                    "getMonthlyReviewCounts" -> runDatabaseCall(result) {
                        // 可选参数：起始月份 yyyy-MM；null 表示统计全部历史。
                        val since = (call.arguments as? Map<*, *>)?.get("since") as? String
                        wordsDatabase.getMonthlyReviewCounts(since)
                    }

                    // 按 id 读取指定单词，供复习后只回刷相关单词。
                    "getWordsByIds" -> runDatabaseCall(result) {
                        // 读取 Dart 传来的 id 列表。
                        val payload = call.arguments as? List<*>
                            ?: error("getWordsByIds 缺少参数")
                        // 只保留数字类型 id，过滤任何异常元素。
                        val ids = payload.mapNotNull { (it as? Number)?.toLong() }
                        wordsDatabase.getWordsByIds(ids)
                    }

                    // 未登记的方法返回 Flutter 标准 notImplemented 错误。
                    else -> result.notImplemented()
                }
            }

        // 注册音节划分通道；Dart 通过它把每个单词的音节切分读写到原生 SQLite。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, syllableChannelName)
            // 每次 Dart invokeMethod 都会进入这个处理器。
            .setMethodCallHandler { call, result ->
                // when 类似 PHP 8 match，根据方法名路由到不同数据库操作。
                when (call.method) {
                    // 读取某单词已保存的音节划分。
                    "getSyllableDivision" -> runDatabaseCall(result) {
                        val payload = call.arguments as? Map<*, *>
                            ?: error("getSyllableDivision 缺少参数")
                        // 参数必须是 Dart 传来的。
                        val word = payload["word"]?.toString()?.trim()
                            ?.takeIf { it.isNotEmpty() }
                            ?: error("getSyllableDivision 缺少有效 word")
                        // 表里没有会返回 null，对应 Dart 的 SyllableRow?。
                        wordsDatabase.getSyllableDivision(word)
                    }

                    // 新增或覆盖某单词的音节划分。
                    "saveSyllableDivision" -> runDatabaseCall(result) {
                        // 参数为 {word, syllables(JSON), source} 的 Map。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("saveSyllableDivision 缺少参数")
                        val word = payload["word"]?.toString()?.trim()
                            ?.takeIf { it.isNotEmpty() }
                            ?: error("saveSyllableDivision 缺少有效 word")
                        val syllablesJson = payload["syllables"]?.toString()
                            ?: error("saveSyllableDivision 缺少 syllables")
                        val source = payload["source"]?.toString()?.trim()
                            ?.takeIf { it.isNotEmpty() }
                            ?: error("saveSyllableDivision 缺少有效 source")
                        // 主键冲突时整体替换，刷新/手动覆盖都只需一次写入，返回 null。
                        wordsDatabase.saveSyllableDivision(word, syllablesJson, source)
                        null
                    }

                    // 未登记的方法返回 Flutter 标准 notImplemented 错误。
                    else -> result.notImplemented()
                }
            }

        // 注册全局设置通道；磁盘读取与写入统一进入 I/O 队列。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, settingsChannelName)
            // 根据方法名读取或写入设置字段。
            .setMethodCallHandler { call, result ->
                // when 类似 PHP match；每个磁盘动作都由 runIoCall 切到后台执行。
                when (call.method) {
                    // 返回当前设置快照。
                    "getSettings" -> runIoCall(result, "SETTINGS_ERROR") {
                        appSettingsStore.getSettings()
                    }

                    // 保存新的口音字符串。
                    "setAccent" -> runIoCall(result, "SETTINGS_ERROR") {
                        // 参数必须是 Dart 传来的 String。
                        val value = call.arguments as? String
                            ?: error("setAccent 缺少字符串参数")
                        // Store 内部继续校验允许值并同步持久化。
                        appSettingsStore.setAccent(value)
                        // void 方法使用 null 表示成功返回值。
                        null
                    }

                    // 保存新的主题字符串。
                    "setTheme" -> runIoCall(result, "SETTINGS_ERROR") {
                        // 参数必须是 Dart 传来的 String。
                        val value = call.arguments as? String
                            ?: error("setTheme 缺少字符串参数")
                        // Store 内部继续校验允许值并同步持久化。
                        appSettingsStore.setTheme(value)
                        // 返回 null 通知 Dart 持久化完成。
                        null
                    }

                    // 保存新的中文释义分隔符。
                    "setDefinitionSeparator" -> runIoCall(result, "SETTINGS_ERROR") {
                        // 参数必须是 Dart 枚举转换后的稳定字符串。
                        val value = call.arguments as? String
                            ?: error("setDefinitionSeparator 缺少字符串参数")
                        // Store 继续校验值是否属于顿号、逗号或分号三者之一。
                        appSettingsStore.setDefinitionSeparator(value)
                        // 返回 null 通知 Dart 刷新全部中文释义。
                        null
                    }

                    // 保存每日复习目标整数。
                    "setDailyGoal" -> runIoCall(result, "SETTINGS_ERROR") {
                        // MethodChannel 可能把 Dart int 映射成 Int 或 Long，因此统一按 Number 读取。
                        val value = (call.arguments as? Number)?.toInt()
                            ?: error("setDailyGoal 缺少整数参数")
                        // Store 校验非负数并同步写入 SharedPreferences。
                        appSettingsStore.setDailyGoal(value)
                        // 返回 null 通知 Dart 刷新目标数字。
                        null
                    }

                    // 保存词义连连每局倒计时整数。
                    "setMeaningMatchDuration" -> runIoCall(result, "SETTINGS_ERROR") {
                        // MethodChannel 可能把 Dart int 映射成 Int 或 Long，因此统一按 Number 读取。
                        val value = (call.arguments as? Number)?.toInt()
                            ?: error("setMeaningMatchDuration 缺少整数参数")
                        // Store 校验非负数并同步写入 SharedPreferences。
                        appSettingsStore.setMeaningMatchDuration(value)
                        // 返回 null 通知 Dart 刷新倒计时。
                        null
                    }

                    // 清空全部设置，恢复到首次安装默认值。
                    "clearAllSettings" -> runIoCall(result, "SETTINGS_ERROR") {
                        // 删除 SharedPreferences 中的全部键值。
                        appSettingsStore.clearAll()
                        // 返回 null 通知 Dart 清空完成。
                        null
                    }

                    // 未登记方法按 Flutter 规范返回 notImplemented。
                    else -> result.notImplemented()
                }
            }

        // 注册音频通道；play 的 result 会由 WordAudioPlayer 在播放完成时返回。
        // 复用已创建的 audioChannel 实例，避免重复注册通道导致 IllegalStateException。
        audioChannel
            // 路由播放和停止方法。
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 播放请求包含拼写和口音。
                    "play" -> {
                        // arguments 对应 Dart 传来的普通 Map。
                        val payload = call.arguments as? Map<*, *>
                        // 读取拼写，错误时使用空字符串交给服务输出统一参数错误。
                        val spelling = payload?.get("spelling") as? String ?: ""
                        // 读取口音，错误时同样由服务统一校验。
                        val accent = payload?.get("accent") as? String ?: ""
                        // 异步下载、缓存并播放；完成前不立即调用 result。
                        wordAudioPlayer.play(spelling, accent, result)
                    }

                    // 页面销毁或进入后台时停止当前播放。
                    "stop" -> wordAudioPlayer.stop(result)

                    // 离线预缓存：Dart 传入全部单词拼写，Kotlin 后台并发缓存并
                    // 通过音频进度事件通道实时上报 {cached,total,done}。方法本身
                    // 立即返回，缓存任务在独立线程池中长期运行，不受抽屉关闭影响。
                    "precache" -> {
                        // 读取 Dart 传来的拼写字符串列表。
                        val payload = call.arguments as? Map<*, *>
                        val spellings = (payload?.get("spellings") as? List<*>)
                            ?.mapNotNull { it as? String } ?: emptyList()
                        // 启动后台批量缓存；进度通过已注册的 EventSink 推回 Dart。
                        wordAudioPlayer.precacheAll(spellings) { batch, cached, total, done ->
                            // EventSink 必须在主线程调用；后台线程池的回调切到 UI 线程。
                            runOnUiThread {
                                // 清空缓存或新批次启动后，排队中的旧事件不能覆盖最新状态。
                                if (!wordAudioPlayer.isCurrentPrecacheBatch(batch)) return@runOnUiThread
                                try {
                                    // 没有订阅者（页面未打开抽屉）或引擎正在销毁时静默丢弃。
                                    // try 防止引擎已解绑后仍调用 success 抛 IllegalStateException。
                                    audioCacheSink?.success(
                                        mapOf(
                                            "cached" to cached,
                                            "total" to total,
                                            "done" to done,
                                        ),
                                    )
                                } catch (_: Throwable) {
                                    // 引擎已销毁等极端情况忽略，不阻塞后台缓存任务。
                                }
                            }
                        }
                        // 方法调用立即结束，缓存在后台继续。
                        result.success(null)
                    }

                    // 查询当前已缓存的音频数量（美式 + 英式），用于抽屉显示初始百分比。
                    "getCacheProgress" -> {
                        // 读取 Dart 传来的拼写字符串列表。
                        val payload = call.arguments as? Map<*, *>
                        val spellings = (payload?.get("spellings") as? List<*>)
                            ?.mapNotNull { it as? String } ?: emptyList()
                        // 遍历并读取 MP3 文件头属于磁盘 I/O，放到后台后再回传二元组。
                        runIoCall(result, "AUDIO_CACHE_ERROR") {
                            val progress = wordAudioPlayer.getCacheProgress(spellings)
                            mapOf(
                                "cached" to progress.first,
                                "total" to progress.second,
                            )
                        }
                    }

                    // 清空全部离线语音缓存文件：删除 word_audio 目录（美式/英式子目录与 mp3）。
                    // 由"清空数据"入口调用，确保删除本地单词时一并移除已下载的音频。
                    "clearAudioCache" -> {
                        // 递归删除目录放入 I/O 队列，避免大缓存目录让 Flutter 丢帧。
                        runIoCall(result, "AUDIO_CACHE_ERROR") {
                            // 只有原生确认目录已经删除，Dart 才会把进度显示为 0%。
                            wordAudioPlayer.clearAudioCache()
                            // EventSink 属于长期 Dart 订阅，清空后仍需保留供下一批复用。
                            true
                        }
                    }

                    // 显示或刷新锁屏/通知栏的媒体控制卡片（标题=拼写，副标题=首条释义）。
                    "mediaSessionShow" -> {
                        // 参数必须是 Dart 传来的拼写、副标题与播放状态 Map。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("mediaSessionShow 缺少参数")
                        // 读取单词拼写（通知标题）。
                        val spelling = payload["spelling"] as? String ?: ""
                        // 读取首条释义（通知副标题）。
                        val subtitle = payload["subtitle"] as? String ?: ""
                        // 读取当前是否正在播放，决定是否显示播放/暂停图标。
                        val isPlaying = payload["isPlaying"] as? Boolean ?: false
                        // 交给媒体服务创建/刷新 Android MediaSession 与通知。
                        wordAudioPlayer.showMediaSession(spelling, subtitle, isPlaying)
                        // 该方法异步驱动 UI，立即返回成功。
                        result.success(null)
                    }

                    // 仅切换播放/暂停状态（通常与 mediaSessionShow 合并调用，此处单独兜底）。
                    "mediaSessionSetPlaying" -> {
                        // 参数只需一个布尔播放状态。
                        val payload = call.arguments as? Map<*, *>
                        // 缺省为未播放，避免空参数导致通知状态错乱。
                        val isPlaying = payload?.get("isPlaying") as? Boolean ?: false
                        // 只更新播放状态与通知图标，不重建元数据。
                        wordAudioPlayer.setMediaPlaying(isPlaying)
                        // 立即返回成功。
                        result.success(null)
                    }

                    // 收起媒体控制并停用会话（页面退出或停止时调用）。
                    "mediaSessionRelease" -> {
                        // 移除通知并释放媒体会话资源。
                        wordAudioPlayer.releaseMediaSession()
                        // 立即返回成功。
                        result.success(null)
                    }

                    // 未登记方法按 Flutter 规范返回 notImplemented。
                    else -> result.notImplemented()
                }
            }

        // 注册离线预缓存进度事件通道：Dart 订阅后拿到 EventSink，Kotlin 在缓存
        // 过程中持续向其 success(...) 推送进度。只要 Dart 端保持订阅，即使抽屉
        // 被关闭、用户回到首页，进度仍会回流到全局缓存服务，重新打开即见最新百分比。
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, audioCacheChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                // Dart 调用 receiveBroadcastStream 时触发，保存接收器备用。
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    audioCacheSink = events
                }

                // Dart 端取消订阅（本 App 长期持有，一般不触发）时清空接收器。
                override fun onCancel(arguments: Any?) {
                    audioCacheSink = null
                }
            })

        // 注册文件通道：导入时选 JSON、导出时写文件，全部走系统 SAF 选择器。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fileIoChannelName)
            // 根据方法名路由到「打开」或「保存」系统选择器。
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 导入：打开系统文件选择器，只显示 JSON。
                    "pickJsonText" -> {
                        // 同一时刻只允许一个文件操作，避免覆盖上一次未完成的结果。
                        if (pendingFileResult != null) {
                            result.error("FILE_BUSY", "上一次文件操作尚未完成", null)
                            return@setMethodCallHandler
                        }
                        // 构造 ACTION_OPEN_DOCUMENT：只列出可打开的 JSON 文件。
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            // CATEGORY_OPENABLE 表示必须是可读的持久化文档。
                            addCategory(Intent.CATEGORY_OPENABLE)
                            // MIME 类型限定 JSON，系统选择器会自动按扩展名过滤。
                            type = "application/json"
                        }
                        // 记录等待中的 Dart 调用与本次动作类型。
                        pendingFileResult = result
                        pendingFileAction = "pick"
                        // 真正调起系统选择器；结果会在 onActivityResult 回调。
                        startActivityForResult(intent, REQUEST_CODE_FILE_IO)
                    }

                    // 导出：打开系统保存框，由用户选择位置并确认文件名。
                    "writeExportJson" -> {
                        // 参数必须是带 fileName 与 jsonText 的 Map。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("writeExportJson 缺少参数")
                        // 预填文件名，例如 MyEnglish-2026-07-28.json。
                        val fileName = payload["fileName"] as? String
                            ?: error("writeExportJson 缺少 fileName")
                        // 要落盘的 JSON 文本。
                        val jsonText = payload["jsonText"] as? String
                            ?: error("writeExportJson 缺少 jsonText")
                        // 同样保证同一时刻只有一个文件操作。
                        if (pendingFileResult != null) {
                            result.error("FILE_BUSY", "上一次文件操作尚未完成", null)
                            return@setMethodCallHandler
                        }
                        // 构造 ACTION_CREATE_DOCUMENT：让用户选位置并保存。
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/json"
                            // EXTRA_TITLE 作为系统保存框默认文件名。
                            putExtra(Intent.EXTRA_TITLE, fileName)
                        }
                        // 记录等待中的 Dart 调用、动作类型与待写内容。
                        pendingFileResult = result
                        pendingFileAction = "write"
                        pendingExportText = jsonText
                        pendingExportName = fileName
                        // 调起系统保存框，结果在 onActivityResult 回调。
                        startActivityForResult(intent, REQUEST_CODE_FILE_IO)
                    }

                        // 未登记方法按 Flutter 规范返回 notImplemented。
                        else -> result.notImplemented()
                }
            }
    }

    /** 引擎与 Activity 解绑时清空进度接收器，避免向已销毁的引擎投递事件。 */
    override fun cleanUpFlutterEngine(engine: FlutterEngine) {
        // 先关闭异步结果出口，排队中的后台动作完成后将静默丢弃回调。
        acceptsChannelResults = false
        // 置空接收器，后续任何后台回调都不会再向它 success，杜绝悬空引用崩溃。
        audioCacheSink = null
        // 走父类标准清理流程。
        super.cleanUpFlutterEngine(engine)
    }

    /** 把数据库动作放入单线程队列，并把结果安全送回 Android 主线程。 */
    private fun runDatabaseCall(result: MethodChannel.Result, action: () -> Any?) {
        // 复用统一后台桥接，仅替换执行器和业务错误码。
        runBackgroundCall(databaseExecutor, result, "WORD_DATABASE_ERROR", action)
    }

    /**
     * 从 MethodChannel 参数中读取一个「模块标识」字符串。
     *
     * 复习模块的多个方法只需要这一个参数，抽出来避免重复的空值判断。
     *
     * @param arguments Dart 传来的原始参数，应为 {module: "..."} 形态。
     * @param method 方法名，仅用于拼出可读的错误信息。
     * @return 去掉首尾空格后的非空模块标识。
     */
    private fun readModule(arguments: Any?, method: String): String {
        // as? 相当于 PHP 的 instanceof 判断，类型不符时得到 null 而不是崩溃。
        val payload = arguments as? Map<*, *> ?: error("$method 缺少参数")
        return payload["module"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
            ?: error("$method 缺少有效 module")
    }

    /**
     * 把 MethodChannel 传来的动态数组收窄成 Long 列表。
     *
     * Dart 的 int 过通道后可能是 Int 也可能是 Long，统一按 Number 读取；
     * 只要有一项不是数字就整体报错，绝不静默丢弃单词。
     *
     * @param value Dart 传来的原始数组。
     * @param field 字段名，仅用于拼出可读的错误信息。
     * @return 全部转换成功的单词主键列表。
     */
    private fun readLongList(value: Any?, field: String): List<Long> {
        val list = value as? List<*> ?: error("$field 必须是数组")
        return list.map { item ->
            (item as? Number)?.toLong() ?: error("$field 必须全部是数字")
        }
    }

    /** 把普通磁盘动作放入独立单线程队列，并把结果安全送回 Android 主线程。 */
    private fun runIoCall(
        result: MethodChannel.Result,
        errorCode: String,
        action: () -> Any?,
    ) {
        // 缓存、设置和 SAF 文件共用顺序 I/O 队列，但不会阻塞 SQLite 事务。
        runBackgroundCall(ioExecutor, result, errorCode, action)
    }

    /** 统一执行后台动作，确保 MethodChannel 结果只在仍存活的主线程返回。 */
    private fun runBackgroundCall(
        executor: ExecutorService,
        result: MethodChannel.Result,
        errorCode: String,
        action: () -> Any?,
    ) {
        try {
            // executor.execute 类似把耗时任务投递到后台 worker。
            executor.execute {
                try {
                    // 在指定后台线程执行真正动作。
                    val value = action()
                    // MethodChannel 结果回到主线程发送，保持 Android UI 调用约定。
                    postChannelResult { result.success(value) }
                } catch (exception: Throwable) {
                    // 将原生异常转换成 Dart 可捕获的 PlatformException。
                    postChannelResult {
                        // errorCode 让 Dart UI 可以区分数据库、文件或缓存错误。
                        result.error(
                            errorCode,
                            // 优先返回具体异常信息，没有信息时返回类名。
                            exception.message ?: exception.javaClass.simpleName,
                            // 当前不把原生堆栈发送到业务层。
                            null,
                        )
                    }
                }
            }
        } catch (exception: RejectedExecutionException) {
            // Activity 销毁期间执行器可能已经关闭；只在页面仍存活时返回明确错误。
            postChannelResult {
                result.error(errorCode, "后台执行器已关闭", null)
            }
        }
    }

    /** 在 Activity 仍存活时把一次通道结果切回主线程。 */
    private fun postChannelResult(callback: () -> Unit) {
        // 已销毁的 FlutterEngine 没有合法接收端，此时丢弃回调比触发悬空调用更安全。
        if (isDestroyed || !acceptsChannelResults) return
        runOnUiThread {
            // 排队期间 Activity 也可能被关闭，因此发送前再次检查。
            if (!isDestroyed && acceptsChannelResults) callback()
        }
    }

    /** 系统选择器关闭后的统一回调：根据本次动作读取或写入 Uri。 */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // 先走父类标准流程，避免影响 Flutter 自身的结果分发。
        super.onActivityResult(requestCode, resultCode, data)
        // 只处理我们自己的文件请求；其它请求码交给父类。
        if (requestCode != REQUEST_CODE_FILE_IO) return
        // 委托给统一处理器。
        handleFileIoResult(resultCode, data)
    }

    /** 系统选择器关闭后的统一处理：根据本次动作读取或写入 Uri。 */
    private fun handleFileIoResult(resultCode: Int, data: Intent?) {
        // 先取出并清空 pending，避免重复回调或后续结果串场。
        val pending = pendingFileResult ?: return
        val action = pendingFileAction
        pendingFileResult = null
        pendingFileAction = null
        val exportText = pendingExportText
        pendingExportText = null
        pendingExportName = null

        // 读取选择器返回的数据与 Uri。
        val uri: Uri? = data?.data

        when (action) {
            // 选文件：用户确认且有 Uri 才读取文本。
            "pick" -> {
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    // 取消或异常都返回 null，Dart 据此不做任何改动。
                    pending.success(null)
                    return
                }
                // 大文件读取放入 I/O 队列，完成后由统一桥接回到主线程。
                runIoCall(pending, "FILE_IO_ERROR") { readUriText(uri) }
            }
            // 写文件：用户确认且有 Uri 才落盘。
            "write" -> {
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    // 取消保存返回 null，Dart 据此不提示。
                    pending.success(null)
                    return
                }
                // 大文件写入放入 I/O 队列，完成后返回真实保存位置供 Dart 提示。
                runIoCall(pending, "FILE_IO_ERROR") {
                    writeUriText(uri, exportText ?: "")
                    uri.toString()
                }
            }
            // 未知动作直接返回 null，不抛异常。
            else -> pending.success(null)
        }
    }

    /** 读取 SAF 返回的 Uri 文本，统一按 UTF-8 解码，类似 PHP file_get_contents。 */
    private fun readUriText(uri: Uri): String {
        // contentResolver 类似系统文件管理器，负责按 Uri 打开输入流。
        val resolver = applicationContext.contentResolver
        // use 类似 PHP 的 try/finally，离开作用域自动关闭流。
        resolver.openInputStream(uri)?.use { stream ->
            BufferedReader(InputStreamReader(stream, StandardCharsets.UTF_8)).use { reader ->
                // 非局部返回：直接把整段文本作为 readUriText 的返回值。
                return reader.readText()
            }
        }
        // 拿不到输入流说明 Uri 不可用。
        throw IOException("无法打开文件输入流：$uri")
    }

    /** 把文本写入 SAF 返回的 Uri，类似 PHP file_put_contents。 */
    private fun writeUriText(uri: Uri, text: String) {
        // contentResolver 负责按 Uri 打开输出流落盘。
        val resolver = applicationContext.contentResolver
        resolver.openOutputStream(uri)?.use { stream ->
            OutputStreamWriter(stream, StandardCharsets.UTF_8).use { writer ->
                // 写入全部 JSON 文本。
                writer.write(text)
            }
            // 写成功后直接结束方法。
            return
        }
        // 拿不到输出流说明 Uri 不可写。
        throw IOException("无法打开文件输出流：$uri")
    }

    // Activity 销毁时释放数据库和线程资源，对应小程序 onUnload 的清理阶段。
    override fun onDestroy() {
        // 系统文件选择器尚未返回时，先把对应 Dart Future 结束为“用户取消”。
        // 这样 Activity 因系统回收或厂商行为被销毁后，导入/导出页面不会永久等待。
        pendingFileResult?.success(null)
        // 清空整组临时状态，避免 Activity 销毁后继续持有大段导出 JSON 文本。
        pendingFileResult = null
        pendingFileAction = null
        pendingExportText = null
        pendingExportName = null
        // Activity 销毁后禁止任何后台任务再回传到 FlutterEngine。
        acceptsChannelResults = false
        // 先停止下载回调并释放 MediaPlayer。
        if (::wordAudioPlayer.isInitialized) wordAudioPlayer.dispose()
        // 先关闭 SQLite 连接。
        if (::wordsDatabase.isInitialized) wordsDatabase.close()
        // 停止后台执行器，不再接收新任务。
        databaseExecutor.shutdown()
        // 同时停止普通文件 I/O 队列。
        ioExecutor.shutdown()
        // 最后执行 FlutterActivity 自己的销毁流程。
        super.onDestroy()
    }
}
