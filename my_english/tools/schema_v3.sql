-- 我的英语新版结构：仅十一张业务表。
-- 运行时来源：StudySchema.kt；所有时间戳为毫秒，耗时为秒。
PRAGMA foreign_keys = ON;

CREATE TABLE settings (
    id          INTEGER  PRIMARY KEY AUTOINCREMENT,
    key         TEXT     NOT NULL,
    value       TEXT     NOT NULL,
    type        TEXT     NOT NULL CHECK(type IN ('string','int','double','bool','json')),
    created_at  INTEGER  NOT NULL,
    updated_at  INTEGER  NOT NULL,
    deleted_at  INTEGER  NULL
);

CREATE TABLE words (
    id           INTEGER  PRIMARY KEY AUTOINCREMENT,
    spelling     TEXT     NOT NULL CHECK(length(trim(spelling)) > 0),
    difficulty   INTEGER  NOT NULL DEFAULT 0 CHECK(difficulty >= 0),
    confusions   TEXT     NOT NULL DEFAULT '[]',
    syllables    TEXT     NOT NULL DEFAULT '[]',
    reviewed_at  INTEGER  NULL,
    created_at   INTEGER  NOT NULL,
    updated_at   INTEGER  NOT NULL,
    deleted_at   INTEGER  NULL
);

CREATE TABLE word_meanings (
    id          INTEGER  PRIMARY KEY AUTOINCREMENT,
    word_id     INTEGER  NOT NULL REFERENCES words(id),
    pos         TEXT     NULL,
    sub_pos     TEXT     NULL,
    definition  TEXT     NOT NULL CHECK(length(trim(definition)) > 0),
    confusions  TEXT     NOT NULL DEFAULT '[]',
    sort        INTEGER  NOT NULL DEFAULT 0,
    created_at  INTEGER  NOT NULL,
    updated_at  INTEGER  NOT NULL,
    deleted_at  INTEGER  NULL
);

CREATE TABLE plans (
    id          INTEGER  PRIMARY KEY AUTOINCREMENT,
    date        TEXT     NOT NULL,
    created_at  INTEGER  NOT NULL,
    updated_at  INTEGER  NOT NULL,
    deleted_at  INTEGER  NULL
);

CREATE TABLE plan_words (
    id          INTEGER  PRIMARY KEY AUTOINCREMENT,
    plan_id     INTEGER  NOT NULL REFERENCES plans(id),
    word_id     INTEGER  NOT NULL REFERENCES words(id),
    word_type   INTEGER  NOT NULL CHECK(word_type IN (1,2)),
    created_at  INTEGER  NOT NULL,
    updated_at  INTEGER  NOT NULL,
    deleted_at  INTEGER  NULL
);

CREATE TABLE sessions (
    id                        INTEGER  PRIMARY KEY AUTOINCREMENT,
    module                    TEXT     NOT NULL,
    date                      TEXT     NOT NULL,
    kind                      INTEGER  NOT NULL CHECK(kind IN (1,2,3)),
    status                    INTEGER  NOT NULL DEFAULT 2 CHECK(status IN (0,1,2,3)),
    requires_answer           INTEGER  NOT NULL CHECK(requires_answer IN (0,1)),
    settlement_status         INTEGER  NOT NULL CHECK(settlement_status IN (0,1,2)),
    plan_id                   INTEGER  NULL REFERENCES plans(id),
    current_main_question_id  INTEGER  NULL REFERENCES session_main_questions(id) DEFERRABLE INITIALLY DEFERRED,
    elapsed_seconds           INTEGER  NOT NULL DEFAULT 0 CHECK(elapsed_seconds >= 0),
    answer_seconds            INTEGER  NOT NULL DEFAULT 0 CHECK(answer_seconds >= 0),
    created_at                INTEGER  NOT NULL,
    updated_at                INTEGER  NOT NULL,
    deleted_at                INTEGER  NULL
);

CREATE TABLE session_main_questions (
    id                       INTEGER  PRIMARY KEY AUTOINCREMENT,
    session_id               INTEGER  NOT NULL REFERENCES sessions(id),
    question_no              INTEGER  NOT NULL CHECK(question_no >= 1),
    phase                    INTEGER  NOT NULL DEFAULT 0 CHECK(phase IN (0,1,2,3)),
    retry_count              INTEGER  NOT NULL DEFAULT 0 CHECK(retry_count >= 0),
    current_sub_question_id  INTEGER  NULL REFERENCES session_sub_questions(id) DEFERRABLE INITIALLY DEFERRED,
    created_at               INTEGER  NOT NULL,
    updated_at               INTEGER  NOT NULL,
    deleted_at               INTEGER  NULL
);

CREATE TABLE session_sub_questions (
    id                INTEGER  PRIMARY KEY AUTOINCREMENT,
    main_question_id  INTEGER  NOT NULL REFERENCES session_main_questions(id),
    question_no       INTEGER  NOT NULL CHECK(question_no >= 1),
    question_type     INTEGER  NOT NULL CHECK(question_type IN (0,100,200,300,400)),
    content_type      INTEGER  NOT NULL CHECK(content_type IN (1,2)),
    answer_type       INTEGER  NOT NULL CHECK(answer_type IN (0,1,2)),
    used_seconds      INTEGER  NOT NULL DEFAULT 0 CHECK(used_seconds >= 0),
    content           TEXT     NOT NULL,
    answers           TEXT     NULL,
    distractors       TEXT     NULL,
    created_at        INTEGER  NOT NULL,
    updated_at        INTEGER  NOT NULL,
    deleted_at        INTEGER  NULL
);

CREATE TABLE session_question_details (
    id               INTEGER  PRIMARY KEY AUTOINCREMENT,
    sub_question_id  INTEGER  NOT NULL REFERENCES session_sub_questions(id),
    word_id          INTEGER  NOT NULL REFERENCES words(id),
    meaning_id       INTEGER  NULL REFERENCES word_meanings(id),
    created_at       INTEGER  NOT NULL,
    updated_at       INTEGER  NOT NULL,
    deleted_at       INTEGER  NULL
);

CREATE TABLE session_question_answers (
    id               INTEGER  PRIMARY KEY AUTOINCREMENT,
    sub_question_id  INTEGER  NOT NULL REFERENCES session_sub_questions(id),
    attempt_no       INTEGER  NOT NULL DEFAULT 1 CHECK(attempt_no >= 1),
    answer           TEXT     NOT NULL,
    is_correct       INTEGER  NOT NULL CHECK(is_correct IN (0,1)),
    created_at       INTEGER  NOT NULL,
    updated_at       INTEGER  NOT NULL,
    deleted_at       INTEGER  NULL
);

CREATE TABLE session_word_settlements (
    id                    INTEGER  PRIMARY KEY AUTOINCREMENT,
    apply_status          INTEGER  NOT NULL DEFAULT 0 CHECK(apply_status IN (0,1)),
    session_id            INTEGER  NOT NULL REFERENCES sessions(id),
    word_id               INTEGER  NOT NULL REFERENCES words(id),
    date                  TEXT     NOT NULL,
    is_correct            INTEGER  NOT NULL CHECK(is_correct IN (0,1)),
    difficulty_before     INTEGER  NOT NULL CHECK(difficulty_before >= 0),
    difficulty_after      INTEGER  NOT NULL CHECK(difficulty_after >= 0),
    suggested_adjustment  INTEGER  NOT NULL CHECK(suggested_adjustment BETWEEN -1 AND 1),
    adjustment            INTEGER  NOT NULL CHECK(adjustment BETWEEN -1 AND 1),
    operation             INTEGER  NOT NULL CHECK(operation IN (1,2)),
    created_at            INTEGER  NOT NULL,
    updated_at            INTEGER  NOT NULL,
    deleted_at            INTEGER  NULL
);

CREATE UNIQUE INDEX settings_key ON settings(key) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX plans_date ON plans(date) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX plan_words_member ON plan_words(plan_id,word_id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX main_questions_order ON session_main_questions(session_id,question_no) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX sub_questions_order ON session_sub_questions(main_question_id,question_no) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX question_details_member ON session_question_details(sub_question_id,word_id,IFNULL(meaning_id,0)) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX word_settlements_member ON session_word_settlements(session_id,word_id) WHERE deleted_at IS NULL;
CREATE INDEX words_spelling ON words(spelling COLLATE NOCASE,id) WHERE deleted_at IS NULL;
CREATE INDEX words_difficulty ON words(difficulty DESC,reviewed_at DESC,id) WHERE deleted_at IS NULL;
CREATE INDEX words_reviewed ON words(reviewed_at ASC,difficulty ASC,id) WHERE deleted_at IS NULL;
CREATE INDEX word_meanings_order ON word_meanings(word_id,sort DESC,id) WHERE deleted_at IS NULL;
CREATE INDEX word_meanings_definition ON word_meanings(definition,word_id) WHERE deleted_at IS NULL;
CREATE INDEX plan_words_order ON plan_words(plan_id,id) WHERE deleted_at IS NULL;
CREATE INDEX sessions_resume ON sessions(module,date,kind,status,id DESC) WHERE deleted_at IS NULL;
CREATE INDEX sessions_settlement ON sessions(settlement_status,status,id) WHERE deleted_at IS NULL;
CREATE INDEX question_answers_attempt ON session_question_answers(sub_question_id,attempt_no,id) WHERE deleted_at IS NULL;
CREATE INDEX question_details_word ON session_question_details(word_id,sub_question_id) WHERE deleted_at IS NULL;
CREATE INDEX word_settlements_date ON session_word_settlements(apply_status,date,word_id) WHERE deleted_at IS NULL;
CREATE INDEX word_settlements_history ON session_word_settlements(word_id,apply_status,updated_at DESC,id DESC) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX sessions_active_home ON sessions(module,date) WHERE deleted_at IS NULL AND status=2 AND kind IN (1,2);
CREATE UNIQUE INDEX sessions_active_self ON sessions(module,date) WHERE deleted_at IS NULL AND status=2 AND kind=3;
