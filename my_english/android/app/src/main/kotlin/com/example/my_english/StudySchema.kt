package com.example.my_english

import android.database.sqlite.SQLiteDatabase

/**
 * 学习数据的唯一建表入口。只使用设计中约定的十一张业务表。
 *
 * 名称从所属对象读到具体内容，大题 / 小题使用 main / sub 成对命名。
 * 编号、业务字段、公共时间字段始终按相同顺序排列；时间为毫秒，耗时为秒。
 */
internal object StudySchema {
    val tables = listOf(
        "settings", "words", "word_meanings", "plans", "plan_words", "sessions",
        "session_main_questions", "session_sub_questions", "session_question_details",
        "session_question_answers", "session_word_settlements",
    )

    /** 导出时这些列还原成数组，导入时统一编码，数据库不出现两种数组格式。 */
    val arrayColumns = mapOf(
        "words" to setOf("confusions", "syllables"),
        "word_meanings" to setOf("confusions"),
        "session_sub_questions" to setOf("content", "answers", "distractors"),
        "session_question_answers" to setOf("answer"),
    )

    private const val common = """
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
    """

    fun create(db: SQLiteDatabase) {
        val definitions = linkedMapOf(
            "settings" to """
                key          TEXT NOT NULL,
                value        TEXT NOT NULL,
                type         TEXT NOT NULL CHECK(type IN ('string','int','double','bool','json'))
            """,
            "words" to """
                spelling     TEXT    NOT NULL CHECK(length(trim(spelling)) > 0),
                difficulty   INTEGER NOT NULL DEFAULT 0 CHECK(difficulty >= 0),
                confusions   TEXT    NOT NULL DEFAULT '[]',
                syllables    TEXT    NOT NULL DEFAULT '[]',
                reviewed_at  INTEGER NULL
            """,
            "word_meanings" to """
                word_id      INTEGER NOT NULL REFERENCES words(id),
                pos          TEXT    NULL,
                sub_pos      TEXT    NULL,
                definition   TEXT    NOT NULL CHECK(length(trim(definition)) > 0),
                confusions   TEXT    NOT NULL DEFAULT '[]',
                sort         INTEGER NOT NULL DEFAULT 0
            """,
            "plans" to """
                date         TEXT NOT NULL
            """,
            "plan_words" to """
                plan_id      INTEGER NOT NULL REFERENCES plans(id),
                word_id      INTEGER NOT NULL REFERENCES words(id),
                word_type    INTEGER NOT NULL CHECK(word_type IN (1,2))
            """,
            "sessions" to """
                module                   TEXT    NOT NULL,
                date                     TEXT    NOT NULL,
                kind                     INTEGER NOT NULL CHECK(kind IN (1,2,3)),
                status                   INTEGER NOT NULL DEFAULT 2 CHECK(status IN (0,1,2,3)),
                requires_answer          INTEGER NOT NULL CHECK(requires_answer IN (0,1)),
                settlement_status        INTEGER NOT NULL CHECK(settlement_status IN (0,1,2)),
                plan_id                  INTEGER NULL REFERENCES plans(id),
                current_main_question_id INTEGER NULL REFERENCES session_main_questions(id) DEFERRABLE INITIALLY DEFERRED,
                elapsed_seconds          INTEGER NOT NULL DEFAULT 0 CHECK(elapsed_seconds >= 0),
                answer_seconds           INTEGER NOT NULL DEFAULT 0 CHECK(answer_seconds >= 0)
            """,
            "session_main_questions" to """
                session_id               INTEGER NOT NULL REFERENCES sessions(id),
                question_no              INTEGER NOT NULL CHECK(question_no >= 1),
                phase                    INTEGER NOT NULL DEFAULT 0 CHECK(phase IN (0,1,2,3)),
                retry_count              INTEGER NOT NULL DEFAULT 0 CHECK(retry_count >= 0),
                current_sub_question_id  INTEGER NULL REFERENCES session_sub_questions(id) DEFERRABLE INITIALLY DEFERRED
            """,
            "session_sub_questions" to """
                main_question_id INTEGER NOT NULL REFERENCES session_main_questions(id),
                question_no      INTEGER NOT NULL CHECK(question_no >= 1),
                question_type    INTEGER NOT NULL CHECK(question_type IN (0,100,200,300,400)),
                content_type     INTEGER NOT NULL CHECK(content_type IN (1,2)),
                answer_type      INTEGER NOT NULL CHECK(answer_type IN (0,1,2)),
                used_seconds     INTEGER NOT NULL DEFAULT 0 CHECK(used_seconds >= 0),
                content          TEXT    NOT NULL,
                answers          TEXT    NULL,
                distractors      TEXT    NULL
            """,
            "session_question_details" to """
                sub_question_id INTEGER NOT NULL REFERENCES session_sub_questions(id),
                word_id         INTEGER NOT NULL REFERENCES words(id),
                meaning_id      INTEGER NULL REFERENCES word_meanings(id)
            """,
            "session_question_answers" to """
                sub_question_id INTEGER NOT NULL REFERENCES session_sub_questions(id),
                attempt_no      INTEGER NOT NULL DEFAULT 1 CHECK(attempt_no >= 1),
                answer          TEXT    NOT NULL,
                is_correct      INTEGER NOT NULL CHECK(is_correct IN (0,1))
            """,
            "session_word_settlements" to """
                apply_status         INTEGER NOT NULL DEFAULT 0 CHECK(apply_status IN (0,1)),
                session_id           INTEGER NOT NULL REFERENCES sessions(id),
                word_id              INTEGER NOT NULL REFERENCES words(id),
                date                 TEXT    NOT NULL,
                is_correct           INTEGER NOT NULL CHECK(is_correct IN (0,1)),
                difficulty_before    INTEGER NOT NULL CHECK(difficulty_before >= 0),
                difficulty_after     INTEGER NOT NULL CHECK(difficulty_after >= 0),
                suggested_adjustment INTEGER NOT NULL CHECK(suggested_adjustment BETWEEN -1 AND 1),
                adjustment           INTEGER NOT NULL CHECK(adjustment BETWEEN -1 AND 1),
                operation            INTEGER NOT NULL CHECK(operation IN (1,2))
            """,
        )
        for ((table, fields) in definitions) {
            db.execSQL("CREATE TABLE $table (id INTEGER PRIMARY KEY AUTOINCREMENT, ${fields.trim()}, $common)")
        }
        // 唯一约束只针对有效记录；软删除后允许重新使用同一天或同一个设置名称。
        val unique = mapOf(
            "settings_key" to "settings(key)",
            "plans_date" to "plans(date)",
            "plan_words_member" to "plan_words(plan_id,word_id)",
            "main_questions_order" to "session_main_questions(session_id,question_no)",
            "sub_questions_order" to "session_sub_questions(main_question_id,question_no)",
            "question_details_member" to "session_question_details(sub_question_id,word_id,IFNULL(meaning_id,0))",
            "word_settlements_member" to "session_word_settlements(session_id,word_id)",
        )
        for ((name, target) in unique) {
            db.execSQL("CREATE UNIQUE INDEX $name ON $target WHERE deleted_at IS NULL")
        }
        val indexes = mapOf(
            "words_spelling" to "words(spelling COLLATE NOCASE,id)",
            "words_difficulty" to "words(difficulty DESC,reviewed_at DESC,id)",
            "words_reviewed" to "words(reviewed_at ASC,difficulty ASC,id)",
            "word_meanings_order" to "word_meanings(word_id,sort DESC,id)",
            "word_meanings_definition" to "word_meanings(definition,word_id)",
            "plan_words_order" to "plan_words(plan_id,id)",
            "sessions_resume" to "sessions(module,date,kind,status,id DESC)",
            "sessions_settlement" to "sessions(settlement_status,status,id)",
            "question_answers_attempt" to "session_question_answers(sub_question_id,attempt_no,id)",
            "question_details_word" to "session_question_details(word_id,sub_question_id)",
            "word_settlements_date" to "session_word_settlements(apply_status,date,word_id)",
            "word_settlements_history" to "session_word_settlements(word_id,apply_status,updated_at DESC,id DESC)",
        )
        for ((name, target) in indexes) {
            db.execSQL("CREATE INDEX $name ON $target WHERE deleted_at IS NULL")
        }
        // 每个模块可以同时保留一局首页练习和一局自测，但各自不能重复开局。
        db.execSQL("CREATE UNIQUE INDEX sessions_active_home ON sessions(module,date) WHERE deleted_at IS NULL AND status=2 AND kind IN (1,2)")
        db.execSQL("CREATE UNIQUE INDEX sessions_active_self ON sessions(module,date) WHERE deleted_at IS NULL AND status=2 AND kind=3")
    }
}
