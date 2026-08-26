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
        // 版本 4 新增 record 表，记录单词听音辨义结果并驱动难度变化。
        // 版本 5 不再新建表，仅补强 record 表的创建时机（onOpen 兜底建表），
        // 解决「库已升到某版本，但 record 表因历史升级路径缺失」导致写入静默失败的问题。
        // 版本 6 新增听音辨义候选项缓存表，让每道拼写/释义题长期复用相同干扰项。
        // 版本 7 新增学习会话表，保存随身听和听音辨义尚未完成的列表与页面进度。
        // 版本 8 为候选缓存增加正确答案位置，使四个候选的完整顺序可以长期恢复。
        // 版本 9 以 README 为业务字段标准，重建词库并统一 JSON/SQLite 命名。
        // 版本 10 新增每日公共复习词单表，四种复习模式当天共用同一批单词。
        // 版本 11 为每日词单增加选词规则版本，规则变化后旧顺序只重建一次。
        // 版本 12 重建整个复习模块：每日词库 + 模块会话 + 复习记录三张表取代
        //         旧的 daily_review_plans 与 record，会话第一次拥有明确的
        //         「进行中 / 完成 / 中断 / 失败」状态，复习记录也开始携带连对次数、
        //         所属会话与复习时间前后值。随身听和词库底部普通听音辨义仍旧
        //         使用 learning_sessions，两套进度互不干扰。
        private const val databaseVersion = 12

        ///
        /// 模块会话类型：每日主线进度。
        ///
        /// 主线是"今天这个模块该做的那一遍"，完成之后模块进度才会翻绿。
        ///
        const val SESSION_KIND_DAILY = 1

        ///
        /// 模块会话类型：无限巩固练习。
        ///
        /// 主线完成后再进入模块开的局，单词取自"今天一半 + 明天一半"，
        /// 只更新难度、不更新单词的复习时间。
        ///
        const val SESSION_KIND_REINFORCE = 2

        /// 会话状态：进行中，同一模块同一天最多只有一条。
        const val SESSION_STATUS_ACTIVE = 1

        /// 会话状态：完成，整局跑完且一次都没错。
        const val SESSION_STATUS_COMPLETED = 2

        /// 会话状态：中断，通常是用户改了「每日复习」数量。
        const val SESSION_STATUS_ABORTED = 3

        /// 会话状态：失败，整局跑完但出现过错误，或者倒计时耗尽。
        const val SESSION_STATUS_FAILED = 4
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
        // 创建听音辨义候选项缓存表。
        createListeningMeaningOptionCacheTable(db)
        // 创建随身听与词库底部普通听音辨义使用的长期会话表。
        createLearningSessionTable(db)
        // 复习模块三张表：每日词库、模块会话、复习记录。
        createReviewSchema(db)
        // 音节划分表：每个单词一条数据，拼写即主键，供“单词拼写”功能复用。
        createSyllableDivisionsTable(db)
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
        // 版本 12 按用户确认「当作新应用重新开始」，直接丢弃旧的复习计划与
        // 听音辨义记录表，用新的三张表重建。词库、释义、分组完全不受影响。
        if (oldVersion < 12 && newVersion >= 12) {
            rebuildReviewSchema(db)
        }
    }

    /**
     * 每次打开数据库连接时兜底补建全部辅助表。
     *
     * 这是防止「库版本已升级，但某张表因历史升级路径缺失」的最后一道保险，
     * 避免写入时因 no such table 静默失败。所有建表语句都带 IF NOT EXISTS，
     * 因此每次打开重复调用完全安全。
     */
    override fun onOpen(db: SQLiteDatabase) {
        // 先执行 SQLiteOpenHelper 标准打开流程。
        super.onOpen(db)
        // 兜底补建候选缓存表，覆盖任何历史升级遗漏。
        createListeningMeaningOptionCacheTable(db)
        // CREATE TABLE IF NOT EXISTS 不会给旧表补字段，因此再单独确认版本 8 的位置列。
        ensureListeningMeaningOptionCorrectIndexColumn(db)
        // 随身听/普通听音辨义的长期会话属于辅助数据，幂等补建可覆盖升级遗漏。
        createLearningSessionTable(db)
        // 复习模块三张表同样使用幂等建表，覆盖任何历史升级遗漏。
        createReviewSchema(db)
        // 分组排序表只是内部实现，幂等补建不会改动 group 业务字段。
        createGroupPositionsTable(db)
        // 音节划分表同样幂等补建，覆盖任何历史升级遗漏。
        createSyllableDivisionsTable(db)
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
        db.execSQL("DROP TABLE IF EXISTS listening_meaning_option_cache")
        db.execSQL("DROP TABLE IF EXISTS learning_sessions")
        db.execSQL("DROP TABLE IF EXISTS daily_review_plans")
        db.execSQL("DROP TABLE IF EXISTS record")
        db.execSQL("DROP TABLE IF EXISTS review_records")
        db.execSQL("DROP TABLE IF EXISTS review_sessions")
        db.execSQL("DROP TABLE IF EXISTS daily_word_sets")
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
        createListeningMeaningOptionCacheTable(db)
        createLearningSessionTable(db)
        createReviewSchema(db)
        createIndexes(db)
    }

    /**
     * 丢弃旧复习数据并建立新的复习模块三张表。
     *
     * 旧的 `daily_review_plans`（每日公共词单）和 `record`（听音辨义记录）字段
     * 结构与新架构差异过大：会话没有状态、记录没有连对次数也没有所属会话。
     * 用户已确认「当作新应用重新开始」，因此这里直接丢弃重建，
     * 换来一个干净、没有历史包袱的复习模块。词库本身完全不受影响。
     *
     * @param db 需要重建复习结构的 SQLite 连接。
     * @return Unit
     */
    private fun rebuildReviewSchema(db: SQLiteDatabase) {
        // 先删子表再删父表：复习记录引用会话，会话引用每日词库。
        db.execSQL("DROP TABLE IF EXISTS review_records")
        db.execSQL("DROP TABLE IF EXISTS review_sessions")
        db.execSQL("DROP TABLE IF EXISTS daily_word_sets")
        // 旧结构不再使用，一并丢弃避免占用空间和造成理解负担。
        db.execSQL("DROP TABLE IF EXISTS daily_review_plans")
        db.execSQL("DROP TABLE IF EXISTS record")
        // 按依赖顺序重建。
        createReviewSchema(db)
    }

    /** 一次性建立复习模块需要的三张表与索引；全部语句幂等。 */
    private fun createReviewSchema(db: SQLiteDatabase) {
        // 每日词库是父表，必须最先建立。
        createDailyWordSetTable(db)
        // 模块会话引用每日词库。
        createReviewSessionTable(db)
        // 复习记录引用会话与单词。
        createReviewRecordTable(db)
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
            db.delete("listening_meaning_option_cache", "word_id = ?", arrayOf(id.toString()))
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
        writableDatabase.delete("listening_meaning_option_cache", "word_id = ?", arrayOf(id.toString()))
        // 会话列表可能包含这个单词；删除后无法完整恢复，因此清掉未完成会话。
        writableDatabase.delete("learning_sessions", null, null)
        // 复习会话同理：单词没了就凑不齐这一局，统一按「中断」收尾，
        // 下次进模块会用修好的每日词库重新开一局。
        abortActiveReviewSessions(onlyStale = false)
    }

    /** 清空全部本地数据，用于「清空数据」与「导入前整库替换」。 */
    fun clearAllWords() {
        // 获取可写连接。
        val db = writableDatabase
        // 事务保证全部业务表与候选缓存要么都被清空，要么都不动。
        db.beginTransaction()
        try {
            // 先清空候选缓存、学习会话与其他子表，再清空父表，避免遗留失效快照。
            db.delete("listening_meaning_option_cache", null, null)
            db.delete("learning_sessions", null, null)
            // 复习侧按「记录 → 会话 → 词库」的依赖顺序清空。
            db.delete("review_records", null, null)
            db.delete("review_sessions", null, null)
            db.delete("daily_word_sets", null, null)
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
            db.delete("listening_meaning_option_cache", null, null)
            db.delete("learning_sessions", null, null)
            // 复习记录、会话和每日词库保存的都是旧词库主键，整库替换后必须同时作废。
            db.delete("review_records", null, null)
            db.delete("review_sessions", null, null)
            db.delete("daily_word_sets", null, null)
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
     * 创建「每日词库」表（幂等：用 IF NOT EXISTS，可重复调用）。
     *
     * 生活化解释：这张表就是「今天要背的这一批词」。四个复习模块共用同一批，
     * 所以一天只有一行，主键就是日期。`word_count` 冗余保存列表长度，让首页
     * 判断「数量是不是还等于设置里的每日复习」时不必先解析 JSON。
     *
     * @param db 需要建表的 SQLite 连接。
     * @return Unit
     */
    private fun createDailyWordSetTable(db: SQLiteDatabase) {
        // set_date 用 UNIQUE 而不是主键，是为了让会话表能用稳定的自增 id 做外键。
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS daily_word_sets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                set_date TEXT NOT NULL UNIQUE,
                word_count INTEGER NOT NULL CHECK (word_count >= 0),
                word_ids_json TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            )
            """.trimIndent(),
        )
    }

    /**
     * 创建「模块会话」表（幂等）。
     *
     * 一个会话 = 一个模块的一局。`kind` 区分「今天的主线任务」和「主线完成后
     * 的无限巩固练习」；`status` 记录这一局最后走到了哪一步。
     *
     * `word_ids_json` 保存本局自己的单词快照，而不是只存 `word_set_id`——因为
     * 巩固会话的单词是「今日一半 + 明日一半」，这批词并不属于任何一个每日词库，
     * 光靠词库 id 无法还原。`word_set_id` 保留成可空的来源标记，方便回溯。
     *
     * @param db 需要建表的 SQLite 连接。
     * @return Unit
     */
    private fun createReviewSessionTable(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS review_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                module TEXT NOT NULL,
                kind INTEGER NOT NULL CHECK (kind IN (1, 2)),
                status INTEGER NOT NULL CHECK (status IN (1, 2, 3, 4)),
                word_set_id INTEGER NULL,
                word_ids_json TEXT NOT NULL,
                state_json TEXT NOT NULL DEFAULT '{}',
                wrong_total INTEGER NOT NULL DEFAULT 0 CHECK (wrong_total >= 0),
                session_date TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                finished_at INTEGER NULL,
                FOREIGN KEY (word_set_id) REFERENCES daily_word_sets(id) ON DELETE SET NULL
            )
            """.trimIndent(),
        )
        // 「今天这个模块最新的一条会话」是最高频查询，(模块, 日期, id) 直接覆盖。
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS review_sessions_module_date " +
                "ON review_sessions(module, session_date, id)",
        )
        // 「所有还在进行中的会话」用于改设置时批量中断，以及跨天清理僵尸会话。
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS review_sessions_status " +
                "ON review_sessions(status, session_date)",
        )
    }

    /**
     * 创建「复习记录」表（幂等）。
     *
     * 四个模块每答完一个单词就写一条，所有模块共用这张表，靠 `module` 区分。
     *
     * 字段里有两组「前后值」：
     * - `difficulty_before` / `difficulty_after`：这次答题让难度怎么变的；
     * - `reviewed_at_before` / `reviewed_at_after`：这次答题有没有推进复习时间。
     *   巩固会话不推进复习时间，两个值会完全相同，一眼就能看出「练了但没算数」。
     *
     * `streak` 是连对次数：答对就在上一条的基础上 +1，答错直接归 0。有了它，
     * 判断「连对 5 次降难度」时不用再回头扫描历史记录。
     *
     * @param db 需要建表和索引的 SQLite 连接。
     * @return Unit
     */
    private fun createReviewRecordTable(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS review_records (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word_id INTEGER NOT NULL,
                streak INTEGER NOT NULL DEFAULT 0 CHECK (streak >= 0),
                module TEXT NOT NULL,
                session_id INTEGER NULL,
                is_correct INTEGER NOT NULL,
                wrong_count INTEGER NOT NULL DEFAULT 0 CHECK (wrong_count >= 0),
                hint_count INTEGER NOT NULL DEFAULT 0 CHECK (hint_count >= 0),
                difficulty_before INTEGER NOT NULL,
                difficulty_after INTEGER NOT NULL,
                reviewed_at_before INTEGER NOT NULL DEFAULT 0,
                reviewed_at_after INTEGER NOT NULL DEFAULT 0,
                extra_json TEXT NOT NULL DEFAULT '{}',
                created_at INTEGER NOT NULL,
                created_date TEXT NOT NULL,
                FOREIGN KEY (word_id) REFERENCES words(id) ON DELETE CASCADE,
                FOREIGN KEY (session_id) REFERENCES review_sessions(id) ON DELETE SET NULL
            )
            """.trimIndent(),
        )
        // 首页统计口径是「今天一次做对的不同单词数」，(日期, 是否全对) 正好覆盖。
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS review_records_date_correct " +
                "ON review_records(created_date, is_correct)",
        )
        // 写记录前要取「这个词上一条记录的连对次数」，(word_id, id) 可直接倒序取首行。
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS review_records_word_seq " +
                "ON review_records(word_id, id)",
        )
        // 结算时要数「本局有没有出过错」，按会话聚合走这条索引。
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS review_records_session " +
                "ON review_records(session_id)",
        )
    }

    /** 创建听音辨义候选项缓存表；一个 cache_key 对应一道具体拼写题或释义题。 */
    private fun createListeningMeaningOptionCacheTable(db: SQLiteDatabase) {
        // 干扰项使用 JSON 数组保存；correct_index 记录正确答案插入三个干扰项的位置。
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS listening_meaning_option_cache (
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
     * 创建音节划分表；一个单词一条数据，spelling 即主键。
     *
     * 这张表为未来的“单词拼写”功能服务：App 为每个单词缓存它的音节切分，
     * 避免每次都靠算法现场算，也允许用户手动覆盖。syllables 用 JSON 数组
     * 保存切好的块（如 ["tra","di","tion"]），source 标记来源，updated_at
     * 记录最后修改时间，便于排查与排重。
     */
    private fun createSyllableDivisionsTable(db: SQLiteDatabase) {
        // 建表语句带 IF NOT EXISTS，每次打开数据库重复调用完全安全。
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS syllable_divisions (
                word TEXT PRIMARY KEY,
                syllables TEXT NOT NULL,
                source TEXT NOT NULL,
                updated_at INTEGER NOT NULL
            )
            """.trimIndent(),
        )
    }

    /** 按单词读取已保存的音节划分；表里没有时返回 null。 */
    fun getSyllableDivision(word: String): Map<String, Any?>? {
        // 精确查询主键，最多只会返回一行。
        readableDatabase.query(
            "syllable_divisions",
            arrayOf("syllables", "source"),
            "word = ?",
            arrayOf(word),
            null,
            null,
            null,
            "1",
        ).use { cursor ->
            // 没有行表示这个单词还没算过或没手动设过。
            if (!cursor.moveToFirst()) return null
            // syllables 是 JSON 数组字符串，直接回传给 Dart 由 jsonDecode 还原成列表。
            return mapOf(
                "syllables" to cursor.getString(cursor.getColumnIndexOrThrow("syllables")),
                "source" to cursor.getString(cursor.getColumnIndexOrThrow("source")),
            )
        }
    }

    /** 新增或覆盖一个单词的音节划分；主键冲突时整体替换。 */
    fun saveSyllableDivision(word: String, syllablesJson: String, source: String) {
        // ContentValues 对应 syllable_divisions 表的一整行。
        val values = ContentValues().apply {
            put("word", word)
            put("syllables", syllablesJson)
            put("source", source)
            // 时间戳用毫秒，和项目里其它表保持一致，便于统一排重与调试。
            put("updated_at", System.currentTimeMillis())
        }
        // word 是 PRIMARY KEY，冲突时整体替换：刷新备选、用户手动覆盖都只需一次写入。
        writableDatabase.insertWithOnConflict(
            "syllable_divisions",
            null,
            values,
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    /**
     * 为旧候选缓存表补上正确答案位置列。
     *
     * SQLite 的 CREATE TABLE IF NOT EXISTS 只会跳过已存在表，不会自动补新字段，
     * 因此升级和打开数据库时都通过 PRAGMA 检查一次。这个操作只改表结构，旧候选
     * 名字完整保留；null 位置会在 Dart 首次读取后自动写成 0～3 的实际下标。
     */
    private fun ensureListeningMeaningOptionCorrectIndexColumn(db: SQLiteDatabase) {
        // PRAGMA table_info 返回表的全部字段定义，其中 name 列保存字段名。
        val hasCorrectIndex = db.rawQuery(
            "PRAGMA table_info(listening_meaning_option_cache)",
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
            "ALTER TABLE listening_meaning_option_cache " +
                "ADD COLUMN correct_index INTEGER NULL CHECK (correct_index BETWEEN 0 AND 3)",
        )
    }

    /** 创建学习会话表；随身听和听音辨义各自最多保存一条未完成记录。 */
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

    /** 按小题 key 读取干扰项及正确答案位置；没有缓存时返回 null。 */
    fun getListeningMeaningOptionCache(cacheKey: String): Map<String, Any?>? {
        // 精确查询主键，最多只会返回一行。
        readableDatabase.query(
            "listening_meaning_option_cache",
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
    fun saveListeningMeaningOptionCache(
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
            "listening_meaning_option_cache",
            null,
            values,
            SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    /** 读取全部未完成学习会话；当前最多返回随身听和听音辨义两行。 */
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

    // ─────────────────────────────────────────────────────────────────────
    // 复习模块：每日词库
    // ─────────────────────────────────────────────────────────────────────

    /**
     * 读取设备本地今天的每日词库；今天还没建过时返回 null。
     *
     * @return 今天的词库行；尚未创建时为 null。
     */
    fun getTodayWordSet(): Map<String, Any?>? {
        // 与复习记录的 created_date 使用同一个方法，跨午夜时口径一致。
        return readWordSet(readableDatabase, localDateString())
    }

    /**
     * 保存（覆盖）今天的每日词库，并顺手清掉更早日期的历史词库。
     *
     * 历史词库没有任何查询价值：会话已经把自己那一局的单词快照存下来了，
     * 复习记录也不依赖词库。留着只会让表越来越大，所以写新的时候一并删掉。
     *
     * @param wordIds 按排序规则选出的单词主键，顺序即答题顺序。
     * @return 实际落库后的词库行。
     */
    fun saveTodayWordSet(wordIds: List<Long>): Map<String, Any?> {
        // 主键必须全部为正数；无效 id 会让四个模块都无法组装同一份词单。
        if (wordIds.any { it <= 0 }) error("每日词库包含无效单词 id")
        val db = writableDatabase
        val today = localDateString()
        val now = System.currentTimeMillis()
        db.beginTransaction()
        try {
            // 先清掉往日词库；会话表的外键是 ON DELETE SET NULL，不会连累历史会话。
            db.delete("daily_word_sets", "set_date <> ?", arrayOf(today))
            // 单词列表与数量每次都覆盖；updated_at 记录最后一次调整时间。
            val mutable = ContentValues().apply {
                put("word_count", wordIds.size)
                put("word_ids_json", JSONArray(wordIds).toString())
                put("updated_at", now)
            }
            // 今天已经有一行时就地更新，保留原来的自增 id，
            // 这样正在进行中的会话不会突然指向一个不存在的词库。
            val updated = db.update("daily_word_sets", mutable, "set_date = ?", arrayOf(today))
            if (updated == 0) {
                // 今天第一次建词库：补上日期与创建时间后整行插入。
                db.insertOrThrow(
                    "daily_word_sets",
                    null,
                    ContentValues(mutable).apply {
                        put("set_date", today)
                        put("created_at", now)
                    },
                )
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        // 重新读一次，把自增 id 与真实时间一起返回给 Dart。
        return readWordSet(db, today) ?: error("每日词库保存后无法读回")
    }

    /** 按日期读取一行每日词库；不存在时返回 null。 */
    private fun readWordSet(db: SQLiteDatabase, date: String): Map<String, Any?>? {
        db.query(
            "daily_word_sets",
            arrayOf("id", "set_date", "word_count", "word_ids_json", "created_at", "updated_at"),
            "set_date = ?",
            arrayOf(date),
            null,
            null,
            null,
            "1",
        ).use { cursor ->
            if (!cursor.moveToFirst()) return null
            return linkedMapOf(
                "id" to cursor.getLong(cursor.getColumnIndexOrThrow("id")),
                "set_date" to cursor.getString(cursor.getColumnIndexOrThrow("set_date")),
                "word_count" to cursor.getInt(cursor.getColumnIndexOrThrow("word_count")),
                "word_ids" to jsonArrayToLongs(
                    cursor.getString(cursor.getColumnIndexOrThrow("word_ids_json")),
                ),
                "created_at" to cursor.getLong(cursor.getColumnIndexOrThrow("created_at")),
                "updated_at" to cursor.getLong(cursor.getColumnIndexOrThrow("updated_at")),
            )
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // 复习模块：模块会话
    // ─────────────────────────────────────────────────────────────────────

    /**
     * 读取某个模块今天最新的一条会话（不论什么状态）。
     *
     * Dart 的「创建会话」流程第一步就是它：拿到最新会话后，如果状态还是
     * 「进行中」就直接续上，否则再决定开主线还是开巩固。
     *
     * @param module 模块稳定标识，例如 listening_meaning。
     * @return 今天最新的一条会话；今天还没开过局时为 null。
     */
    fun getLatestReviewSession(module: String): Map<String, Any?>? {
        return queryReviewSession(
            "module = ? AND session_date = ?",
            arrayOf(module, localDateString()),
        )
    }

    /**
     * 读取某个模块今天「已完成」的主线会话。
     *
     * 有这条记录，才说明今天的主线任务已经过关，接下来进模块开的是巩固局。
     *
     * @param module 模块稳定标识。
     * @return 今天最新一条已完成的主线会话；没有时为 null。
     */
    fun getCompletedDailyReviewSession(module: String): Map<String, Any?>? {
        return queryReviewSession(
            "module = ? AND session_date = ? AND kind = ? AND status = ?",
            arrayOf(
                module,
                localDateString(),
                SESSION_KIND_DAILY.toString(),
                SESSION_STATUS_COMPLETED.toString(),
            ),
        )
    }

    /**
     * 读取今天四个模块各自最新一条会话的状态，供首页卡片显示三态。
     *
     * SQL 里用「每个模块取 id 最大的那一行」的写法：先按模块分组取最大 id，
     * 再回表拿这一行的详细状态。
     *
     * @return 每项形如 {module, kind, status}；今天没开过局的模块不会出现。
     */
    fun getTodayReviewSessionStates(): List<Map<String, Any?>> {
        val result = ArrayList<Map<String, Any?>>()
        readableDatabase.rawQuery(
            """
           SELECT s.module, s.kind, s.status, s.state_json
           FROM review_sessions AS s
            INNER JOIN (
                SELECT module, MAX(id) AS max_id
                FROM review_sessions
                WHERE session_date = ?
                GROUP BY module
            ) AS latest ON latest.max_id = s.id
            ORDER BY s.module ASC
            """.trimIndent(),
            arrayOf(localDateString()),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                // 解析最新会话的页面快照，取出首页进度条要的分子分母。
                val stateJson = cursor.getString(3)
                result.add(
                    linkedMapOf(
                        "module" to cursor.getString(0),
                        "kind" to cursor.getInt(1),
                        "status" to cursor.getInt(2),
                        // 首页还要区分「今天主线到底过没过」，因此额外带上这一位。
                        "daily_completed" to hasCompletedDailySession(cursor.getString(0)),
                        // 首页进度条：已完成单词数 / 总单词数。
                        "reviewed_word_count" to parseStateInt(stateJson, "reviewedWordCount"),
                        "total_word_count" to parseStateInt(stateJson, "totalWordCount"),
                    ),
                )
            }
        }
        return result
    }

    /** 从会话页面快照（JSON）里安全读取一个整数字段；坏数据返回 0。 */
    private fun parseStateInt(stateJson: String?, key: String): Int {
        if (stateJson.isNullOrBlank()) return 0
        return try {
            JSONObject(stateJson).optInt(key, 0)
        } catch (e: Exception) {
            0
        }
    }

    /** 今天这个模块有没有一条已完成的主线会话。 */
    private fun hasCompletedDailySession(module: String): Boolean {
        readableDatabase.rawQuery(
            """
            SELECT 1 FROM review_sessions
            WHERE module = ? AND session_date = ? AND kind = ? AND status = ?
            LIMIT 1
            """.trimIndent(),
            arrayOf(
                module,
                localDateString(),
                SESSION_KIND_DAILY.toString(),
                SESSION_STATUS_COMPLETED.toString(),
            ),
        ).use { cursor -> return cursor.moveToFirst() }
    }

    /**
     * 新建一局会话并返回完整行。
     *
     * 同一模块同一天不允许出现两条「进行中」，因此插入前先把该模块残留的
     * 进行中会话统一改成「中断」——正常流程走不到这里，这是并发点击的保险。
     *
     * @param module 模块稳定标识。
     * @param kind 1=每日主线，2=无限巩固。
     * @param wordSetId 来源每日词库 id；巩固局也记录当天词库，便于回溯。
     * @param wordIds 本局实际单词快照，顺序即答题顺序。
     * @param stateJson 页面初始进度，通常是 "{}"。
     * @return 新建后的完整会话行。
     */
    fun createReviewSession(
        module: String,
        kind: Int,
        wordSetId: Long?,
        wordIds: List<Long>,
        stateJson: String,
    ): Map<String, Any?> {
        if (module.isBlank()) error("会话模块不能为空")
        if (kind != SESSION_KIND_DAILY && kind != SESSION_KIND_REINFORCE) {
            error("会话类型只能是 1（主线）或 2（巩固）")
        }
        if (wordIds.isEmpty()) error("会话单词列表不能为空")
        if (wordIds.any { it <= 0 }) error("会话包含无效单词 id")
        val db = writableDatabase
        val today = localDateString()
        val now = System.currentTimeMillis()
        var newId: Long
        db.beginTransaction()
        try {
            // 同模块残留的进行中会话先收尾，保证「最新一条」的语义永远干净。
            db.update(
                "review_sessions",
                ContentValues().apply {
                    put("status", SESSION_STATUS_ABORTED)
                    put("updated_at", now)
                    put("finished_at", now)
                },
                "module = ? AND status = ?",
                arrayOf(module, SESSION_STATUS_ACTIVE.toString()),
            )
            val values = ContentValues().apply {
                put("module", module)
                put("kind", kind)
                put("status", SESSION_STATUS_ACTIVE)
                if (wordSetId == null) putNull("word_set_id") else put("word_set_id", wordSetId)
                put("word_ids_json", JSONArray(wordIds).toString())
                put("state_json", stateJson.ifBlank { "{}" })
                put("wrong_total", 0)
                put("session_date", today)
                put("created_at", now)
                put("updated_at", now)
                putNull("finished_at")
            }
            newId = db.insertOrThrow("review_sessions", null, values)
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        return queryReviewSession("id = ?", arrayOf(newId.toString()))
            ?: error("会话创建后无法读回")
    }

    /**
     * 更新一局进行中会话的页面进度与累计错误数。
     *
     * 只允许改「进行中」的会话：已经结算的局不该再被 dispose 时的延迟保存覆盖。
     *
     * @param sessionId 会话主键。
     * @param stateJson 页面自己组装的进度 JSON。
     * @param wrongTotal 本局到目前为止的累计错误数。
     * @return Unit
     */
    fun updateReviewSessionProgress(sessionId: Long, stateJson: String, wrongTotal: Int) {
        if (stateJson.isBlank()) error("会话进度不能为空")
        writableDatabase.update(
            "review_sessions",
            ContentValues().apply {
                put("state_json", stateJson)
                put("wrong_total", wrongTotal.coerceAtLeast(0))
                put("updated_at", System.currentTimeMillis())
            },
            "id = ? AND status = ?",
            arrayOf(sessionId.toString(), SESSION_STATUS_ACTIVE.toString()),
        )
    }

    /**
     * 给一局会话结算：写入最终状态、最后一份进度和结束时间。
     *
     * @param sessionId 会话主键。
     * @param status 2=完成，3=中断，4=失败。
     * @param stateJson 结算时的最后一份进度；传 null 表示保持原样。
     * @param wrongTotal 结算时的累计错误数；传 null 表示保持原样。
     * @return 结算后的完整会话行。
     */
    fun finishReviewSession(
        sessionId: Long,
        status: Int,
        stateJson: String?,
        wrongTotal: Int?,
    ): Map<String, Any?> {
        if (status !in listOf(
                SESSION_STATUS_COMPLETED,
                SESSION_STATUS_ABORTED,
                SESSION_STATUS_FAILED,
            )
        ) {
            error("结算状态只能是 2（完成）、3（中断）或 4（失败）")
        }
        val now = System.currentTimeMillis()
        writableDatabase.update(
            "review_sessions",
            ContentValues().apply {
                put("status", status)
                put("updated_at", now)
                put("finished_at", now)
                if (stateJson != null && stateJson.isNotBlank()) put("state_json", stateJson)
                if (wrongTotal != null) put("wrong_total", wrongTotal.coerceAtLeast(0))
            },
            // 只结算尚未结算的局，重复点击「完成」不会把状态改来改去。
            "id = ? AND status = ?",
            arrayOf(sessionId.toString(), SESSION_STATUS_ACTIVE.toString()),
        )
        return queryReviewSession("id = ?", arrayOf(sessionId.toString()))
            ?: error("会话结算后无法读回")
    }

    /**
     * 把「进行中」的会话统一改成「中断」。
     *
     * 两种场景会用到：
     * 1. 用户改了设置里的「每日复习」数量——今天这批词要重新算，旧局作废；
     * 2. 跨天后打开 App——昨天没打完的局挂在那里没有意义，一起收掉。
     *
     * @param onlyStale true 表示只中断「不是今天」的会话（跨天清理）；
     *                  false 表示全部中断（改设置）。
     * @return 实际被中断的会话条数。
     */
    fun abortActiveReviewSessions(onlyStale: Boolean): Int {
        val now = System.currentTimeMillis()
        val values = ContentValues().apply {
            put("status", SESSION_STATUS_ABORTED)
            put("updated_at", now)
            put("finished_at", now)
        }
        return if (onlyStale) {
            writableDatabase.update(
                "review_sessions",
                values,
                "status = ? AND session_date <> ?",
                arrayOf(SESSION_STATUS_ACTIVE.toString(), localDateString()),
            )
        } else {
            writableDatabase.update(
                "review_sessions",
                values,
                "status = ?",
                arrayOf(SESSION_STATUS_ACTIVE.toString()),
            )
        }
    }

    /** 按条件读取一条会话（永远取 id 最大的那条），并转成 Dart 可解析的 Map。 */
    private fun queryReviewSession(
        selection: String,
        selectionArgs: Array<String>,
    ): Map<String, Any?>? {
        readableDatabase.query(
            "review_sessions",
            arrayOf(
                "id", "module", "kind", "status", "word_set_id", "word_ids_json",
                "state_json", "wrong_total", "session_date",
                "created_at", "updated_at", "finished_at",
            ),
            selection,
            selectionArgs,
            null,
            null,
            // 同一模块同一天可能有多条历史，永远取最新写入的那一条。
            "id DESC",
            "1",
        ).use { cursor ->
            if (!cursor.moveToFirst()) return null
            return linkedMapOf(
                "id" to cursor.getLong(cursor.getColumnIndexOrThrow("id")),
                "module" to cursor.getString(cursor.getColumnIndexOrThrow("module")),
                "kind" to cursor.getInt(cursor.getColumnIndexOrThrow("kind")),
                "status" to cursor.getInt(cursor.getColumnIndexOrThrow("status")),
                "word_set_id" to cursor.nullableLong("word_set_id"),
                "word_ids" to jsonArrayToLongs(
                    cursor.getString(cursor.getColumnIndexOrThrow("word_ids_json")),
                ),
                "state_json" to cursor.getString(cursor.getColumnIndexOrThrow("state_json")),
                "wrong_total" to cursor.getInt(cursor.getColumnIndexOrThrow("wrong_total")),
                "session_date" to cursor.getString(
                    cursor.getColumnIndexOrThrow("session_date"),
                ),
                "created_at" to cursor.getLong(cursor.getColumnIndexOrThrow("created_at")),
                "updated_at" to cursor.getLong(cursor.getColumnIndexOrThrow("updated_at")),
                "finished_at" to cursor.nullableLong("finished_at"),
            )
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // 复习模块：复习记录
    // ─────────────────────────────────────────────────────────────────────

    /**
     * 记录一次单词复习结果，并在同一事务内更新连对次数、难度与复习时间。
     *
     * 全部规则都在这一个事务里完成，调用方只要把「这次错了几下、提示了几次」
     * 交上来即可：
     *
     * 1. **连对次数**：取这个词上一条记录的 streak。本次全对就 +1，
     *    本次出过错就直接归 0 再从 0 开始（下一次答对是 1）。
     *    连对次数跨模块累计——听音辨义答对、词义连连接着答对，算连续两次。
     * 2. **难度**：本次出过错 → +1；本次全对且连对次数正好是 5 的倍数
     *    （5、10、15…）→ -1，下限 0。
     * 3. **复习时间**：只有 [updateReviewedAt] 为 true（每日主线会话）才推进到现在。
     *    巩固会话传 false，单词的复习时间原地不动，明天照样能被选中。
     *
     * @param wordId 本次完成的单词主键。
     * @param module 模块稳定标识。
     * @param sessionId 所属会话主键；没有会话（例如词库底部普通听音辨义）传 null。
     * @param wrongCount 本次选错次数，0 表示一气呵成。
     * @param hintCount 本次点击提示次数，只留档不影响正误。
     * @param updateReviewedAt 是否推进单词的复习时间。
     * @param extraJson 各模块自己的扩展字段 JSON；没有就传 "{}"。
     * @return 本次写入后的关键结果，供页面即时展示难度变化。
     */
    fun addReviewRecord(
        wordId: Long,
        module: String,
        sessionId: Long?,
        wrongCount: Int,
        hintCount: Int,
        updateReviewedAt: Boolean,
        extraJson: String,
    ): Map<String, Any?> {
        if (module.isBlank()) error("复习记录模块不能为空")
        // 写连接与事务保证「插记录 + 改难度 + 改复习时间」原子，要么全成要么全回滚。
        val db = writableDatabase
        db.beginTransaction()
        try {
            val today = localDateString()
            val now = System.currentTimeMillis()
            // 本次是否「一气呵成」：一次都没选错才算正确，点提示不影响判定。
            val isCorrect = wrongCount <= 0
            // 读取单词当前难度与复习时间，作为记录里的 before 值。
            val before = readWordReviewState(db, wordId)
            val difficultyBefore = before.first
            val reviewedAtBefore = before.second
            // 上一条记录的连对次数；这个词从没练过时视为 0。
            val previousStreak = readLatestStreak(db, wordId)
            // 答对就在上一条基础上 +1，答错直接断链归 0。
            val streak = if (isCorrect) previousStreak + 1 else 0
            // 难度：错一次 +1；连对次数每满 5 的倍数 -1，最低 0。
            val difficultyAfter = when {
                !isCorrect -> difficultyBefore + 1
                streak > 0 && streak % 5 == 0 -> (difficultyBefore - 1).coerceAtLeast(0)
                else -> difficultyBefore
            }
            // 复习时间：主线会话推进到现在，巩固会话保持原值。
            val reviewedAtAfter = if (updateReviewedAt) now else reviewedAtBefore

            val values = ContentValues().apply {
                put("word_id", wordId)
                put("streak", streak)
                put("module", module)
                if (sessionId == null) putNull("session_id") else put("session_id", sessionId)
                put("is_correct", if (isCorrect) 1 else 0)
                put("wrong_count", wrongCount.coerceAtLeast(0))
                put("hint_count", hintCount.coerceAtLeast(0))
                put("difficulty_before", difficultyBefore)
                put("difficulty_after", difficultyAfter)
                put("reviewed_at_before", reviewedAtBefore)
                put("reviewed_at_after", reviewedAtAfter)
                put("extra_json", extraJson.ifBlank { "{}" })
                put("created_at", now)
                put("created_date", today)
            }
            db.insertOrThrow("review_records", null, values)

            // 难度每次都写回；复习时间只有主线会话才动。
            val wordValues = ContentValues().apply {
                put("difficulty", difficultyAfter)
                if (updateReviewedAt) put("reviewed_at", reviewedAtAfter)
            }
            db.update("words", wordValues, "id = ?", arrayOf(wordId.toString()))

            // 会话累计错误数同步 +N，结算时不必再回头扫记录表。
            if (sessionId != null && wrongCount > 0) {
                db.execSQL(
                    "UPDATE review_sessions SET wrong_total = wrong_total + ?, updated_at = ? " +
                        "WHERE id = ?",
                    arrayOf<Any>(wrongCount.coerceAtLeast(0), now, sessionId),
                )
            }
            db.setTransactionSuccessful()
            return linkedMapOf(
                "streak" to streak,
                "is_correct" to isCorrect,
                "difficulty_before" to difficultyBefore,
                "difficulty_after" to difficultyAfter,
                "reviewed_at_before" to reviewedAtBefore,
                "reviewed_at_after" to reviewedAtAfter,
            )
        } finally {
            // 异常自动回滚，保证记录、难度与复习时间三者一致。
            db.endTransaction()
        }
    }

    /** 读取单词当前的难度与最近复习时间；单词不存在时按 (0, 0) 处理。 */
    private fun readWordReviewState(db: SQLiteDatabase, wordId: Long): Pair<Int, Long> {
        db.query(
            "words",
            arrayOf("difficulty", "reviewed_at"),
            "id = ?",
            arrayOf(wordId.toString()),
            null, null, null,
        ).use { cursor ->
            if (cursor.moveToNext()) {
                val difficultyIndex = cursor.getColumnIndexOrThrow("difficulty")
                val reviewedIndex = cursor.getColumnIndexOrThrow("reviewed_at")
                val difficulty = if (cursor.isNull(difficultyIndex)) 0 else cursor.getInt(difficultyIndex)
                val reviewedAt = if (cursor.isNull(reviewedIndex)) 0L else cursor.getLong(reviewedIndex)
                return difficulty to reviewedAt
            }
        }
        return 0 to 0L
    }

    /**
     * 读取某个单词最近一条复习记录的连对次数。
     *
     * 只取一行：新架构把连对次数直接存进了记录里，不必再像以前那样倒着扫
     * 一整串历史记录去数"连着对了几次"。
     *
     * @param db 当前事务使用的连接。
     * @param wordId 单词主键。
     * @return 上一条记录的连对次数；从未练过时返回 0。
     */
    private fun readLatestStreak(db: SQLiteDatabase, wordId: Long): Int {
        db.query(
            "review_records",
            arrayOf("streak"),
            "word_id = ?",
            arrayOf(wordId.toString()),
            null, null,
            // 自增主键倒序 = 写入顺序倒序，比 created_at 更稳（同毫秒也不会乱序）。
            "id DESC",
            "1",
        ).use { cursor ->
            if (cursor.moveToFirst()) return cursor.getInt(0)
        }
        return 0
    }

    // ─────────────────────────────────────────────────────────────────────
    // 复习模块：统计
    // ─────────────────────────────────────────────────────────────────────

    /**
     * 统计口径说明（首页数字、趋势曲线、打卡热力图三处必须完全一致）。
     *
     * 只统计 `is_correct = 1` 的记录，也就是「这次一气呵成、一个都没错」。
     * 练了但错过的词不算数——用户要的是「今天真正拿下了多少个词」。
     * 不区分模块，也不区分主线还是巩固：练了就算。
     */
    private val correctOnlyFilter = "is_correct = 1"

    /**
     * 今日复习数量：今天「一次做对」过的不同单词数。
     *
     * 同一个词今天练了三遍、其中一遍全对，就算 1 个；三遍都错，算 0 个。
     *
     * @return 今日一次做对过的不同单词数量。
     */
    fun getTodayReviewWordCount(): Int {
        readableDatabase.rawQuery(
            """
            SELECT COUNT(DISTINCT word_id)
            FROM review_records
            WHERE created_date = ? AND $correctOnlyFilter
            """.trimIndent(),
            arrayOf(localDateString()),
        ).use { cursor ->
            if (cursor.moveToFirst()) return cursor.getInt(0)
        }
        return 0
    }

    /**
     * 按天统计复习单词数（每天按单词去重），供趋势曲线与打卡热力图使用。
     *
     * @param sinceDate 起始日期（含），格式 yyyy-MM-dd；传 null 表示统计全部历史。
     * @return 按日期升序的列表，每项形如 {date: "2026-08-18", count: 12}。
     */
    fun getDailyReviewCounts(sinceDate: String?): List<Map<String, Any?>> {
        val result = ArrayList<Map<String, Any?>>()
        val where = if (sinceDate == null) {
            "WHERE $correctOnlyFilter"
        } else {
            "WHERE created_date >= ? AND $correctOnlyFilter"
        }
        readableDatabase.rawQuery(
            """
            SELECT created_date, COUNT(DISTINCT word_id)
            FROM review_records
            $where
            GROUP BY created_date
            ORDER BY created_date ASC
            """.trimIndent(),
            if (sinceDate == null) null else arrayOf(sinceDate),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                result.add(mapOf("date" to cursor.getString(0), "count" to cursor.getInt(1)))
            }
        }
        return result
    }

    /**
     * 按月统计复习单词数（每月按单词去重），供趋势曲线"半年/一年"档使用。
     *
     * 按月去重才是正确口径：同一个词在同月的两天各拿下一次，月度只应算 1 次，
     * 所以不能把每日去重数相加，而由 SQLite 直接按月 GROUP BY。
     *
     * @param sinceYearMonth 起始月份（含），格式 yyyy-MM；传 null 表示全部历史。
     * @return 按月份升序的列表，每项形如 {month: "2026-08", count: 34}。
     */
    fun getMonthlyReviewCounts(sinceYearMonth: String?): List<Map<String, Any?>> {
        val result = ArrayList<Map<String, Any?>>()
        val where = if (sinceYearMonth == null) {
            "WHERE $correctOnlyFilter"
        } else {
            "WHERE substr(created_date, 1, 7) >= ? AND $correctOnlyFilter"
        }
        readableDatabase.rawQuery(
            """
            SELECT substr(created_date, 1, 7), COUNT(DISTINCT word_id)
            FROM review_records
            $where
            GROUP BY substr(created_date, 1, 7)
            ORDER BY substr(created_date, 1, 7) ASC
            """.trimIndent(),
            if (sinceYearMonth == null) null else arrayOf(sinceYearMonth),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                result.add(mapOf("month" to cursor.getString(0), "count" to cursor.getInt(1)))
            }
        }
        return result
    }

    /**
     * 按天统计「掌握」单词数（每天按单词去重），供首页趋势曲线「掌握量」使用。
     *
     * 「掌握」的口径比「一次做对」更严格：要求这一遍既没错过（wrong_count=0）
     * 也没用过提示（hint_count=0），即用户口中「0 错 0 提醒」的记录。
     *
     * @param sinceDate 起始日期（含），格式 yyyy-MM-dd；传 null 表示统计全部历史。
     * @return 按日期升序的列表，每项形如 {date: "2026-08-18", count: 8}。
     */
    fun getDailyMasteredCounts(sinceDate: String?): List<Map<String, Any?>> {
        val result = ArrayList<Map<String, Any?>>()
        // 过滤条件：没错且没提示，才是真正的「掌握」。
        val filter = "wrong_count = 0 AND hint_count = 0"
        val where = if (sinceDate == null) {
            "WHERE $filter"
        } else {
            "WHERE created_date >= ? AND $filter"
        }
        readableDatabase.rawQuery(
            """
            SELECT created_date, COUNT(DISTINCT word_id)
            FROM review_records
            $where
            GROUP BY created_date
            ORDER BY created_date ASC
            """.trimIndent(),
            if (sinceDate == null) null else arrayOf(sinceDate),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                result.add(mapOf("date" to cursor.getString(0), "count" to cursor.getInt(1)))
            }
        }
        return result
    }

    /**
     * 按天统计「不论对错」的复习单词总数（每天按单词去重），供打卡热力图「复习总数」使用。
     *
     * 只要这一天练过的词就算数，不论答对还是答错、用没用提示。
     * 这一指标反映的是「练了几个」，而不是「掌握几个」。
     *
     * @param sinceDate 起始日期（含），格式 yyyy-MM-dd；传 null 表示统计全部历史。
     * @return 按日期升序的列表，每项形如 {date: "2026-08-18", count: 15}。
     */
    fun getDailyTotalCounts(sinceDate: String?): List<Map<String, Any?>> {
        val result = ArrayList<Map<String, Any?>>()
        // 不加任何对错过滤，按日期分组统计去重单词数。
        val where = if (sinceDate == null) {
            ""
        } else {
            "WHERE created_date >= ?"
        }
        readableDatabase.rawQuery(
            """
            SELECT created_date, COUNT(DISTINCT word_id)
            FROM review_records
            $where
            GROUP BY created_date
            ORDER BY created_date ASC
            """.trimIndent(),
            if (sinceDate == null) null else arrayOf(sinceDate),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                result.add(mapOf("date" to cursor.getString(0), "count" to cursor.getInt(1)))
            }
        }
        return result
    }

    /**
     * 读取今日全部复习记录，供「今日复习」明细展示。
     *
     * 这里返回的是原始记录（含答错的那些），去重和过滤交给调用方，
     * 与上面三个聚合口径互不影响。
     *
     * @return 今日全部复习记录，按写入时间升序排列。
     */
    fun getTodayReviewRecords(): List<Map<String, Any?>> {
        val result = ArrayList<Map<String, Any?>>()
        readableDatabase.query(
            "review_records",
            null,
            "created_date = ?",
            arrayOf(localDateString()),
            null, null,
            "id ASC",
        ).use { cursor ->
            while (cursor.moveToNext()) {
                result.add(
                    linkedMapOf(
                        "id" to cursor.getLong(cursor.getColumnIndexOrThrow("id")),
                        "word_id" to cursor.getLong(cursor.getColumnIndexOrThrow("word_id")),
                        "streak" to cursor.getInt(cursor.getColumnIndexOrThrow("streak")),
                        "module" to cursor.getString(cursor.getColumnIndexOrThrow("module")),
                        "session_id" to cursor.nullableLong("session_id"),
                        "is_correct" to (
                            cursor.getInt(cursor.getColumnIndexOrThrow("is_correct")) == 1
                            ),
                        "wrong_count" to cursor.getInt(
                            cursor.getColumnIndexOrThrow("wrong_count"),
                        ),
                        "hint_count" to cursor.getInt(cursor.getColumnIndexOrThrow("hint_count")),
                        "difficulty_before" to cursor.getInt(
                            cursor.getColumnIndexOrThrow("difficulty_before"),
                        ),
                        "difficulty_after" to cursor.getInt(
                            cursor.getColumnIndexOrThrow("difficulty_after"),
                        ),
                        "reviewed_at_before" to cursor.getLong(
                            cursor.getColumnIndexOrThrow("reviewed_at_before"),
                        ),
                        "reviewed_at_after" to cursor.getLong(
                            cursor.getColumnIndexOrThrow("reviewed_at_after"),
                        ),
                        "extra_json" to cursor.getString(
                            cursor.getColumnIndexOrThrow("extra_json"),
                        ),
                        "created_at" to cursor.getLong(cursor.getColumnIndexOrThrow("created_at")),
                        "created_date" to cursor.getString(
                            cursor.getColumnIndexOrThrow("created_date"),
                        ),
                    ),
                )
            }
        }
        return result
    }

    /** 把 SQLite TEXT 列里的 JSON 数字数组还原成 Long 列表。 */
    private fun jsonArrayToLongs(value: String): List<Long> {
        val array = JSONArray(value)
        return List(array.length()) { index -> array.getLong(index) }
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
