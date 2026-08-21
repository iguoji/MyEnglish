package com.example.my_english

import android.content.ContentValues
// Context 用来确定数据库文件属于哪个 App。
import android.content.Context
// SQLiteDatabase 提供事务、查询和写入 API。
import android.database.sqlite.SQLiteDatabase
// SQLiteOpenHelper 负责数据库创建、版本升级和连接复用。
import android.database.sqlite.SQLiteOpenHelper
// JSONArray 负责还原 SQLite TEXT 列中保存的字符串数组。
import org.json.JSONArray
// JSONObject 负责在未来字段传入 JSON 对象时将其安全序列化到 TEXT 列。
import org.json.JSONObject
// ParsePosition 用于确保日期文本被完整解析，不接受只匹配前半段的错误日期。
import java.text.ParsePosition
// SimpleDateFormat 与 Date 负责把当前时刻格式化成 'yyyy-MM-dd' 本地日期。
import java.text.SimpleDateFormat
// Date 表示当前时刻，配合 SimpleDateFormat 取本地日期。
import java.util.Date
// Locale 决定日期格式化的区域（数字与顺序），不影响 yyyy-MM-dd 结构。
import java.util.Locale

/**
 * word/meaning 本地 SQLite 数据库。
 *
 * 负责 SQLite 建表、升级和业务数据读写；导入导出数据由 Dart 解析后传入。
 */
class WordsDatabase(context: Context) :
    SQLiteOpenHelper(context, databaseName, null, databaseVersion) {

    companion object {
        // 数据库文件保存在 Android App 私有目录，卸载应用时由系统删除。
        private const val databaseName = "my_english.db"
        // 版本 3 新增 group 与 groupMember 两张表，让单词-分组关系持久化。
        // 版本 4 新增 record 表，记录单词默写结果并驱动难度变化。
        // 版本 5 不再新建表，仅补强 record 表的创建时机（onOpen 兜底建表），
        // 解决「库已升到某版本，但 record 表因历史升级路径缺失」导致写入静默失败的问题。
        // 版本 6 新增默写候选项缓存表，让每道拼写/释义题长期复用相同干扰项。
        // 版本 7 新增学习会话表，保存随身听和默写尚未完成的列表与页面进度。
        // 版本 8 为候选缓存增加正确答案位置，使四个候选的完整顺序可以长期恢复。
        // 版本 9 以 README 为业务字段标准，重建词库并统一 JSON/SQLite 命名。
        // 版本 10 新增每日公共复习词单表，四种复习模式当天共用同一批单词。
        // 版本 11 为每日词单增加选词规则版本，规则变化后旧顺序只重建一次。
        private const val databaseVersion = 11
    }

    // 每次打开连接时启用外键约束，保证 meaning.word_id 必须指向真实 word。
    override fun onConfigure(db: SQLiteDatabase) {
        // 先执行 SQLiteOpenHelper 标准配置。
        super.onConfigure(db)
        // Android SQLite 默认可能关闭外键，这里显式开启。
        db.setForeignKeyConstraintsEnabled(true)
    }

    // 数据库首次创建时建立完整结构。
    override fun onCreate(db: SQLiteDatabase) {
        // 创建允许重复 spelling 的 words 表。
        createWordsTable(db)
        // 创建关联 meanings 表。
        createMeaningsTable(db)
        // 创建分组业务表；界面排序由下一张内部表单独保存。
        createGroupsTable(db)
        // 分组顺序是界面内部状态，不混入 README 定义的 group 业务字段。
        createGroupPositionsTable(db)
        // 创建单词-分组关联表（多对多）。
        createGroupMembersTable(db)
        // 创建单词默写记录表（每次默写一条，允许同一天重复复习并驱动难度变化）。
        createRecordTable(db)
        // 创建默写候选项缓存表。
        createDictationOptionCacheTable(db)
        // 创建未完成学习会话表。
        createLearningSessionTable(db)
        // 创建四种复习模式当天共用的固定词单表。
        createDailyReviewPlanTable(db)
        // 最后建立查询索引。
        createIndexes(db)
    }

    // 按数据库版本补齐增量结构。
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // 用户已确认旧词库可从 words.json 重新导入；版本 9 直接重建可避免
        // 同时维护 sort_index/definitions_json 等历史别名与新字段的复杂迁移。
        if (oldVersion < 9 && newVersion >= 9) {
            rebuildVocabularySchema(db)
        }
        // 版本 10 只增加独立辅助表，不改动现有词库和复习记录。
        if (oldVersion < 10 && newVersion >= 10) createDailyReviewPlanTable(db)
        // 版本 11 只给辅助表补一列；默认 0 代表旧规则，词库和复习记录不受影响。
        if (oldVersion < 11 && newVersion >= 11) {
            ensureDailyReviewPlanSelectionVersionColumn(db)
        }
    }

    /**
     * 每次打开数据库连接时兜底：只要 record 表缺失就补建。
     *
     * 这是防止「库版本已升级，但 record 表因历史原因没建出来」的最后一道保险，
     * 避免 addDictationRecord 因 no such table 静默失败、默写数据无法持久化。
     * onCreate / onUpgrade 之后必然走到这里，配合 CREATE TABLE IF NOT EXISTS 重复调用也安全。
     */
    override fun onOpen(db: SQLiteDatabase) {
        // 先执行 SQLiteOpenHelper 标准打开流程。
        super.onOpen(db)
        // 兜底补建 record 表（建表语句已用 IF NOT EXISTS，存在则无操作）。
        createRecordTable(db)
        // 同样兜底补建候选缓存表，覆盖任何历史升级遗漏。
        createDictationOptionCacheTable(db)
        // CREATE TABLE IF NOT EXISTS 不会给旧表补字段，因此再单独确认版本 8 的位置列。
        ensureDictationOptionCorrectIndexColumn(db)
        // 学习会话属于辅助数据，幂等补建可覆盖跨版本升级遗漏。
        createLearningSessionTable(db)
        // 每日公共词单同样使用幂等建表，覆盖任何历史升级遗漏。
        createDailyReviewPlanTable(db)
        // CREATE TABLE IF NOT EXISTS 不会给旧表补字段，因此打开时再做一次幂等检查。
        ensureDailyReviewPlanSelectionVersionColumn(db)
        // 分组排序表只是内部实现，幂等补建不会改动 group 业务字段。
        createGroupPositionsTable(db)
    }

    /** 创建 words 表；spelling 只要求非空，不再带 UNIQUE。 */
    private fun createWordsTable(db: SQLiteDatabase) {
        // execSQL 执行固定结构 SQL，不拼接任何用户输入。
        db.execSQL(
            """
            CREATE TABLE words (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                spelling TEXT NOT NULL COLLATE BINARY,
                difficulty INTEGER NOT NULL DEFAULT 0 CHECK (difficulty >= 0),
                phonetic_uk TEXT NULL,
                phonetic_us TEXT NULL,
                plural TEXT NOT NULL DEFAULT '[]',
                third_person_singular TEXT NOT NULL DEFAULT '[]',
                gerund TEXT NOT NULL DEFAULT '[]',
                past_tense TEXT NOT NULL DEFAULT '[]',
                past_participle TEXT NOT NULL DEFAULT '[]',
                comparative TEXT NOT NULL DEFAULT '[]',
                superlative TEXT NOT NULL DEFAULT '[]',
                reviewed_at INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL DEFAULT 0,
                deleted_at INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent(),
        )
    }

    /** 创建 meanings 表；字段名与 README/JSON 保持一致。 */
    private fun createMeaningsTable(db: SQLiteDatabase) {
        // SQLite 没有数组类型，definitions 列内部仍保存 JSON 文本，但不再改字段名。
        db.execSQL(
            """
            CREATE TABLE meanings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word_id INTEGER NOT NULL,
                "index" INTEGER NOT NULL DEFAULT 0,
                pos TEXT NOT NULL,
                definitions TEXT NOT NULL DEFAULT '[]',
                created_at INTEGER NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL DEFAULT 0,
                deleted_at INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (word_id) REFERENCES words(id) ON DELETE CASCADE
            )
            """.trimIndent(),
        )
    }

    /**
     * 创建 README 定义的 group 业务表。
     *
     * 界面拖动顺序改由 group_positions 保存，避免为 JSON 分组对象引入 README
     * 之外的 sort_order 字段。
     */
    private fun createGroupsTable(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE groups (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                created_at INTEGER NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL DEFAULT 0,
                deleted_at INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent(),
        )
    }

    /**
     * 创建单词-分组关联表，严格使用 README 的 group_id/word_id 两个字段。
     */
    private fun createGroupMembersTable(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE group_members (
                group_id INTEGER NOT NULL,
                word_id INTEGER NOT NULL,
                PRIMARY KEY(group_id, word_id),
                FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE,
                FOREIGN KEY (word_id) REFERENCES words(id) ON DELETE CASCADE
            )
            """.trimIndent(),
        )
    }

    /** 创建分组界面顺序表；它不属于导入导出的业务数据。 */
    private fun createGroupPositionsTable(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS group_positions (
                group_id INTEGER PRIMARY KEY,
                position INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE
            )
            """.trimIndent(),
        )
    }

    /** 创建首页和 Meaning 批量查询需要的普通索引。 */
    private fun createIndexes(db: SQLiteDatabase) {
        // 首页默认按 id 读取；该索引优化软删除过滤与稳定排序。
        db.execSQL("CREATE INDEX words_deleted_id ON words(deleted_at, id)")
        // 一次查询全部 Meaning 时按 word_id 和排序值组织，该索引避免额外全表排序。
        db.execSQL(
            "CREATE INDEX meanings_word_sort ON meanings(word_id, deleted_at, \"index\" DESC)",
        )
    }

    /** 丢弃旧词库并按 README 字段重建全部相关表。 */
    private fun rebuildVocabularySchema(db: SQLiteDatabase) {
        // 先删除引用 words/groups 的子表，再删父表，符合外键依赖顺序。
        db.execSQL("DROP TABLE IF EXISTS dictation_option_cache")
        db.execSQL("DROP TABLE IF EXISTS learning_sessions")
        db.execSQL("DROP TABLE IF EXISTS daily_review_plans")
        db.execSQL("DROP TABLE IF EXISTS record")
        db.execSQL("DROP TABLE IF EXISTS group_positions")
        db.execSQL("DROP TABLE IF EXISTS group_members")
        db.execSQL("DROP TABLE IF EXISTS meanings")
        db.execSQL("DROP TABLE IF EXISTS groups")
        db.execSQL("DROP TABLE IF EXISTS words")
        // 按新安装的建表顺序恢复完整结构。
        createWordsTable(db)
        createMeaningsTable(db)
        createGroupsTable(db)
        createGroupPositionsTable(db)
        createGroupMembersTable(db)
        createRecordTable(db)
        createDictationOptionCacheTable(db)
        createLearningSessionTable(db)
        createDailyReviewPlanTable(db)
        createIndexes(db)
    }

    /** 按 id 列表读取单词（含 Meaning 与分组聚合），供「只回刷本次复习涉及的单词」使用。 */
    fun getWordsByIds(ids: List<Long>): List<Map<String, Any?>> {
        // 空列表直接返回，避免拼出无意义的 IN () 占位。
        if (ids.isEmpty()) return emptyList()
        // readableDatabase 会复用现有连接；占位符与参数一一对应。
        val db = readableDatabase
        val placeholders = ids.joinToString(separator = ",") { "?" }
        val args = ids.map { it.toString() }.toTypedArray()
        // 三张表都用同一组占位符与参数做 IN 过滤。
        return queryWordsInternal(db, placeholders, args)
    }

    /** 一次性读取全部未软删除 Word，并用第二次查询组装 Meaning，避免 N+1 查询。 */
    fun getAllWords(): List<Map<String, Any?>> {
        // 全部读取等价于不附加任何 id 过滤。
        return queryWordsInternal(readableDatabase, null, null)
    }

    /**
     * 内部共用：先按 word_id 聚合 Meaning 与分组，再读取 words 组装成 Dart
     * Word.fromMap 需要的 Map。[placeholders]/[args] 同时裁剪 words、meanings、
     * group_members 三张表；为空表示读取全部，非空时三表都按相同 id 列表 IN 过滤。
     */
    private fun queryWordsInternal(
        db: SQLiteDatabase,
        placeholders: String?,
        args: Array<String>?,
    ): List<Map<String, Any?>> {
        // 只指定 id 时三张表都追加 IN 占位符；否则不加任何 id 过滤。
        val idFilter = if (placeholders != null) " AND word_id IN ($placeholders)" else ""
        val wordIdFilter = if (placeholders != null) " AND id IN ($placeholders)" else ""

        // 先按 word_id 分组读取 Meaning（按需裁剪到指定单词）。
        val meaningsByWord = mutableMapOf<Long, MutableList<Map<String, Any?>>>()
        db.query(
            // 查询 meanings 表。
            "meanings",
            // null 表示读取全部列。
            null,
            // 只读取未软删除 Meaning，并按需裁剪到指定单词。
            "deleted_at = 0$idFilter",
            args,
            // 不分组。
            null,
            // 不使用 HAVING。
            null,
            // 按 word_id 聚合，并按 index 从大到小保持 README 顺序。
            "word_id ASC, \"index\" DESC, id ASC",
        ).use { cursor ->
            // moveToNext 类似遍历数据库结果集。
            while (cursor.moveToNext()) {
                // 当前 Meaning 所属单词 id。
                val wordId = cursor.getLong(cursor.getColumnIndexOrThrow("word_id"))
                // definitions TEXT 列内部是 JSON，还原成平台通道支持的字符串 List。
                val definitions = jsonArrayToStrings(
                    cursor.getString(cursor.getColumnIndexOrThrow("definitions")),
                )
                // 构造 Dart Meaning.fromMap 所需字段。
                val meaning = linkedMapOf<String, Any?>(
                    "id" to cursor.getLong(cursor.getColumnIndexOrThrow("id")),
                    "word_id" to wordId,
                    "index" to cursor.getInt(cursor.getColumnIndexOrThrow("index")),
                    "pos" to cursor.getString(cursor.getColumnIndexOrThrow("pos")),
                    "definitions" to definitions,
                    "created_at" to cursor.nullableLong("created_at"),
                    "updated_at" to cursor.nullableLong("updated_at"),
                    "deleted_at" to cursor.nullableLong("deleted_at"),
                )
                // getOrPut 对应 PHP `$map[$wordId] ??= []`，再追加当前 Meaning。
                meaningsByWord.getOrPut(wordId) { mutableListOf() }.add(meaning)
            }
        }

        // 聚合每个单词所属的所有分组：group_members 是多对多关联表。
        // 例如 word 1 同时被复制进分组 2 和 3，这里得到 [2, 3]。
        val memberGroupsByWord = mutableMapOf<Long, MutableList<Long>>()
        db.query(
            // 只读关联表的两个外键。
            "group_members",
            arrayOf("group_id", "word_id"),
            // 按需裁剪到指定单词；不指定时读取全部有效成员。
            if (placeholders != null) "word_id IN ($placeholders)" else null,
            args,
            null,
            null,
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                // 当前关联指向的单词。
                val wordId = cursor.getLong(cursor.getColumnIndexOrThrow("word_id"))
                // 当前关联指向的分组。
                val groupId = cursor.getLong(cursor.getColumnIndexOrThrow("group_id"))
                // 按单词归集分组 id 列表。
                memberGroupsByWord.getOrPut(wordId) { mutableListOf() }.add(groupId)
            }
        }

        // 创建最终结果列表；ArrayList 适合已知会连续追加大量元素的场景。
        val words = ArrayList<Map<String, Any?>>()
        // 再读取符合条件的 Word；与 meanings 查询构成固定两次 SQL，不会每个 Word 查询一次。
        db.query(
            "words",
            null,
            // 只读取未软删除 Word，并按需裁剪到指定 id。
            "deleted_at = 0$wordIdFilter",
            args,
            null,
            null,
            "id ASC",
        ).use { cursor ->
            // 逐条构造 Dart Word.fromMap 所需字段。
            while (cursor.moveToNext()) {
                // 读取主键供 meaningsByWord 关联。
                val id = cursor.getLong(cursor.getColumnIndexOrThrow("id"))
                // linkedMapOf 保持字段顺序，便于调试日志阅读。
                words.add(
                    linkedMapOf(
                        "id" to id,
                        "spelling" to cursor.getString(
                            cursor.getColumnIndexOrThrow("spelling"),
                        ),
                        "meanings" to (meaningsByWord[id] ?: emptyList<Map<String, Any?>>()),
                        // 聚合后的分组 id 列表；Dart Word.groupIds 接收它。
                        "group_ids" to (memberGroupsByWord[id] ?: emptyList<Long>()),
                        "difficulty" to cursor.nullableLong("difficulty"),
                        "phonetic_uk" to cursor.nullableString("phonetic_uk"),
                        "phonetic_us" to cursor.nullableString("phonetic_us"),
                        "plural" to cursor.jsonStringList("plural"),
                        "third_person_singular" to cursor.jsonStringList(
                            "third_person_singular",
                        ),
                        "gerund" to cursor.jsonStringList("gerund"),
                        "past_tense" to cursor.jsonStringList("past_tense"),
                        "past_participle" to cursor.jsonStringList("past_participle"),
                        "comparative" to cursor.jsonStringList("comparative"),
                        "superlative" to cursor.jsonStringList("superlative"),
                        "reviewed_at" to cursor.nullableLong("reviewed_at"),
                        "created_at" to cursor.nullableLong("created_at"),
                        "updated_at" to cursor.nullableLong("updated_at"),
                        "deleted_at" to cursor.nullableLong("deleted_at"),
                    ),
                )
            }
        }
        // 返回完整列表，Flutter ListView.builder 只会构建可见行。
        return words
    }

    /** 创建一个 Word、全部 Meaning 与分组关系，并返回自增主键。 */
    fun createWord(payload: Map<*, *>): Long {
        // 获取可写连接。
        val db = writableDatabase
        // 开始事务，保证 Word 与 Meaning 同时成功或同时失败。
        db.beginTransaction()
        try {
            // 当前时间供缺失 created_at/updated_at 时使用。
            val now = System.currentTimeMillis()
            // 从 Dart Map 创建 words 表字段。
            val values = wordValuesFromPayload(payload, now, touchUpdatedAt = false)
            // insertOrThrow 返回 SQLite 新生成的主键。
            val wordId = db.insertOrThrow("words", null, values)
            // 写入所有嵌套 Meaning。
            replaceMeanings(db, wordId, payload["meanings"])
            // 在同一事务写入全部分组关系，任一外键错误都会让主体与释义一起回滚。
            replaceWordGroups(db, wordId, payload["group_ids"])
            // 标记事务成功。
            db.setTransactionSuccessful()
            // 把 id 返回 Dart Store。
            return wordId
        } finally {
            // 释放事务锁。
            db.endTransaction()
        }
    }

    /** 更新 Word，并用提交的 Meaning 与分组列表替换旧关系数据。 */
    fun updateWord(payload: Map<*, *>) {
        // 更新必须携带主键。
        val id = (payload["id"] as? Number)?.toLong() ?: error("updateWord 缺少有效 id")
        // 获取可写连接并开始事务。
        val db = writableDatabase
        db.beginTransaction()
        try {
            // 使用当前时间作为 updated_at 回退值。
            val values = wordValuesFromPayload(
                payload,
                System.currentTimeMillis(),
                touchUpdatedAt = true,
            )
            // 根据 id 更新单词主体。
            val changed = db.update("words", values, "id = ?", arrayOf(id.toString()))
            // 0 行表示目标不存在，主动抛错而不是静默成功。
            if (changed == 0) error("找不到要更新的单词 id=$id")
            // 删除旧 Meaning 后按新提交列表重建，保持操作简单且原子。
            db.delete("meanings", "word_id = ?", arrayOf(id.toString()))
            // 拼写或释义可能已经变化，旧候选项不能继续复用。
            db.delete("dictation_option_cache", "word_id = ?", arrayOf(id.toString()))
            // 会话可能引用旧题目内容，编辑后作废；公共词单只存 id，继续保留当天批次。
            db.delete("learning_sessions", null, null)
            replaceMeanings(db, id, payload["meanings"])
            // 分组关系也属于本次保存；失败时主体和 Meaning 同时回滚。
            replaceWordGroups(db, id, payload["group_ids"])
            // 标记整个更新成功。
            db.setTransactionSuccessful()
        } finally {
            // 异常时自动回滚。
            db.endTransaction()
        }
    }

    /** 软删除 Word：首页查询只读取 deleted_at 为 0 的记录。 */
    fun softDeleteWord(id: Long) {
        // 使用同一毫秒值记录删除与最后更新时间。
        val now = System.currentTimeMillis()
        // 组装局部更新字段。
        val values = ContentValues().apply {
            put("deleted_at", now)
            put("updated_at", now)
        }
        // 根据主键更新；Meaning 保留供未来恢复或审计。
        val changed = writableDatabase.update(
            "words",
            values,
            "id = ?",
            arrayOf(id.toString()),
        )
        // 删除不存在 id 时给调用方明确错误。
        if (changed == 0) error("找不到要删除的单词 id=$id")
        // 单词软删除后不再属于任何分组，直接清理其全部关联行。
        writableDatabase.delete("group_members", "word_id = ?", arrayOf(id.toString()))
        // 软删除不会触发外键级联，因此显式删除该词全部候选缓存。
        writableDatabase.delete("dictation_option_cache", "word_id = ?", arrayOf(id.toString()))
        // 会话列表可能包含这个单词；删除后无法完整恢复，因此清掉未完成会话。
        writableDatabase.delete("learning_sessions", null, null)
    }

    /** 清空全部本地数据，用于「清空数据」与「导入前整库替换」。 */
    fun clearAllWords() {
        // 获取可写连接。
        val db = writableDatabase
        // 事务保证全部业务表与候选缓存要么都被清空，要么都不动。
        db.beginTransaction()
        try {
            // 先清空候选缓存、学习会话与其他子表，再清空父表，避免遗留失效快照。
            db.delete("dictation_option_cache", null, null)
            db.delete("learning_sessions", null, null)
            db.delete("daily_review_plans", null, null)
            db.delete("group_members", null, null)
            db.delete("groups", null, null)
            db.delete("meanings", null, null)
            db.delete("words", null, null)
            // 标记事务成功。
            db.setTransactionSuccessful()
        } finally {
            // 异常时自动回滚。
            db.endTransaction()
        }
    }

    /**
     * 批量导入单词：先清空旧数据，再按提交列表整库替换写入。
     *
     * 这样无论是「导入 words.json 原始词表」还是「导入本 App 导出的备份」，
     * 结果都一致且可重复，不会出现重复累加。
     */
    fun importWords(rawWords: List<*>) {
        // 原始数组包装成统一导入结构；缺少 groups 表示保留现有分组列表。
        importData(mapOf("words" to rawWords))
    }

    // ---------- 分组与分组成员 ----------

    /** 读取全部未软删除的分组，内部排序表只向 Dart 提供界面顺序。 */
    fun getAllGroups(): List<Map<String, Any?>> {
        // 只读连接即可。
        val db = readableDatabase
        // 结果列表。
        val groups = ArrayList<Map<String, Any?>>()
        // 查询未删除分组。
        db.rawQuery(
            """
            SELECT
                groups.*,
                COALESCE(group_positions.position, groups.id) AS ui_position
            FROM groups
            LEFT JOIN group_positions ON group_positions.group_id = groups.id
            WHERE groups.deleted_at = 0
            ORDER BY ui_position ASC, groups.id ASC
            """.trimIndent(),
            null,
        ).use { cursor ->
            // 逐行构造 Dart 需要的 Map。
            while (cursor.moveToNext()) {
                groups.add(
                    linkedMapOf(
                        "id" to cursor.getLong(cursor.getColumnIndexOrThrow("id")),
                        "name" to cursor.getString(cursor.getColumnIndexOrThrow("name")),
                        // sort_order 只是 Dart 现有 GroupStore 使用的界面别名，不是 groups 表字段。
                        "sort_order" to cursor.getInt(cursor.getColumnIndexOrThrow("ui_position")),
                        "created_at" to cursor.nullableLong("created_at"),
                        "updated_at" to cursor.nullableLong("updated_at"),
                        "deleted_at" to cursor.nullableLong("deleted_at"),
                    ),
                )
            }
        }
        // 返回分组列表。
        return groups
    }

    /** 新建分组并在内部表记录初始显示位置。 */
    fun createGroup(name: String, sortOrder: Int): Long {
        // 当前时间供创建与更新字段使用。
        val now = System.currentTimeMillis()
        val db = writableDatabase
        db.beginTransaction()
        try {
            // groups 严格只保存 README 业务字段。
            val values = ContentValues().apply {
                put("name", name.trim().ifEmpty { "未命名" })
                put("created_at", now)
                put("updated_at", now)
                put("deleted_at", 0)
            }
            val groupId = db.insertOrThrow("groups", null, values)
            // 界面顺序放在独立内部表，导出 group 时不会出现该字段。
            saveGroupPosition(db, groupId, sortOrder)
            db.setTransactionSuccessful()
            return groupId
        } finally {
            db.endTransaction()
        }
    }

    /** 重命名指定分组。 */
    fun renameGroup(id: Long, name: String) {
        // 仅更新名称与更新时间。
        val values = ContentValues().apply {
            put("name", name.trim().ifEmpty { "未命名" })
            put("updated_at", System.currentTimeMillis())
        }
        // 更新不存在时主动报错。
        val changed = writableDatabase.update("groups", values, "id = ?", arrayOf(id.toString()))
        if (changed == 0) error("找不到要重命名的分组 id=$id")
    }

    /** 调整分组界面顺序；业务表本身不新增 sort_order 字段。 */
    fun setGroupOrder(id: Long, sortOrder: Int) {
        saveGroupPosition(writableDatabase, id, sortOrder)
    }

    /** 软删除分组，并清理其全部成员关联。 */
    fun deleteGroup(id: Long) {
        // 写连接与事务。
        val db = writableDatabase
        db.beginTransaction()
        try {
            // 先删关联行，避免外键约束或遗留脏数据。
            db.delete("group_members", "group_id = ?", arrayOf(id.toString()))
            // 再软删除分组主体。
            val values = ContentValues().apply {
                put("deleted_at", System.currentTimeMillis())
                put("updated_at", System.currentTimeMillis())
            }
            db.update("groups", values, "id = ?", arrayOf(id.toString()))
            // 标记成功。
            db.setTransactionSuccessful()
        } finally {
            // 异常回滚。
            db.endTransaction()
        }
    }

    /** 把单词加入某分组；联合唯一约束保证重复加入不报错（幂等）。 */
    fun addGroupMember(groupId: Long, wordId: Long) {
        // 关联表严格只有 README 的两个外键字段。
        val values = ContentValues().apply {
            put("group_id", groupId)
            put("word_id", wordId)
        }
        // 唯一约束冲突时忽略，等价于已经在该分组。
        writableDatabase.insertWithOnConflict(
            "group_members",
            null,
            values,
            SQLiteDatabase.CONFLICT_IGNORE,
        )
    }

    /** 把单词从某分组移除。 */
    fun removeGroupMember(groupId: Long, wordId: Long) {
        // 按两个外键精确删除一行。
        writableDatabase.delete(
            "group_members",
            "group_id = ? AND word_id = ?",
            arrayOf(groupId.toString(), wordId.toString()),
        )
    }

    /**
     * 设置单词的全部所属分组（移动语义）：先删该单词旧的全部关联，
     * 再按给定列表重新建立。空列表表示移回「未分组」。
     */
    fun setWordGroups(wordId: Long, groupIds: List<*>) {
        // 写连接与事务保证原子。
        val db = writableDatabase
        db.beginTransaction()
        try {
            // 复用无嵌套事务的内部实现，保持单独分组操作与单词保存规则一致。
            replaceWordGroups(db, wordId, groupIds)
            // 标记成功。
            db.setTransactionSuccessful()
        } finally {
            // 异常回滚。
            db.endTransaction()
        }
    }

    /** 在调用方现有事务中整体替换一个单词的分组关系。 */
    private fun replaceWordGroups(db: SQLiteDatabase, wordId: Long, rawGroupIds: Any?) {
        // MethodChannel 应传 List；缺失或类型不符时按空列表处理，即移动到“未分组”。
        val groupIds = rawGroupIds as? List<*> ?: emptyList<Any?>()
        // 先清掉旧关系，后续任一插入失败会由外层事务恢复原状。
        db.delete("group_members", "word_id = ?", arrayOf(wordId.toString()))
        // 按新列表重建；非法元素直接跳过，不让动态通道类型导致崩溃。
        for (rawGroupId in groupIds) {
            // 数字类型统一转换为 SQLite Long 主键。
            val groupId = (rawGroupId as? Number)?.toLong() ?: continue
            // 组装关联行及创建时间。
            val values = ContentValues().apply {
                put("group_id", groupId)
                put("word_id", wordId)
            }
            // 重复 id 使用联合唯一约束忽略；不存在的外键仍会抛错并回滚事务。
            db.insertWithOnConflict(
                "group_members",
                null,
                values,
                SQLiteDatabase.CONFLICT_IGNORE,
            )
        }
    }

    /** 新增或覆盖一个分组的内部界面位置。 */
    private fun saveGroupPosition(db: SQLiteDatabase, groupId: Long, position: Int) {
        val values = ContentValues().apply {
            put("group_id", groupId)
            put("position", position.coerceAtLeast(0))
        }
        db.insertWithOnConflict(
            "group_positions",
            null,
            values,
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    /** 按 SQLite 实际表结构导入单词、释义、分组及所属关系。 */
    fun importData(payload: Map<*, *>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            // 导入会替换词库，与旧单词主键绑定的记录、候选和会话也失效。
            db.delete("dictation_option_cache", null, null)
            db.delete("learning_sessions", null, null)
            // 公共词单保存的是旧词库主键，整库替换后必须同时作废。
            db.delete("daily_review_plans", null, null)
            db.delete("group_members", null, null)
            db.delete("meanings", null, null)
            db.delete("words", null, null)
            // 只有文件明确携带 groups 时才替换分组；原始 words.json 继续保留本地分组。
            val replacesGroups = payload["groups"] is List<*>
            if (replacesGroups) db.delete("groups", null, null)

            // 先用当前数据库中的分组主键建立默认映射，支持仅导入 words 的情况。
            val groupIdMap = mutableMapOf<Long, Long>()
            if (!replacesGroups) {
                db.query("groups", arrayOf("id"), "deleted_at = 0", null, null, null, null)
                    .use { cursor ->
                        while (cursor.moveToNext()) {
                            val id = cursor.getLong(0)
                            groupIdMap[id] = id
                        }
                    }
            }
            val rawGroups = payload["groups"] as? List<*> ?: emptyList<Any?>()
            for ((position, rawGroup) in rawGroups.withIndex()) {
                val group = rawGroup as? Map<*, *> ?: continue
                val oldId = positiveId(group["id"])
                val values = buildImportValues(db, "groups", group)
                // name 是 README 必填文本，缺失时给人类可识别的回退值。
                if (!values.containsKey("name")) values.put("name", "未命名")
                val newId = insertRow(db, "groups", values)
                if (oldId != null) groupIdMap[oldId] = newId
                // JSON groups 数组的先后即界面顺序，无需额外导出 sort_order。
                saveGroupPosition(db, newId, position)
            }

            val wordIdMap = mutableMapOf<Long, Long>()
            val nestedMemberships = mutableListOf<Pair<Long, Long>>()
            val rawWords = payload["words"] as? List<*> ?: emptyList<Any?>()
            for (rawWord in rawWords) {
                val word = rawWord as? Map<*, *> ?: continue
                val oldId = positiveId(word["id"])
                val values = buildImportValues(db, "words", word)
                val spelling = values.getAsString("spelling")?.trim().orEmpty()
                require(spelling.isNotEmpty()) { "words.spelling 不能为空" }
                values.put("spelling", spelling)
                val newId = insertRow(db, "words", values)
                if (oldId != null) wordIdMap[oldId] = newId
                // meanings 是 words 上的嵌套关系，拆开后同样按 meanings 实际表结构写入。
                val meanings = word["meanings"] as? List<*> ?: emptyList<Any?>()
                for (rawMeaning in meanings) {
                    val meaning = rawMeaning as? Map<*, *> ?: continue
                    val meaningValues = buildImportValues(
                        db,
                        "meanings",
                        meaning,
                        overrides = mapOf("word_id" to newId),
                    )
                    if (!meaningValues.containsKey("pos")) meaningValues.put("pos", "")
                    insertRow(db, "meanings", meaningValues)
                }
                // 兼容人工 JSON 在单词内直接写 groups/group_ids 的简写方式。
                val rawGroupIds = (word["groups"] ?: word["group_ids"]) as? List<*>
                for (rawGroupId in rawGroupIds ?: emptyList<Any?>()) {
                    val oldGroupId = positiveId(rawGroupId) ?: continue
                    nestedMemberships.add(newId to oldGroupId)
                }
            }

            val rawMembers = payload["members"] as? List<*> ?: emptyList<Any?>()
            for (rawMember in rawMembers) {
                val member = rawMember as? Map<*, *> ?: continue
                val oldGroup = positiveId(member["group_id"]) ?: continue
                val oldWord = positiveId(member["word_id"]) ?: continue
                val newGroup = groupIdMap[oldGroup] ?: continue
                val newWord = wordIdMap[oldWord] ?: continue
                insertGroupMember(db, newGroup, newWord)
            }
            for ((newWord, oldGroup) in nestedMemberships) {
                val newGroup = groupIdMap[oldGroup] ?: continue
                insertGroupMember(db, newGroup, newWord)
            }

            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    /** 按业务表实际字段导出人类可读的单词与分组数据。 */
    fun exportData(): Map<String, Any?> {
        val db = readableDatabase
        val meaningRows = exportRows(
            db,
            "meanings",
            "deleted_at = 0",
            jsonArrayColumns = setOf("definitions"),
        )
        val meaningsByWord = meaningRows.groupBy { row -> (row["word_id"] as Number).toLong() }
        val words = exportRows(
            db,
            "words",
            "deleted_at = 0",
            jsonArrayColumns = setOf(
                "plural",
                "third_person_singular",
                "gerund",
                "past_tense",
                "past_participle",
                "comparative",
                "superlative",
            ),
        ).map { row ->
            val wordId = (row["id"] as Number).toLong()
            LinkedHashMap(row).apply {
                // meanings 是 JSON 嵌套关系；其内部普通字段仍全部来自真实表结构。
                put("meanings", meaningsByWord[wordId] ?: emptyList<Map<String, Any?>>())
            }
        }
        // 分组数组顺序代表界面顺序，group_positions 不作为业务字段导出。
        val groupColumns = tableColumns(db, "groups")
        val groups = mutableListOf<Map<String, Any?>>()
        db.rawQuery(
            """
            SELECT groups.*
            FROM groups
            LEFT JOIN group_positions ON group_positions.group_id = groups.id
            WHERE groups.deleted_at = 0
            ORDER BY COALESCE(group_positions.position, groups.id), groups.id
            """.trimIndent(),
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                groups.add(exportCursorRow(cursor, groupColumns, emptySet()))
            }
        }
        return linkedMapOf(
            "words" to words,
            "groups" to groups,
            "members" to exportRows(db, "group_members", null),
        )
    }

    /** SQLite PRAGMA table_info 返回的单个字段定义。 */
    private data class TableColumn(
        val name: String,
        val declaredType: String,
        val primaryKey: Boolean,
    )

    /** 读取固定业务表的真实字段，作为导入白名单与类型来源。 */
    private fun tableColumns(db: SQLiteDatabase, table: String): LinkedHashMap<String, TableColumn> {
        // table 只由本类中固定的 words/meanings/groups/group_members 传入，不接收用户表名。
        val columns = linkedMapOf<String, TableColumn>()
        db.rawQuery("PRAGMA table_info($table)", null).use { cursor ->
            val nameIndex = cursor.getColumnIndexOrThrow("name")
            val typeIndex = cursor.getColumnIndexOrThrow("type")
            val primaryKeyIndex = cursor.getColumnIndexOrThrow("pk")
            while (cursor.moveToNext()) {
                val column = TableColumn(
                    name = cursor.getString(nameIndex),
                    declaredType = cursor.getString(typeIndex).uppercase(Locale.ROOT),
                    primaryKey = cursor.getInt(primaryKeyIndex) > 0,
                )
                columns[column.name] = column
            }
        }
        return columns
    }

    /** 只把 JSON 中数据库真实存在的字段转换为 ContentValues。 */
    private fun buildImportValues(
        db: SQLiteDatabase,
        table: String,
        raw: Map<*, *>,
        overrides: Map<String, Any?> = emptyMap(),
    ): ContentValues {
        val columns = tableColumns(db, table)
        val values = ContentValues()
        // 遍历 JSON 对象的属性；不在 PRAGMA 结果中的嵌套关系或未知字段直接忽略。
        for ((rawName, rawValue) in raw) {
            val name = rawName as? String ?: continue
            val column = columns[name] ?: continue
            putImportValue(values, column, rawValue)
        }
        // 外键等上下文值必须覆盖 JSON 旧值，保证指向本次新插入的主键。
        for ((name, value) in overrides) {
            val column = columns[name] ?: continue
            putImportValue(values, column, value)
        }
        // 缺失的普通数字与日期字段按用户约定统一补 0；自增主键由 SQLite 生成。
        for (column in columns.values) {
            if (column.primaryKey || values.containsKey(column.name)) continue
            if (column.name.endsWith("_at") || column.declaredType.contains("INT")) {
                values.put(column.name, 0)
            }
        }
        return values
    }

    /** 根据 SQLite 声明类型写入一个 JSON 值。 */
    private fun putImportValue(values: ContentValues, column: TableColumn, rawValue: Any?) {
        val name = column.name
        // id 空值或非正数不伪造 0 号记录，而是交给 SQLite 自增。
        if (column.primaryKey) {
            val id = positiveId(rawValue) ?: return
            values.put(name, id)
            return
        }
        // SQLite 把日期保存为 INTEGER，通过 README 统一的 *_at 命名识别日期语义。
        if (name.endsWith("_at")) {
            values.put(name, parseImportDate(rawValue))
            return
        }
        when {
            column.declaredType.contains("INT") -> values.put(name, parseImportInteger(rawValue))
            column.declaredType.contains("REAL") ||
                column.declaredType.contains("FLOA") ||
                column.declaredType.contains("DOUB") -> values.put(name, parseImportReal(rawValue))
            rawValue == null -> values.putNull(name)
            rawValue is List<*> -> values.put(name, JSONArray(rawValue).toString())
            rawValue is Map<*, *> -> values.put(name, JSONObject(rawValue).toString())
            else -> values.put(name, rawValue.toString())
        }
    }

    /** 数字、数字文本和布尔值转整数；空值或错误内容统一为 0。 */
    private fun parseImportInteger(value: Any?): Long = when (value) {
        is Number -> value.toLong()
        is Boolean -> if (value) 1 else 0
        is String -> value.trim().toLongOrNull()
            ?: value.trim().toDoubleOrNull()?.toLong()
            ?: 0
        else -> 0
    }

    /** 动态值转浮点数；空值或错误内容统一为 0。 */
    private fun parseImportReal(value: Any?): Double = when (value) {
        is Number -> value.toDouble()
        is String -> value.trim().toDoubleOrNull() ?: 0.0
        else -> 0.0
    }

    /** 只接受正数主键/外键，空值不生成虚假的 0 号关联。 */
    private fun positiveId(value: Any?): Long? {
        val parsed = when (value) {
            is Number -> value.toLong()
            is String -> value.trim().toLongOrNull()
            else -> null
        }
        return parsed?.takeIf { it > 0 }
    }

    /** 导入日期并统一转为毫秒时间戳；空值或错误日期返回 0。 */
    private fun parseImportDate(value: Any?): Long {
        if (value is Number) return normalizeTimestamp(value.toLong())
        val text = value?.toString()?.trim().orEmpty()
        if (text.isEmpty()) return 0
        text.toLongOrNull()?.let { return normalizeTimestamp(it) }
        // 按人类常用程度从完整时区时间逐步回退到纯日期。
        val patterns = listOf(
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy-MM-dd",
            "yyyy/MM/dd",
        )
        for (pattern in patterns) {
            val formatter = SimpleDateFormat(pattern, Locale.getDefault()).apply { isLenient = false }
            val position = ParsePosition(0)
            val parsed = formatter.parse(text, position)
            if (parsed != null && position.index == text.length) return parsed.time
        }
        return 0
    }

    /** 自动区分秒级与毫秒级时间戳。 */
    private fun normalizeTimestamp(value: Long): Long {
        if (value == 0L) return 0
        // 当前秒级时间戳约 10 位，毫秒级约 13 位；1000 亿是安全分界。
        return if (kotlin.math.abs(value) < 100_000_000_000L) value * 1000 else value
    }

    /** 插入已完成新旧主键映射的分组所属关系。 */
    private fun insertGroupMember(db: SQLiteDatabase, groupId: Long, wordId: Long) {
        val values = ContentValues().apply {
            put("group_id", groupId)
            put("word_id", wordId)
        }
        db.insertWithOnConflict(
            "group_members",
            null,
            values,
            SQLiteDatabase.CONFLICT_IGNORE,
        )
    }

    /**
     * 插入一行 ContentValues，并为表名和字段名补上 SQLite 标识符引号。
     *
     * Android 自带的 insertOrThrow 不会给 ContentValues 的字段名加引号，README
     * 使用的 meaning.index 又恰好是 SQLite 保留字，因此动态导入统一走该方法。
     *
     * @param db 当前写事务使用的 SQLite 连接。
     * @param table 需要写入的固定业务表名。
     * @param values 已按真实表结构和字段类型转换的数据。
     * @return 新插入记录的主键；没有自增主键的表由 SQLite 返回 rowid。
     */
    private fun insertRow(db: SQLiteDatabase, table: String, values: ContentValues): Long {
        require(values.size() > 0) { "$table 没有可写入字段" }
        val columns = values.keySet().toList()
        val sql = buildString {
            append("INSERT INTO ")
            append(quoteIdentifier(table))
            append(" (")
            append(columns.joinToString(", ") { name -> quoteIdentifier(name) })
            append(") VALUES (")
            append(List(columns.size) { "?" }.joinToString(", "))
            append(")")
        }
        return db.compileStatement(sql).use { statement ->
            for ((index, column) in columns.withIndex()) {
                val parameterIndex = index + 1
                when (val value = values.get(column)) {
                    null -> statement.bindNull(parameterIndex)
                    is ByteArray -> statement.bindBlob(parameterIndex, value)
                    is Float -> statement.bindDouble(parameterIndex, value.toDouble())
                    is Double -> statement.bindDouble(parameterIndex, value)
                    is Number -> statement.bindLong(parameterIndex, value.toLong())
                    is Boolean -> statement.bindLong(parameterIndex, if (value) 1 else 0)
                    else -> statement.bindString(parameterIndex, value.toString())
                }
            }
            statement.executeInsert()
        }
    }

    /** 把可信表名或字段名转成 SQLite 双引号标识符。 */
    private fun quoteIdentifier(identifier: String): String =
        "\"${identifier.replace("\"", "\"\"")}\""

    /** 读取指定业务表的全部实际字段并转成可导出对象。 */
    private fun exportRows(
        db: SQLiteDatabase,
        table: String,
        selection: String?,
        jsonArrayColumns: Set<String> = emptySet(),
    ): List<Map<String, Any?>> {
        val columns = tableColumns(db, table)
        val rows = mutableListOf<Map<String, Any?>>()
        db.query(table, null, selection, null, null, null, "rowid ASC").use { cursor ->
            while (cursor.moveToNext()) {
                rows.add(exportCursorRow(cursor, columns, jsonArrayColumns))
            }
        }
        return rows
    }

    /** 把一行 SQLite 数据按字段语义转成人类可读的 JSON 值。 */
    private fun exportCursorRow(
        cursor: android.database.Cursor,
        columns: Map<String, TableColumn>,
        jsonArrayColumns: Set<String>,
    ): Map<String, Any?> {
        val row = linkedMapOf<String, Any?>()
        for (column in columns.values) {
            val index = cursor.getColumnIndexOrThrow(column.name)
            if (column.name.endsWith("_at")) {
                val timestamp = if (cursor.isNull(index)) 0 else cursor.getLong(index)
                row[column.name] = formatExportDate(timestamp)
                continue
            }
            if (cursor.isNull(index)) {
                // 数字空值导出 0，普通文本继续保持 null 语义。
                row[column.name] = if (column.declaredType.contains("INT") ||
                    column.declaredType.contains("REAL")) 0 else null
                continue
            }
            row[column.name] = when {
                column.declaredType.contains("INT") -> cursor.getLong(index)
                column.declaredType.contains("REAL") ||
                    column.declaredType.contains("FLOA") ||
                    column.declaredType.contains("DOUB") -> cursor.getDouble(index)
                column.name in jsonArrayColumns -> decodeExportArray(cursor.getString(index))
                else -> cursor.getString(index)
            }
        }
        return row
    }

    /** 把明确声明为数组的 SQLite TEXT 字段还原为 JSON 数组。 */
    private fun decodeExportArray(value: String): Any {
        return try {
            val array = JSONArray(value)
            List(array.length()) { index ->
                val item = array.get(index)
                if (item == JSONObject.NULL) null else item
            }
        } catch (_: Exception) {
            value
        }
    }

    /** 毫秒时间戳导出为本机时区的完整日期时间；0 导出空字符串。 */
    private fun formatExportDate(timestamp: Long): String {
        if (timestamp == 0L) return ""
        return SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date(timestamp))
    }

    /**
     * 创建单词默写记录表（幂等：用 IF NOT EXISTS，可重复调用）。
     *
     * 每次默写提交都新增一条记录，同一单词同一天可以有多条。`created_date`
     * 使用本机时区的 'YYYY-MM-DD' 字符串，供今日记录查询和去重统计使用。
     *
     * @param db 需要创建记录表和索引的 SQLite 连接。
     * @return Unit
     */
    private fun createRecordTable(db: SQLiteDatabase) {
        // execSQL 执行固定结构 SQL，不拼接任何用户输入；IF NOT EXISTS 保证重复建表不报错。
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS record (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                module TEXT NOT NULL,
                word_id INTEGER NOT NULL,
                is_correct INTEGER NOT NULL,
                wrong_count INTEGER NOT NULL DEFAULT 0,
                hint_count INTEGER NOT NULL DEFAULT 0,
                difficulty_before INTEGER NOT NULL,
                difficulty_after INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                created_date TEXT NOT NULL,
                FOREIGN KEY (word_id) REFERENCES words(id) ON DELETE CASCADE
            )
            """.trimIndent(),
        )
        // 按日期查询"今日复习"时用得到，建索引加速；IF NOT EXISTS 保证幂等。
        db.execSQL("CREATE INDEX IF NOT EXISTS record_created_date ON record(created_date)")
        // 难度判定要按单词取"最近 N 条"记录，一天多条后这类查询会变频繁，
        // 用 (word_id, id) 复合索引让"某词最近几条"可以直接走索引倒序扫描。
        db.execSQL("CREATE INDEX IF NOT EXISTS record_word_id_seq ON record(word_id, id)")
    }

    /** 创建默写候选项缓存表；一个 cache_key 对应一道具体拼写题或释义题。 */
    private fun createDictationOptionCacheTable(db: SQLiteDatabase) {
        // 干扰项使用 JSON 数组保存；correct_index 记录正确答案插入三个干扰项的位置。
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS dictation_option_cache (
                cache_key TEXT PRIMARY KEY,
                word_id INTEGER NULL,
                distractors_json TEXT NOT NULL,
                correct_index INTEGER NULL CHECK (correct_index BETWEEN 0 AND 3),
                updated_at INTEGER NOT NULL,
                FOREIGN KEY (word_id) REFERENCES words(id) ON DELETE CASCADE
            )
            """.trimIndent(),
        )
    }

    /**
     * 为旧候选缓存表补上正确答案位置列。
     *
     * SQLite 的 CREATE TABLE IF NOT EXISTS 只会跳过已存在表，不会自动补新字段，
     * 因此升级和打开数据库时都通过 PRAGMA 检查一次。这个操作只改表结构，旧候选
     * 名字完整保留；null 位置会在 Dart 首次读取后自动写成 0～3 的实际下标。
     */
    private fun ensureDictationOptionCorrectIndexColumn(db: SQLiteDatabase) {
        // PRAGMA table_info 返回表的全部字段定义，其中 name 列保存字段名。
        val hasCorrectIndex = db.rawQuery(
            "PRAGMA table_info(dictation_option_cache)",
            null,
        ).use { cursor ->
            // 找到 name 列，逐行确认 correct_index 是否已经存在。
            val nameColumn = cursor.getColumnIndexOrThrow("name")
            var found = false
            while (cursor.moveToNext()) {
                if (cursor.getString(nameColumn) == "correct_index") {
                    found = true
                    break
                }
            }
            found
        }
        // 新数据库已经由建表语句包含该字段，无需重复执行 ALTER TABLE。
        if (hasCorrectIndex) return
        // 可空字段兼容版本 6～7 的历史行；CHECK 阻止未来写入 0～3 之外的位置。
        db.execSQL(
            "ALTER TABLE dictation_option_cache " +
                "ADD COLUMN correct_index INTEGER NULL CHECK (correct_index BETWEEN 0 AND 3)",
        )
    }

    /** 创建学习会话表；随身听和默写各自最多保存一条未完成记录。 */
    private fun createLearningSessionTable(db: SQLiteDatabase) {
        // 单词 id 列表和页面状态都使用 JSON 文本，既保留顺序，也允许两种页面保存不同字段。
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS learning_sessions (
                session_type TEXT PRIMARY KEY,
                word_ids_json TEXT NOT NULL,
                state_json TEXT NOT NULL,
                updated_at INTEGER NOT NULL
            )
            """.trimIndent(),
        )
    }

    /** 创建每日公共复习词单表；任意时刻只需要保留设备本地当天的一行。 */
    private fun createDailyReviewPlanTable(db: SQLiteDatabase) {
        // JSON 数组保留选词顺序；daily_goal 保存首次生成时冻结的目标数量。
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS daily_review_plans (
                plan_date TEXT PRIMARY KEY,
                daily_goal INTEGER NOT NULL CHECK (daily_goal >= 0),
                word_ids_json TEXT NOT NULL,
                selection_version INTEGER NOT NULL DEFAULT 0 CHECK (selection_version >= 0),
                created_at INTEGER NOT NULL
            )
            """.trimIndent(),
        )
    }

    /** 为版本 10 的每日词单表补上选词规则版本列；重复调用不会再次修改结构。 */
    private fun ensureDailyReviewPlanSelectionVersionColumn(db: SQLiteDatabase) {
        // PRAGMA table_info 读取真实列名，作用类似先检查 PHP 数据库迁移是否已经执行。
        val hasSelectionVersion = db.rawQuery(
            "PRAGMA table_info(daily_review_plans)",
            null,
        ).use { cursor ->
            // name 列保存每一项字段名。
            val nameColumn = cursor.getColumnIndexOrThrow("name")
            // 默认尚未找到，逐行遇到目标字段后立即停止。
            var found = false
            while (cursor.moveToNext()) {
                if (cursor.getString(nameColumn) == "selection_version") {
                    found = true
                    break
                }
            }
            found
        }
        // 新安装或已经升级过的数据库无需执行 ALTER TABLE。
        if (hasSelectionVersion) return
        // 历史计划统一写入 0，Dart 会据此使用当前规则重建一次并覆盖为新版本。
        db.execSQL(
            "ALTER TABLE daily_review_plans " +
                "ADD COLUMN selection_version INTEGER NOT NULL DEFAULT 0 " +
                "CHECK (selection_version >= 0)",
        )
    }

    /** 读取设备本地今天的公共复习词单；尚未创建时返回 null。 */
    fun getTodayReviewPlan(): Map<String, Any?>? {
        // 原生日期与 record.created_date 使用同一个方法，跨午夜时口径一致。
        val today = localDateString()
        readableDatabase.query(
            "daily_review_plans",
            arrayOf(
                "plan_date",
                "daily_goal",
                "word_ids_json",
                "selection_version",
                "created_at",
            ),
            "plan_date = ?",
            arrayOf(today),
            null,
            null,
            null,
            "1",
        ).use { cursor ->
            if (!cursor.moveToFirst()) return null
            // MethodChannel 可直接传 List<Long>，Dart 端统一转成 int。
            val json = JSONArray(cursor.getString(cursor.getColumnIndexOrThrow("word_ids_json")))
            val wordIds = List(json.length()) { index -> json.getLong(index) }
            return linkedMapOf(
                "plan_date" to cursor.getString(cursor.getColumnIndexOrThrow("plan_date")),
                "daily_goal" to cursor.getInt(cursor.getColumnIndexOrThrow("daily_goal")),
                "word_ids" to wordIds,
                "selection_version" to cursor.getInt(
                    cursor.getColumnIndexOrThrow("selection_version"),
                ),
                "created_at" to cursor.getLong(cursor.getColumnIndexOrThrow("created_at")),
            )
        }
    }

    /** 保存今天的公共词单并删除其他日期的过期计划，返回实际保存的数据。 */
    fun saveTodayReviewPlan(
        dailyGoal: Int,
        wordIds: List<Long>,
        selectionVersion: Int,
    ): Map<String, Any?> {
        if (dailyGoal < 0) error("每日复习量不能为负数")
        if (selectionVersion < 0) error("选词规则版本不能为负数")
        // 主键必须全部为正数；无效 id 会让四个模式都无法恢复同一份词单。
        if (wordIds.any { it <= 0 }) error("每日复习计划包含无效单词 id")
        val db = writableDatabase
        val today = localDateString()
        val now = System.currentTimeMillis()
        db.beginTransaction()
        try {
            // 计划只在当天有效，写入新计划前清掉昨天及更早的数据。
            db.delete("daily_review_plans", "plan_date <> ?", arrayOf(today))
            val values = ContentValues().apply {
                put("plan_date", today)
                put("daily_goal", dailyGoal)
                put("word_ids_json", JSONArray(wordIds).toString())
                put("selection_version", selectionVersion)
                put("created_at", now)
            }
            db.insertWithOnConflict(
                "daily_review_plans",
                null,
                values,
                SQLiteDatabase.CONFLICT_REPLACE,
            )
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        return linkedMapOf(
            "plan_date" to today,
            "daily_goal" to dailyGoal,
            "word_ids" to wordIds,
            "selection_version" to selectionVersion,
            "created_at" to now,
        )
    }

    /** 按小题 key 读取干扰项及正确答案位置；没有缓存时返回 null。 */
    fun getDictationOptionCache(cacheKey: String): Map<String, Any?>? {
        // 精确查询主键，最多只会返回一行。
        readableDatabase.query(
            "dictation_option_cache",
            arrayOf("distractors_json", "correct_index"),
            "cache_key = ?",
            arrayOf(cacheKey),
            null,
            null,
            null,
            "1",
        ).use { cursor ->
            // 没有行表示第一次遇到这道题。
            if (!cursor.moveToFirst()) return null
            // 把 JSON 数组还原成 MethodChannel 可直接传输的字符串列表。
            val json = JSONArray(cursor.getString(cursor.getColumnIndexOrThrow("distractors_json")))
            val distractors = List(json.length()) { index -> json.getString(index) }
            // 版本 8 之前的历史缓存没有位置，数据库升级后该字段为 null。
            val correctIndexColumn = cursor.getColumnIndexOrThrow("correct_index")
            val correctIndex = if (cursor.isNull(correctIndexColumn)) {
                null
            } else {
                cursor.getInt(correctIndexColumn)
            }
            // Map 可由 MethodChannel 直接传给 Dart，并为以后扩展缓存字段保留空间。
            return mapOf(
                "distractors" to distractors,
                "correctIndex" to correctIndex,
            )
        }
    }

    /** 新增或覆盖一道题的干扰项和正确答案位置。 */
    fun saveDictationOptionCache(
        cacheKey: String,
        wordId: Long?,
        distractors: List<String>,
        correctIndex: Int,
    ) {
        // ContentValues 对应缓存表的一整行。
        val values = ContentValues().apply {
            put("cache_key", cacheKey)
            // putNull 与可空外键匹配，主要兼容尚未落库的开发测试数据。
            if (wordId == null) putNull("word_id") else put("word_id", wordId)
            put("distractors_json", JSONArray(distractors).toString())
            // 正确答案位置与干扰项一起覆盖，完整代表用户最后看到的四个按钮顺序。
            put("correct_index", correctIndex)
            put("updated_at", System.currentTimeMillis())
        }
        // PRIMARY KEY 冲突时整体替换，长按刷新可用一次写入覆盖旧数组。
        writableDatabase.insertWithOnConflict(
            "dictation_option_cache",
            null,
            values,
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    /** 读取全部未完成学习会话；当前最多返回随身听和默写两行。 */
    fun getLearningSessions(): List<Map<String, Any?>> {
        // 返回顺序按最近更新时间排列，未来首页若展示时间可直接复用。
        val sessions = ArrayList<Map<String, Any?>>()
        readableDatabase.query(
            "learning_sessions",
            arrayOf("session_type", "word_ids_json", "state_json", "updated_at"),
            null,
            null,
            null,
            null,
            "updated_at DESC",
        ).use { cursor ->
            // 每一行都保持 JSON 原文，交给 Dart 强类型模型统一解析。
            while (cursor.moveToNext()) {
                sessions.add(
                    linkedMapOf(
                        "session_type" to cursor.getString(
                            cursor.getColumnIndexOrThrow("session_type"),
                        ),
                        "word_ids_json" to cursor.getString(
                            cursor.getColumnIndexOrThrow("word_ids_json"),
                        ),
                        "state_json" to cursor.getString(
                            cursor.getColumnIndexOrThrow("state_json"),
                        ),
                        "updated_at" to cursor.getLong(
                            cursor.getColumnIndexOrThrow("updated_at"),
                        ),
                    ),
                )
            }
        }
        return sessions
    }

    /** 新增或覆盖一个学习会话；session_type 主键保证同类型永远只有最新一条。 */
    fun saveLearningSession(sessionType: String, wordIdsJson: String, stateJson: String) {
        // 空类型或空 JSON 没有恢复价值，原生层也执行最后一道参数校验。
        if (sessionType.isBlank()) error("学习会话类型不能为空")
        if (wordIdsJson.isBlank()) error("学习会话单词列表不能为空")
        if (stateJson.isBlank()) error("学习会话状态不能为空")
        // ContentValues 对应 SQLite 中的一整行。
        val values = ContentValues().apply {
            put("session_type", sessionType)
            put("word_ids_json", wordIdsJson)
            put("state_json", stateJson)
            put("updated_at", System.currentTimeMillis())
        }
        // REPLACE 让“重新开始”或每次进度推进都原子覆盖旧快照。
        writableDatabase.insertWithOnConflict(
            "learning_sessions",
            null,
            values,
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    /** 删除一种已完成或失效的学习会话。 */
    fun deleteLearningSession(sessionType: String) {
        // 精确匹配主键，不影响另一种学习方式的恢复记录。
        writableDatabase.delete(
            "learning_sessions",
            "session_type = ?",
            arrayOf(sessionType),
        )
    }

    /** 取设备本机时区下的 'yyyy-MM-dd' 日期字符串，作为 created_date 与"今日"判定基准。 */
    private fun localDateString(): String {
        // Locale.getDefault() 拿到设备区域；SimpleDateFormat 默认用设备时区，即本地日期。
        val format = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
        // Date() 为当前时刻，format 后即为本地年月日。
        return format.format(Date())
    }

    /**
     * 记录一次单词默写结果，并在同一事务内更新单词难度与复习时间。
     *
     * 规则：
     * 1. 每次提交都插入新记录，并更新单词的 reviewed_at。
     * 2. 同一天重复默写同一个词会保留多条独立记录。
     * 3. 难度调整：
     *    - 本次错误（isCorrect = false，即中途选错过）→ 难度 +1；
     *    - 本次正确 → 从本次向前数「连续完美（无错）」的记录条数，再把本次计入总数。
     *      只有「连续完美总数 > 1 且为 5 的倍数」时才难度 -1（即第 5、10、15…次连续正确才降），
     *      其余情况不动。遇到一次有错误的记录即终止计数，链条被错误打断就不再累加。
     *    - 难度有下限 0（words 表的 CHECK 约束不允许负数）。
     *
     * @param wordId 本次完成默写的单词主键。
     * @param isCorrect 本次是否没有选错候选项。
     * @param wrongCount 本次选错候选项的次数。
     * @param hintCount 本次点击提示的次数。
     * @param module 本次记录所属的稳定复习模式标识。
     * @return Unit
     */
    fun addDictationRecord(
        wordId: Long,
        isCorrect: Boolean,
        wrongCount: Int,
        hintCount: Int,
        module: String,
    ) {
        // 写连接与事务保证"插记录 + 改难度"原子，要么都成要么都回滚。
        val db = writableDatabase
        db.beginTransaction()
        try {
            // 本机时区下的"今天"，写入 created_date 供按天统计使用。
            val today = localDateString()
            // 读取当前难度（null 视为 0）。
            val curDiff = getWordDifficulty(db, wordId)
            // 先以当前难度作基准，下面再决定增减。
            var newDiff = curDiff
            if (!isCorrect) {
                // 本次默写出过错：难度 +1，下次会更早被安排复习。
                newDiff = curDiff + 1
            } else {
                // 本次正确：先数「本次之前」连续完美的历史条数（查询时本次记录尚未插入，天然不含本次）。
                // 遇到第一条有错误的记录立即停止，链条被错误打断就只统计到错误为止。
                val priorPerfect = countConsecutivePerfect(db, wordId)
                // 把本次（必然完美）计入总数，得到「连续完美总数」。
                val streak = priorPerfect + 1
                // 第 5、10、15…次连续完美时降低难度；下限由 words 表约束为 0。
                if (streak > 1 && streak % 5 == 0) newDiff = (curDiff - 1).coerceAtLeast(0)
            }
            // 插入本次记录（不再判断今天是否已有）。
            val now = System.currentTimeMillis()
            val values = ContentValues().apply {
                // 不再写死 dictation，让首页四种模式可以分别按该字段统计进度。
                put("module", module)
                put("word_id", wordId)
                put("is_correct", if (isCorrect) 1 else 0)
                put("wrong_count", wrongCount)
                put("hint_count", hintCount)
                put("difficulty_before", curDiff)
                put("difficulty_after", newDiff)
                put("created_at", now)
                put("created_date", today)
            }
            // 插入失败（如并发）直接抛错，由调用方转成 PlatformException。
            db.insertOrThrow("record", null, values)
            // 更新单词难度与最近复习时间。
            val wordValues = ContentValues().apply {
                put("difficulty", newDiff)
                put("reviewed_at", now)
            }
            db.update("words", wordValues, "id = ?", arrayOf(wordId.toString()))
            // 标记事务成功。
            db.setTransactionSuccessful()
        } finally {
            // 异常自动回滚，保证记录与难度一致。
            db.endTransaction()
        }
    }

    /** 读取单词当前难度，null 视为 0。 */
    private fun getWordDifficulty(db: SQLiteDatabase, wordId: Long): Int {
        // 只查 difficulty 一列。
        db.query(
            "words",
            arrayOf("difficulty"),
            "id = ?",
            arrayOf(wordId.toString()),
            null, null, null,
        ).use { cursor ->
            // 找不到或字段为 null 都返回 0。
            if (cursor.moveToNext()) {
                val index = cursor.getColumnIndexOrThrow("difficulty")
                if (cursor.isNull(index)) return 0
                return cursor.getInt(index)
            }
        }
        // 单词不存在也保护为 0。
        return 0
    }

    /**
     * 统计「本次之前」该单词**连续完美**（无错）的历史记录条数。
     *
     * 调用方在插入「本次记录」之前调用本函数，因此按 id 倒序取到的记录全是本次之前的，
     * 天然不含本次；是否再降难度由调用方把本次累加后用「总数 > 1 且为 5 的倍数」判断。
     *
     * 注意这里按"记录条"而不是"天"统计：一天内多次默写会产生多条记录，每条都算数。
     * 按 id 倒序（等价于写入顺序倒序）从最新往前数，遇到第一条错误立即停止——
     * 连续链条一旦被错误打断，更久以前的正确记录不再计入。
     *
     * 查询不加 LIMIT：必须数到第一条错误才停，截断会漏掉打断点导致计数偏多、
     * 进而误判"又是 5 的倍数"重复减难度。由于遇到错误即停，正常数据量下返回不会很大。
     *
     * @param db 当前默写事务使用的 SQLite 连接。
     * @param wordId 需要统计连续正确次数的单词主键。
     * @return 本次记录写入前连续完美的历史记录数量。
     */
    private fun countConsecutivePerfect(
        db: SQLiteDatabase,
        wordId: Long,
    ): Int {
        // 本次之前连续完美的条数。
        var count = 0
        // 查该词全部历史记录，按 id 倒序（最新在前），由下方循环在遇到错误时打断。
        db.query(
            "record",
            arrayOf("is_correct"),
            "word_id = ?",
            arrayOf(wordId.toString()),
            null, null,
            // 自增主键倒序 = 写入时间倒序，比 created_at 更稳（同毫秒也不会乱序）。
            "id DESC",
        ).use { cursor ->
            while (cursor.moveToNext()) {
                // 这一条是否正确（原生用 1/0 存布尔）。
                val correct = cursor.getInt(cursor.getColumnIndexOrThrow("is_correct")) == 1
                // 正确才累加，遇到错误立即打断计数。
                if (correct) {
                    count += 1
                } else {
                    break
                }
            }
        }
        // 返回本次之前的连续完美条数（不含本次）。
        return count
    }

    /**
     * 今日复习的单词数量：按天 + 按单词汇总。
     *
     * 首页副标题「今日复习 X/目标」用的就是它。由于同一个词一天可能有多条记录
     * （重复默写、再试一次），必须用 COUNT(DISTINCT word_id) 去重，
     * 否则同一个词练两遍会被算成两个词。
     *
     * @return 今日完成过默写的不同单词数量。
     */
    fun getTodayReviewWordCount(): Int {
        // 只读连接即可。
        val db = readableDatabase
        // 本机时区下的"今天"。
        val today = localDateString()
        // rawQuery 直接执行聚合 SQL，参数用占位符防注入。
        // 只统计"已开发的复习模块"：未开放玩法（词义连连等）即使以后误写入，
        // 也不会让首页"今日复习 X/目标"提前虚涨。兼容历史 dictation 记录。
        db.rawQuery(
            """
            SELECT COUNT(DISTINCT word_id)
            FROM record
            WHERE created_date = ?
              AND module IN ('listening_meaning', 'dictation')
            """.trimIndent(),
            arrayOf(today),
        ).use { cursor ->
            // 聚合查询必定返回一行一列，取第 0 列即为去重后的单词数。
            if (cursor.moveToFirst()) return cursor.getInt(0)
        }
        // 理论上不会走到这里，兜底返回 0。
        return 0
    }

    /**
     * 按复习模式统计今日完成的单词数，每个模式内部按单词去重。
     *
     * 普通默写使用 dictation，它不属于首页四种复习模块，因此查询只接收四个
     * 稳定模块键。升级前的普通默写记录仍参与首页总复习量，但不会冒充听音辨义。
     *
     * @return 按模块标识升序的列表，每项形如 {module: "listening_meaning", count: 12}。
     */
    fun getTodayReviewCountsByModule(): List<Map<String, Any?>> {
        // 只读连接即可，不会改变任何历史记录。
        val db = readableDatabase
        // 本机时区下的“今天”，与写入 created_date 时使用同一套格式。
        val today = localDateString()
        // MethodChannel 能直接传输 List<Map>，Dart 端再转成按键读取的 Map。
        val result = ArrayList<Map<String, Any?>>()
        db.rawQuery(
            """
            SELECT
                module AS review_module,
                COUNT(DISTINCT word_id)
            FROM record
            WHERE created_date = ?
              AND module IN (
                  'listening_meaning',
                  'meaning_match',
                  'spelling_reinforcement',
                  'meaning_word_choice'
              )
            GROUP BY review_module
            ORDER BY review_module ASC
            """.trimIndent(),
            arrayOf(today),
        ).use { cursor ->
            // 每个模块只返回一行，未产生记录的模块不会出现在结果里。
            while (cursor.moveToNext()) {
                result.add(
                    mapOf(
                        "module" to cursor.getString(0),
                        "count" to cursor.getInt(1),
                    ),
                )
            }
        }
        return result
    }

    /**
     * 按天统计复习单词数（每天按单词去重），供首页趋势曲线与打卡质量卡使用。
     *
     * SQL 直接 GROUP BY created_date 并 COUNT(DISTINCT word_id)：
     * - 走 record_created_date 索引，本地库量级（一年几万条）下为毫秒级；
     * - 聚合在原生完成，只把"日期 → 数量"的少量结果送回 Dart。
     *
     * @param sinceDate 起始日期（含），格式 yyyy-MM-dd；传 null 表示统计全部历史。
     * @return 按日期升序的列表，每项形如 {date: "2026-08-18", count: 12}。
     */
    fun getDailyReviewCounts(sinceDate: String?): List<Map<String, Any?>> {
        // 只读连接即可。
        val db = readableDatabase
        // 结果列表：一天一个 Entry。
        val result = ArrayList<Map<String, Any?>>()
        // 模块白名单：曲线 / 打卡质量只统计已开发玩法，未开放模块的记录
        // 不参与总趋势，避免以后接入新玩法时旧图表口径悄悄变化。
        val moduleFilter = "AND module IN ('listening_meaning', 'dictation')"
        // 有起始日期就带上 WHERE 过滤，否则统计全部；占位符防注入。
        val cursor = if (sinceDate == null) {
            db.rawQuery(
                """
                SELECT created_date, COUNT(DISTINCT word_id)
                FROM record
                WHERE 1 = 1 $moduleFilter
                GROUP BY created_date
                ORDER BY created_date ASC
                """.trimIndent(),
                null,
            )
        } else {
            db.rawQuery(
                """
                SELECT created_date, COUNT(DISTINCT word_id)
                FROM record
                WHERE created_date >= ?
                  $moduleFilter
                GROUP BY created_date
                ORDER BY created_date ASC
                """.trimIndent(),
                arrayOf(sinceDate),
            )
        }
        cursor.use {
            // 逐行读取"日期 + 去重数量"。
            while (it.moveToNext()) {
                result.add(
                    mapOf(
                        "date" to it.getString(0),
                        "count" to it.getInt(1),
                    ),
                )
            }
        }
        return result
    }

    /**
     * 按月统计复习单词数（每月按单词去重），供趋势曲线"半年/一年"档使用。
     *
     * 用 substr(created_date, 1, 7) 截取 'yyyy-MM' 作为月份键；按月去重可以
     * 正确处理"同一个词在同一个月的不同天各复习一遍"——不能把每日去重数
     * 简单相加，否则会重复计数。
     *
     * @param sinceYearMonth 起始月份（含），格式 yyyy-MM；传 null 表示统计全部历史。
     * @return 按月份升序的列表，每项形如 {month: "2026-08", count: 34}。
     */
    fun getMonthlyReviewCounts(sinceYearMonth: String?): List<Map<String, Any?>> {
        // 只读连接即可。
        val db = readableDatabase
        // 结果列表：一月一个 Entry。
        val result = ArrayList<Map<String, Any?>>()
        // 月份键截取前 7 位；WHERE 同样按月份键比较，保持口径一致。
        // 同样只统计已开发模块，与日粒度口径对齐。
        val moduleFilter = "AND module IN ('listening_meaning', 'dictation')"
        val whereClause = if (sinceYearMonth == null) "" else "WHERE substr(created_date, 1, 7) >= ?"
        val finalWhere = if (whereClause.isEmpty()) {
            "WHERE 1 = 1 $moduleFilter"
        } else {
            "$whereClause $moduleFilter"
        }
        val args = if (sinceYearMonth == null) null else arrayOf(sinceYearMonth)
        db.rawQuery(
            """
            SELECT substr(created_date, 1, 7), COUNT(DISTINCT word_id)
            FROM record
            $finalWhere
            GROUP BY substr(created_date, 1, 7)
            ORDER BY substr(created_date, 1, 7) ASC
            """.trimIndent(),
            args,
        ).use { cursor ->
            // 逐行读取"月份 + 去重数量"。
            while (cursor.moveToNext()) {
                result.add(
                    mapOf(
                        "month" to cursor.getString(0),
                        "count" to cursor.getInt(1),
                    ),
                )
            }
        }
        return result
    }

    /**
     * 读取今日全部默写记录，供"今日复习"展示。
     *
     * 返回完整记录 Map 列表（每条含 word_id 等），Dart 端再去重出单词列表。
     *
     * @return 今日全部默写记录，按写入时间升序排列。
     */
    fun getTodayReviewWords(): List<Map<String, Any?>> {
        // 只读连接即可。
        val db = readableDatabase
        // 本机时区下的"今天"。
        val today = localDateString()
        // 结果列表。
        val result = ArrayList<Map<String, Any?>>()
        // 查询今天的全部记录，按时间升序。
        db.query(
            "record",
            null,
            "created_date = ?",
            arrayOf(today),
            null, null,
            "created_at ASC",
        ).use { cursor ->
            // 逐行拼成 Dart 需要的 Map。
            while (cursor.moveToNext()) {
                result.add(
                    linkedMapOf(
                        "id" to cursor.getLong(cursor.getColumnIndexOrThrow("id")),
                        "module" to cursor.getString(cursor.getColumnIndexOrThrow("module")),
                        "word_id" to cursor.getLong(cursor.getColumnIndexOrThrow("word_id")),
                        "is_correct" to (cursor.getInt(cursor.getColumnIndexOrThrow("is_correct")) == 1),
                        "wrong_count" to cursor.getInt(cursor.getColumnIndexOrThrow("wrong_count")),
                        "hint_count" to cursor.getInt(cursor.getColumnIndexOrThrow("hint_count")),
                        "difficulty_before" to cursor.getInt(cursor.getColumnIndexOrThrow("difficulty_before")),
                        "difficulty_after" to cursor.getInt(cursor.getColumnIndexOrThrow("difficulty_after")),
                        "created_at" to cursor.getLong(cursor.getColumnIndexOrThrow("created_at")),
                        "created_date" to cursor.getString(cursor.getColumnIndexOrThrow("created_date")),
                    ),
                )
            }
        }
        // 返回今日记录列表。
        return result
    }

    /** 把 Dart Word.toMap 的字段转换成 SQLite ContentValues。 */
    private fun wordValuesFromPayload(
        payload: Map<*, *>,
        now: Long,
        touchUpdatedAt: Boolean,
    ): ContentValues {
        // spelling 为业务必填字段，并移除意外首尾空格。
        val spelling = payload["spelling"]?.toString()?.trim().orEmpty()
        // 空拼写不允许进入数据库。
        require(spelling.isNotEmpty()) { "spelling 不能为空" }
        // apply 让多次 put 都作用于同一个 ContentValues。
        return ContentValues().apply {
            // 保存区分大小写的拼写。
            put("spelling", spelling)
            // 普通数字空值统一为 0，数据库 CHECK 会再次阻止负难度。
            put("difficulty", ((payload["difficulty"] as? Number)?.toLong() ?: 0).coerceAtLeast(0))
            // 可空音标保持 null，不将文本空值伪造成数字。
            putNullableString("phonetic_uk", payload["phonetic_uk"]?.toString())
            putNullableString("phonetic_us", payload["phonetic_us"]?.toString())
            // SQLite TEXT 列使用 JSON 数组字符串保存各类词形。
            put("plural", jsonStringArray(payload["plural"]))
            put("third_person_singular", jsonStringArray(payload["third_person_singular"]))
            put("gerund", jsonStringArray(payload["gerund"]))
            put("past_tense", jsonStringArray(payload["past_tense"]))
            put("past_participle", jsonStringArray(payload["past_participle"]))
            put("comparative", jsonStringArray(payload["comparative"]))
            put("superlative", jsonStringArray(payload["superlative"]))
            // 保存最近复习时间。
            put("reviewed_at", (payload["reviewed_at"] as? Number)?.toLong() ?: 0)
            // 新数据没有 created_at 时使用 now。
            put("created_at", (payload["created_at"] as? Number)?.toLong() ?: now)
            // 编辑操作始终使用 now；创建时允许保留导入数据传入的 updated_at。
            put(
                "updated_at",
                if (touchUpdatedAt) now else (payload["updated_at"] as? Number)?.toLong() ?: now,
            )
            // 支持未来恢复/软删除数据同步。
            put("deleted_at", (payload["deleted_at"] as? Number)?.toLong() ?: 0)
        }
    }

    /** 将提交的 Meaning 列表写入指定 Word。 */
    private fun replaceMeanings(db: SQLiteDatabase, wordId: Long, rawMeanings: Any?) {
        // MethodChannel 把 Dart List 还原成 Kotlin List；其他类型按空列表处理。
        val meanings = rawMeanings as? List<*> ?: emptyList<Any?>()
        // 遍历每条 Meaning Map。
        for (rawMeaning in meanings) {
            // 类型不正确时跳过并进入下一项，避免原生 ClassCastException。
            val meaning = rawMeaning as? Map<*, *> ?: continue
            // definitions 应为字符串列表。
            val definitions = (meaning["definitions"] as? List<*>)
                // 把动态项统一转换为字符串。
                ?.map { it.toString() }
                // 缺失时使用空数组。
                ?: emptyList()
            // 组装数据库字段。
            val values = ContentValues().apply {
                put("word_id", wordId)
                put("index", (meaning["index"] as? Number)?.toInt() ?: 0)
                put("pos", meaning["pos"]?.toString() ?: "")
                put("definitions", JSONArray(definitions).toString())
                put("created_at", (meaning["created_at"] as? Number)?.toLong() ?: 0)
                put("updated_at", (meaning["updated_at"] as? Number)?.toLong() ?: 0)
                put("deleted_at", (meaning["deleted_at"] as? Number)?.toLong() ?: 0)
            }
            // 外键与事务会确保关联正确。
            insertRow(db, "meanings", values)
        }
    }

    /** 将 SQLite 保存的 definitions JSON 文本还原为字符串列表。 */
    private fun jsonArrayToStrings(value: String): List<String> {
        // 解析 JSON 数组。
        val array = JSONArray(value)
        // 按数组长度生成不可变 List。
        return List(array.length()) { index -> array.getString(index) }
    }

    /** 把动态数组转成 SQLite TEXT 列使用的 JSON 字符串。 */
    private fun jsonStringArray(value: Any?): String {
        val items = (value as? List<*>)?.mapNotNull { item -> item?.toString() } ?: emptyList()
        return JSONArray(items).toString()
    }

    /** ContentValues 没有便捷可空 Long API，因此统一封装 put/putNull。 */
    private fun ContentValues.putNullableLong(key: String, value: Long?) {
        // 非空写真实数值，空值显式写 SQLite NULL。
        if (value == null) putNull(key) else put(key, value)
    }

    /** ContentValues 显式写入可空文本。 */
    private fun ContentValues.putNullableString(key: String, value: String?) {
        if (value == null) putNull(key) else put(key, value)
    }

    /** Cursor 安全读取可空 INTEGER 字段。 */
    private fun android.database.Cursor.nullableLong(columnName: String): Long? {
        // 先找到列下标，字段不存在时立即抛出便于定位 schema 错误。
        val index = getColumnIndexOrThrow(columnName)
        // SQLite NULL 对应 Kotlin null，否则读取 Long。
        return if (isNull(index)) null else getLong(index)
    }

    /** Cursor 安全读取可空文本字段。 */
    private fun android.database.Cursor.nullableString(columnName: String): String? {
        val index = getColumnIndexOrThrow(columnName)
        return if (isNull(index)) null else getString(index)
    }

    /** Cursor 把指定 JSON TEXT 列还原成 MethodChannel 支持的字符串列表。 */
    private fun android.database.Cursor.jsonStringList(columnName: String): List<String> {
        val index = getColumnIndexOrThrow(columnName)
        return if (isNull(index)) emptyList() else jsonArrayToStrings(getString(index))
    }
}
