package com.example.my_english

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * 在真实 Android SQLite 上验证 WordsDatabase 的建表、导入与导出，
 * 重点覆盖「脏数据导入」的容错：越界枚举、悬空外键、同 key 重复设置，
 * 都不应让整份备份还原失败或让 App 崩溃。
 */
@RunWith(AndroidJUnit4::class)
class WordsDatabaseImportTest {

    private lateinit var db: WordsDatabase

    // 每个用例独立的测试库名，保证彼此绝不共用 SQLite 连接与数据；
    // 绝不能碰生产用的 my_english_v2.db。
    private var dbSeq = 0

    @Before
    fun setUp() {
        dbSeq += 1
        val context = ApplicationProvider.getApplicationContext<Context>()
        val testDbName = "my_english_test_$dbSeq.db"
        context.deleteDatabase(testDbName)
        db = WordsDatabase(context, testDbName)
        db.writableDatabase
    }

    @After
    fun tearDown() {
        val name = db.databaseName
        db.close()
        ApplicationProvider.getApplicationContext<Context>().deleteDatabase(name)
    }

    /** 备份里有重复的 settings key 时，唯一索引不应让导入失败。 */
    @Test
    fun import_duplicateSettingsKeys_keepsLastAndDoesNotAbort() {
        val backup = baseBackup().apply {
            this["settings"] = listOf(
                mapOf("key" to "accent", "value" to "american", "type" to "string"),
                mapOf("key" to "accent", "value" to "british", "type" to "string"),
            )
        }
        db.importData(backup)
        val settings = db.getSettings()
        // 后写的那条胜出，且同 key 只有一条活。
        val accentRow = settings["accent"] as? Map<*, *>
        assertEquals("british", accentRow?.get("value"))
    }

    /**
     * 枚举越界（status=9、kind=9）与 record result=7 都不应让备份还原失败。
     * kind/status 归一到合法枚举；result 按「错误(0)」兜底。
     */
    @Test
    fun import_outOfRangeEnums_coercesInsteadOfAbort() {
        val backup = baseBackup().apply {
            this["words"] = mutableListOf(wordRow(1, "hello"))
            this["meanings"] = mutableListOf(
                mapOf("id" to 100, "word_id" to 1, "definition" to "你好", "pos" to "n."),
            )
            this["sessions"] = mutableListOf(
                mapOf("id" to 10, "module" to "listen", "kind" to 99, "status" to 0, "date" to "2026-08-29"),
            )
            this["session_records"] = mutableListOf(
                mapOf("id" to 500, "session_id" to 10, "word_id" to 1, "result" to 7),
            )
        }
        db.importData(backup)
        // 会话与记录都应还在，且数值被归一到合法值。
        assertEquals(1, count("sessions"))
        assertEquals(1, count("session_records"))
        // kind 归一到 KIND_DAILY，status 归一到 STATUS_ACTIVE。
        assertEquals(WordsDatabase.KIND_DAILY.toLong(), longColumn("sessions", "kind", "id = ?", 10))
        assertEquals(WordsDatabase.STATUS_ACTIVE.toLong(), longColumn("sessions", "status", "id = ?", 10))
        // result=7 → 按错误(0)兜底。
        assertEquals(0L, longColumn("session_records", "result", "id = ?", 500))
    }

    /** 悬空外键（记录指向不存在的会话/单词/含义）应被跳过，而不是让整表报错。 */
    @Test
    fun import_danglingForeignKeys_skipsOrphans() {
        val backup = baseBackup().apply {
            this["words"] = mutableListOf(wordRow(1, "hello"))
            this["meanings"] = mutableListOf(
                mapOf("id" to 100, "word_id" to 1, "definition" to "你好", "pos" to "n."),
            )
            this["sessions"] = mutableListOf(
                mapOf("id" to 10, "module" to "listen", "kind" to 1, "status" to 1, "date" to "2026-08-29"),
            )
            // 600 指向不存在的会话 999，应被跳过；601 正常。
            this["session_records"] = mutableListOf(
                mapOf("id" to 600, "session_id" to 999, "word_id" to 1),
                mapOf("id" to 601, "session_id" to 10, "word_id" to 1),
            )
        }
        db.importData(backup)
        assertEquals(1, count("session_records"))
        assertEquals(601L, longColumn("session_records", "id", "id = ?", 601))
    }

    /** 含义指向不存在的单词时，该条含义被跳过，其它正常词不受牵连。 */
    @Test
    fun import_meaningWithDeadWordParent_isSkipped() {
        val backup = baseBackup().apply {
            this["words"] = mutableListOf(wordRow(1, "hello"))
            this["meanings"] = mutableListOf(
                mapOf("id" to 100, "word_id" to 1, "definition" to "你好", "pos" to "n."),
                mapOf("id" to 101, "word_id" to 999, "definition" to "幽灵释义", "pos" to "n."),
            )
        }
        db.importData(backup)
        // 只导入挂在活着单词下的那条含义。
        assertEquals(1, count("meanings"))
        assertEquals(100L, longColumn("meanings", "id", "id = ?", 100))
    }

    // ---- 测试辅助 ------------------------------------------------------

    private fun baseBackup(): MutableMap<String, Any?> = mutableMapOf(
        "version" to 2,
        "settings" to mutableListOf<Any?>(),
        "words" to mutableListOf<Any?>(),
        "meanings" to mutableListOf<Any?>(),
        "word_sets" to mutableListOf<Any?>(),
        "sessions" to mutableListOf<Any?>(),
        "session_records" to mutableListOf<Any?>(),
    )

    private fun wordRow(id: Long, spelling: String): Map<String, Any?> = mapOf(
        "id" to id,
        "spelling" to spelling,
    )

    private fun count(table: String): Int =
        db.readableDatabase.rawQuery("SELECT COUNT(*) FROM $table", null).use { cursor ->
            cursor.moveToFirst(); cursor.getInt(0)
        }

    /** 取某表中满足 where 的第一行的某列 Long 值；无数据显示 0。 */
    private fun longColumn(table: String, column: String, where: String, arg: Long): Long =
        db.readableDatabase.rawQuery(
            "SELECT $column FROM $table WHERE $where LIMIT 1",
            arrayOf(arg.toString()),
        ).use { cursor -> if (!cursor.moveToFirst()) 0L else cursor.getLong(0) }
}