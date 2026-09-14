package com.example.my_english

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.database.sqlite.SQLiteStatement
import java.io.Closeable
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 单词、设置和备份的本地入口；学习过程由 StudyRepository 使用同一连接处理。
 * 新库有独立文件名，原来的 v2 数据库保持原样，升级不删除用户已保存的旧数据。
 */
class WordsDatabase(context: Context, dbName: String = DATABASE_NAME) :
    SQLiteOpenHelper(context, dbName, null, 1) {
    companion object {
        private const val DATABASE_NAME = "my_english_v3.db"
        const val LAYER_HARD = 1
        const val LAYER_STALE = 2
        internal const val LISTENING_PLAYBACK_KEY = "listeningPlayback"
    }

    internal val study by lazy { StudyRepository(this) }

    override fun onCreate(db: SQLiteDatabase) = StudySchema.create(db)
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        error("没有从结构 $oldVersion 升级到 $newVersion 的规则")
    }
    override fun onConfigure(db: SQLiteDatabase) = db.setForeignKeyConstraintsEnabled(true)

    /** 共用事务：一组写入全部成功才保存；嵌套业务复用外层事务。 */
    internal fun <T> transaction(action: () -> T): T {
        val db = writableDatabase
        val owns = !db.inTransaction()
        if (owns) db.beginTransaction()
        try {
            val result = action()
            if (owns) db.setTransactionSuccessful()
            return result
        } finally {
            if (owns) db.endTransaction()
        }
    }

    internal fun rows(sql: String, args: List<Any?> = emptyList()): List<Map<String, Any?>> =
        readableDatabase.rawQuery(sql, args.map { it?.toString().orEmpty() }.toTypedArray()).use { cursor ->
            val result = mutableListOf<Map<String, Any?>>()
            while (cursor.moveToNext()) {
                val row = linkedMapOf<String, Any?>()
                for (i in 0 until cursor.columnCount) {
                    row[cursor.getColumnName(i)] = when (cursor.getType(i)) {
                        Cursor.FIELD_TYPE_NULL -> null
                        Cursor.FIELD_TYPE_INTEGER -> cursor.getLong(i)
                        Cursor.FIELD_TYPE_FLOAT -> cursor.getDouble(i)
                        else -> cursor.getString(i)
                    }
                }
                result.add(row)
            }
            result
        }

    internal fun insert(table: String, fields: Map<String, Any?>): Long {
        val now = System.currentTimeMillis()
        return writableDatabase.insertOrThrow(table, null, values(
            mapOf("created_at" to now, "updated_at" to now) + fields,
        ))
    }

    /** 同一张试卷的大量同类行复用一条已编译语句，仍由外层事务整体提交。 */
    internal fun batchInserter(table: String, columns: List<String>) = BatchInserter(
        writableDatabase.compileStatement("INSERT INTO $table (${(columns + listOf("created_at", "updated_at")).joinToString(",")}) VALUES (${marks(columns.size + 2)})"), columns.size,
    )

    internal fun update(table: String, id: Long, fields: Map<String, Any?>): Int =
        writableDatabase.update(table, values(fields + ("updated_at" to System.currentTimeMillis())), "id=?", arrayOf(id.toString()))

    private fun values(fields: Map<String, Any?>): ContentValues = ContentValues().apply {
        for ((key, value) in fields) when (value) {
            null -> putNull(key)
            is Boolean -> put(key, if (value) 1 else 0)
            is Int -> put(key, value)
            is Long -> put(key, value)
            is Number -> put(key, value.toDouble())
            is List<*>, is Map<*, *> -> put(key, encode(value))
            else -> put(key, value.toString())
        }
    }

    /** 首次升级只迁移随身听的编号和位置；之后直接读取固定设置，不加载会话副本。 */
    fun getSettings(): Map<String, Any?> {
        study.migrateListeningPlayback()
        return rows(
            "SELECT key,value,type FROM settings WHERE deleted_at IS NULL AND key NOT LIKE 'session.%' ORDER BY key",
        ).associate { it["key"].toString() to mapOf("value" to it["value"], "type" to it["type"]) }
    }

    fun setSetting(key: String, value: String, type: String) {
        require(key.isNotBlank() && !key.startsWith("session.")) { "无效的偏好设置名称" }
        if (type == "json") decode(value)
        putSetting(key, value, type)
    }

    internal fun putSetting(key: String, value: String, type: String = "json") {
        require(type in setOf("string", "int", "double", "bool", "json")) { "未知设置类型：$type" }
        // 内部调用的 JSON 都由 encode 生成；不把刚编码的大副本立即再解码一遍。
        val old = rows("SELECT id,value,type FROM settings WHERE key=? AND deleted_at IS NULL", listOf(key)).firstOrNull()
        if (old != null && old["value"] == value && old["type"] == type) return
        if (old == null) insert("settings", mapOf("key" to key, "value" to value, "type" to type))
        else update("settings", old.long("id"), mapOf("value" to value, "type" to type))
    }

    internal fun setting(key: String): Any? = rows(
        "SELECT value FROM settings WHERE key=? AND deleted_at IS NULL", listOf(key),
    ).firstOrNull()?.get("value")?.toString()?.let(::decode)

    internal fun settingInt(key: String, default: Int): Int = rows(
        "SELECT value FROM settings WHERE key=? AND deleted_at IS NULL", listOf(key),
    ).firstOrNull()?.get("value")?.toString()?.toIntOrNull() ?: default

    /** 重置偏好及随身听清单，保留答题会话的历史内容副本。 */
    fun clearSettings() = transaction {
        val now = System.currentTimeMillis()
        writableDatabase.execSQL(
            "UPDATE settings SET deleted_at=?,updated_at=? WHERE deleted_at IS NULL AND key NOT LIKE 'session.%'",
            arrayOf(now, now),
        )
        // 明确重置后的空清单也是一种结果，不能下次启动又把旧会话迁回来。
        putSetting(LISTENING_PLAYBACK_KEY, encode(mapOf("revision" to "empty", "word_ids" to emptyList<Long>())))
    }

    fun getAllWords(): List<Map<String, Any?>> = readWords(rows("SELECT * FROM words WHERE deleted_at IS NULL ORDER BY id"))

    fun getWordsByIds(ids: List<Long>): List<Map<String, Any?>> = ids.distinct().chunked(800).flatMap { batch ->
        readWords(rows("SELECT * FROM words WHERE deleted_at IS NULL AND id IN (${marks(batch.size)}) ORDER BY id", batch))
    }

    fun getWordsByMeaningIds(ids: List<Long>): List<Map<String, Any?>> = getWordsByIds(
        ids.distinct().chunked(800).flatMap { batch -> rows(
            "SELECT DISTINCT word_id FROM word_meanings WHERE deleted_at IS NULL AND id IN (${marks(batch.size)})", batch,
        ).map { it.long("word_id") } },
    )

    private fun readWords(source: List<Map<String, Any?>>): List<Map<String, Any?>> {
        if (source.isEmpty()) return emptyList()
        val meanings = source.map { it.long("id") }.chunked(800).flatMap { ids -> rows(
            "SELECT * FROM word_meanings WHERE deleted_at IS NULL AND word_id IN (${marks(ids.size)}) ORDER BY sort DESC,id", ids,
        ) }.groupBy { it.long("word_id") }
        return source.map { row -> row + mapOf(
            "confusions" to strings(row["confusions"]),
            "syllables" to textArray(row["syllables"]),
            "meanings" to (meanings[row.long("id")] ?: emptyList()).map { it + ("confusions" to strings(it["confusions"])) },
        ) }
    }

    fun createWord(payload: Map<*, *>): Long = transaction {
        val id = insert("words", wordFields(payload) + ("created_at" to (payload["created_at"] as? Number)?.toLong().let { it ?: System.currentTimeMillis() }))
        writeMeanings(id, payload["meanings"])
        id
    }

    fun updateWord(payload: Map<*, *>) = transaction {
        val id = (payload["id"] as? Number)?.toLong() ?: error("更新单词缺少编号")
        require(rows("SELECT id FROM words WHERE id=? AND deleted_at IS NULL", listOf(id)).isNotEmpty()) { "单词已不存在" }
        update("words", id, wordFields(payload))
        val now = System.currentTimeMillis()
        writableDatabase.execSQL("UPDATE word_meanings SET deleted_at=?,updated_at=? WHERE word_id=? AND deleted_at IS NULL", arrayOf(now, now, id))
        writeMeanings(id, payload["meanings"])
    }

    private fun wordFields(payload: Map<*, *>): Map<String, Any?> {
        val spelling = payload["spelling"]?.toString()?.trim().orEmpty()
        require(spelling.isNotEmpty()) { "单词拼写不能为空" }
        val difficulty = (payload["difficulty"] as? Number)?.toLong() ?: 0L
        require(difficulty >= 0) { "难度不能小于零" }
        return mapOf("spelling" to spelling, "difficulty" to difficulty,
            "confusions" to strings(payload["confusions"]), "syllables" to textArray(payload["syllables"]),
            "reviewed_at" to (payload["reviewed_at"] as? Number)?.toLong())
    }

    private fun writeMeanings(wordId: Long, raw: Any?) {
        val meanings = raw as? List<*> ?: emptyList<Any?>()
        for ((index, value) in meanings.withIndex()) {
            val row = value as? Map<*, *> ?: error("第 ${index + 1} 条含义格式不正确")
            val definition = row["definition"]?.toString()?.trim().orEmpty()
            require(definition.isNotEmpty()) { "含义不能为空" }
            insert("word_meanings", mapOf(
                "word_id" to wordId, "pos" to row["pos"]?.toString()?.trim()?.takeIf { it.isNotEmpty() && it != "*" },
                "sub_pos" to row["sub_pos"]?.toString()?.trim()?.takeIf { it.isNotEmpty() },
                "definition" to definition, "confusions" to strings(row["confusions"]), "sort" to meanings.size - index,
            ))
        }
    }

    fun deleteWord(id: Long) = transaction {
        val now = System.currentTimeMillis()
        update("words", id, mapOf("deleted_at" to now))
        writableDatabase.execSQL("UPDATE word_meanings SET deleted_at=?,updated_at=? WHERE word_id=? AND deleted_at IS NULL", arrayOf(now, now, id))
        // 计划在下次获取时补缺；已开局内容和历史结算都继续保留。
    }

    fun saveWordConfusions(id: Long, raw: Any?) { update("words", id, mapOf("confusions" to strings(raw))) }
    fun saveMeaningConfusions(id: Long, raw: Any?) { update("word_meanings", id, mapOf("confusions" to strings(raw))) }
    fun saveWordSyllables(id: Long, raw: Any?) { update("words", id, mapOf("syllables" to textArray(raw))) }

    /**
     * 两层选词，排序逐项对应《功能描述.md》「优选单词」那一节。
     *
     * 难词层：难度降 → 含义数降 → 含义字数降 → 复习时间降 → 字母升 → 编号升
     * 久词层：复习时间升 → 含义数升 → 含义字数升 → 难度升 → 字母升 → 编号升
     *
     * 两层的口味是**相反的**：难词层要「又难又重」的，含义越多、释义越长的越先挑；
     * 久词层要「又轻又久」的，含义越少越短、越久没复习的越先挑。
     *
     * 生活化解释：这两行原来把后三项整段写反了（都写成了 DESC），于是「难词」
     * 挑出来的是释义最多最长的词，「久词」也不再优先含义少的。更早的版本还漏掉了
     * 含义数和字数这两项，只看难度。40/60 的配额一直是对的，坏的是配额里挑谁。
     *
     * 复习时间升序时 NULL 排最前，这是 SQLite `ASC` 的默认行为，正好满足
     * 「从没复习过的久词优先」——不需要额外写 `NULLS FIRST`。
     */
    fun pickWords(limit: Int, exclude: List<Long>, layer: Int): List<Long> {
        if (limit <= 0) return emptyList()
        // 字母序、编号序两层共用，拼在 ORDER BY 末尾，不重复写进各层分支。
        val order = if (layer == LAYER_HARD)
            "w.difficulty DESC,meaning_count DESC,meaning_length DESC,w.reviewed_at DESC"
        else "w.reviewed_at ASC,meaning_count ASC,meaning_length ASC,w.difficulty ASC"
        // 排除列表在内存中过滤，避免大词库自测超过 SQLite 的参数个数上限。
        val excluded = exclude.toHashSet()
        return rows("""
            SELECT w.id,COUNT(m.id) AS meaning_count,COALESCE(SUM(length(trim(m.definition))),0) AS meaning_length
            FROM words w LEFT JOIN word_meanings m ON m.word_id=w.id AND m.deleted_at IS NULL
            WHERE w.deleted_at IS NULL GROUP BY w.id
            ORDER BY $order,w.spelling COLLATE NOCASE ASC,w.id ASC
        """.trimIndent()).asSequence().map { it.long("id") }.filterNot { it in excluded }.take(limit).toList()
    }

    /** 完整备份保持十一张表、原始编号和毫秒时间；包含软删除行以保留历史关联。 */
    fun exportData(): Map<String, Any?> = transaction {
        linkedMapOf<String, Any?>("version" to 3, "time_unit" to "milliseconds").apply {
            for (table in StudySchema.tables) put(table, rows("SELECT * FROM $table ORDER BY id").map { row ->
                row.mapValues { (column, value) ->
                    if (column in (StudySchema.arrayColumns[table] ?: emptySet()) && value != null) decode(value.toString()) else value
                }
            })
        }
    }

    /**
     * 导入先校验整份结构，再在一个事务内替换。
     * 任何字段、外键或快照有问题都整体回滚，绝不悄悄跳过坏行后报告成功。
     */
    fun importData(data: Map<*, *>) {
        require((data["version"] as? Number)?.toInt() == 3) { "请导入新版格式（version=3），旧备份需要先转换" }
        require(data["time_unit"] == null || data["time_unit"] == "milliseconds") { "时间单位必须为 milliseconds" }
        val prepared = linkedMapOf<String, List<Map<String, Any?>>>()
        for (table in StudySchema.tables) {
            val source = data[table] as? List<*> ?: error("备份缺少 $table 数组")
            val columns = rows("PRAGMA table_info($table)").map { it["name"].toString() }.toSet()
            prepared[table] = source.mapIndexed { index, value ->
                val row = value as? Map<*, *> ?: error("$table 第 ${index + 1} 行不是对象")
                require(row.keys.all { it is String && it in columns }) { "$table 第 ${index + 1} 行含未知字段" }
                val result = row.entries.associate { it.key.toString() to it.value }.toMutableMap()
                require((result["id"] as? Number)?.toLong()?.let { it > 0 } == true) { "$table 第 ${index + 1} 行编号无效" }
                for (column in StudySchema.arrayColumns[table] ?: emptySet()) {
                    // 完整恢复保留原顺序和重复元素；音节等列表不能按候选词去重。
                    if (result[column] != null) result[column] = textArray(result[column])
                }
                for (column in listOf("created_at", "updated_at", "deleted_at", "reviewed_at")) {
                    if (column in columns && result[column] != null) require(result[column] is Number && (result[column] as Number).toDouble() == (result[column] as Number).toLong().toDouble()) { "$table.$column 必须是毫秒整数" }
                }
                if ("date" in columns) require(validDate(result["date"]?.toString().orEmpty())) { "$table 的日期无效" }
                if (table == "settings" && result["type"] == "json") decode(result["value"]?.toString() ?: error("设置缺少 value"))
                result
            }
        }
        study.clearSnapshotCache()
        try {
            transaction {
                // 会话与大题互相指向当前题目，整个事务结束时统一检查这些引用。
                writableDatabase.execSQL("PRAGMA defer_foreign_keys = ON")
                for (table in StudySchema.tables.asReversed()) writableDatabase.delete(table, null, null)
                for ((table, source) in prepared) for (row in source) insert(table, row)
                require(rows("PRAGMA foreign_key_check").isEmpty()) { "备份存在无法对应的编号" }
                study.validateImportedData()
            }
        } finally {
            // 校验期间可能读取导入数据；即使事务撤回，也不能沿用那份内存副本。
            study.clearSnapshotCache()
        }
    }

    /** 清空是明确的维护操作；同时清掉偏好及会话快照，旧 v2 文件不受影响。 */
    fun clearAll() = transaction {
        study.clearSnapshotCache()
        writableDatabase.execSQL("PRAGMA defer_foreign_keys = ON")
        for (table in StudySchema.tables.asReversed()) writableDatabase.delete(table, null, null)
    }

    fun localDateString(millis: Long = System.currentTimeMillis()): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(millis))

    internal fun validDate(text: String): Boolean {
        if (!Regex("\\d{4}-\\d{2}-\\d{2}").matches(text)) return false
        return runCatching { SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { isLenient = false }.parse(text) != null }.getOrDefault(false)
    }
}

internal fun Map<*, *>.long(key: String): Long = (this[key] as? Number)?.toLong() ?: 0L
internal fun Map<*, *>.int(key: String): Int = long(key).toInt()
internal fun marks(count: Int): String = List(count) { "?" }.joinToString(",")
internal fun encode(value: Any?): String = when (value) {
    null -> "null"
    is Map<*, *> -> JSONObject(value).toString()
    is List<*> -> JSONArray(value).toString()
    else -> JSONObject.wrap(value)?.toString() ?: "null"
}
internal fun decode(text: String): Any? = unwrap(JSONTokener(text).nextValue())
private fun unwrap(value: Any?): Any? = when (value) {
    null, JSONObject.NULL -> null
    is JSONArray -> (0 until value.length()).map { unwrap(value.get(it)) }
    is JSONObject -> value.keys().asSequence().associateWith { unwrap(value.get(it)) }
    else -> value
}
/** 只校验文本数组；备份和音节需要逐项保留，重复片段也有意义。 */
internal fun textArray(raw: Any?): List<String> {
    val decoded = if (raw is String) decode(raw) else raw
    if (decoded == null) return emptyList()
    require(decoded is List<*> && decoded.all { it is String }) { "文本数组格式不正确" }
    return decoded.map { it as String }
}

/** 候选与单次答案按文本去重；不要用于需要保留重复项的有序资料。 */
internal fun strings(raw: Any?): List<String> =
    textArray(raw).map { it.trim() }.filter { it.isNotEmpty() }.distinct()

/** 批量写入只替换参数，省去每道题重复生成 SQL 和 ContentValues。 */
internal class BatchInserter(private val statement: SQLiteStatement, private val count: Int) : Closeable {
    private val createdAt = System.currentTimeMillis()
    fun add(values: List<Any?>): Long {
        require(values.size == count)
        statement.clearBindings()
        for ((index, value) in values.withIndex()) {
            val at = index + 1
            when (value) {
                null -> statement.bindNull(at)
                is Boolean -> statement.bindLong(at, if (value) 1 else 0)
                is Byte, is Short, is Int, is Long -> statement.bindLong(at, (value as Number).toLong())
                is Number -> statement.bindDouble(at, value.toDouble())
                is List<*>, is Map<*, *> -> statement.bindString(at, encode(value))
                else -> statement.bindString(at, value.toString())
            }
        }
        statement.bindLong(count + 1, createdAt)
        statement.bindLong(count + 2, createdAt)
        return statement.executeInsert().also { check(it > 0) { "试卷保存失败" } }
    }
    override fun close() = statement.close()
}
