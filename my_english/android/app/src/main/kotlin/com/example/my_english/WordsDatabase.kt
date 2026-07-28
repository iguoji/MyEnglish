// package 相当于 PHP namespace，让本类与 MainActivity 位于同一模块。
package com.example.my_english

// ContentValues 是 Android 写 SQLite 时使用的键值对象，类似 PHP insert 的关联数组。
import android.content.ContentValues
// Context 用来确定数据库文件属于哪个 App。
import android.content.Context
// SQLiteDatabase 提供事务、查询和写入 API。
import android.database.sqlite.SQLiteDatabase
// SQLiteOpenHelper 负责数据库创建、版本升级和连接复用。
import android.database.sqlite.SQLiteOpenHelper
// JSONArray 负责还原 SQLite 中保存的 definitions_json。
import org.json.JSONArray
// DatabaseUtils 提供按条件统计行数，用来判定"今天是否已有记录"。
import android.database.DatabaseUtils
// SimpleDateFormat 与 Date 负责把当前时刻格式化成 'yyyy-MM-dd' 本地日期。
import java.text.SimpleDateFormat
// Date 表示当前时刻，配合 SimpleDateFormat 取本地日期。
import java.util.Date
// Locale 决定日期格式化的区域（数字与顺序），不影响 yyyy-MM-dd 结构。
import java.util.Locale

/**
 * word/meaning 本地 SQLite 数据库。
 *
 * 这相当于 PHP 项目中的 Migration + Store：onCreate 建表，公开方法只负责 SQLite
 * 查询和 CRUD。JSON 读取及内存模式完全由 Dart Store 管理，不会进入本数据库。
 */
class WordsDatabase(context: Context) :
    SQLiteOpenHelper(context, databaseName, null, databaseVersion) {

    // companion object 类似 PHP 类常量区，所有实例共享同一份配置。
    companion object {
        // 数据库文件保存在 Android App 私有目录，卸载应用时由系统删除。
        private const val databaseName = "my_english.db"
        // 版本 3 新增 group 与 groupMember 两张表，让单词-分组关系持久化。
        // 版本 4 新增 record 表，记录单词默写结果并驱动难度变化。
        private const val databaseVersion = 4
    }

    // 每次打开连接时启用外键约束，保证 meaning.word_id 必须指向真实 word。
    override fun onConfigure(db: SQLiteDatabase) {
        // 先执行 SQLiteOpenHelper 标准配置。
        super.onConfigure(db)
        // Android SQLite 默认可能关闭外键，这里显式开启。
        db.setForeignKeyConstraintsEnabled(true)
    }

    // 数据库文件第一次创建时执行，作用类似 PHP migration up()。
    override fun onCreate(db: SQLiteDatabase) {
        // 创建允许重复 spelling 的 words 表。
        createWordsTable(db)
        // 创建关联 meanings 表。
        createMeaningsTable(db)
        // 创建分组表（名称与排序）。
        createGroupsTable(db)
        // 创建单词-分组关联表（多对多）。
        createGroupMembersTable(db)
        // 创建单词默写记录表（每天每条单词一条，驱动难度变化）。
        createRecordTable(db)
        // 最后建立查询索引。
        createIndexes(db)
    }

    // 已安装旧版本升级时执行，作用类似 Laravel migration 的后续版本。
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // 只有从版本 1 升到 2 或更高时，才需要删除 spelling 唯一约束。
        if (oldVersion < 2 && newVersion >= 2) {
            // SQLite 无法直接 DROP UNIQUE，所以用新表复制数据完成迁移。
            migrateToVersion2(db)
        }
        // 从版本 2 升到 3：已有用户只缺 group/groupMember 两张表，直接补齐，
        // 不动 words/meanings，避免无谓的数据搬迁。
        if (oldVersion < 3 && newVersion >= 3) {
            createGroupsTable(db)
            createGroupMembersTable(db)
        }
        // 从版本 3 升到 4：已有用户只缺 record 一张表，直接补齐，不迁旧数据。
        if (oldVersion < 4 && newVersion >= 4) {
            createRecordTable(db)
        }
    }

    /** 创建 words 表；spelling 只要求非空，不再带 UNIQUE。 */
    private fun createWordsTable(db: SQLiteDatabase) {
        // execSQL 执行固定结构 SQL，不拼接任何用户输入。
        db.execSQL(
            """
            CREATE TABLE words (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                spelling TEXT NOT NULL COLLATE BINARY,
                difficulty INTEGER NULL CHECK (difficulty IS NULL OR difficulty >= 0),
                reviewed_at INTEGER NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER NULL
            )
            """.trimIndent(),
        )
    }

    /** 创建 meanings 表；外键仍然通过 Word.id 关联，不依赖 spelling。 */
    private fun createMeaningsTable(db: SQLiteDatabase) {
        // definitions 数组继续以 JSON 字符串保存。
        db.execSQL(
            """
            CREATE TABLE meanings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word_id INTEGER NOT NULL,
                sort_index INTEGER NOT NULL DEFAULT 0,
                pos TEXT NOT NULL,
                definitions_json TEXT NOT NULL,
                created_at INTEGER NULL,
                updated_at INTEGER NULL,
                deleted_at INTEGER NULL,
                FOREIGN KEY (word_id) REFERENCES words(id) ON DELETE CASCADE
            )
            """.trimIndent(),
        )
    }

    /**
     * 创建分组表。
     *
     * README 的 group 表只列 id/name/时间；这里额外加 sort_order 用于持久化
     * 用户在「分组管理」里调整的顺序（README 未约束排序方式，此为必要补充）。
     */
    private fun createGroupsTable(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE groups (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER NULL
            )
            """.trimIndent(),
        )
    }

    /**
     * 创建单词-分组关联表，实现 README 的 groupMember（多对多）。
     *
     * 在 README 的 group_id/word_id 联合唯一之外，补一个自增 id 与主键，
     * 便于后续软删除与行级更新；UNIQUE 约束保证同一单词在同一分组不会重复。
     */
    private fun createGroupMembersTable(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE group_members (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                group_id INTEGER NOT NULL,
                word_id INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                deleted_at INTEGER NULL,
                UNIQUE(group_id, word_id),
                FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE,
                FOREIGN KEY (word_id) REFERENCES words(id) ON DELETE CASCADE
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
            "CREATE INDEX meanings_word_sort ON meanings(word_id, deleted_at, sort_index DESC)",
        )
    }

    /** 把版本 1 的 UNIQUE spelling 表迁移成版本 2 的普通 spelling 字段。 */
    private fun migrateToVersion2(db: SQLiteDatabase) {
        // 先重命名子表，保留全部 Meaning 数据和旧索引。
        db.execSQL("ALTER TABLE meanings RENAME TO meanings_v1")
        // 再重命名父表；SQLite 会同步调整旧子表中的外键目标。
        db.execSQL("ALTER TABLE words RENAME TO words_v1")

        // 按版本 2 结构创建没有 spelling UNIQUE 的新父表。
        createWordsTable(db)
        // 创建重新指向新 words 表的 Meaning 子表。
        createMeaningsTable(db)

        // 明确列名复制 Word，避免未来增加字段时发生列顺序错位。
        db.execSQL(
            """
            INSERT INTO words (
                id, spelling, difficulty, reviewed_at, created_at, updated_at, deleted_at
            )
            SELECT
                id, spelling, difficulty, reviewed_at, created_at, updated_at, deleted_at
            FROM words_v1
            """.trimIndent(),
        )
        // Meaning 同样保留原主键、外键、排序和全部时间字段。
        db.execSQL(
            """
            INSERT INTO meanings (
                id, word_id, sort_index, pos, definitions_json,
                created_at, updated_at, deleted_at
            )
            SELECT
                id, word_id, sort_index, pos, definitions_json,
                created_at, updated_at, deleted_at
            FROM meanings_v1
            """.trimIndent(),
        )

        // 先删除旧子表，避免外键级联影响已复制的数据。
        db.execSQL("DROP TABLE meanings_v1")
        // 再删除带 UNIQUE 约束的旧父表。
        db.execSQL("DROP TABLE words_v1")
        // 旧索引随旧表删除后，使用原名称重建版本 2 索引。
        createIndexes(db)
    }

    /** 一次性读取全部未软删除 Word，并用第二次查询组装 Meaning，避免 N+1 查询。 */
    fun getAllWords(): List<Map<String, Any?>> {
        // readableDatabase 会复用现有连接。
        val db = readableDatabase
        // 先按 word_id 分组读取全部 Meaning。
        val meaningsByWord = mutableMapOf<Long, MutableList<Map<String, Any?>>>()
        // query 返回 Cursor，use 会在完成后自动关闭。
        db.query(
            // 查询 meanings 表。
            "meanings",
            // null 表示读取全部列。
            null,
            // 只读取未软删除 Meaning。
            "deleted_at IS NULL",
            // 本查询没有占位参数。
            null,
            // 不分组。
            null,
            // 不使用 HAVING。
            null,
            // 按 word_id 聚合，并按 index 从大到小保持 README 顺序。
            "word_id ASC, sort_index DESC, id ASC",
        ).use { cursor ->
            // moveToNext 类似遍历数据库结果集。
            while (cursor.moveToNext()) {
                // 当前 Meaning 所属单词 id。
                val wordId = cursor.getLong(cursor.getColumnIndexOrThrow("word_id"))
                // definitions_json 还原成平台通道支持的字符串 List。
                val definitions = jsonArrayToStrings(
                    cursor.getString(cursor.getColumnIndexOrThrow("definitions_json")),
                )
                // 构造 Dart Meaning.fromMap 所需字段。
                val meaning = linkedMapOf<String, Any?>(
                    "id" to cursor.getLong(cursor.getColumnIndexOrThrow("id")),
                    "word_id" to wordId,
                    "index" to cursor.getInt(cursor.getColumnIndexOrThrow("sort_index")),
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
            // 全部有效成员都在表里（删除即物理删除或随外键级联）。
            null,
            null,
            null,
            null,
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                // 当前关联指向的单词。
                val wordId = cursor.getLong(cursor.getColumnIndexOrThrow("word_id"))
                // 当前关联指向的分组。
                val groupId = cursor.getLong(cursor.getColumnIndexOrThrow("group_id"))
                // 按单词归集分组 id 列表，类似 PHP 的 $map[$wordId][] = $groupId。
                memberGroupsByWord.getOrPut(wordId) { mutableListOf() }.add(groupId)
            }
        }

        // 创建最终结果列表；ArrayList 适合已知会连续追加大量元素的场景。
        val words = ArrayList<Map<String, Any?>>()
        // 再读取全部 Word；这与上一条查询构成固定两次 SQL，不会每个 Word 查询一次。
        db.query(
            "words",
            null,
            "deleted_at IS NULL",
            null,
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
                        "reviewed_at" to cursor.nullableLong("reviewed_at"),
                        "created_at" to cursor.nullableLong("created_at"),
                        "updated_at" to cursor.nullableLong("updated_at"),
                        "deleted_at" to cursor.nullableLong("deleted_at"),
                    ),
                )
            }
        }
        // 返回一次性加载的完整列表，Flutter ListView.builder 只会构建可见行。
        return words
    }

    /** 创建一个 Word 及其全部 Meaning，并返回自增主键。 */
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
            // 标记事务成功。
            db.setTransactionSuccessful()
            // 把 id 返回 Dart Store。
            return wordId
        } finally {
            // 释放事务锁。
            db.endTransaction()
        }
    }

    /** 更新 Word，并用提交的 Meaning 列表替换旧关系数据。 */
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
            replaceMeanings(db, id, payload["meanings"])
            // 标记整个更新成功。
            db.setTransactionSuccessful()
        } finally {
            // 异常时自动回滚。
            db.endTransaction()
        }
    }

    /** 软删除 Word：首页查询会自动排除 deleted_at 非空记录。 */
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
    }

    /** 清空全部本地数据，用于「清空数据」与「导入前整库替换」。 */
    fun clearAllWords() {
        // 获取可写连接。
        val db = writableDatabase
        // 事务保证四张表要么都被清空，要么都不动。
        db.beginTransaction()
        try {
            // 先清空子表，再清空父表，避免外键约束报错。
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
        // 获取可写连接并开启事务，保证整批原子写入。
        val db = writableDatabase
        db.beginTransaction()
        try {
            // 先清空历史数据，导入即整库替换。
            // 原始 words.json 没有分组信息，导入后单词都应回到「未分组」，
            // 因此一并清空 group_members；分组列表本身保留，方便用户重新归类。
            db.delete("group_members", null, null)
            db.delete("meanings", null, null)
            db.delete("words", null, null)
            // 逐条写入，跳过类型不正确的元素，避免原生崩溃。
            for (rawWord in rawWords) {
                // 类型不正确时跳过并进入下一项，避免 ClassCastException。
                val payload = rawWord as? Map<*, *> ?: continue
                // 当前时间供缺失 created_at/updated_at 使用。
                val now = System.currentTimeMillis()
                // 复用单条写入逻辑构造 words 字段。
                val values = wordValuesFromPayload(payload, now, touchUpdatedAt = false)
                // 插入并返回新主键。
                val wordId = db.insertOrThrow("words", null, values)
                // 写入嵌套 Meaning。
                replaceMeanings(db, wordId, payload["meanings"])
            }
            // 全部成功才提交。
            db.setTransactionSuccessful()
        } finally {
            // 异常时回滚，保持数据库一致。
            db.endTransaction()
        }
    }

    // ---------- 分组与分组成员 ----------

    /** 读取全部未软删除的分组，按排序值升序、主键升序稳定排列。 */
    fun getAllGroups(): List<Map<String, Any?>> {
        // 只读连接即可。
        val db = readableDatabase
        // 结果列表。
        val groups = ArrayList<Map<String, Any?>>()
        // 查询未删除分组。
        db.query(
            "groups",
            null,
            "deleted_at IS NULL",
            null,
            null,
            null,
            "sort_order ASC, id ASC",
        ).use { cursor ->
            // 逐行构造 Dart 需要的 Map。
            while (cursor.moveToNext()) {
                groups.add(
                    linkedMapOf(
                        "id" to cursor.getLong(cursor.getColumnIndexOrThrow("id")),
                        "name" to cursor.getString(cursor.getColumnIndexOrThrow("name")),
                        "sort_order" to cursor.getInt(cursor.getColumnIndexOrThrow("sort_order")),
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

    /** 新建分组并返回自增主键；sortOrder 决定初始显示顺序。 */
    fun createGroup(name: String, sortOrder: Int): Long {
        // 当前时间供创建与更新字段使用。
        val now = System.currentTimeMillis()
        // 组装字段；空名称回退为「未命名」。
        val values = ContentValues().apply {
            put("name", name.trim().ifEmpty { "未命名" })
            put("sort_order", sortOrder)
            put("created_at", now)
            put("updated_at", now)
        }
        // 插入并返回自增主键。
        return writableDatabase.insertOrThrow("groups", null, values)
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

    /** 调整分组排序值；移动分组位置后由 Dart 端计算并写入。 */
    fun setGroupOrder(id: Long, sortOrder: Int) {
        // 排序与更新时间同步。
        val values = ContentValues().apply {
            put("sort_order", sortOrder)
            put("updated_at", System.currentTimeMillis())
        }
        // 静默更新，分组一定存在。
        writableDatabase.update("groups", values, "id = ?", arrayOf(id.toString()))
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
        // 组装关联行。
        val values = ContentValues().apply {
            put("group_id", groupId)
            put("word_id", wordId)
            put("created_at", System.currentTimeMillis())
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
            // 清掉旧关系。
            db.delete("group_members", "word_id = ?", arrayOf(wordId.toString()))
            // 按新列表重建；跳过非法元素避免崩溃。
            for (rawGroupId in groupIds) {
                // 类型不正确时跳过该元素。
                val groupId = (rawGroupId as? Number)?.toLong() ?: continue
                // 组装新建关联行。
                val values = ContentValues().apply {
                    put("group_id", groupId)
                    put("word_id", wordId)
                    put("created_at", System.currentTimeMillis())
                }
                // 冲突忽略，保证幂等。
                db.insertWithOnConflict(
                    "group_members",
                    null,
                    values,
                    SQLiteDatabase.CONFLICT_IGNORE,
                )
            }
            // 标记成功。
            db.setTransactionSuccessful()
        } finally {
            // 异常回滚。
            db.endTransaction()
        }
    }

    /**
     * 导入完整备份（含 groups/words/members）。
     *
     * 与 importWords 不同，这里连分组也整库替换，因此要重建 group 表；
     * 由于 words/group 自增主键会变，先收集旧 id→新 id 映射，再把
     * members 里的 group_id/word_id 一并换成新值，保证关系不丢失。
     */
    fun importData(payload: Map<*, *>) {
        // 写连接与整体事务。
        val db = writableDatabase
        db.beginTransaction()
        try {
            // 整库清空四张表。
            db.delete("group_members", null, null)
            db.delete("groups", null, null)
            db.delete("meanings", null, null)
            db.delete("words", null, null)

            // 重建分组，记录旧 id → 新 id 映射。
            val groupIdMap = mutableMapOf<Long, Long>()
            // 容错：groups 缺失时按空列表处理。
            val rawGroups = payload["groups"] as? List<*> ?: emptyList<Any?>()
            for (rawGroup in rawGroups) {
                // 类型不正确时跳过。
                val group = rawGroup as? Map<*, *> ?: continue
                // 必须有旧主键才能建立映射。
                val oldId = (group["id"] as? Number)?.toLong() ?: continue
                // 当前时间回退值。
                val now = System.currentTimeMillis()
                // 组装分组字段。
                val values = ContentValues().apply {
                    put("name", group["name"]?.toString()?.trim()?.ifEmpty { "未命名" } ?: "未命名")
                    put("sort_order", (group["sort_order"] as? Number)?.toInt() ?: 0)
                    put("created_at", (group["created_at"] as? Number)?.toLong() ?: now)
                    put("updated_at", (group["updated_at"] as? Number)?.toLong() ?: now)
                }
                // 插入并取新主键。
                val newId = db.insertOrThrow("groups", null, values)
                // 记录映射。
                groupIdMap[oldId] = newId
            }

            // 重建单词与释义，记录旧 id → 新 id 映射。
            val wordIdMap = mutableMapOf<Long, Long>()
            // 容错：words 缺失时按空列表处理。
            val rawWords = payload["words"] as? List<*> ?: emptyList<Any?>()
            for (rawWord in rawWords) {
                // 类型不正确时跳过。
                val word = rawWord as? Map<*, *> ?: continue
                // 旧主键可选（原始 words.json 可能没有）。
                val oldId = (word["id"] as? Number)?.toLong()
                // 当前时间回退值。
                val now = System.currentTimeMillis()
                // 复用单词字段转换。
                val values = wordValuesFromPayload(word, now, touchUpdatedAt = false)
                // 插入并取新主键。
                val newId = db.insertOrThrow("words", null, values)
                // 记录映射（仅当存在旧主键）。
                if (oldId != null) wordIdMap[oldId] = newId
                // 重建释义。
                replaceMeanings(db, newId, word["meanings"])
            }

            // 重建成员关联，用映射把旧外键换成新外键。
            // 容错：members 缺失时按空列表处理。
            val rawMembers = payload["members"] as? List<*> ?: emptyList<Any?>()
            for (rawMember in rawMembers) {
                // 类型不正确时跳过。
                val member = rawMember as? Map<*, *> ?: continue
                // 读取旧外键。
                val oldGroup = (member["group_id"] as? Number)?.toLong() ?: continue
                val oldWord = (member["word_id"] as? Number)?.toLong() ?: continue
                // 通过映射换成新外键；任一映射缺失则跳过该行。
                val newGroup = groupIdMap[oldGroup] ?: continue
                val newWord = wordIdMap[oldWord] ?: continue
                // 组装关联行。
                val values = ContentValues().apply {
                    put("group_id", newGroup)
                    put("word_id", newWord)
                    put("created_at", System.currentTimeMillis())
                }
                // 冲突忽略，保证幂等。
                db.insertWithOnConflict(
                    "group_members",
                    null,
                    values,
                    SQLiteDatabase.CONFLICT_IGNORE,
                )
            }

            // 全部成功才提交。
            db.setTransactionSuccessful()
        } finally {
            // 异常时回滚，保持数据库一致。
            db.endTransaction()
        }
    }

    /**
     * 创建单词默写记录表。
     *
     * 每个单词每天只留一条记录（首条为准）。`created_date` 用本机时区算好的
     * 'YYYY-MM-DD' 字符串存储，查询时直接比字符串即可，无需在 SQL 里再算时区。
     */
    private fun createRecordTable(db: SQLiteDatabase) {
        // execSQL 执行固定结构 SQL，不拼接任何用户输入。
        db.execSQL(
            """
            CREATE TABLE record (
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
        // 按日期查询"今日复习"时用得到，建索引加速。
        db.execSQL("CREATE INDEX record_created_date ON record(created_date)")
    }

    /** 取设备本机时区下的 'yyyy-MM-dd' 日期字符串，作为 created_date 与"今日"判定基准。 */
    private fun localDateString(): String {
        // Locale.getDefault() 拿到设备区域；SimpleDateFormat 默认用设备时区，即本地日期。
        val format = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
        // Date() 为当前时刻，format 后即为本地年月日。
        return format.format(Date())
    }

    /**
     * 记录一次单词默写结果，并在同一事务内更新单词难度。
     *
     * 规则（每天首条记录为准）：
     * - 今日已有该词记录 → 直接忽略（后续完成不再插记录、不改难度，满足"每天一条"）。
     * - 本次不完美（有错或用了提示）→ 难度 +1（每天最多 +1）。
     * - 本次完美 → 检查最近 5 个练习日是否"每天首条都完美"，是则难度 -1。
     */
    fun addDictationRecord(
        wordId: Long,
        isCorrect: Boolean,
        wrongCount: Int,
        hintCount: Int,
    ) {
        // 写连接与事务保证"插记录 + 改难度"原子，要么都成要么都回滚。
        val db = writableDatabase
        db.beginTransaction()
        try {
            // 本机时区下的"今天"。
            val today = localDateString()
            // 今日是否已有该词记录（每天一条）。
            val existing = DatabaseUtils.queryNumEntries(
                db,
                "record",
                "word_id = ? AND created_date = ?",
                arrayOf(wordId.toString(), today),
            )
            // 已有则跳过，既不插记录也不改难度。
            if (existing > 0) {
                db.setTransactionSuccessful()
                return
            }
            // 读取当前难度（null 视为 0）。
            val curDiff = getWordDifficulty(db, wordId)
            // 完美 = 最终全对、且中途零错误零提示。
            val perfect = isCorrect && wrongCount == 0 && hintCount == 0
            // 先以当前难度作基准，下面再决定增减。
            var newDiff = curDiff
            if (!perfect) {
                // 不完美：每天最多 +1。
                newDiff = curDiff + 1
            } else {
                // 完美：往前数最近 4 个练习日（不含今天），全部完美才 -1。
                // 加上今天这条完美记录，正好凑满"最近 5 个练习日全完美"。
                val priorPerfectDays = countConsecutivePerfectDays(db, wordId, today, 4)
                if (priorPerfectDays >= 4) newDiff = curDiff - 1
            }
            // 插入今日唯一记录。
            val now = System.currentTimeMillis()
            val values = ContentValues().apply {
                put("module", "dictation")
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
     * 从今天往前数，连续完美（全对且无错无提示）的练习天数，最多数 [limit] 天。
     *
     * 按 created_date 倒序取最近 [limit] 天，遇到第一个不完美的就停止——
     * 因为"最近 5 天全完美"要求连续，中间任何一天不完美都打断链条。
     */
    private fun countConsecutivePerfectDays(
        db: SQLiteDatabase,
        wordId: Long,
        today: String,
        limit: Int,
    ): Int {
        // 统计连续完美天数。
        var count = 0
        // 查今天之前最近的 limit 天记录（每天一条）。
        db.query(
            "record",
            arrayOf("is_correct", "wrong_count", "hint_count"),
            "word_id = ? AND created_date < ?",
            arrayOf(wordId.toString(), today),
            null, null,
            "created_date DESC",
            limit.toString(),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                // 取出这一天的三项判定字段。
                val correct = cursor.getInt(cursor.getColumnIndexOrThrow("is_correct")) == 1
                val wrong = cursor.getInt(cursor.getColumnIndexOrThrow("wrong_count"))
                val hint = cursor.getInt(cursor.getColumnIndexOrThrow("hint_count"))
                // 完美才累加，否则打断并停止计数。
                if (correct && wrong == 0 && hint == 0) {
                    count += 1
                } else {
                    break
                }
            }
        }
        // 返回连续完美天数（封顶 limit）。
        return count
    }

    /**
     * 读取今日全部默写记录，供"今日复习"展示。
     *
     * 返回完整记录 Map 列表（每条含 word_id 等），Dart 端再去重出单词列表。
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
            // 非空 difficulty 必须大于等于 0，数据库 CHECK 会再次保护。
            putNullableLong("difficulty", (payload["difficulty"] as? Number)?.toLong())
            // 保存最近复习时间。
            putNullableLong("reviewed_at", (payload["reviewed_at"] as? Number)?.toLong())
            // 新数据没有 created_at 时使用 now。
            put("created_at", (payload["created_at"] as? Number)?.toLong() ?: now)
            // 编辑操作始终使用 now；创建时允许保留导入数据传入的 updated_at。
            put(
                "updated_at",
                if (touchUpdatedAt) now else (payload["updated_at"] as? Number)?.toLong() ?: now,
            )
            // 支持未来恢复/软删除数据同步。
            putNullableLong("deleted_at", (payload["deleted_at"] as? Number)?.toLong())
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
                put("sort_index", (meaning["index"] as? Number)?.toInt() ?: 0)
                put("pos", meaning["pos"]?.toString() ?: "")
                put("definitions_json", JSONArray(definitions).toString())
                putNullableLong("created_at", (meaning["created_at"] as? Number)?.toLong())
                putNullableLong("updated_at", (meaning["updated_at"] as? Number)?.toLong())
                putNullableLong("deleted_at", (meaning["deleted_at"] as? Number)?.toLong())
            }
            // 外键与事务会确保关联正确。
            db.insertOrThrow("meanings", null, values)
        }
    }

    /** 将 SQLite 保存的 definitions JSON 文本还原为字符串列表。 */
    private fun jsonArrayToStrings(value: String): List<String> {
        // 解析 JSON 数组。
        val array = JSONArray(value)
        // 按数组长度生成不可变 List。
        return List(array.length()) { index -> array.getString(index) }
    }

    /** ContentValues 没有便捷可空 Long API，因此统一封装 put/putNull。 */
    private fun ContentValues.putNullableLong(key: String, value: Long?) {
        // 非空写真实数值，空值显式写 SQLite NULL。
        if (value == null) putNull(key) else put(key, value)
    }

    /** Cursor 安全读取可空 INTEGER 字段。 */
    private fun android.database.Cursor.nullableLong(columnName: String): Long? {
        // 先找到列下标，字段不存在时立即抛出便于定位 schema 错误。
        val index = getColumnIndexOrThrow(columnName)
        // SQLite NULL 对应 Kotlin null，否则读取 Long。
        return if (isNull(index)) null else getLong(index)
    }
}
