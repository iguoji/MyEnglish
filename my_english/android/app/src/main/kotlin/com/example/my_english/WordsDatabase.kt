// package 相当于 PHP namespace，必须与 Android application namespace 对应。
package com.example.my_english

// ContentValues 是一行数据的键值容器，写库时代替手写 INSERT 语句。
import android.content.ContentValues
// Context 提供数据库文件所在的 App 私有目录。
import android.content.Context
// Cursor 是查询结果的游标，逐行读取。
import android.database.Cursor
// SQLiteDatabase / SQLiteOpenHelper 是 Android 自带的 SQLite 封装。
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
// org.json 是 Android 自带的 JSON 工具，用来读写数组型字段。
import org.json.JSONArray
import org.json.JSONObject
// SimpleDateFormat / Date / Locale 负责「毫秒时间戳 ↔ 可读日期」的互转。
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 「我的英语」的唯一持久化入口。
 *
 * 整个 App 只有这一个数据库、五张表，没有第二份持久化：
 *   settings         设置（当可持久化的 Redis 用）
 *   words            单词
 *   meanings         含义（一行就是一条中文释义）
 *   word_sets        复习词库（今天要背的这一批）
 *   sessions         会话（一个模块的一局）
 *   session_records  会话记录（每点一次写一条）
 *
 * 离线语音 mp3 仍是文件缓存 —— 它可以随时重新下载，不属于业务数据。
 *
 * 表结构与索引的完整说明见 `tools/schema_v2.sql`。
 *
 * 环境约束（minSdk 24 = Android 7，SQLite 3.9）：
 * 部分索引可用，但**没有 JSON 函数**，所以 JSON 字段一律在这里用 org.json 解析，
 * 绝不能在 SQL 里写 json_extract 之类。
 */
class WordsDatabase(
    context: Context,
    dbName: String = DATABASE_NAME,
) : SQLiteOpenHelper(context, dbName, null, DATABASE_VERSION) {

    // 保留 App Context 副本：升级前自动备份要写私有目录，而 SQLiteOpenHelper
    // 的 context 是 protected，外部查询不到，需要自己存一份。
    private val appContext: Context = context

    companion object {
        // 数据库文件名；换了新名字，旧库文件原样留在磁盘上作为最后一道保险。
        private const val DATABASE_NAME = "my_english_v2.db"

        // 结构版本；这一版是全新设计，没有从旧库升级的路径。
        private const val DATABASE_VERSION = 1

        // 会话类型：每日主线进度。
        const val KIND_DAILY = 1

        // 会话类型：无限巩固练习。
        const val KIND_REINFORCE = 2

        // 会话状态：进行中。
        const val STATUS_ACTIVE = 1

        // 会话状态：完成。
        const val STATUS_COMPLETED = 2

        // 会话状态：中断。
        const val STATUS_ABORTED = 3

        // 会话状态：失败。
        const val STATUS_FAILED = 4

        // 选词第一层：难度降序打头，专挑难词。
        const val LAYER_HARD = 1

        // 选词第二层：复习时间升序打头，专挑久未复习的词。
        const val LAYER_STALE = 2

        // 连对次数往回扫的最大轮数。
        //
        // 生活化解释：判断「连对满 5 次降难度」时要数出连续答对了几轮。理论上
        // 一直答对就要一直往回数，这里封顶 500 轮——一个词连对 500 次早就不用
        // 再练了，封顶只是防止极端数据把一次查询拖慢。
        private const val STREAK_SCAN_LIMIT = 500
    }

    // -----------------------------------------------------------------------
    // 建表
    // -----------------------------------------------------------------------

    /** 首次安装时建表。 */
    override fun onCreate(db: SQLiteDatabase) {
        createSchema(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        exportBackupBeforeUpgrade(db, oldVersion, newVersion)
        dropSchema(db)
        createSchema(db)
    }

    /**
     * 升级（删库）前先自动导出一份完整备份到 app 私有目录。
     *
     * 删库是不可逆操作，靠用户记得手动导出太脆弱——哪怕迁移文档写了流程，
     * 一次疏忽就丢光。这里用旧表结构导出完整 JSON 落盘，作为最后一道保险。
     * 导出失败不阻断升级：升级才是目标，备份只是兜底。
     */
    private fun exportBackupBeforeUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        try {
            val snapshot = linkedMapOf<String, Any?>(
                "version" to 2,
                "settings" to exportRows(db, "settings"),
                "words" to exportRows(db, "words", jsonArrayColumns = setOf("confusions", "syllables")),
                "meanings" to exportRows(db, "meanings", jsonArrayColumns = setOf("confusions")),
                "word_sets" to exportRows(
                    db, "word_sets",
                    jsonArrayColumns = setOf("today_word_ids", "tomorrow_word_ids"),
                ),
                "sessions" to exportRows(db, "sessions", jsonArrayColumns = setOf("items")),
                "session_records" to exportRows(db, "session_records"),
            )
            val fileName = "my_english-upgrade-v${oldVersion}to${newVersion}.json"
            val file = java.io.File(appContext.filesDir, fileName)
            file.parentFile?.mkdirs()
            file.writeText(org.json.JSONObject(snapshot).toString(2))
        } catch (error: Throwable) {
            android.util.Log.w("WordsDatabase", "升级前自动备份失败（不影响升级进行）：$error")
        }
    }

    /** 每次打开连接都确认外键约束已启用。 */
    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        // 外键让「删单词 → 连带删含义与记录」由数据库自己保证，不用应用层记着。
        db.setForeignKeyConstraintsEnabled(true)
    }

    /** 按 `tools/schema_v2.sql` 建全部表与索引。 */
    private fun createSchema(db: SQLiteDatabase) {
        // ---- 设置表：一个可持久化的 Redis --------------------------------
        db.execSQL(
            """
            CREATE TABLE settings (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                key        TEXT    NOT NULL,
                value      TEXT    NOT NULL,
                type       TEXT    NOT NULL DEFAULT 'string'
                                   CHECK (type IN ('string','int','double','bool','json')),
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER NULL
            )
            """.trimIndent(),
        )
        // 同一个 key 在「活着的行」里只能有一条；软删掉的旧行不再占用这个名字。
        db.execSQL("CREATE UNIQUE INDEX settings_key ON settings(key) WHERE deleted_at IS NULL")

        // ---- 单词表 -------------------------------------------------------
        db.execSQL(
            """
            CREATE TABLE words (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                spelling    TEXT    NOT NULL,
                difficulty  INTEGER NOT NULL DEFAULT 0 CHECK (difficulty >= 0),
                confusions  TEXT    NOT NULL DEFAULT '[]',
                syllables   TEXT    NOT NULL DEFAULT '[]',
                reviewed_at INTEGER NULL,
                created_at  INTEGER NOT NULL,
                updated_at  INTEGER NOT NULL,
                deleted_at  INTEGER NULL
            )
            """.trimIndent(),
        )
        // 选词第一层：难度降序 → 复习时间升序。实测完整走索引，无额外排序。
        db.execSQL(
            "CREATE INDEX words_pick_hard ON words(difficulty DESC, reviewed_at ASC, id ASC) " +
                "WHERE deleted_at IS NULL",
        )
        // 选词第二层：复习时间升序 → 难度降序。reviewed_at 为 NULL 的（没复习过的）
        // 会被 SQLite 自动排在最前面，正好等于「先未复习」的规则。
        db.execSQL(
            "CREATE INDEX words_pick_stale ON words(reviewed_at ASC, difficulty DESC, id ASC) " +
                "WHERE deleted_at IS NULL",
        )
        // 词库搜索、按拼写排序、生成混淆词时按拼写找相似词。
        db.execSQL(
            "CREATE INDEX words_spelling ON words(spelling COLLATE NOCASE) WHERE deleted_at IS NULL",
        )

        // ---- 含义表：一行就是一条中文释义 --------------------------------
        db.execSQL(
            """
            CREATE TABLE meanings (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                word_id    INTEGER NOT NULL REFERENCES words(id) ON DELETE CASCADE,
                pos        TEXT    NOT NULL,
                sub_pos    TEXT    NULL,
                definition TEXT    NOT NULL,
                confusions TEXT    NOT NULL DEFAULT '[]',
                sort       INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER NULL
            )
            """.trimIndent(),
        )
        // 「取某个单词的全部含义，排序值大的在前」是全项目最高频的一句查询。
        db.execSQL(
            "CREATE INDEX meanings_word ON meanings(word_id, sort DESC, id ASC) " +
                "WHERE deleted_at IS NULL",
        )

        // ---- 复习词库表 ---------------------------------------------------
        db.execSQL(
            """
            CREATE TABLE word_sets (
                id                INTEGER PRIMARY KEY AUTOINCREMENT,
                word_count        INTEGER NOT NULL CHECK (word_count >= 0),
                today_word_ids    TEXT    NOT NULL DEFAULT '[]',
                tomorrow_word_ids TEXT    NOT NULL DEFAULT '[]',
                date              TEXT    NOT NULL,
                created_at        INTEGER NOT NULL,
                updated_at        INTEGER NOT NULL,
                deleted_at        INTEGER NULL
            )
            """.trimIndent(),
        )
        // 「永远取今日最新的那一条」：date 倒序 + id 倒序，取第一行即可。
        db.execSQL(
            "CREATE INDEX word_sets_date ON word_sets(date DESC, id DESC) WHERE deleted_at IS NULL",
        )

        // ---- 会话表 -------------------------------------------------------
        db.execSQL(
            """
            CREATE TABLE sessions (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                module      TEXT    NOT NULL,
                kind        INTEGER NOT NULL CHECK (kind IN (1, 2)),
                status      INTEGER NOT NULL CHECK (status IN (1, 2, 3, 4)),
                word_set_id INTEGER NULL REFERENCES word_sets(id) ON DELETE SET NULL,
                items       TEXT    NOT NULL DEFAULT '[]',
                cursor      INTEGER NOT NULL DEFAULT 0 CHECK (cursor >= 0),
                elapsed     INTEGER NOT NULL DEFAULT 0 CHECK (elapsed >= 0),
                date        TEXT    NOT NULL,
                created_at  INTEGER NOT NULL,
                updated_at  INTEGER NOT NULL,
                deleted_at  INTEGER NULL
            )
            """.trimIndent(),
        )
        // 点进模块时的第一句 SQL：「今天这个模块最新的一条会话」。
        db.execSQL(
            "CREATE INDEX sessions_module_date ON sessions(module, date DESC, id DESC) " +
                "WHERE deleted_at IS NULL",
        )
        // 改「每日复习」数量时批量中断全部进行中的会话。
        db.execSQL(
            "CREATE INDEX sessions_status ON sessions(status, date DESC) WHERE deleted_at IS NULL",
        )

        // ---- 会话记录表：每点一次写一条 ----------------------------------
        db.execSQL(
            """
            CREATE TABLE session_records (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                word_id    INTEGER NOT NULL REFERENCES words(id) ON DELETE CASCADE,
                meaning_id INTEGER NULL REFERENCES meanings(id) ON DELETE CASCADE,
                input      TEXT    NOT NULL DEFAULT '',
                result     INTEGER NOT NULL CHECK (result IN (0, 1)),
                date       TEXT    NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER NULL
            )
            """.trimIndent(),
        )
        // 派生「连对次数」：按单词倒序扫。每答完一个词都要跑一次，是最高频的读。
        db.execSQL(
            "CREATE INDEX records_word ON session_records(word_id, id DESC) WHERE deleted_at IS NULL",
        )
        // 会话恢复（这一局这个词答过没有、点错过哪些候选）与本局错误数统计。
        db.execSQL(
            "CREATE INDEX records_session ON session_records(session_id, word_id, meaning_id) " +
                "WHERE deleted_at IS NULL",
        )
        // 首页数字、趋势曲线、打卡热力图：按日期分组 + 按单词去重。
        db.execSQL(
            "CREATE INDEX records_date ON session_records(date, word_id) WHERE deleted_at IS NULL",
        )
    }

    /** 删光全部表；只在结构升级和「清空数据」时调用。 */
    private fun dropSchema(db: SQLiteDatabase) {
        // 先删引用别人的子表，再删被引用的父表，符合外键依赖顺序。
        for (table in listOf("session_records", "sessions", "word_sets", "meanings", "words", "settings")) {
            db.execSQL("DROP TABLE IF EXISTS $table")
        }
    }

    // -----------------------------------------------------------------------
    // 设置表
    // -----------------------------------------------------------------------

    /**
     * 一次读出全部设置。
     *
     * 返回 `{ key: { "value": 文本, "type": 类型名 } }`，
     * 由 Dart 侧按 type 还原成真正的类型。
     */
    fun getSettings(): Map<String, Any?> {
        val result = linkedMapOf<String, Any?>()
        readableDatabase.query(
            "settings",
            arrayOf("key", "value", "type"),
            "deleted_at IS NULL",
            null, null, null, "key ASC",
        ).use { cursor ->
            while (cursor.moveToNext()) {
                result[cursor.getString(0)] = linkedMapOf(
                    "value" to cursor.getString(1),
                    "type" to cursor.getString(2),
                )
            }
        }
        return result
    }

    /**
     * 写入一个设置项；同名的活行会被整体覆盖。
     *
     * 生活化解释：就像往 Redis 里 `SET key value`——有就改，没有就建。
     */
    fun setSetting(key: String, value: String, type: String) {
        require(key.isNotBlank()) { "设置项的 key 不能为空" }
        require(type in setOf("string", "int", "double", "bool", "json")) { "不支持的设置类型：$type" }
        val db = writableDatabase
        val now = System.currentTimeMillis()
        db.beginTransaction()
        try {
            // 先尝试更新已有的活行，改动最小。
            val updated = db.update(
                "settings",
                ContentValues().apply {
                    put("value", value)
                    put("type", type)
                    put("updated_at", now)
                },
                "key = ? AND deleted_at IS NULL",
                arrayOf(key),
            )
            // 一条都没更新到说明这个 key 还不存在，插一条新的。
            if (updated == 0) {
                db.insertOrThrow(
                    "settings",
                    null,
                    ContentValues().apply {
                        put("key", key)
                        put("value", value)
                        put("type", type)
                        put("created_at", now)
                        put("updated_at", now)
                    },
                )
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    /** 清空全部设置（软删除），恢复到首次安装的状态。 */
    fun clearSettings() {
        writableDatabase.execSQL(
            "UPDATE settings SET deleted_at = ?, updated_at = ? WHERE deleted_at IS NULL",
            arrayOf<Any>(System.currentTimeMillis(), System.currentTimeMillis()),
        )
    }

    // -----------------------------------------------------------------------
    // 单词与含义
    // -----------------------------------------------------------------------

    /** 读取全部未删除的单词，每个单词带上它的全部含义。 */
    fun getAllWords(): List<Map<String, Any?>> = readWords(null, null)

    /** 按主键批量读取单词；空列表直接返回空结果。 */
    fun getWordsByIds(ids: List<Long>): List<Map<String, Any?>> {
        if (ids.isEmpty()) return emptyList()
        // joinToString 拼出 "?,?,?"，参数仍然走占位符绑定，不存在注入风险。
        val placeholders = ids.joinToString(",") { "?" }
        return readWords("id IN ($placeholders)", ids.map { it.toString() }.toTypedArray())
    }

    /**
     * 按含义主键反查它们所属的单词。
     *
     * 看义选词的数据列表存的是含义主键，恢复会话时要靠它把候选单词捞回来。
     */
    fun getWordsByMeaningIds(meaningIds: List<Long>): List<Map<String, Any?>> {
        if (meaningIds.isEmpty()) return emptyList()
        val placeholders = meaningIds.joinToString(",") { "?" }
        val wordIds = mutableListOf<Long>()
        readableDatabase.rawQuery(
            "SELECT DISTINCT word_id FROM meanings " +
                "WHERE id IN ($placeholders) AND deleted_at IS NULL",
            meaningIds.map { it.toString() }.toTypedArray(),
        ).use { cursor -> while (cursor.moveToNext()) wordIds.add(cursor.getLong(0)) }
        return getWordsByIds(wordIds)
    }

    /** 单词读取的统一实现：一次查单词、一次查含义，在内存里拼装。 */
    private fun readWords(extraWhere: String?, args: Array<String>?): List<Map<String, Any?>> {
        val db = readableDatabase
        // 含义先按 word_id 归组，避免每个单词各查一次数据库（N+1 查询）。
        val meaningsByWord = linkedMapOf<Long, MutableList<Map<String, Any?>>>()
        db.query(
            "meanings", null, "deleted_at IS NULL", null, null, null,
            "word_id ASC, sort DESC, id ASC",
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val wordId = cursor.getLong(cursor.getColumnIndexOrThrow("word_id"))
                meaningsByWord.getOrPut(wordId) { mutableListOf() }.add(readMeaningRow(cursor))
            }
        }

        val where = if (extraWhere == null) "deleted_at IS NULL" else "deleted_at IS NULL AND $extraWhere"
        val words = mutableListOf<Map<String, Any?>>()
        db.query("words", null, where, args, null, null, "id ASC").use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getLong(cursor.getColumnIndexOrThrow("id"))
                words.add(
                    linkedMapOf(
                        "id" to id,
                        "spelling" to cursor.getString(cursor.getColumnIndexOrThrow("spelling")),
                        "difficulty" to cursor.getInt(cursor.getColumnIndexOrThrow("difficulty")),
                        "confusions" to decodeStringArray(
                            cursor.getString(cursor.getColumnIndexOrThrow("confusions")),
                        ),
                        "syllables" to decodeStringArray(
                            cursor.getString(cursor.getColumnIndexOrThrow("syllables")),
                        ),
                        "reviewed_at" to cursor.getLongOrNull("reviewed_at"),
                        "created_at" to cursor.getLong(cursor.getColumnIndexOrThrow("created_at")),
                        "updated_at" to cursor.getLong(cursor.getColumnIndexOrThrow("updated_at")),
                        "meanings" to (meaningsByWord[id] ?: emptyList<Map<String, Any?>>()),
                    ),
                )
            }
        }
        return words
    }

    /** 把含义表的一行游标读成 Map。 */
    private fun readMeaningRow(cursor: Cursor): Map<String, Any?> = linkedMapOf(
        "id" to cursor.getLong(cursor.getColumnIndexOrThrow("id")),
        "word_id" to cursor.getLong(cursor.getColumnIndexOrThrow("word_id")),
        "pos" to cursor.getString(cursor.getColumnIndexOrThrow("pos")),
        "sub_pos" to cursor.getStringOrNull("sub_pos"),
        "definition" to cursor.getString(cursor.getColumnIndexOrThrow("definition")),
        "confusions" to decodeStringArray(cursor.getString(cursor.getColumnIndexOrThrow("confusions"))),
        "sort" to cursor.getInt(cursor.getColumnIndexOrThrow("sort")),
    )

    /**
     * 新增一个单词及其全部含义；返回单词主键。
     *
     * 单词主体和含义在同一个事务里写入，任何一步失败都整体回滚，
     * 不会留下「有单词没含义」的半截数据。
     */
    fun createWord(payload: Map<*, *>): Long {
        val db = writableDatabase
        db.beginTransaction()
        try {
            val now = System.currentTimeMillis()
            val wordId = db.insertOrThrow(
                "words",
                null,
                ContentValues().apply {
                    put("spelling", (payload["spelling"] as? String).orEmpty().trim())
                    put("difficulty", (payload["difficulty"] as? Number)?.toInt() ?: 0)
                    put("confusions", encodeStringArray(payload["confusions"]))
                    put("syllables", encodeStringArray(payload["syllables"]))
                    val reviewedAt = (payload["reviewed_at"] as? Number)?.toLong()
                    if (reviewedAt == null || reviewedAt == 0L) putNull("reviewed_at") else put("reviewed_at", reviewedAt)
                    put("created_at", (payload["created_at"] as? Number)?.toLong() ?: now)
                    put("updated_at", now)
                },
            )
            writeMeanings(db, wordId, payload["meanings"], now)
            db.setTransactionSuccessful()
            return wordId
        } finally {
            db.endTransaction()
        }
    }

    /**
     * 更新一个单词；含义整体替换（旧含义软删除，新含义重新插入）。
     *
     * 用「软删旧的 + 插新的」而不是逐条比对更新，是因为编辑界面允许任意增删改排序，
     * 逐条比对的代码复杂度远高于收益；而软删除保证历史记录里的含义引用不会断掉。
     */
    fun updateWord(payload: Map<*, *>) {
        val wordId = (payload["id"] as? Number)?.toLong() ?: error("更新单词必须提供 id")
        val db = writableDatabase
        db.beginTransaction()
        try {
            val now = System.currentTimeMillis()
            db.update(
                "words",
                ContentValues().apply {
                    put("spelling", (payload["spelling"] as? String).orEmpty().trim())
                    put("difficulty", (payload["difficulty"] as? Number)?.toInt() ?: 0)
                    put("confusions", encodeStringArray(payload["confusions"]))
                    put("syllables", encodeStringArray(payload["syllables"]))
                    val reviewedAt = (payload["reviewed_at"] as? Number)?.toLong()
                    if (reviewedAt == null || reviewedAt == 0L) putNull("reviewed_at") else put("reviewed_at", reviewedAt)
                    put("updated_at", now)
                },
                "id = ?",
                arrayOf(wordId.toString()),
            )
            // 旧含义整批软删除，历史会话记录里的 meaning_id 仍能查到内容。
            db.execSQL(
                "UPDATE meanings SET deleted_at = ?, updated_at = ? WHERE word_id = ? AND deleted_at IS NULL",
                arrayOf<Any>(now, now, wordId),
            )
            writeMeanings(db, wordId, payload["meanings"], now)
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    /**
     * 把一批含义写进数据库。
     *
     * 排序值按「传入顺序」倒着发放：第一条拿最大值，界面上就排在最前面。
     * 这样上层只要按想显示的顺序传进来即可，不必自己算排序数字。
     */
    private fun writeMeanings(db: SQLiteDatabase, wordId: Long, raw: Any?, now: Long) {
        val list = raw as? List<*> ?: return
        val total = list.size
        for ((offset, item) in list.withIndex()) {
            val meaning = item as? Map<*, *> ?: continue
            val definition = (meaning["definition"] as? String)?.trim().orEmpty()
            // 空释义无法出题，也没有展示价值，直接跳过。
            if (definition.isEmpty()) continue
            db.insertOrThrow(
                "meanings",
                null,
                ContentValues().apply {
                    put("word_id", wordId)
                    put("pos", (meaning["pos"] as? String).orEmpty().trim())
                    val subPos = (meaning["sub_pos"] as? String)?.trim()
                    if (subPos.isNullOrEmpty()) putNull("sub_pos") else put("sub_pos", subPos)
                    put("definition", definition)
                    put("confusions", encodeStringArray(meaning["confusions"]))
                    // 传入顺序的第一条拿到最大排序值。
                    put("sort", total - offset)
                    put("created_at", now)
                    put("updated_at", now)
                },
            )
        }
    }

    /** 软删除一个单词；它的含义一并软删除。 */
    fun deleteWord(id: Long) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            val now = System.currentTimeMillis()
            db.execSQL(
                "UPDATE words SET deleted_at = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL",
                arrayOf<Any>(now, now, id),
            )
            db.execSQL(
                "UPDATE meanings SET deleted_at = ?, updated_at = ? WHERE word_id = ? AND deleted_at IS NULL",
                arrayOf<Any>(now, now, id),
            )
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    /**
     * 回写单词的混淆词。
     *
     * 只要有字段被改动就同步刷新 updated_at，全表一视同仁：
     * 「这一行什么时候变过」永远是可信的，不区分改动来自用户还是程序。
     */
    fun saveWordConfusions(wordId: Long, confusions: Any?) {
        val now = System.currentTimeMillis()
        // 只作用在还活着的单词上；已删除（软删除）的词不接收回写。
        writableDatabase.execSQL(
            "UPDATE words SET confusions = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL",
            arrayOf<Any>(encodeStringArray(confusions), now, wordId),
        )
    }

    /** 回写含义的混淆词；同样刷新 updated_at，同样只在活着的含义上写。 */
    fun saveMeaningConfusions(meaningId: Long, confusions: Any?) {
        val now = System.currentTimeMillis()
        writableDatabase.execSQL(
            "UPDATE meanings SET confusions = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL",
            arrayOf<Any>(encodeStringArray(confusions), now, meaningId),
        )
    }

    /** 回写单词的音节拆分；同样刷新 updated_at，同样只在活着的单词上写。 */
    fun saveWordSyllables(wordId: Long, syllables: Any?) {
        val now = System.currentTimeMillis()
        writableDatabase.execSQL(
            "UPDATE words SET syllables = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL",
            arrayOf<Any>(encodeStringArray(syllables), now, wordId),
        )
    }

    /**
     * 按复习规则挑单词，返回主键列表。
     *
     * 两层规则的区别只在「难度」与「复习时间」谁排前面：
     * - [LAYER_HARD]  难度降序打头 —— 专挑最难的词；
     * - [LAYER_STALE] 复习时间升序打头 —— 专挑最久没碰的词。
     *
     * 后面几层两者相同：含义条数少的先来 → 含义字数少的先来 → 字母序 → 编号序。
     * 「含义条数 / 字数」需要 JOIN 含义表现算，所以这句 SQL 会做一次临时排序；
     * 实测一万级词库约 25 毫秒，而它每局只跑一次，完全够用。
     */
    fun pickWords(limit: Int, exclude: List<Long>, layer: Int): List<Long> {
        if (limit <= 0) return emptyList()
        // 排除列表拼成 "?,?,?"，值仍走占位符绑定。
        val excludeClause = if (exclude.isEmpty()) "" else
            " AND w.id NOT IN (${exclude.joinToString(",") { "?" }})"
        // 两层规则只有前两项顺序不同。
        val primaryOrder = if (layer == LAYER_HARD) {
            "w.difficulty DESC, w.reviewed_at ASC"
        } else {
            "w.reviewed_at ASC, w.difficulty DESC"
        }
        val sql = """
            SELECT w.id
            FROM words w
            LEFT JOIN meanings m ON m.word_id = w.id AND m.deleted_at IS NULL
            WHERE w.deleted_at IS NULL$excludeClause
            GROUP BY w.id
            ORDER BY $primaryOrder,
                     COUNT(m.id) ASC,
                     COALESCE(SUM(LENGTH(m.definition)), 0) ASC,
                     w.spelling COLLATE NOCASE ASC,
                     w.id ASC
            LIMIT ?
        """.trimIndent()
        val args = (exclude.map { it.toString() } + limit.toString()).toTypedArray()
        val ids = mutableListOf<Long>()
        readableDatabase.rawQuery(sql, args).use { cursor ->
            while (cursor.moveToNext()) ids.add(cursor.getLong(0))
        }
        // 把命中主键补齐拼写写进单日日志：复查时直接看到「当时按规则选出了哪几个词」。
        // 排序规则属于静态逻辑，这里连同层名一起记下，配 Dart 侧 ReviewFlow 的
        // 「为什么调这一层」上下文日志，就能完整还原当时的选词现场。
        if (ids.isNotEmpty()) {
            // 第二次小查询只为拿拼写；词量通常只有几十个，代价可以忽略。
            val placeholders = ids.joinToString(",") { "?" }
            val spellingById = HashMap<Long, String>()
            readableDatabase.rawQuery(
                "SELECT id, spelling FROM words WHERE deleted_at IS NULL AND id IN ($placeholders)",
                ids.map { it.toString() }.toTypedArray(),
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    spellingById[cursor.getLong(0)] = cursor.getString(1)
                }
            }
            // 两层规则的差异只在「难度」与「复习时间」谁先，日志把完整规则也写全。
            val layerName = if (layer == LAYER_HARD) "hard(难度优先)" else "stale(久未复习优先)"
            val rule = if (layer == LAYER_HARD) {
                "难度降序→复习时间升序→含义条数升序→含义字数升序→字母序→编号序"
            } else {
                "复习时间升序→难度降序→含义条数升序→含义字数升序→字母序→编号序"
            }
            val picked = ids.joinToString(",") { id -> "${spellingById[id] ?: "?"}($id)" }
            AppLog.i(
                "review",
                "选词 层=$layerName limit=$limit exclude=${exclude.size} 规则=$rule 命中=[$picked]",
            )
        }
        return ids
    }

    // -----------------------------------------------------------------------
    // 复习词库
    // -----------------------------------------------------------------------

    /** 取某天最新的一条词库；没有则返回 null。 */
    fun getLatestWordSet(date: String): Map<String, Any?>? {
        readableDatabase.query(
            "word_sets", null, "date = ? AND deleted_at IS NULL", arrayOf(date),
            null, null, "id DESC", "1",
        ).use { cursor ->
            if (!cursor.moveToFirst()) return null
            return linkedMapOf(
                "id" to cursor.getLong(cursor.getColumnIndexOrThrow("id")),
                "word_count" to cursor.getInt(cursor.getColumnIndexOrThrow("word_count")),
                "today_word_ids" to decodeLongArray(
                    cursor.getString(cursor.getColumnIndexOrThrow("today_word_ids")),
                ),
                "tomorrow_word_ids" to decodeLongArray(
                    cursor.getString(cursor.getColumnIndexOrThrow("tomorrow_word_ids")),
                ),
                "date" to cursor.getString(cursor.getColumnIndexOrThrow("date")),
            )
        }
    }

    /** 新建一条词库；返回主键。 */
    fun createWordSet(
        wordCount: Int,
        todayWordIds: List<Long>,
        tomorrowWordIds: List<Long>,
        date: String,
    ): Long {
        val now = System.currentTimeMillis()
        val id = writableDatabase.insertOrThrow(
            "word_sets",
            null,
            ContentValues().apply {
                put("word_count", wordCount.coerceAtLeast(0))
                put("today_word_ids", encodeLongArray(todayWordIds))
                put("tomorrow_word_ids", encodeLongArray(tomorrowWordIds))
                put("date", date)
                put("created_at", now)
                put("updated_at", now)
            },
        )
        // 建库落成记录汇总：今天/明天各几个；明细由上面的 pickWords 按层逐条记下。
        AppLog.i(
            "review",
            "建词库 date=$date wordCount=$wordCount today=${todayWordIds.size} 个 tomorrow=${tomorrowWordIds.size} 个",
        )
        return id
    }

    // -----------------------------------------------------------------------
    // 会话
    // -----------------------------------------------------------------------

    /** 取某模块某天最新的一条会话；没有则返回 null。 */
    fun getLatestSession(module: String, date: String): Map<String, Any?>? =
        querySession("module = ? AND date = ? AND deleted_at IS NULL", arrayOf(module, date))

    /** 取某模块某天「已完成的主线会话」；用于判断今日任务过没过关。 */
    fun getCompletedDailySession(module: String, date: String): Map<String, Any?>? =
        querySession(
            "module = ? AND date = ? AND kind = ? AND status = ? AND deleted_at IS NULL",
            arrayOf(module, date, KIND_DAILY.toString(), STATUS_COMPLETED.toString()),
        )

    /** 会话查询的统一实现，永远取 id 最大的那一条。 */
    private fun querySession(where: String, args: Array<String>): Map<String, Any?>? {
        readableDatabase.query("sessions", null, where, args, null, null, "id DESC", "1")
            .use { cursor ->
                if (!cursor.moveToFirst()) return null
                return readSessionRow(cursor)
            }
    }

    /** 把会话表的一行游标读成 Map。 */
    private fun readSessionRow(cursor: Cursor): Map<String, Any?> = linkedMapOf(
        "id" to cursor.getLong(cursor.getColumnIndexOrThrow("id")),
        "module" to cursor.getString(cursor.getColumnIndexOrThrow("module")),
        "kind" to cursor.getInt(cursor.getColumnIndexOrThrow("kind")),
        "status" to cursor.getInt(cursor.getColumnIndexOrThrow("status")),
        "word_set_id" to cursor.getLongOrNull("word_set_id"),
        // items 的元素形状因模块而异（数字或数字对），原样交给 Dart 解析。
        "items" to cursor.getString(cursor.getColumnIndexOrThrow("items")),
        "cursor" to cursor.getInt(cursor.getColumnIndexOrThrow("cursor")),
        "elapsed" to cursor.getInt(cursor.getColumnIndexOrThrow("elapsed")),
        "date" to cursor.getString(cursor.getColumnIndexOrThrow("date")),
        "created_at" to cursor.getLong(cursor.getColumnIndexOrThrow("created_at")),
        "updated_at" to cursor.getLong(cursor.getColumnIndexOrThrow("updated_at")),
    )

    /**
     * 取今天全部模块的进度状态，供首页一次性渲染四张卡片。
     *
     * 每个模块返回：最新一条会话的类型与状态、今日主线过没过关、
     * 以及「本局做到第几个 / 一共几个」用来画进度条。
     */
    fun getTodaySessionStates(date: String): List<Map<String, Any?>> {
        val states = mutableListOf<Map<String, Any?>>()
        val db = readableDatabase
        // 先拿到今天出现过的全部模块名。
        val modules = mutableListOf<String>()
        db.rawQuery(
            "SELECT DISTINCT module FROM sessions WHERE date = ? AND deleted_at IS NULL ORDER BY module ASC",
            arrayOf(date),
        ).use { cursor -> while (cursor.moveToNext()) modules.add(cursor.getString(0)) }

        for (module in modules) {
            val latest = getLatestSession(module, date) ?: continue
            val dailyCompleted = getCompletedDailySession(module, date) != null
            // 数据列表的长度就是本局总题数。
            // items 是从用户导入备份里带进来的，可能缺失或损坏——首页渲染不能
            // 因为一条坏会话而整个白屏。解析失败时把 total 记为 0（视为"已读完"），
            // 而不是抛 JSONException。
            val total = runCatching {
                JSONArray(latest["items"] as? String ?: "").length()
            }.getOrDefault(0).coerceAtLeast(0)
            states.add(
                linkedMapOf(
                    "module" to module,
                    "kind" to latest["kind"],
                    "status" to latest["status"],
                    "daily_completed" to dailyCompleted,
                    "cursor" to latest["cursor"],
                    "total" to total,
                ),
            )
        }
        return states
    }

    /** 新建一局会话；返回主键。 */
    fun createSession(
        module: String,
        kind: Int,
        wordSetId: Long?,
        itemsJson: String,
        date: String,
    ): Long {
        require(module.isNotBlank()) { "会话模块不能为空" }
        require(kind == KIND_DAILY || kind == KIND_REINFORCE) { "不支持的会话类型：$kind" }
        val now = System.currentTimeMillis()
        return writableDatabase.insertOrThrow(
            "sessions",
            null,
            ContentValues().apply {
                put("module", module)
                put("kind", kind)
                put("status", STATUS_ACTIVE)
                if (wordSetId == null) putNull("word_set_id") else put("word_set_id", wordSetId)
                put("items", itemsJson.ifBlank { "[]" })
                put("cursor", 0)
                put("elapsed", 0)
                put("date", date)
                put("created_at", now)
                put("updated_at", now)
            },
        )
    }

    /** 保存一局的进度：做到第几条、已经花了多少秒。 */
    fun updateSessionProgress(id: Long, cursor: Int, elapsed: Int) {
        writableDatabase.update(
            "sessions",
            ContentValues().apply {
                put("cursor", cursor.coerceAtLeast(0))
                put("elapsed", elapsed.coerceAtLeast(0))
                put("updated_at", System.currentTimeMillis())
            },
            "id = ?",
            arrayOf(id.toString()),
        )
    }

    /** 给一局判成败：完成 / 中断 / 失败。 */
    fun finishSession(id: Long, status: Int, cursor: Int?, elapsed: Int?) {
        require(status in listOf(STATUS_COMPLETED, STATUS_ABORTED, STATUS_FAILED)) {
            "结算状态只能是完成、中断或失败：$status"
        }
        writableDatabase.update(
            "sessions",
            ContentValues().apply {
                put("status", status)
                if (cursor != null) put("cursor", cursor.coerceAtLeast(0))
                if (elapsed != null) put("elapsed", elapsed.coerceAtLeast(0))
                put("updated_at", System.currentTimeMillis())
            },
            "id = ?",
            arrayOf(id.toString()),
        )
    }

    /**
     * 中断「不是今天」的进行中会话，返回被中断的局数。
     *
     * 跨天后昨天没打完的局挂着没有意义——今天有今天的词库。
     * 今天的进度完整保留。
     */
    fun abortStaleSessions(today: String): Int {
        val now = System.currentTimeMillis()
        return writableDatabase.update(
            "sessions",
            ContentValues().apply {
                put("status", STATUS_ABORTED)
                put("updated_at", now)
            },
            "status = ? AND date <> ? AND deleted_at IS NULL",
            arrayOf(STATUS_ACTIVE.toString(), today),
        )
    }

    /**
     * 中断全部进行中的会话。
     *
     * 用户改了「每日复习」数量时调用：今天这批词的数量变了，
     * 正在进行的每一局都对不上新的词库，只能整体作废重来。
     */
    fun abortActiveSessions(): Int {
        val now = System.currentTimeMillis()
        return writableDatabase.update(
            "sessions",
            ContentValues().apply {
                put("status", STATUS_ABORTED)
                put("updated_at", now)
            },
            "status = ? AND deleted_at IS NULL",
            arrayOf(STATUS_ACTIVE.toString()),
        )
    }

    // -----------------------------------------------------------------------
    // 会话记录
    // -----------------------------------------------------------------------

    /**
     * 记一次点击。
     *
     * 每点一次就写一条，不论对错。正因为「每一次点击都留痕」，
     * 中途退出后的现场（做到第几条、哪几个候选已经点错了）
     * 全都能从这张表反查出来，不再需要一份又大又脆的页面快照。
     *
     * 注意：这里**不动**单词的难度和复习时间——那是「这个词整个过完一遍」
     * 之后的事，由 [settleWord] 统一结算。
     */
    fun addRecord(
        sessionId: Long,
        wordId: Long,
        meaningId: Long?,
        input: String,
        result: Int,
    ): Long {
        require(result == 0 || result == 1) { "复习结果只能是 1（对）或 0（错）：$result" }
        val now = System.currentTimeMillis()
        return writableDatabase.insertOrThrow(
            "session_records",
            null,
            ContentValues().apply {
                put("session_id", sessionId)
                put("word_id", wordId)
                if (meaningId == null) putNull("meaning_id") else put("meaning_id", meaningId)
                put("input", input)
                put("result", result)
                put("date", localDateString(now))
                put("created_at", now)
                put("updated_at", now)
            },
        )
    }

    /**
     * 结算一个单词：更新它的难度，必要时推进复习时间。
     *
     * 在「这个词在本局里已经整个过完一遍」时调用一次。
     *
     * 判定口径：**本局本词有没有点错过**。一次都没错才算这一轮答对。
     *
     * 难度规则：
     * - 答错 → 难度 +1；
     * - 答对 → 连对次数 +1；连对次数每满 5 的倍数，难度 -1（最低 0）。
     *
     * 复习时间规则：只有主线会话（[updateReviewedAt] 为 true）才推进。
     * 巩固局练的是「今天一半 + 明天一半」，若把明天那批词的复习时间也推进了，
     * 明天按规则选词就选不到它们了。
     *
     * 连对次数不再单独存字段，而是从记录表现算：按会话倒着看每一轮的表现，
     * 数出连续答对了几轮。
     */
    fun settleWord(sessionId: Long, wordId: Long, updateReviewedAt: Boolean): Map<String, Any?> {
        val db = writableDatabase
        db.beginTransaction()
        try {
            val now = System.currentTimeMillis()
            // 本局本词只要出现过一条 result=0，这一轮就算答错。
            val isCorrect = db.rawQuery(
                "SELECT COUNT(*) FROM session_records " +
                    "WHERE session_id = ? AND word_id = ? AND result = 0 AND deleted_at IS NULL",
                arrayOf(sessionId.toString(), wordId.toString()),
            ).use { cursor -> cursor.moveToFirst() && cursor.getInt(0) == 0 }

            val difficultyBefore = readWordDifficulty(db, wordId)
            // 连对次数：包含刚刚结算的这一轮。
            val streak = if (isCorrect) countCorrectStreak(db, wordId) else 0
            val difficultyAfter = when {
                !isCorrect -> difficultyBefore + 1
                streak > 0 && streak % 5 == 0 -> (difficultyBefore - 1).coerceAtLeast(0)
                else -> difficultyBefore
            }

            // 只作用在**仍然存活**的单词上：若这个词已被删除（软删除），
            // 一律不再结算——把难度/复习时间也算到一行用户已删的数据上，
            // 既污染词库又可能在下次选词或统计时把「死词」重现出来。
            db.update(
                "words",
                ContentValues().apply {
                    put("difficulty", difficultyAfter)
                    // 复习时间只有主线会话才推进。
                    if (updateReviewedAt) put("reviewed_at", now)
                    // 字段变了就刷新修改时间，与全表口径一致。
                    put("updated_at", now)
                },
                "id = ? AND deleted_at IS NULL",
                arrayOf(wordId.toString()),
            )
            db.setTransactionSuccessful()
            return linkedMapOf(
                "is_correct" to isCorrect,
                "streak" to streak,
                "difficulty_before" to difficultyBefore,
                "difficulty_after" to difficultyAfter,
                "reviewed_at" to if (updateReviewedAt) now else null,
            )
        } finally {
            db.endTransaction()
        }
    }

    /** 读取单词当前难度；单词不存在时按 0 处理。 */
    private fun readWordDifficulty(db: SQLiteDatabase, wordId: Long): Int {
        db.query("words", arrayOf("difficulty"), "id = ?", arrayOf(wordId.toString()), null, null, null)
            .use { cursor -> return if (cursor.moveToFirst()) cursor.getInt(0) else 0 }
    }

    /**
     * 数出一个单词最近连续答对了几轮。
     *
     * 「一轮」= 这个词在某一局会话里的整体表现：只要那一局里错过一次，这一轮就算错。
     * 所以这里按会话分组，每组取最差成绩（MIN(result)），再从最近的一局往回数。
     *
     * 用 MAX(id) 而不是 session_id 排序：会话 id 未必与答题先后一致（比如同一天
     * 先后开了两个模块），用「这一组里最后一条记录的 id」才是真正的时间顺序。
     */
    private fun countCorrectStreak(db: SQLiteDatabase, wordId: Long): Int {
        var streak = 0
        db.rawQuery(
            """
            SELECT MIN(result) AS worst
            FROM session_records
            WHERE word_id = ? AND deleted_at IS NULL
            GROUP BY session_id
            ORDER BY MAX(id) DESC
            LIMIT ?
            """.trimIndent(),
            arrayOf(wordId.toString(), STREAK_SCAN_LIMIT.toString()),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                // 碰到第一轮答错就断链，不用再往回看。
                if (cursor.getInt(0) != 1) break
                streak += 1
            }
        }
        return streak
    }

    /**
     * 读取一局会话的全部记录，供中途退出后还原现场。
     *
     * 页面拿到它就能算出：哪几条已经答完了、当前这条点错过哪些候选。
     */
    fun getSessionRecords(sessionId: Long): List<Map<String, Any?>> {
        val records = mutableListOf<Map<String, Any?>>()
        readableDatabase.query(
            "session_records",
            arrayOf("id", "word_id", "meaning_id", "input", "result"),
            "session_id = ? AND deleted_at IS NULL",
            arrayOf(sessionId.toString()),
            null, null, "id ASC",
        ).use { cursor ->
            while (cursor.moveToNext()) {
                records.add(
                    linkedMapOf(
                        "id" to cursor.getLong(0),
                        "word_id" to cursor.getLong(1),
                        "meaning_id" to if (cursor.isNull(2)) null else cursor.getLong(2),
                        "input" to cursor.getString(3),
                        "result" to cursor.getInt(4),
                    ),
                )
            }
        }
        return records
    }

    /**
     * 今天「一次做对」过的不同单词数。
     *
     * 口径：这个词今天有过记录，且今天从来没在任何一局里点错过。
     * 首页副标题「今日复习 X / 目标」用的就是它。
     */
    fun getTodayCorrectWordCount(date: String): Int {
        readableDatabase.rawQuery(
            """
            SELECT COUNT(DISTINCT r.word_id)
            FROM session_records r
            WHERE r.date = ? AND r.deleted_at IS NULL
              AND NOT EXISTS (
                SELECT 1 FROM session_records b
                WHERE b.date = r.date AND b.word_id = r.word_id
                  AND b.result = 0 AND b.deleted_at IS NULL
              )
            """.trimIndent(),
            arrayOf(date),
        ).use { cursor -> return if (cursor.moveToFirst()) cursor.getInt(0) else 0 }
    }

    /** 今天「一次做对」过的不同单词主键，供首页明细列表使用。 */
    fun getTodayCorrectWordIds(date: String): List<Long> {
        val ids = mutableListOf<Long>()
        readableDatabase.rawQuery(
            """
            SELECT DISTINCT r.word_id
            FROM session_records r
            WHERE r.date = ? AND r.deleted_at IS NULL
              AND NOT EXISTS (
                SELECT 1 FROM session_records b
                WHERE b.date = r.date AND b.word_id = r.word_id
                  AND b.result = 0 AND b.deleted_at IS NULL
              )
            ORDER BY r.word_id ASC
            """.trimIndent(),
            arrayOf(date),
        ).use { cursor -> while (cursor.moveToNext()) ids.add(cursor.getLong(0)) }
        return ids
    }

    /**
     * 按天统计单词数（每天按单词去重）。
     *
     * [correctOnly] 为 true 时只算「这一天一次都没错过」的词（首页趋势曲线的「掌握量」）；
     * 为 false 时不论对错，练了就算（打卡热力图的「复习总数」）。
     */
    fun getDailyCounts(since: String?, correctOnly: Boolean): List<Map<String, Any?>> {
        val sinceClause = if (since == null) "" else " AND r.date >= ?"
        val correctClause = if (!correctOnly) "" else """
            AND NOT EXISTS (
              SELECT 1 FROM session_records b
              WHERE b.date = r.date AND b.word_id = r.word_id
                AND b.result = 0 AND b.deleted_at IS NULL
            )
        """.trimIndent()
        val sql = """
            SELECT r.date AS date, COUNT(DISTINCT r.word_id) AS count
            FROM session_records r
            WHERE r.deleted_at IS NULL$sinceClause
            $correctClause
            GROUP BY r.date
            ORDER BY r.date ASC
        """.trimIndent()
        return readCounts(sql, if (since == null) emptyArray() else arrayOf(since), "date")
    }

    /**
     * 按月统计复习单词数（每月按单词去重）。
     *
     * 必须由 SQLite 直接按月分组，不能把每日的去重数相加——
     * 同一个词在同月的两天各拿下一次，月度只应算 1 个。
     */
    fun getMonthlyCounts(since: String?): List<Map<String, Any?>> {
        val sinceClause = if (since == null) "" else " AND substr(r.date, 1, 7) >= ?"
        val sql = """
            SELECT substr(r.date, 1, 7) AS month, COUNT(DISTINCT r.word_id) AS count
            FROM session_records r
            WHERE r.deleted_at IS NULL$sinceClause
            GROUP BY month
            ORDER BY month ASC
        """.trimIndent()
        return readCounts(sql, if (since == null) emptyArray() else arrayOf(since), "month")
    }

    /** 统计查询的统一读取：返回 [{键: 值, count: 数量}]。 */
    private fun readCounts(sql: String, args: Array<String>, keyField: String): List<Map<String, Any?>> {
        val rows = mutableListOf<Map<String, Any?>>()
        readableDatabase.rawQuery(sql, args).use { cursor ->
            while (cursor.moveToNext()) {
                rows.add(linkedMapOf(keyField to cursor.getString(0), "count" to cursor.getInt(1)))
            }
        }
        return rows
    }

    // -----------------------------------------------------------------------
    // 导入 / 导出 / 清空
    // -----------------------------------------------------------------------

    /**
     * 导出完整备份。
     *
     * 每个时间字段都导两份：
     * - `xxx_at`    人类可读的 `yyyy-MM-dd HH:mm:ss`（本地时区），方便你手工改；
     * - `xxx_at_ms` 原始毫秒时间戳，精度完整。
     *
     * 导入时若两者对得上就用毫秒（更精确），对不上说明你手工改过可读时间，
     * 那就以可读时间为准。
     */
    fun exportData(): Map<String, Any?> {
        val db = readableDatabase
        return linkedMapOf(
            "version" to 2,
            "settings" to exportRows(db, "settings"),
            "words" to exportRows(db, "words", jsonArrayColumns = setOf("confusions", "syllables")),
            "meanings" to exportRows(db, "meanings", jsonArrayColumns = setOf("confusions")),
            "word_sets" to exportRows(
                db, "word_sets",
                jsonArrayColumns = setOf("today_word_ids", "tomorrow_word_ids"),
            ),
            "sessions" to exportRows(db, "sessions", jsonArrayColumns = setOf("items")),
            "session_records" to exportRows(db, "session_records"),
        )
    }

    /** 把一整张表导成可读的行列表。 */
    private fun exportRows(
        db: SQLiteDatabase,
        table: String,
        jsonArrayColumns: Set<String> = emptySet(),
    ): List<Map<String, Any?>> {
        val rows = mutableListOf<Map<String, Any?>>()
        db.query(table, null, null, null, null, null, "id ASC").use { cursor ->
            val columns = (0 until cursor.columnCount).map { cursor.getColumnName(it) }
            while (cursor.moveToNext()) {
                val row = linkedMapOf<String, Any?>()
                for ((index, name) in columns.withIndex()) {
                    when {
                        // 时间字段导两份：可读的 + 精确的。
                        name.endsWith("_at") -> {
                            val millis = if (cursor.isNull(index)) null else cursor.getLong(index)
                            row[name] = formatExportTime(millis)
                            row["${name}_ms"] = millis
                        }
                        // JSON 数组字段还原成真正的数组，导出文件更好读。
                        name in jsonArrayColumns -> row[name] = decodeJsonValue(cursor.getString(index))
                        cursor.isNull(index) -> row[name] = null
                        cursor.getType(index) == Cursor.FIELD_TYPE_INTEGER -> row[name] = cursor.getLong(index)
                        cursor.getType(index) == Cursor.FIELD_TYPE_FLOAT -> row[name] = cursor.getDouble(index)
                        else -> row[name] = cursor.getString(index)
                    }
                }
                rows.add(row)
            }
        }
        return rows
    }

    /**
     * 导入完整备份：先清空，再整库替换。
     *
     * 只认新格式（顶层带 words / meanings 等键的对象）。主键原样保留，
     * 所以会话记录里的外键引用不会错位。
     *
     * 这一版做**逐行校验 + 容错**：单条坏数据（越界枚举、悬空外键、重复设置键）
     * 会被安全跳过或归一到合法值，绝不让一条脏行把整份备份的还原搞挂。
     * 导入绝不是「一个健壮性靠运气」的流程——用户备份来之不易。
     */
    fun importData(data: Map<*, *>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            // 整库替换：先物理清空，主键计数器一并归零，避免自增值越滚越大。
            for (table in listOf("session_records", "sessions", "word_sets", "meanings", "words", "settings")) {
                db.delete(table, null, null)
                db.delete("sqlite_sequence", "name = ?", arrayOf(table))
            }

            // 先按父→子的顺序导入，并让 importTable 收到「哪些父行真的写进去了」，
            // 这样孤儿引用（引用了不存在的主词/会话）能被识别出来直接跳过。
            // 返回每张表实际导入成功的 id 集合，交给下一个子表做外键校验。
            val wordIds = importTable(db, data["words"], "words",
                listOf("id", "spelling", "difficulty", "confusions", "syllables"),
                jsonArrayColumns = setOf("confusions", "syllables"),
                nullableIntColumns = setOf("reviewed_at"),
                // 难度只允许 ≥0，越界归一。
                intRanges = mapOf("difficulty" to (0 until Int.MAX_VALUE)))
            val meaningIds = importTable(db, data["meanings"], "meanings",
                listOf("id", "word_id", "pos", "sub_pos", "definition", "confusions", "sort"),
                jsonArrayColumns = setOf("confusions"),
                // word_id 必须真正存在，引用死了的词整条跳过。
                requiredParents = mapOf("word_id" to wordIds))
            val wordSetIds = importTable(db, data["word_sets"], "word_sets",
                listOf("id", "word_count", "today_word_ids", "tomorrow_word_ids", "date"),
                jsonArrayColumns = setOf("today_word_ids", "tomorrow_word_ids"),
                intRanges = mapOf("word_count" to (0 until Int.MAX_VALUE)))
            // 设置表按「同 key 只留最后一条活行」去重，避免唯一索引/软删并存的旧备份爆掉。
            importSettings(db, data["settings"])

            val sessionIds = importTable(db, data["sessions"], "sessions",
                listOf("id", "module", "kind", "status", "word_set_id", "items", "cursor", "elapsed", "date"),
                jsonArrayColumns = setOf("items"),
                // kind / status 是受 CHECK 约束的枚举，写成合法值而不是整体报错。
                enumColumns = mapOf(
                    "kind" to setOf(KIND_DAILY.toLong(), KIND_REINFORCE.toLong()),
                    "status" to setOf(
                        STATUS_ACTIVE.toLong(), STATUS_COMPLETED.toLong(),
                        STATUS_ABORTED.toLong(), STATUS_FAILED.toLong(),
                    ),
                ),
                intRanges = mapOf("cursor" to (0 until Int.MAX_VALUE), "elapsed" to (0 until Int.MAX_VALUE)),
                // word_set_id 可空；引用到不存在的词库（备份里被删了）时把该引用清空而不是整行报错。
                optionalParents = mapOf("word_set_id" to wordSetIds))
            importRecord(db, data["session_records"], sessionIds, wordIds, meaningIds)

            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    /** 把备份里的一张表写回，返回成功写入的主键集合；一条坏行只备记录单行而不会让整表失败。 */
    private fun importTable(
        db: SQLiteDatabase,
        raw: Any?,
        table: String,
        columns: List<String>,
        jsonArrayColumns: Set<String> = emptySet(),
        nullableIntColumns: Set<String> = emptySet(),
        intRanges: Map<String, IntRange> = emptyMap(),
        // enumColumns 的那些列值必须属于这个集合，否则该行用「合法默认」顶替。
        enumColumns: Map<String, Set<Long>> = emptyMap(),
        // requiredParents 的那些列值必须出现在给定集合里，否则整行跳过（孤儿数据不录入）。
        requiredParents: Map<String, Set<Long>> = emptyMap(),
        // optionalParents 可空引用的父集：引用存在就写，引用不存在的父行就置 NULL（不丢行）。
        optionalParents: Map<String, Set<Long>> = emptyMap(),
    ): Set<Long> {
        val importedIds = mutableSetOf<Long>()
        val rows = raw as? List<*> ?: return importedIds
        val now = System.currentTimeMillis()
        for (item in rows) {
            val row = item as? Map<*, *> ?: continue
            // 孤儿校验：父表还没写入的引用直接丢这一行，不拖累其它正常行。
            var orphan = false
            for ((column, validIds) in requiredParents) {
                val value = (row[column] as? Number)?.toLong()
                if (value != null && value !in validIds) { orphan = true; break }
            }
            if (orphan) continue

            val values = ContentValues()
            for (column in columns) {
                // 备份里没带这一列，就让 SQLite 用建表时的 DEFAULT 兜底，
                // 而不是硬塞一个 null（对 NOT NULL DEFAULT 的列会直接撞约束）。
                if (!row.containsKey(column)) continue
                val value = row[column]
                when {
                    column in jsonArrayColumns -> values.put(column, encodeJsonValue(value))
                    else -> putScalarOrNull(values, column, value, intRanges, enumColumns)
                }
            }
            // 可空引用落空：父表里没有对应行时把该外键置 NULL，保留这一行（例：词库被删的会话）。
            for ((column, validIds) in optionalParents) {
                val ref = (row[column] as? Number)?.toLong()
                if (ref != null && ref !in validIds) values.putNull(column)
            }
            // 可空的时间字段（如单词的复习时间）单独处理，0 与缺失都视为「还没发生」。
            for (column in nullableIntColumns) {
                val millis = resolveImportTime(row, column)
                if (millis == null || millis == 0L) values.putNull(column) else values.put(column, millis)
            }
            // 三个通用时间戳统一走「可读时间 vs 毫秒」的比对规则。
            values.put("created_at", resolveImportTime(row, "created_at") ?: now)
            values.put("updated_at", resolveImportTime(row, "updated_at") ?: now)
            val deletedAt = resolveImportTime(row, "deleted_at")
            if (deletedAt == null || deletedAt == 0L) values.putNull("deleted_at") else values.put("deleted_at", deletedAt)

            // 单行仍可能因残余脏数据（如某列非空但值为 null）撞约束。
            // 只跳过这一行，绝不让一道坏行把整份备份还原搞挂。
            try {
                val insertedId = db.insertOrThrow(table, null, values)
                importedIds.add(insertedId)
            } catch (error: android.database.SQLException) {
                android.util.Log.w("WordsDatabase", "导入跳过一行非法数据（$table）：$error")
            }
        }
        return importedIds
    }

    /** 设置表专用：同 key 只保留最后一条活着的行，避免备份里新旧同 key 并存时触发唯一索引。 */
    private fun importSettings(db: SQLiteDatabase, raw: Any?) {
        val rows = raw as? List<*> ?: return
        val now = System.currentTimeMillis()
        // 收集每个 key 的「活行」（未标删除）里 key 去重，最后一条有效值胜出。
        // 与 getSettings 的口径一致：都只用 deleted_at IS NULL 的那行。
        val seenKeys = linkedSetOf<String>()
        // 先正向收集所有待导入的 key，遇到同一个 key 的新行时把旧行标记为软删除，
        // 保证唯一索引（settings_key WHERE deleted_at IS NULL）永不冲突。
        for (item in rows) {
            val row = item as? Map<*, *> ?: continue
            val key = row["key"]?.toString() ?: continue
            // 重复的活 key：若这一行是新的，先把上一行软删除。
            if (!seenKeys.add(key)) {
                db.execSQL(
                    "UPDATE settings SET deleted_at = ? WHERE key = ? AND deleted_at IS NULL",
                    arrayOf<Any>(now, key),
                )
            }
            // type 必须在合法枚举内，否则塞进一行自重：SQLite 的 CHECK 会让 insert 崩。
            val type = row["type"]?.toString()
            val safeType = if (type in setOf("string", "int", "double", "bool", "json")) type else "string"
            val created = resolveImportTime(row, "created_at") ?: now
            val updated = resolveImportTime(row, "updated_at") ?: created
            val deleted = resolveImportTime(row, "deleted_at")
            val values = ContentValues().apply {
                (row["id"] as? Number)?.let { put("id", it.toLong()) }
                put("key", key)
                put("value", row["value"]?.toString().orEmpty())
                put("type", safeType)
                put("created_at", created)
                put("updated_at", updated)
                if (deleted == null || deleted == 0L) putNull("deleted_at") else put("deleted_at", deleted)
            }
            db.insert("settings", null, values)
        }
    }

    /** 会话记录专用导入：任何外键（会话/词/含义）悬空都直接丢该行，保证引用一致性。 */
    private fun importRecord(
        db: SQLiteDatabase,
        raw: Any?,
        sessionIds: Set<Long>,
        wordIds: Set<Long>,
        meaningIds: Set<Long>,
    ) {
        val rows = raw as? List<*> ?: return
        val now = System.currentTimeMillis()
        for (item in rows) {
            val row = item as? Map<*, *> ?: continue
            val sessionId = (row["session_id"] as? Number)?.toLong() ?: continue
            val wordId = (row["word_id"] as? Number)?.toLong() ?: continue
            val meaningId = (row["meaning_id"] as? Number)?.toLong()
            // 外键必须指向已导入的行，指向失败则跳过该记录。
            if (sessionId !in sessionIds || wordId !in wordIds) continue
            if (meaningId != null && meaningId !in meaningIds) continue
            // 读取真正对应的 result。缺失或不在 {0,1} 的值都按「错误(0)」兜底——
            // 宁可让一个词被当作答错而多复习一次，也不能把一条脏记录算成「答对」去虚增掌握量。
            val result = (row["result"] as? Number)?.toInt() ?: 0
            val values = ContentValues().apply {
                (row["id"] as? Number)?.let { put("id", it.toLong()) }
                put("session_id", sessionId)
                put("word_id", wordId)
                if (meaningId == null) putNull("meaning_id") else put("meaning_id", meaningId)
                put("input", row["input"]?.toString().orEmpty())
                put("result", if (result == 1) 1 else 0)
                put("date", row["date"]?.toString() ?: "1970-01-01")
                put("created_at", resolveImportTime(row, "created_at") ?: now)
                put("updated_at", resolveImportTime(row, "updated_at") ?: now)
                val deletedAt = resolveImportTime(row, "deleted_at")
                if (deletedAt == null || deletedAt == 0L) putNull("deleted_at") else put("deleted_at", deletedAt)
            }
            db.insert("session_records", null, values)
        }
    }

    /** 把列值按「整数值范围/枚举白名单」写进 ContentValues；越界回落到 [intRanges]/[enumColumns] 给的默认。 */
    private fun putScalarOrNull(
        values: ContentValues,
        column: String,
        value: Any?,
        intRanges: Map<String, IntRange>,
        enumColumns: Map<String, Set<Long>>,
    ) {
        val numeric = value as? Number
        when {
            value == null -> values.putNull(column)
            value is Boolean -> values.put(column, if (value) 1L else 0L)
            numeric != null -> {
                val long = numeric.toLong()
                // 枚举白名单：值不在集合就回落到集合的第一个合法值，避免撞 CHECK。
                val enumSet = enumColumns[column]
                if (enumSet != null) {
                    // 显式 Long 避免 ContentValues.put 的多个数字重载无法判别。
                    val coerced: Long = if (long in enumSet) long else enumSet.first()
                    values.put(column, coerced)
                    return
                }
                val range = intRanges[column]
                if (range != null) {
                    val lo: Long = range.first.toLong()
                    val hi: Long = (range.last - 1).toLong()
                    val clamped: Long = long.coerceIn(lo, hi)
                    values.put(column, clamped)
                    return
                }
                // 整数值写 Long，非整数值写 Double，类型与原值一致。
                if (numeric.toDouble() == long.toDouble()) {
                    values.put(column, long)
                } else {
                    values.put(column, numeric.toDouble())
                }
            }
            else -> values.put(column, value.toString())
        }
    }

    /**
     * 决定一个时间字段最终写入什么值。
     *
     * 备份里同一个时间有两份：可读字符串和毫秒时间戳。
     * - 两者指向同一秒 → 用毫秒（精度更高）；
     * - 对不上 → 说明你手工改过可读时间，以可读时间为准；
     * - 只有其中一份 → 用有的那份。
     */
    private fun resolveImportTime(row: Map<*, *>, column: String): Long? {
        val millis = (row["${column}_ms"] as? Number)?.toLong()
        val text = (row[column] as? String)?.trim()
        val fromText = if (text.isNullOrEmpty()) null else parseExportTime(text)
        // 只有一份时没得选。
        if (millis == null) return fromText
        if (fromText == null) return millis
        // 精确到秒相等，说明可读时间没被改过，用毫秒保留完整精度。
        return if (millis / 1000 == fromText / 1000) millis else fromText
    }

    /** 清空全部业务数据；设置与离线语音由调用方另行处理。 */
    fun clearAll() {
        val db = writableDatabase
        db.beginTransaction()
        try {
            for (table in listOf("session_records", "sessions", "word_sets", "meanings", "words")) {
                db.delete(table, null, null)
                db.delete("sqlite_sequence", "name = ?", arrayOf(table))
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    // -----------------------------------------------------------------------
    // 小工具
    // -----------------------------------------------------------------------

    /** 当天的 yyyy-MM-dd（本地时区）。 */
    fun localDateString(millis: Long = System.currentTimeMillis()): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(millis))

    /** 毫秒时间戳转成人类可读的本地时间；没有时间时返回 null。 */
    private fun formatExportTime(millis: Long?): String? {
        if (millis == null || millis == 0L) return null
        return SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(millis))
    }

    /** 把可读时间解析回毫秒时间戳；格式不对时返回 null 而不是抛错。 */
    private fun parseExportTime(text: String): Long? = try {
        SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).parse(text)?.time
    } catch (error: java.text.ParseException) {
        null
    }

    /** 把 JSON 数组文本读成字符串列表；内容损坏时返回空列表而不是让页面崩溃。 */
    private fun decodeStringArray(text: String?): List<String> {
        if (text.isNullOrBlank()) return emptyList()
        return try {
            val array = JSONArray(text)
            List(array.length()) { array.getString(it) }
        } catch (error: org.json.JSONException) {
            emptyList()
        }
    }

    /** 把 JSON 数组文本读成数字列表。 */
    private fun decodeLongArray(text: String?): List<Long> {
        if (text.isNullOrBlank()) return emptyList()
        return try {
            val array = JSONArray(text)
            List(array.length()) { array.getLong(it) }
        } catch (error: org.json.JSONException) {
            emptyList()
        }
    }

    /** 把任意列表编码成 JSON 数组文本。 */
    private fun encodeStringArray(raw: Any?): String {
        val list = raw as? List<*> ?: return "[]"
        val array = JSONArray()
        for (item in list) if (item != null) array.put(item.toString())
        return array.toString()
    }

    /** 把数字列表编码成 JSON 数组文本。 */
    private fun encodeLongArray(values: List<Long>): String {
        val array = JSONArray()
        for (value in values) array.put(value)
        return array.toString()
    }

    /**
     * 导出时把 JSON 文本还原成普通的 List / Map，让备份文件更好读。
     *
     * 必须转成 Kotlin 原生集合，不能直接回传 JSONArray——MethodChannel 的
     * 标准编解码器只认识 null / 布尔 / 数字 / 字符串 / List / Map，
     * 塞一个 JSONArray 进去会在过桥时直接抛异常。
     */
    private fun decodeJsonValue(text: String?): Any? {
        if (text.isNullOrBlank()) return null
        return try {
            when {
                text.startsWith("[") -> jsonArrayToList(JSONArray(text))
                text.startsWith("{") -> jsonObjectToMap(JSONObject(text))
                else -> text
            }
        } catch (error: org.json.JSONException) {
            text
        }
    }

    /** 把 JSONArray 递归转成普通 List。 */
    private fun jsonArrayToList(array: JSONArray): List<Any?> = List(array.length()) { index ->
        when (val item = array.get(index)) {
            JSONObject.NULL -> null
            is JSONArray -> jsonArrayToList(item)
            is JSONObject -> jsonObjectToMap(item)
            else -> item
        }
    }

    /** 把 JSONObject 递归转成普通 Map。 */
    private fun jsonObjectToMap(json: JSONObject): Map<String, Any?> {
        val map = linkedMapOf<String, Any?>()
        for (key in json.keys()) {
            map[key] = when (val item = json.get(key)) {
                JSONObject.NULL -> null
                is JSONArray -> jsonArrayToList(item)
                is JSONObject -> jsonObjectToMap(item)
                else -> item
            }
        }
        return map
    }

    /** 导入时把备份里的数组/对象编码回 JSON 文本。 */
    private fun encodeJsonValue(value: Any?): String = when (value) {
        null -> "[]"
        is String -> value
        is List<*> -> JSONArray(value).toString()
        is Map<*, *> -> JSONObject(value).toString()
        else -> value.toString()
    }

    /** 读取可空的整数列；列为 NULL 时返回 null 而不是 0。 */
    private fun Cursor.getLongOrNull(column: String): Long? {
        val index = getColumnIndexOrThrow(column)
        return if (isNull(index)) null else getLong(index)
    }

    /** 读取可空的文本列。 */
    private fun Cursor.getStringOrNull(column: String): String? {
        val index = getColumnIndexOrThrow(column)
        return if (isNull(index)) null else getString(index)
    }
}
