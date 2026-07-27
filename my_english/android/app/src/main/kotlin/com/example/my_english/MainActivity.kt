// package 相当于 PHP namespace，必须与 Android application namespace 对应。
package com.example.my_english

// FlutterActivity 是 Android 承载 Flutter 页面所需的原生 Activity 基类。
import io.flutter.embedding.android.FlutterActivity
// FlutterEngine 提供 Dart 与 Android 原生层之间的运行引擎。
import io.flutter.embedding.engine.FlutterEngine
// MethodChannel 类似小程序 JS 调用原生插件时使用的桥接 API。
import io.flutter.plugin.common.MethodChannel
// Executors 提供单独数据库线程，避免 SQLite 和 JSON 导入阻塞 Flutter UI。
import java.util.concurrent.Executors

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

    // 单线程执行器保证导入、读取、写入不会并发破坏事务顺序。
    private val databaseExecutor = Executors.newSingleThreadExecutor()

    // lateinit 表示 Activity 创建后再初始化，类似 PHP 类中稍后注入 Store 属性。
    private lateinit var wordsDatabase: WordsDatabase

    // 原生设置 Store 与 Dart SettingsStore 一一对应。
    private lateinit var appSettingsStore: AppSettingsStore

    // 原生音频服务可以跨 Flutter Widget 重建持续工作。
    private lateinit var wordAudioPlayer: WordAudioPlayer

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
