// package 与播放器一致，渠道实现与播放器同属一层。
package com.example.my_english

// Context 用于取 SharedPreferences，持久化 device_id 与游客 token。
import android.content.Context

// SharedPreferences 保存 token 及其签发时间，跨进程重启后不必重新登录。
import android.content.SharedPreferences

// ByteArrayOutputStream 累积 Thrift 请求体。
import java.io.ByteArrayOutputStream

// HttpURLConnection 发 POST；接口是自研 HTTP 传输，不用 Retrofit。
import java.net.HttpURLConnection

// URL 拼装请求地址。
import java.net.URL

// SimpleDateFormat 生成 Cookie 里的 serial（ddHHmmss）。
import java.text.SimpleDateFormat

// Date 配合 SimpleDateFormat 取当前时间。
import java.util.Date

// Locale 固定序列化格式，避免系统语言影响数字与日期。
import java.util.Locale

// Random 生成 16 位 hex 设备号。
import kotlin.random.Random

/**
 * 百词斩发音渠道（接口调用型）。
 *
 * 取音分三步，全部在本类内部完成，播放器只看到 [audioUrl]：
 * 1. 用固定的 device_id 领游客 token（免注册），token 缓存 12 小时；
 * 2. 调 `get_dict_by_word_v2` 查词，拿接口下发的音频相对路径；
 * 3. 拼 CDN 前缀并做 percent-encode，得到可直接下载的 MP3 地址。
 *
 * 协议要点（逆向自 1.5.6，详见 memory/百词斩）：
 * - POST，body = 4 字节大端帧长 + TCompactProtocol 消息；
 * - 响应同样带帧头，解析前先剥掉；
 * - 业务错误也返回 HTTP 200，靠 bomb/boom 结构里的 code 区分；
 * - 音频文件名毫无规律，只能读接口下发的 URI，不能自己拼；
 * - 查询大小写敏感，星期/月份名要首字母大写，空壳词条要按未收录处理。
 *
 * 线程安全：所有接口调用串行化（预缓存四个线程会同时进来），并做最小间隔节流，
 * 避免短时间内大量请求触发风控。
 */
class BaicizhanAudioSource(
    context: Context,
    // 允许测试注入；默认用独立文件，避免和设置项混在一起。
    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE),
) : ApiAudioResolver {

    // 查询锁：token 刷新、查词、短期结果缓存都在这把锁内，天然串行。
    private val queryLock = Any()

    // 节流锁：保证两次接口请求之间至少间隔 MIN_REQUEST_INTERVAL_MILLIS。
    private val throttleLock = Any()

    // 上一次真正发出请求的时刻。
    private var lastRequestAtMillis = 0L

    // 最近查询过的单词及其结果（含“未收录”的 null），供同一词的另一个口音直接复用。
    private var lastWord: String? = null

    // 最近一次查询结果；null 表示该词未收录。
    private var lastUris: WordAudioUris? = null

    /** 一次查词拿到的美式与英式音频相对路径。 */
    private data class WordAudioUris(val usUri: String, val ukUri: String)

    /** 已登录的凭据：device_id 与 access_token 必须成对使用。 */
    private data class Credentials(val deviceId: String, val token: String)

    /** 单次查词的三种结局，区分“可重试”和“确定没有”。 */
    private sealed class DictOutcome {
        // 查到词条；meanCount 为 0 表示空壳词条，按未收录处理。
        data class Success(val uris: WordAudioUris, val meanCount: Int) : DictOutcome()

        // 业务错误，code 来自 LogicException/SystemException。
        data class Failure(val code: Int, val message: String) : DictOutcome()

        // 网络层失败，可以原地重试一次。
        object Retryable : DictOutcome()
    }

    /**
     * 解析某个单词在指定口音下的音频地址。
     *
     * 失败时抛异常，由播放器把本渠道判为本次不可用，不影响其他渠道。
     */
    override fun audioUrl(spelling: String, accent: String): String {
        // 上层已经 trim 过，这里再保险一次，避免首尾空格影响查词。
        val word = spelling.trim()
        check(word.isNotEmpty()) { "单词拼写不能为空" }
        // 同一词的两种口音只查一次接口。
        val uris = wordAudioUris(word) ?: throw IllegalStateException("百词斩未收录：$word")
        // 美式取字段 5，英式取字段 6；两者都是相对路径。
        val uri = if (accent == AMERICAN) uris.usUri else uris.ukUri
        check(uri.isNotEmpty()) { "百词斩缺少 $accent 发音：$word" }
        return cdnUrl(uri)
    }

    /**
     * 查询一个单词的音频路径，带“首字母大写重试”。
     *
     * 百词斩对星期、月份、语言名这类词条区分大小写：小写会报未收录，
     * 或返回成功但内容为空的空壳。两种都要用首字母大写再试一次。
     */
    private fun wordAudioUris(spelling: String): WordAudioUris? = synchronized(queryLock) {
        // 预缓存按“单词 → 口音 → 渠道”顺序跑，同一词的第二次口音直接命中。
        if (lastWord == spelling) return lastUris

        var uris = queryWord(spelling)
        if (uris == null) {
            val capitalized = capitalizeFirst(spelling)
            if (capitalized != spelling) {
                AppLog.i("audio", "百词斩首字母大写重试 拼写=$capitalized")
                uris = queryWord(capitalized)
            }
        }
        // 只在真正拿到音频路径时缓存：网络失败或未收录都不写，
        // 让同一词的另一个口音重新试一次，而不是直接继承一次偶发失败。
        if (uris != null) {
            lastWord = spelling
            lastUris = uris
        }
        uris
    }

    /** 查一次词，内部处理 token 失效重登与网络偶发失败重试。 */
    private fun queryWord(word: String): WordAudioUris? {
        var credentials = ensureCredentials(forceRefresh = false) ?: return null
        var outcome = queryDict(word, credentials)

        // token 过期或被服务端判未登录时，重新领一个再试一次。
        if (outcome is DictOutcome.Failure && outcome.code == ERR_NOT_LOGIN) {
            AppLog.i("audio", "百词斩 token 失效，重新领取游客 token")
            credentials = ensureCredentials(forceRefresh = true) ?: return null
            outcome = queryDict(word, credentials)
        }
        // 网络层偶发失败重试一次，避免一次超时就把整个词判死。
        if (outcome === DictOutcome.Retryable) {
            outcome = queryDict(word, credentials)
        }

        val success = outcome as? DictOutcome.Success ?: return null
        // 空壳词条：接口说成功，但没有释义也没有音频，按未收录处理。
        if (success.meanCount == 0) {
            AppLog.i("audio", "百词斩返回空壳词条 拼写=$word")
            return null
        }
        return success.uris
    }

    /**
     * 取可用凭据：优先用 12 小时内的缓存 token，过期或强制刷新时重新领游客 token。
     *
     * device_id 必须持久化：服务端把 token 和设备绑定，换设备号就要重新登录。
     */
    private fun ensureCredentials(forceRefresh: Boolean): Credentials? {
        val now = System.currentTimeMillis()
        // device_id 一次生成、长期复用。
        val deviceId = prefs.getString(KEY_DEVICE_ID, null) ?: newDeviceId().also { fresh ->
            prefs.edit().putString(KEY_DEVICE_ID, fresh).apply()
        }
        if (!forceRefresh) {
            val token = prefs.getString(KEY_TOKEN, null)
            val issuedAt = prefs.getLong(KEY_TOKEN_AT, 0L)
            val valid = !token.isNullOrEmpty() &&
                now >= issuedAt &&
                now - issuedAt < TOKEN_TTL_MILLIS
            if (valid) return Credentials(deviceId, token)
        }
        val fresh = login(deviceId) ?: return null
        prefs.edit()
            .putString(KEY_TOKEN, fresh)
            .putLong(KEY_TOKEN_AT, now)
            .apply()
        return Credentials(deviceId, fresh)
    }

    /** 领游客 token：passport 的 have_a_try_v2，无参数。 */
    private fun login(deviceId: String): String? {
        val writer = ThriftWriter()
        writer.messageBegin("have_a_try_v2")
        writer.structBegin()
        writer.fieldStop()
        writer.structEnd()
        val url = "$PASSPORT_HOST$USER_PATH/have_a_try_v2/${System.currentTimeMillis()}"
        val raw = post(url, writer.framed(), deviceId, null) ?: return null
        return try {
            val reader = ThriftReader(deframe(raw))
            reader.messageBegin()
            // result 结构：字段 0 是 UserTryResult{1: username, 2: token}。
            val token = reader.readStruct().struct(0)?.string(2).orEmpty()
            AppLog.i("audio", "百词斩游客 token 领取${if (token.isEmpty()) "失败" else "成功"}")
            token.takeIf { it.isNotEmpty() }
        } catch (error: Throwable) {
            AppLog.e("audio", "百词斩 token 响应解析失败：${error.message ?: error.javaClass.simpleName}")
            null
        }
    }

    /** 调 get_dict_by_word_v2 查词。 */
    private fun queryDict(word: String, credentials: Credentials): DictOutcome {
        val writer = ThriftWriter()
        writer.messageBegin("get_dict_by_word_v2")
        writer.structBegin()
        writer.stringField(1, word)
        writer.fieldStop()
        writer.structEnd()
        val url = "$API_HOST$RESOURCE_PATH/get_dict_by_word_v2/${System.currentTimeMillis()}"
        val raw = post(url, writer.framed(), credentials.deviceId, credentials.token)
            ?: return DictOutcome.Retryable

        return try {
            val reader = ThriftReader(deframe(raw))
            reader.messageBegin()
            // result 结构：0=success，1=bomb(LogicException)，2=boom(SystemException)。
            val result = reader.readStruct()
            val success = result.struct(0)
            if (success != null) {
                // word_basic_info 是字段 1，音频在它的第 5、6 个字段。
                val basic = success.struct(1)
                val uris = WordAudioUris(
                    usUri = basic?.string(5).orEmpty(),
                    ukUri = basic?.string(6).orEmpty(),
                )
                // chn_means 是字段 2；数量为 0 说明是空壳词条。
                val meanCount = (success.value(2) as? List<*>)?.size ?: 0
                return DictOutcome.Success(uris, meanCount)
            }
            val exception = result.struct(1) ?: result.struct(2)
            val code = (exception?.value(3) as? Int) ?: -1
            val message = exception?.string(4).orEmpty()
            if (code != ERR_NOT_FOUND) {
                AppLog.e("audio", "百词斩查词失败 拼写=$word code=$code message=$message")
            }
            DictOutcome.Failure(code, message)
        } catch (error: Throwable) {
            AppLog.e("audio", "百词斩响应解析失败：${error.message ?: error.javaClass.simpleName}")
            DictOutcome.Retryable
        }
    }

    /** 发一次 POST：body 已带 4 字节帧头，返回原始响应体（同样带帧头）。 */
    private fun post(
        url: String,
        body: ByteArray,
        deviceId: String,
        token: String?,
    ): ByteArray? {
        // 串行节流：预缓存四个线程同时进来时，避免瞬间打出一串请求。
        throttle()
        return try {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.connectTimeout = CONNECT_TIMEOUT_MILLIS
            connection.readTimeout = READ_TIMEOUT_MILLIS
            connection.doOutput = true
            connection.setRequestProperty("Accept", "application/x-thrift")
            connection.setRequestProperty("Content-Type", "application/x-thrift")
            connection.setRequestProperty("User-Agent", USER_AGENT)
            connection.setRequestProperty("Cookie", cookie(deviceId, token))
            connection.outputStream.use { it.write(body) }
            val status = connection.responseCode
            if (status != HttpURLConnection.HTTP_OK) {
                AppLog.e("audio", "百词斩接口 HTTP $status url=$url")
                return null
            }
            connection.inputStream.use { it.readBytes() }
        } catch (error: Throwable) {
            AppLog.e("audio", "百词斩接口请求失败：${error.message ?: error.javaClass.simpleName}")
            null
        }
    }

    /** 保证两次请求之间有最小间隔，降低被风控的概率。 */
    private fun throttle() {
        synchronized(throttleLock) {
            val wait = MIN_REQUEST_INTERVAL_MILLIS -
                (System.currentTimeMillis() - lastRequestAtMillis)
            if (wait > 0) {
                try {
                    Thread.sleep(wait)
                } catch (_: InterruptedException) {
                    // 线程被中断（预缓存批次取消）时不再等待，由调用方继续走失败分支。
                    Thread.currentThread().interrupt()
                }
            }
            lastRequestAtMillis = System.currentTimeMillis()
        }
    }

    /** 拼 Cookie；格式与官方客户端一致，token 为空时不带 access_token。 */
    private fun cookie(deviceId: String, token: String?): String {
        val items = mutableListOf(
            "device_name" to "android/Pixel6Pro",
            "version" to APP_VERSION,
            "os_version" to OS_VERSION,
            "app_name" to "1",
            "channel" to "official",
            "client_time" to (System.currentTimeMillis() / 1000).toString(),
            "device_id" to deviceId,
            "serial" to serial(deviceId),
            "time_zone" to "Asia/Shanghai",
        )
        if (!token.isNullOrEmpty()) items += "access_token" to token
        return items.joinToString("; ") { "${it.first}=${it.second}" }
    }

    /** serial = device_id 前 5 位 + 后 5 位 + ddHHmmss。 */
    private fun serial(deviceId: String): String {
        val stamp = SimpleDateFormat("ddHHmmss", Locale.US).format(Date())
        return deviceId.take(5) + deviceId.takeLast(5) + stamp
    }

    /** 16 位 hex 设备号。 */
    private fun newDeviceId(): String = buildString {
        repeat(16) { append(HEX_DIGITS[Random.nextInt(HEX_DIGITS.length)]) }
    }

    /** 首字母转大写；已经是首字母大写的词原样返回，避免无意义重试。 */
    private fun capitalizeFirst(word: String): String {
        if (word.isEmpty()) return word
        val first = word[0]
        if (!first.isLowerCase()) return word
        return first.titlecaseChar() + word.substring(1)
    }

    /** 把接口下发的相对路径变成 CDN 上的完整地址。 */
    private fun cdnUrl(uri: String): String {
        // 少数词条直接下发绝对地址，原样返回。
        if (uri.startsWith("http://") || uri.startsWith("https://")) return uri
        return CDN_BASE + encodePath(uri)
    }

    /**
     * 路径 percent-encode，保留 `/`。
     *
     * 接口偶尔下发带原始空格的文件名（例如 `/r/air conditioner.mp3`），
     * 不编码会 404；编码后 `/r/air%20conditioner.mp3` 可正常下载。
     */
    private fun encodePath(path: String): String {
        val builder = StringBuilder()
        for (byte in path.toByteArray(Charsets.UTF_8)) {
            val value = byte.toInt() and 0xFF
            val char = value.toChar()
            val safe = char in 'A'..'Z' || char in 'a'..'z' || char in '0'..'9' ||
                char == '/' || char == '-' || char == '_' || char == '.' || char == '~'
            if (safe) {
                builder.append(char)
            } else {
                builder.append('%')
                builder.append(HEX_DIGITS[value ushr 4])
                builder.append(HEX_DIGITS[value and 0x0F])
            }
        }
        return builder.toString()
    }

    /** 剥掉响应体前 4 字节的大端帧长。 */
    private fun deframe(raw: ByteArray): ByteArray {
        if (raw.size < 4) return raw
        val length = ((raw[0].toInt() and 0xFF) shl 24) or
            ((raw[1].toInt() and 0xFF) shl 16) or
            ((raw[2].toInt() and 0xFF) shl 8) or
            (raw[3].toInt() and 0xFF)
        return if (length in 1..(raw.size - 4)) raw.copyOfRange(4, 4 + length) else raw
    }

    /** 一个反序列化出来的 Thrift 字段。 */
    private data class ThriftField(val id: Int, val type: Int, val value: Any?)

    /** 从字段列表里按 id 取值。 */
    private fun List<ThriftField>.value(id: Int): Any? = firstOrNull { it.id == id }?.value

    /** 按 id 取嵌套结构；不是结构时返回 null。 */
    private fun List<ThriftField>.struct(id: Int): List<ThriftField>? {
        val raw = value(id) as? List<*> ?: return null
        // 嵌套结构在读取阶段已经被解析成 ThriftField 列表。
        return raw.filterIsInstance<ThriftField>()
    }

    /** 按 id 取字符串；缺失或类型不符时返回空串。 */
    private fun List<ThriftField>.string(id: Int): String = value(id) as? String ?: ""

    /**
     * TCompactProtocol 写入器。
     *
     * 只实现本渠道需要的消息头、结构、字符串三种原语，
     * 请求体固定为 35 字节左右的模板，不需要完整 Thrift 库。
     */
    private class ThriftWriter {
        // 请求体字节流。
        private val buffer = ByteArrayOutputStream()

        // 当前结构内上一个字段 id，用于紧凑编码的增量。
        private var lastFieldId = 0

        // 嵌套结构的 lastFieldId 栈。
        private val fieldIdStack = java.util.ArrayDeque<Int>()

        /** 写消息头：0x82 | 版本与类型 | seqid | 方法名。 */
        fun messageBegin(name: String, messageType: Int = MESSAGE_TYPE_CALL) {
            buffer.write(0x82)
            buffer.write(1 or (messageType shl 5))
            writeVarint(1)
            writeString(name)
        }

        /** 进入一个结构。 */
        fun structBegin() {
            fieldIdStack.addLast(lastFieldId)
            lastFieldId = 0
        }

        /** 离开一个结构。 */
        fun structEnd() {
            lastFieldId = fieldIdStack.removeLast()
        }

        /** 写一个字符串字段。 */
        fun stringField(id: Int, value: String) {
            field(id, TYPE_STRING)
            writeString(value)
        }

        /** 结构结束标记。 */
        fun fieldStop() {
            buffer.write(0)
        }

        /** 加 4 字节大端帧长。 */
        fun framed(): ByteArray {
            val body = buffer.toByteArray()
            val framed = ByteArray(body.size + 4)
            framed[0] = ((body.size ushr 24) and 0xFF).toByte()
            framed[1] = ((body.size ushr 16) and 0xFF).toByte()
            framed[2] = ((body.size ushr 8) and 0xFF).toByte()
            framed[3] = (body.size and 0xFF).toByte()
            System.arraycopy(body, 0, framed, 4, body.size)
            return framed
        }

        /** 写字段头：增量在 1..15 时用紧凑形式，否则写完整字段 id。 */
        private fun field(id: Int, compactType: Int) {
            val delta = id - lastFieldId
            if (delta in 1..15) {
                buffer.write((delta shl 4) or compactType)
            } else {
                buffer.write(compactType)
                writeVarint(zigzag32(id))
            }
            lastFieldId = id
        }

        /** 写字符串：varint 长度 + UTF-8 字节。 */
        private fun writeString(value: String) {
            val bytes = value.toByteArray(Charsets.UTF_8)
            writeVarint(bytes.size)
            buffer.write(bytes)
        }

        /** 写无符号 varint（只用于非负值）。 */
        private fun writeVarint(value: Int) {
            var remaining = value
            while (true) {
                if (remaining and 0x7F.inv() == 0) {
                    buffer.write(remaining)
                    return
                }
                buffer.write((remaining and 0x7F) or 0x80)
                remaining = remaining ushr 7
            }
        }

        /** 32 位 zigzag。 */
        private fun zigzag32(value: Int): Int = (value shl 1) xor (value shr 31)
    }

    /**
     * TCompactProtocol 读取器。
     *
     * 完整读取响应结构：字符串、整数、列表、嵌套结构都会解析，
     * 未知类型直接抛异常，避免静默错位后拿到错误的音频地址。
     */
    private class ThriftReader(private val data: ByteArray) {
        // 当前读取位置。
        private var index = 0

        // 当前结构内上一个字段 id。
        private var lastFieldId = 0

        // 嵌套结构的 lastFieldId 栈。
        private val fieldIdStack = java.util.ArrayDeque<Int>()

        /** 读消息头：0x82 | 版本与类型 | seqid | 方法名。 */
        fun messageBegin() {
            val protocol = readByte()
            check(protocol == 0x82) { "百词斩响应协议头异常：0x${protocol.toString(16)}" }
            readByte()
            readVarint()
            readString()
        }

        /** 读一个结构，返回字段列表。 */
        fun readStruct(): List<ThriftField> {
            fieldIdStack.addLast(lastFieldId)
            lastFieldId = 0
            val fields = mutableListOf<ThriftField>()
            while (true) {
                val header = readByte()
                if (header == 0) break
                val delta = (header ushr 4) and 0x0F
                val type = header and 0x0F
                val id = if (delta == 0) unzigzag32(readVarint()) else lastFieldId + delta
                lastFieldId = id
                fields += ThriftField(id, type, readValue(type))
            }
            lastFieldId = fieldIdStack.removeLast()
            return fields
        }

        /** 按线上紧凑类型读一个值。 */
        private fun readValue(type: Int): Any? = when (type) {
            TYPE_TRUE -> true
            TYPE_FALSE -> false
            TYPE_BYTE -> readByte().toByte()
            TYPE_I16, TYPE_I32 -> unzigzag32(readVarint())
            TYPE_I64 -> unzigzag64(readVarint64())
            TYPE_DOUBLE -> readDouble()
            TYPE_STRING -> readString()
            TYPE_LIST, TYPE_SET -> readList()
            TYPE_MAP -> readMap()
            TYPE_STRUCT -> readStruct()
            else -> throw IllegalStateException("百词斩响应含未知字段类型 $type")
        }

        /** 读列表：头部低 4 位是元素类型，高 4 位是长度（15 表示后跟 varint）。 */
        private fun readList(): List<Any?> {
            val header = readByte()
            var size = (header ushr 4) and 0x0F
            val elementType = header and 0x0F
            if (size == 15) size = readVarint()
            return List(size) { readValue(elementType) }
        }

        /** 读 map：先 varint 长度，再一个字节给出 key/value 类型。 */
        private fun readMap(): Map<Any?, Any?> {
            val size = readVarint()
            if (size == 0) return emptyMap()
            val types = readByte()
            val keyType = (types ushr 4) and 0x0F
            val valueType = types and 0x0F
            val result = LinkedHashMap<Any?, Any?>()
            repeat(size) {
                val key = readValue(keyType)
                result[key] = readValue(valueType)
            }
            return result
        }

        /** 读字符串：varint 长度 + UTF-8 字节。 */
        private fun readString(): String {
            val length = readVarint()
            check(index + length <= data.size) { "百词斩响应字符串越界" }
            val value = String(data, index, length, Charsets.UTF_8)
            index += length
            return value
        }

        /** 读一个字节；越界视为响应损坏。 */
        private fun readByte(): Int {
            check(index < data.size) { "百词斩响应提前结束" }
            return data[index++].toInt() and 0xFF
        }

        /** 读 32 位 varint。 */
        private fun readVarint(): Int {
            var result = 0
            var shift = 0
            while (true) {
                val byte = readByte()
                result = result or ((byte and 0x7F) shl shift)
                if (byte and 0x80 == 0) return result
                shift += 7
                check(shift <= 35) { "百词斩响应 varint 过长" }
            }
        }

        /** 读 64 位 varint。 */
        private fun readVarint64(): Long {
            var result = 0L
            var shift = 0
            while (true) {
                val byte = readByte()
                result = result or ((byte.toLong() and 0x7F) shl shift)
                if (byte and 0x80 == 0) return result
                shift += 7
                check(shift <= 70) { "百词斩响应 varint 过长" }
            }
        }

        /** 读 8 字节小端 double。 */
        private fun readDouble(): Double {
            var bits = 0L
            repeat(8) { offset ->
                bits = bits or (readByte().toLong() shl (8 * offset))
            }
            return java.lang.Double.longBitsToDouble(bits)
        }

        /** 32 位 unzigzag。 */
        private fun unzigzag32(value: Int): Int = (value ushr 1) xor -(value and 1)

        /** 64 位 unzigzag。 */
        private fun unzigzag64(value: Long): Long = (value ushr 1) xor -(value and 1L)
    }

    /** 协议常量集中定义，避免魔法数字散落在编解码里。 */
    private companion object {
        // 主接口主机。
        const val API_HOST = "https://resource.baicizhan.com"

        // 接口路径前缀。
        const val RESOURCE_PATH = "/rpc/resource_api"

        // 游客登录主机。
        const val PASSPORT_HOST = "https://passport.baicizhan.com"

        // 游客登录路径前缀。
        const val USER_PATH = "/rpc/unified_user_service"

        // 音频 CDN 前缀，接口只给相对路径。
        const val CDN_BASE = "https://word.bczcdn.com"

        // 伪装成官方客户端的版本号与系统版本，接口对 UA 没有强校验。
        const val APP_VERSION = "7.2.0"
        const val OS_VERSION = "33"
        const val USER_AGENT = "bcz_app/android/$APP_VERSION os_version/$OS_VERSION"

        // token 有效期 12 小时；到期后重新领游客 token。
        const val TOKEN_TTL_MILLIS = 12L * 60L * 60L * 1000L

        // 接口查询超时：比 MP3 下载宽松，RPC 要换 token 再查词。
        const val CONNECT_TIMEOUT_MILLIS = 4_000
        const val READ_TIMEOUT_MILLIS = 6_000

        // 两次请求的最小间隔，降低被风控的概率。
        const val MIN_REQUEST_INTERVAL_MILLIS = 250L

        // 业务错误码：未登录、单词未收录。
        const val ERR_NOT_LOGIN = 8
        const val ERR_NOT_FOUND = 3

        // SharedPreferences 文件名与键。
        const val PREFS_NAME = "baicizhan_audio"
        const val KEY_DEVICE_ID = "device_id"
        const val KEY_TOKEN = "access_token"
        const val KEY_TOKEN_AT = "access_token_at"

        // 口音协议值，与播放器保持一致。
        const val AMERICAN = "american"

        // hex 字符表。
        const val HEX_DIGITS = "0123456789ABCDEF"

        // Thrift 消息类型与线上紧凑类型。
        const val MESSAGE_TYPE_CALL = 1
        const val TYPE_TRUE = 1
        const val TYPE_FALSE = 2
        const val TYPE_BYTE = 3
        const val TYPE_I16 = 4
        const val TYPE_I32 = 5
        const val TYPE_I64 = 6
        const val TYPE_DOUBLE = 7
        const val TYPE_STRING = 8
        const val TYPE_LIST = 9
        const val TYPE_SET = 10
        const val TYPE_MAP = 11
        const val TYPE_STRUCT = 12
    }
}
