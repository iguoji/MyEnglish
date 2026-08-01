package com.example.my_english

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * 在真实 Android SQLite 上验证 README 字段与导入导出往返。
 *
 * 测试使用 Android 设备保护存储区，它与 App 正式数据库使用的普通存储目录分开，
 * 因此可以安全重建 my_english.db 而不触碰用户数据。
 */
@RunWith(AndroidJUnit4::class)
class WordsDatabaseImportExportTest {
    /** 核对四张业务表的字段名与 README 一致。 */
    @Test
    fun schemaUsesReadmeFieldNames() {
        withDatabase { database ->
            assertEquals(
                setOf(
                    "id",
                    "spelling",
                    "difficulty",
                    "phonetic_uk",
                    "phonetic_us",
                    "plural",
                    "third_person_singular",
                    "gerund",
                    "past_tense",
                    "past_participle",
                    "comparative",
                    "superlative",
                    "reviewed_at",
                    "created_at",
                    "updated_at",
                    "deleted_at",
                ),
                columnNames(database, "words"),
            )
            assertEquals(
                setOf(
                    "id",
                    "word_id",
                    "index",
                    "pos",
                    "definitions",
                    "created_at",
                    "updated_at",
                    "deleted_at",
                ),
                columnNames(database, "meanings"),
            )
            assertEquals(
                setOf("id", "name", "created_at", "updated_at", "deleted_at"),
                columnNames(database, "groups"),
            )
            assertEquals(
                setOf("group_id", "word_id"),
                columnNames(database, "group_members"),
            )
        }
    }

    /** 验证类型转换、未知字段忽略及导出后再导入不丢数据。 */
    @Test
    fun importAndExportRoundTripUsesDatabaseTypes() {
        withDatabase { database ->
            val payload = linkedMapOf<String, Any?>(
                "groups" to listOf(
                    linkedMapOf<String, Any?>(
                        "id" to 9,
                        "name" to "重点词",
                        "created_at" to "2026-08-01 12:34:56",
                        "updated_at" to 1_785_558_096,
                        "deleted_at" to "",
                        "unknown_group_field" to "ignored",
                    ),
                ),
                "words" to listOf(
                    linkedMapOf<String, Any?>(
                        "id" to 7,
                        "spelling" to "study",
                        "difficulty" to "",
                        // 普通文本即使外观像 JSON 数组，也必须保持字符串类型。
                        "phonetic_uk" to "[study]",
                        "phonetic_us" to null,
                        "plural" to emptyList<String>(),
                        "third_person_singular" to listOf("studies"),
                        "gerund" to listOf("studying"),
                        "past_tense" to listOf("studied"),
                        "past_participle" to listOf("studied"),
                        "comparative" to emptyList<String>(),
                        "superlative" to emptyList<String>(),
                        "reviewed_at" to "wrong-date",
                        "created_at" to "2026-08-01",
                        "updated_at" to 1_785_558_096_000,
                        "deleted_at" to null,
                        "unknown_word_field" to 123,
                        "meanings" to listOf(
                            linkedMapOf<String, Any?>(
                                "id" to 11,
                                "index" to "",
                                "pos" to "v.",
                                "definitions" to listOf("学习", "研究"),
                                "created_at" to null,
                                "updated_at" to "not-a-date",
                                "deleted_at" to "",
                                "unknown_meaning_field" to true,
                            ),
                        ),
                    ),
                ),
                "members" to listOf(mapOf("group_id" to 9, "word_id" to 7)),
            )

            database.importData(payload)
            val firstExport = database.exportData()
            val words = firstExport["words"] as List<*>
            val word = words.single() as Map<*, *>
            assertEquals(0L, word["difficulty"])
            assertEquals("[study]", word["phonetic_uk"])
            assertEquals("", word["reviewed_at"])
            assertEquals("2026-08-01 00:00:00", word["created_at"])
            assertEquals(listOf("studies"), word["third_person_singular"])
            assertFalse(word.containsKey("unknown_word_field"))

            val meanings = word["meanings"] as List<*>
            val meaning = meanings.single() as Map<*, *>
            assertEquals(0L, meaning["index"])
            assertEquals(listOf("学习", "研究"), meaning["definitions"])
            assertEquals("", meaning["updated_at"])
            assertFalse(meaning.containsKey("unknown_meaning_field"))

            val members = firstExport["members"] as List<*>
            assertEquals(1, members.size)
            assertEquals(9L, (members.single() as Map<*, *>)["group_id"])

            database.importData(firstExport)
            val secondExport = database.exportData()
            assertEquals(firstExport, secondExport)
            assertTrue((secondExport["groups"] as List<*>).isNotEmpty())
        }
    }

    /** 验证版本 8 的历史字段会在升级时重建为 README 字段。 */
    @Test
    fun version8UpgradeRebuildsVocabularySchema() {
        val context = isolatedContext()
        context.deleteDatabase("my_english.db")
        // 先模拟一个带历史字段和旧数据的版本 8 数据库。
        context.openOrCreateDatabase("my_english.db", Context.MODE_PRIVATE, null).use { database ->
            database.execSQL(
                """
                CREATE TABLE words (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    spelling TEXT NOT NULL,
                    difficulty INTEGER NULL,
                    reviewed_at INTEGER NULL,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    deleted_at INTEGER NULL
                )
                """.trimIndent(),
            )
            database.execSQL(
                """
                CREATE TABLE meanings (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    word_id INTEGER NOT NULL,
                    sort_index INTEGER NOT NULL,
                    pos TEXT NOT NULL,
                    definitions_json TEXT NOT NULL,
                    created_at INTEGER NULL,
                    updated_at INTEGER NULL,
                    deleted_at INTEGER NULL,
                    FOREIGN KEY (word_id) REFERENCES words(id) ON DELETE CASCADE
                )
                """.trimIndent(),
            )
            database.execSQL(
                "INSERT INTO words " +
                    "(id, spelling, difficulty, created_at, updated_at) " +
                    "VALUES (1, 'old', NULL, 1, 1)",
            )
            database.execSQL(
                "INSERT INTO meanings " +
                    "(word_id, sort_index, pos, definitions_json) " +
                    "VALUES (1, 1, 'n.', '[\"旧数据\"]')",
            )
            // SQLiteOpenHelper 看到版本 8 后会执行本次新增的版本 9 升级逻辑。
            database.version = 8
        }

        val upgraded = WordsDatabase(context)
        try {
            assertTrue("index" in columnNames(upgraded, "meanings"))
            assertFalse("sort_index" in columnNames(upgraded, "meanings"))
            assertTrue("definitions" in columnNames(upgraded, "meanings"))
            assertFalse("definitions_json" in columnNames(upgraded, "meanings"))
            // 用户已确认旧词库不迁移，升级后等待重新导入 words.json。
            upgraded.readableDatabase.rawQuery("SELECT COUNT(*) FROM words", null).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(0, cursor.getInt(0))
            }
        } finally {
            upgraded.close()
            context.deleteDatabase("my_english.db")
        }
    }

    /** 使用设备保护目录的隔离数据库执行用例，结束后删除测试文件。 */
    private fun withDatabase(block: (WordsDatabase) -> Unit) {
        val context = isolatedContext()
        context.deleteDatabase("my_english.db")
        val database = WordsDatabase(context)
        try {
            block(database)
        } finally {
            database.close()
            context.deleteDatabase("my_english.db")
        }
    }

    /** 获取不会触碰正式 App 数据目录的设备保护存储上下文。 */
    private fun isolatedContext(): Context {
        val application = ApplicationProvider.getApplicationContext<Context>()
        return application.createDeviceProtectedStorageContext()
    }

    /** 通过 PRAGMA 读取指定表的字段名集合。 */
    private fun columnNames(database: WordsDatabase, table: String): Set<String> {
        val names = linkedSetOf<String>()
        database.readableDatabase.rawQuery("PRAGMA table_info($table)", null).use { cursor ->
            val nameIndex = cursor.getColumnIndexOrThrow("name")
            while (cursor.moveToNext()) names.add(cursor.getString(nameIndex))
        }
        return names
    }
}
