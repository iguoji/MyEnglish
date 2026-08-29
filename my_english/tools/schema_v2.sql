-- ===========================================================================
-- 我的英语 · 新库结构（v2）
--
-- 依据：项目根目录 `数据结构.md`
-- 目标：整个 App 只有这 5 张表，没有第二份持久化（离线语音 mp3 除外，
--       它是可再生的文件缓存，不属于业务数据）。
--
-- 环境约束（minSdk 24 = Android 7，SQLite 3.9）：
--   · 部分索引（带 WHERE 的索引）  可用
--   · COLLATE NOCASE               可用
--   · 窗口函数 / JSON1 函数        不可用 —— 所以 JSON 数组一律在 Kotlin 侧解析，
--                                  「连对次数」也在 Kotlin 里循环算，不写 SQL 窗口函数
--
-- 通用约定：
--   · 每张表都有 id / created_at / updated_at / deleted_at
--   · 时间一律毫秒时间戳（INTEGER）
--   · deleted_at 为 NULL 表示未删除；删除只写时间，不真删行
--   · 所有索引都带 `WHERE deleted_at IS NULL`，让索引里只存活着的行，更小更快
-- ===========================================================================

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- 1. 设置表 —— 一个可持久化的 Redis
--
-- type 声明 value 的真实类型，读的时候按它还原。
-- 生活化解释：value 列永远是文本，type 就是贴在瓶子上的标签，
-- 告诉你瓶里装的是数字、开关还是一整块 JSON。
-- ---------------------------------------------------------------------------
CREATE TABLE settings (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    key         TEXT    NOT NULL,
    value       TEXT    NOT NULL,
    type        TEXT    NOT NULL DEFAULT 'string'
                        CHECK (type IN ('string', 'int', 'double', 'bool', 'json')),
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    deleted_at  INTEGER NULL
);

-- 同一个 key 在「活着的行」里只能有一条；软删掉的旧行不占用这个名字。
CREATE UNIQUE INDEX settings_key ON settings(key) WHERE deleted_at IS NULL;


-- ---------------------------------------------------------------------------
-- 2. 单词表
--
-- confusions（混淆词）与 syllables（拆分）都是 JSON 数组文本。
-- 混淆词按「用到才生成」的策略：某个模块第一次遇到这个词时算一批存进来，
-- 之后所有模块直接复用；用户长按某个混淆词可以重算并覆盖。
--
-- 重要：回写 confusions 时**不要动 updated_at**，
-- 否则复习行为会把词库的「最近修改」顺序全部打乱。
-- ---------------------------------------------------------------------------
CREATE TABLE words (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    spelling    TEXT    NOT NULL,
    difficulty  INTEGER NOT NULL DEFAULT 0 CHECK (difficulty >= 0),
    confusions  TEXT    NOT NULL DEFAULT '[]',
    syllables   TEXT    NOT NULL DEFAULT '[]',
    -- 可空：NULL 代表「从来没复习过」。
    -- SQLite 的 ORDER BY ... ASC 天然把 NULL 排在最前面，
    -- 正好等于选词规则里的「先未复习、再早期复习、最后近期复习」。
    reviewed_at INTEGER NULL,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    deleted_at  INTEGER NULL
);

-- 选词第一层（难度降序打头，专挑难词）。已验证：完整走索引，无额外排序。
CREATE INDEX words_pick_hard
    ON words(difficulty DESC, reviewed_at ASC, id ASC)
    WHERE deleted_at IS NULL;

-- 选词第二层（复习时间升序打头，专挑久未复习的词）。同样完整走索引。
CREATE INDEX words_pick_stale
    ON words(reviewed_at ASC, difficulty DESC, id ASC)
    WHERE deleted_at IS NULL;

-- 词库搜索、按拼写排序、生成混淆词时按拼写找相似词。
CREATE INDEX words_spelling
    ON words(spelling COLLATE NOCASE)
    WHERE deleted_at IS NULL;


-- ---------------------------------------------------------------------------
-- 3. 含义表 —— 一行就是一条中文释义
--
-- pos 是主词性（n. / v. / adj. ...），sub_pos 是子词性（vt. / vi. / vlink.）。
-- 未选词性时 pos 存空串，界面照旧显示成 '*'。
-- sort 数字越大越靠前（与旧库 index DESC 的显示顺序完全一致）。
-- ---------------------------------------------------------------------------
CREATE TABLE meanings (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    word_id     INTEGER NOT NULL REFERENCES words(id) ON DELETE CASCADE,
    pos         TEXT    NOT NULL,
    sub_pos     TEXT    NULL,
    definition  TEXT    NOT NULL,
    confusions  TEXT    NOT NULL DEFAULT '[]',
    sort        INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    deleted_at  INTEGER NULL
);

-- 「取某个单词的全部含义，排序值大的在前」是全项目最高频的一句查询。
CREATE INDEX meanings_word
    ON meanings(word_id, sort DESC, id ASC)
    WHERE deleted_at IS NULL;


-- ---------------------------------------------------------------------------
-- 4. 复习词库表 —— 今天要背的这一批
--
-- 每天最多几条（改了「每日复习」数量就新建一条），永远取当天最新的那条。
-- tomorrow_word_ids 只服务于「今天的巩固局」，第二天不复用。
-- ---------------------------------------------------------------------------
CREATE TABLE word_sets (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    word_count        INTEGER NOT NULL CHECK (word_count >= 0),
    today_word_ids    TEXT    NOT NULL DEFAULT '[]',
    tomorrow_word_ids TEXT    NOT NULL DEFAULT '[]',
    date              TEXT    NOT NULL,
    created_at        INTEGER NOT NULL,
    updated_at        INTEGER NOT NULL,
    deleted_at        INTEGER NULL
);

-- 「永远取今日最新的那一条」：date 倒序 + id 倒序，取第一行即可。
CREATE INDEX word_sets_date
    ON word_sets(date DESC, id DESC)
    WHERE deleted_at IS NULL;


-- ---------------------------------------------------------------------------
-- 5. 会话表 —— 一个模块的一局
--
-- items（数据列表）是 JSON 数组，形状按模块而定：
--   随身听     [单词id, ...]
--   听音辨义   [单词id, ...]
--   词义连连   [[单词id, 含义id], ...]
--   拼写巩固   [单词id, ...]
--   看义选词   [含义id, ...]
--
-- cursor 是 items 的外层索引；一条 item 内部走到哪一步不存这里，
-- 靠会话记录表反查（每点一次都有记录，所以能精确还原）。
-- ---------------------------------------------------------------------------
CREATE TABLE sessions (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    module      TEXT    NOT NULL,
    -- 1 每日主线进度，2 无限巩固练习
    kind        INTEGER NOT NULL CHECK (kind IN (1, 2)),
    -- 1 进行中，2 完成，3 中断，4 失败
    status      INTEGER NOT NULL CHECK (status IN (1, 2, 3, 4)),
    word_set_id INTEGER NULL REFERENCES word_sets(id) ON DELETE SET NULL,
    items       TEXT    NOT NULL DEFAULT '[]',
    cursor      INTEGER NOT NULL DEFAULT 0 CHECK (cursor >= 0),
    -- 所用时间，单位秒
    elapsed     INTEGER NOT NULL DEFAULT 0 CHECK (elapsed >= 0),
    date        TEXT    NOT NULL,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    deleted_at  INTEGER NULL
);

-- 点进模块时的第一句 SQL：「今天这个模块最新的一条会话」。
CREATE INDEX sessions_module_date
    ON sessions(module, date DESC, id DESC)
    WHERE deleted_at IS NULL;

-- 改「每日复习」数量时批量中断全部进行中的会话；跨天清理僵尸会话也走它。
CREATE INDEX sessions_status
    ON sessions(status, date DESC)
    WHERE deleted_at IS NULL;


-- ---------------------------------------------------------------------------
-- 6. 会话记录表 —— 每点一次就写一条
--
-- 这张表是整个新设计的支点：因为「每次点击都留痕」，
-- 会话中断后的现场（做到第几条、哪几个候选已经点错了）全都能反查出来，
-- 不再需要旧版那个又大又脆的 state_json 快照。
--
-- 随身听是被动听，没有对错，不写这张表。
-- ---------------------------------------------------------------------------
CREATE TABLE session_records (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id  INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    word_id     INTEGER NOT NULL REFERENCES words(id) ON DELETE CASCADE,
    -- 可空：听音辨义的「选拼写」这一步不针对具体含义。
    meaning_id  INTEGER NULL REFERENCES meanings(id) ON DELETE CASCADE,
    -- 用户实际选的那个候选词，或拼错的完整单词。
    input       TEXT    NOT NULL DEFAULT '',
    -- 1 对，0 错
    result      INTEGER NOT NULL CHECK (result IN (0, 1)),
    date        TEXT    NOT NULL,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    deleted_at  INTEGER NULL
);

-- 派生「连对次数」：按单词倒序扫，数到第一个 0 就停。每答一题都要跑一次，
-- 是这张表上最高频的读，必须有这条索引。
CREATE INDEX records_word
    ON session_records(word_id, id DESC)
    WHERE deleted_at IS NULL;

-- 会话恢复（这一局这个词/这条含义答过没有、点错过哪些候选）、
-- 以及结算时数「本局错了几次」，都走这条。
CREATE INDEX records_session
    ON session_records(session_id, word_id, meaning_id)
    WHERE deleted_at IS NULL;

-- 首页数字、趋势曲线、打卡热力图：按日期分组 + 按单词去重。
CREATE INDEX records_date
    ON session_records(date, word_id)
    WHERE deleted_at IS NULL;
