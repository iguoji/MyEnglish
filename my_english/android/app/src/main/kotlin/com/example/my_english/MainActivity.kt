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
// Executors 提供单独数据库线程，避免 SQLite 和 JSON 导入阻塞 Flutter UI。
import java.util.concurrent.Executors

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
 * JSON 是否存在由 Dart Store 先判断；只有没有 JSON 时，Dart 才通过 MethodChannel
 * 调用这里访问 SQLite。所有数据库工作都在单线程队列中顺序执行，不阻塞 Android 主线程。
 */
class MainActivity : FlutterActivity() {
    // 通道名相当于接口路由，必须与 Dart LocalWordStore 中的字符串完全一致。
    private val channelName = "my_english/word_store"

    // 设置通道负责 SharedPreferences 读取和写入。
    private val settingsChannelName = "my_english/settings"

    // 音频通道负责缓存、双来源下载和 MediaPlayer 播放。
    private val audioChannelName = "my_english/word_audio"

    // 离线预缓存进度事件通道：Kotlin 在后台批量缓存时持续推送 {cached,total,done}。
    private val audioCacheChannelName = "my_english/audio_cache"

    // 当前 Dart 端对进度流的订阅接收器；null 表示还没有任何页面在监听。
    private var audioCacheSink: EventChannel.EventSink? = null

    // 文件通道负责 SAF 选 JSON 与导出写文件，与 word_store 同风格的原生桥接。
    private val fileIoChannelName = "my_english/file_io"

    // 单线程执行器保证导入、读取、写入不会并发破坏事务顺序。
    private val databaseExecutor = Executors.newSingleThreadExecutor()

    // lateinit 表示 Activity 创建后再初始化，类似 PHP 类中稍后注入 Store 属性。
    private lateinit var wordsDatabase: WordsDatabase

    // 原生设置 Store 与 Dart SettingsStore 一一对应。
    private lateinit var appSettingsStore: AppSettingsStore

    // 原生音频服务可以跨 Flutter Widget 重建持续工作。
    private lateinit var wordAudioPlayer: WordAudioPlayer

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
        // 创建 SQLite helper；applicationContext 可避免持有 Activity 导致内存泄漏。
        wordsDatabase = WordsDatabase(applicationContext)
        // 创建 App 私有设置 Store。
        appSettingsStore = AppSettingsStore(applicationContext)
        // 创建下载与播放服务。
        wordAudioPlayer = WordAudioPlayer(applicationContext)

        // 在当前 FlutterEngine 上注册 Dart ↔ Android 方法通道。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            // 每次 Dart invokeMethod 都会进入这个处理器。
            .setMethodCallHandler { call, result ->
                // when 类似 PHP 8 match，根据方法名路由到不同数据库操作。
                when (call.method) {
                    // Dart 已确认 JSON 不存在后，才会调用这里读取全部 SQLite Word/Meaning。
                    "getAllWords" -> runDatabaseCall(result) {
                        // 只查询 SQLite，不读取 JSON，也不会执行任何导入或写入。
                        wordsDatabase.getAllWords()
                    }

                    // 为未来新增单词页面预留创建接口。
                    "createWord" -> runDatabaseCall(result) {
                        // arguments 对应 Dart 传来的 Map；类型不符时主动抛出清晰错误。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("createWord 缺少单词参数")
                        // 在事务内创建 Word 和 Meanings，并返回自增主键。
                        wordsDatabase.createWord(payload)
                    }

                    // 为未来编辑页面预留更新接口。
                    "updateWord" -> runDatabaseCall(result) {
                        // 读取 Dart Word.toMap 生成的数据。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("updateWord 缺少单词参数")
                        // 更新完成后返回 null，对应 Dart Future<void>。
                        wordsDatabase.updateWord(payload)
                        null
                    }

                    // 为未来删除操作预留软删除接口。
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

                    // 清空全部单词与释义，对应「清空数据」入口。
                    "clearAllWords" -> runDatabaseCall(result) {
                        // 删除四张表全部记录（含分组与成员）。
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

                    // 导入完整备份（含 groups/words/members）。
                    "importData" -> runDatabaseCall(result) {
                        // 参数必须是 Dart 传来的完整备份 Map。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("importData 缺少备份数据")
                        // 在事务内重建四张表，返回 null 对应 Dart Future<void>。
                        wordsDatabase.importData(payload)
                        null
                    }

                    // 记录一次单词默写结果并在事务内更新难度与复习时间（每次都插一条）。
                    "addDictationRecord" -> runDatabaseCall(result) {
                        // 读取 Dart 传来的本次默写结果。
                        val payload = call.arguments as? Map<*, *>
                            ?: error("addDictationRecord 缺少参数")
                        // 单词主键必须为数字。
                        val wordId = (payload["wordId"] as? Number)?.toLong()
                            ?: error("addDictationRecord 缺少有效 wordId")
                        // 是否最终全对（布尔）。
                        val isCorrect = payload["isCorrect"] as? Boolean
                            ?: error("addDictationRecord 缺少 isCorrect")
                        // 错误次数与提示次数缺省为 0。
                        val wrongCount = (payload["wrongCount"] as? Number)?.toInt() ?: 0
                        val hintCount = (payload["hintCount"] as? Number)?.toInt() ?: 0
                        // 写入记录并刷新难度，返回 null 对应 Dart Future<void>。
                        wordsDatabase.addDictationRecord(wordId, isCorrect, wrongCount, hintCount)
                        null
                    }

                    // 读取今日全部默写记录，供"今日复习"明细展示。
                    "getTodayReviewWords" -> runDatabaseCall(result) {
                        // 直接返回今日记录列表，Dart RecordStore 负责解析。
                        wordsDatabase.getTodayReviewWords()
                    }

                    // 今日复习数量：按天 + 按单词去重汇总，供首页副标题直接使用。
                    "getTodayReviewWordCount" -> runDatabaseCall(result) {
                        // 原生用 COUNT(DISTINCT word_id) 聚合，避免把整天记录搬到 Dart 再去重。
                        wordsDatabase.getTodayReviewWordCount()
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

        // 注册全局设置通道；读取发生在 Dart runApp 之前。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, settingsChannelName)
            // 根据方法名读取或写入两个设置字段。
            .setMethodCallHandler { call, result ->
                try {
                    // when 类似 PHP match。
                    when (call.method) {
                        // 返回当前口音和主题快照。
                        "getSettings" -> result.success(appSettingsStore.getSettings())

                        // 保存新的口音字符串。
                        "setAccent" -> {
                            // 参数必须是 Dart 传来的 String。
                            val value = call.arguments as? String
                                ?: error("setAccent 缺少字符串参数")
                            // Store 内部继续校验允许值并同步持久化。
                            appSettingsStore.setAccent(value)
                            // void 方法使用 null 表示成功。
                            result.success(null)
                        }

                        // 保存新的主题字符串。
                        "setTheme" -> {
                            // 参数必须是 Dart 传来的 String。
                            val value = call.arguments as? String
                                ?: error("setTheme 缺少字符串参数")
                            // Store 内部继续校验允许值并同步持久化。
                            appSettingsStore.setTheme(value)
                            // 通知 Dart 持久化完成。
                            result.success(null)
                        }

                        // 保存新的中文释义分隔符。
                        "setDefinitionSeparator" -> {
                            // 参数必须是 Dart 枚举转换后的稳定字符串。
                            val value = call.arguments as? String
                                ?: error("setDefinitionSeparator 缺少字符串参数")
                            // Store 继续校验值是否属于顿号、逗号或分号三者之一。
                            appSettingsStore.setDefinitionSeparator(value)
                        // 通知 Dart 持久化完成，可以刷新全部中文释义。
                        result.success(null)
                    }

                    // 清空全部设置，恢复到首次安装默认值。
                    "clearAllSettings" -> {
                        // 删除 SharedPreferences 中的全部键值。
                        appSettingsStore.clearAll()
                        // 通知 Dart 清空完成，可以刷新主题与口音。
                        result.success(null)
                    }

                    // 未登记方法按 Flutter 规范返回 notImplemented。
                    else -> result.notImplemented()
                    }
                } catch (exception: Throwable) {
                    // 参数或磁盘错误返回 Dart，设置面板会显示 SnackBar。
                    result.error(
                        "SETTINGS_ERROR",
                        exception.message ?: exception.javaClass.simpleName,
                        null,
                    )
                }
            }

        // 注册音频通道；play 的 result 会由 WordAudioPlayer 在播放完成时返回。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioChannelName)
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
                        wordAudioPlayer.precacheAll(spellings) { cached, total, done ->
                            // 没有订阅者（页面未打开抽屉）时静默丢弃，不报错。
                            audioCacheSink?.success(
                                mapOf(
                                    "cached" to cached,
                                    "total" to total,
                                    "done" to done,
                                ),
                            )
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
                        // 返回 {cached, total} 二元组供 Dart 计算百分比。
                        val progress = wordAudioPlayer.getCacheProgress(spellings)
                        result.success(
                            mapOf(
                                "cached" to progress.first,
                                "total" to progress.second,
                            ),
                        )
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

    /** 把数据库动作放入单线程队列，并把结果安全送回 Android 主线程。 */
    private fun runDatabaseCall(result: MethodChannel.Result, action: () -> Any?) {
        // executor.execute 类似把耗时任务投递到后台 worker。
        databaseExecutor.execute {
            try {
                // 在数据库线程执行真正动作。
                val value = action()
                // MethodChannel 结果回到主线程发送，保持 Android UI 调用约定。
                runOnUiThread { result.success(value) }
            } catch (exception: Throwable) {
                // 将原生异常转换成 Dart 可捕获的 PlatformException。
                runOnUiThread {
                    // errorCode 便于未来在 Dart UI 中区分本地数据错误。
                    result.error(
                        "WORD_DATABASE_ERROR",
                        // 优先返回具体异常信息，没有信息时返回类名。
                        exception.message ?: exception.javaClass.simpleName,
                        // 当前不把原生堆栈发送到业务层。
                        null,
                    )
                }
            }
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

        try {
            when (action) {
                // 选文件：用户确认且有 Uri 才读取文本。
                "pick" -> {
                    if (resultCode != Activity.RESULT_OK || uri == null) {
                        // 取消或异常都返回 null，Dart 据此不做任何改动。
                        pending.success(null)
                        return
                    }
                    // 把 Uri 内容读成 UTF-8 文本回传 Dart。
                    pending.success(readUriText(uri))
                }
                // 写文件：用户确认且有 Uri 才落盘。
                "write" -> {
                    if (resultCode != Activity.RESULT_OK || uri == null) {
                        // 取消保存返回 null，Dart 据此不提示。
                        pending.success(null)
                        return
                    }
                    // 把暂存的 JSON 文本写入 Uri。
                    writeUriText(uri, exportText ?: "")
                    // 返回真实保存位置（Uri 字符串）供 Dart 提示。
                    pending.success(uri.toString())
                }
                // 未知动作直接返回 null，不抛异常。
                else -> pending.success(null)
            }
        } catch (exception: Throwable) {
            // 读取或写入失败，转换成 Dart 可捕获的 PlatformException。
            pending.error(
                "FILE_IO_ERROR",
                exception.message ?: exception.javaClass.simpleName,
                null,
            )
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
        // 先停止下载回调并释放 MediaPlayer。
        if (::wordAudioPlayer.isInitialized) wordAudioPlayer.dispose()
        // 先关闭 SQLite 连接。
        if (::wordsDatabase.isInitialized) wordsDatabase.close()
        // 停止后台执行器，不再接收新任务。
        databaseExecutor.shutdown()
        // 最后执行 FlutterActivity 自己的销毁流程。
        super.onDestroy()
    }
}
