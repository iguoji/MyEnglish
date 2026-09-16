package com.example.my_english

import android.os.SystemClock
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.max

/**
 * 计划、试卷、答题和结算共用的业务入口。
 * 页面只提交题号和实际答案；判对、重试遍次、完成检查及防重复结算都由数据库保证。
 */
internal class StudyRepository(private val owner: WordsDatabase) {
    private companion object {
        // 一份字段清单就是页面与数据库之间的接口约定，所有模块共用。
        val pageGroupFields = listOf("id", "question_no", "phase", "retry_count", "current_sub_question_id")
        val pageQuestionFields = listOf("id", "main_question_id", "question_no", "question_type",
            "content_type", "answer_type", "used_seconds", "content", "answers", "distractors")
        val pageDetailFields = listOf("word_id", "meaning_id")
    }

    /** 一次取齐试卷并按编号建索引，避免每道题单独打开一个数据库游标。 */
    private class PaperRows(
        val groups: List<Map<String, Any?>>,
        val questions: List<Map<String, Any?>>,
        val details: List<Map<String, Any?>>,
    ) {
        val questionsByGroup = questions.groupBy { it.long("main_question_id") }
        val questionById = questions.associateBy { it.long("id") }
        val detailsByQuestion = details.groupBy { it.long("sub_question_id") }
    }

    private fun loadPaper(id: Long) = PaperRows(groups(id), allQuestions(id), rows(
        "SELECT d.* FROM session_question_details d JOIN session_sub_questions q ON q.id=d.sub_question_id " +
            "JOIN session_main_questions g ON g.id=q.main_question_id WHERE g.session_id=? " +
            "AND d.deleted_at IS NULL AND q.deleted_at IS NULL AND g.deleted_at IS NULL ORDER BY d.id", id,
    ))

    private fun currentAnswers(id: Long) = rows(
        "SELECT a.* FROM session_question_answers a JOIN session_sub_questions q ON q.id=a.sub_question_id " +
            "JOIN session_main_questions g ON g.id=q.main_question_id WHERE g.session_id=? " +
            "AND a.attempt_no=g.retry_count+1 AND a.deleted_at IS NULL AND q.deleted_at IS NULL " +
            "AND g.deleted_at IS NULL ORDER BY a.id", id,
    )

    private fun rows(sql: String, vararg args: Any?) = owner.rows(sql, args.toList())
    private fun one(sql: String, vararg args: Any?) = rows(sql, *args).firstOrNull()
    private fun session(id: Long) = one("SELECT * FROM sessions WHERE id=? AND deleted_at IS NULL", id) ?: error("会话已不存在")
    private fun group(id: Long) = one("SELECT * FROM session_main_questions WHERE id=? AND deleted_at IS NULL", id) ?: error("大题已不存在")
    private fun question(id: Long) = one("SELECT * FROM session_sub_questions WHERE id=? AND deleted_at IS NULL", id) ?: error("小题已不存在")
    private fun groups(id: Long) = rows("SELECT * FROM session_main_questions WHERE session_id=? AND deleted_at IS NULL ORDER BY question_no", id)
    private fun questions(id: Long) = rows("SELECT * FROM session_sub_questions WHERE main_question_id=? AND deleted_at IS NULL ORDER BY question_no", id)
    private fun details(id: Long) = rows("SELECT * FROM session_question_details WHERE sub_question_id=? AND deleted_at IS NULL ORDER BY id", id)
    private fun answers(id: Long, attempt: Int) = rows("SELECT * FROM session_question_answers WHERE sub_question_id=? AND attempt_no=? AND deleted_at IS NULL ORDER BY id", id, attempt)
    private fun allQuestions(id: Long) = rows("SELECT q.* FROM session_sub_questions q JOIN session_main_questions g ON g.id=q.main_question_id WHERE g.session_id=? AND g.deleted_at IS NULL AND q.deleted_at IS NULL ORDER BY g.question_no,q.question_no", id)
    /** 只在数据库串行队列使用，最多缓存两局原始副本；不会让历史会话无限占内存。 */
    private class WordSnapshot(val words: List<Map<*, *>>) {
        val byWord = words.associateBy { it.long("id") }
        val meanings = words.flatMap { word ->
            ((word["meanings"] as? List<*>) ?: emptyList<Any?>()).filterIsInstance<Map<*, *>>().map {
                it.long("id") to (word.long("id") to it)
            }
        }.toMap()
    }
    private val snapshotCache = object : LinkedHashMap<Long, WordSnapshot>(3, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<Long, WordSnapshot>?): Boolean = size > 2
    }
    fun clearSnapshotCache() = snapshotCache.clear()

    /**
     * 随身听改用设置中的唯一清单。首次升级保留最后一次播放的顺序及进度，
     * 只查询单词编号和题目游标，不读取上千份正文，也不改动旧历史会话。
     */
    fun migrateListeningPlayback() = owner.transaction {
        val key = WordsDatabase.LISTENING_PLAYBACK_KEY
        if (owner.setting(key) != null) return@transaction
        val previous = one("SELECT * FROM sessions WHERE module='listening' AND deleted_at IS NULL ORDER BY id DESC LIMIT 1")
        if (previous == null) {
            owner.putSetting(key, encode(mapOf("revision" to "empty", "word_ids" to emptyList<Long>())))
            return@transaction
        }
        val id = previous.long("id")
        val wordIds = rows(
            "SELECT d.word_id FROM session_question_details d " +
                "JOIN session_sub_questions q ON q.id=d.sub_question_id " +
                "JOIN session_main_questions g ON g.id=q.main_question_id " +
                "WHERE g.session_id=? AND g.deleted_at IS NULL AND q.deleted_at IS NULL " +
                "AND d.deleted_at IS NULL ORDER BY g.question_no,q.question_no,d.id", id,
        ).map { it.long("word_id") }.distinct()
        val playback = owner.setting("session.$id.playback") as? Map<*, *> ?: emptyMap<Any?, Any?>()
        val finished = previous.int("status") == 1
        owner.putSetting(key, encode(mapOf(
            "revision" to "legacy-$id", "word_ids" to wordIds,
            "cursor" to position(previous).first.coerceIn(0, (wordIds.size - 1).coerceAtLeast(0)),
            "elapsed_seconds" to previous.int("elapsed_seconds"),
            "completed_repeats" to (playback["completed_repeats"] ?: 0),
            "remaining_seconds" to (playback["remaining_seconds"] ?: owner.settingInt("listeningInterval", 2)),
            "waiting_interval" to (playback["waiting_interval"] == true),
            "is_playing" to (!finished && playback["is_playing"] != false && wordIds.isNotEmpty()),
            "is_finished" to finished,
        )))
    }

    private fun baseSnapshot(id: Long): WordSnapshot = snapshotCache[id] ?: WordSnapshot(
        (owner.setting("session.$id.snapshot") as? List<*>)?.filterIsInstance<Map<*, *>>() ?: error("会话缺少词库快照"),
    ).also { snapshotCache[id] = it }

    /** 混淆字段以小补丁保存，读取时合入原副本；兼容已有完整副本和新版备份。 */
    private fun snapshot(id: Long): List<Map<*, *>> {
        val base = baseSnapshot(id)
        val prefix = "session.$id.confusions."
        val changes = rows("SELECT key,value FROM settings WHERE key>=? AND key<? AND deleted_at IS NULL ORDER BY key", prefix, prefix + "\uffff")
        if (changes.isEmpty()) return base.words
        val wordChanges = mutableMapOf<Long, List<String>>()
        val meaningChanges = mutableMapOf<Long, List<String>>()
        val affected = mutableSetOf<Long>()
        for (change in changes) {
            val suffix = change["key"].toString().removePrefix(prefix).split('.')
            require(suffix.size == 2) { "混淆快照名称无效" }
            val target = suffix[1].toLongOrNull() ?: error("混淆快照编号无效")
            val values = strings(change["value"])
            if (suffix[0] == "word") {
                require(target in base.byWord) { "混淆快照引用的单词不存在" }
                wordChanges[target] = values
                affected.add(target)
            } else {
                require(suffix[0] == "meaning" && target in base.meanings) { "混淆快照引用的含义不存在" }
                meaningChanges[target] = values
                affected.add(base.meanings.getValue(target).first)
            }
        }
        return base.words.map { word ->
            val wordId = word.long("id")
            if (wordId !in affected) word else word.toMutableMap().apply {
                wordChanges[wordId]?.let { put("confusions", it) }
                put("meanings", ((word["meanings"] as? List<*>) ?: emptyList<Any?>()).map { value ->
                    val meaning = value as Map<*, *>
                    val patch = meaningChanges[meaning.long("id")]
                    if (patch == null) meaning else meaning.toMutableMap().apply { put("confusions", patch) }
                })
            }
        }
    }
    private fun nextDate(date: String): String {
        val format = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { isLenient = false }
        val calendar = Calendar.getInstance().apply { time = format.parse(date) ?: error("日期无效"); add(Calendar.DATE, 1) }
        return format.format(calendar.time)
    }

    /** 通道参数集中在这里解析，MainActivity 只承担线程切换。 */
    fun call(method: String, p: Map<*, *>): Any? = when (method) {
        "resolvePlan" -> resolvePlan(p["date"].toString(), p.int("dailyGoal"), p["ensureTomorrow"] != false,
            (p["exclude"] as? List<*>)?.map { (it as Number).toLong() } ?: emptyList())
        "getLatestWordSet", "getPlan" -> readPlan(p["date"].toString())
        "createStudySession" -> createSession(p)
        "getSession" -> readSession(p.long("id"))
        "getActiveSession" -> activeSession(p["module"].toString(), p["date"].toString(), p["selfTest"] == true)?.takeIf {
            // 自测刚打开就返回只留下空试卷，不算需要继续的作答进度。
            // 按钮查询和真正恢复走同一判断，不能只把图标涂灰却仍允许恢复空局。
            p["selfTest"] != true || hasRecordedAnswers(it.long("id"))
        }?.let {
            if (p["headerOnly"] == true) it + mapOf("elapsed" to it["elapsed_seconds"], "word_set_id" to it["plan_id"]) else readSession(it.long("id"))
        }
        "getLatestSession" -> latestSession(p["module"].toString(), p["date"].toString(), p["selfTest"] == true)?.let { readSession(it.long("id")) }
        "getCompletedDailySession" -> one("SELECT * FROM sessions WHERE module=? AND date=? AND kind=1 AND status=1 AND deleted_at IS NULL ORDER BY id DESC LIMIT 1", p["module"], p["date"])
        "getTodaySessionStates" -> moduleStates(p["date"].toString())
        "updateSessionProgress" -> saveProgress(p)
        "submitStudyAnswer" -> submit(p)
        "retryStudyGroup" -> retry(p.long("sessionId"), p.long("groupId"))
        "saveQuestionDistractors" -> saveDistractors(p)
        "prepareSettlement" -> owner.transaction { prepare(p.long("sessionId"), p.long("wordId")) }
        "upsertSettlementDraft" -> owner.transaction { prepare(p.long("sessionId"), p.long("wordId")); null }
        "updateSettlementDraft" -> adjust(p)
        "getSettlementDrafts" -> settlementRows(p.long("sessionId"))
        "finishSession" -> finish(p)
        "finalizeSessionSettlement" -> finalize(p.long("sessionId"))
        "recoverPendingSettlements" -> rows("SELECT id FROM sessions WHERE status=1 AND settlement_status=0 AND deleted_at IS NULL ORDER BY id").sumOf { finalize(it.long("id")) }
        "settleStaleSessions" -> closeStale(p["date"].toString())
        "abortActiveSessions" -> abortWhere("1=1", emptyList())
        "getSessionRecords" -> records(p.long("sessionId"))
        "getTodayReviewedWordCount", "getTodayCorrectWordCount" -> reviewedIds(p["date"].toString()).size
        "getTodayReviewedWordIds", "getTodayCorrectWordIds" -> reviewedIds(p["date"].toString())
        "getDailyCounts" -> dailyCounts(p["since"]?.toString())
        "getDailyDurations" -> dailyDurations(p["since"]?.toString())
        "getMonthlyCounts" -> rows("SELECT substr(date,1,7) AS month,COUNT(DISTINCT word_id) AS count FROM session_word_settlements WHERE apply_status=1 AND deleted_at IS NULL AND date>=? GROUP BY substr(date,1,7) ORDER BY month", p["since"]?.toString() ?: "0000-01-01")
        else -> error("未知学习操作：$method")
    }

    private fun activeSession(module: String, date: String, self: Boolean) = one(
        "SELECT * FROM sessions WHERE module=? AND date=? AND ${if (self) "kind=3" else "kind IN (1,2)"} AND status=2 AND deleted_at IS NULL ORDER BY id DESC LIMIT 1", module, date,
    )

    /** 只检查一条已保存答案；不读取整份试卷，也不改动已有会话或历史记录。 */
    private fun hasRecordedAnswers(id: Long): Boolean = one(
        "SELECT a.id FROM session_question_answers a " +
            "JOIN session_sub_questions q ON q.id=a.sub_question_id " +
            "JOIN session_main_questions g ON g.id=q.main_question_id " +
            "WHERE g.session_id=? AND a.deleted_at IS NULL AND q.deleted_at IS NULL " +
            "AND g.deleted_at IS NULL LIMIT 1", id,
    ) != null
    private fun latestSession(module: String, date: String, self: Boolean) = one(
        "SELECT * FROM sessions WHERE module=? AND date=? AND ${if (self) "kind=3" else "kind IN (1,2)"} AND deleted_at IS NULL ORDER BY id DESC LIMIT 1", module, date,
    )

    /** 每次获取都按当前目标补缺，词库暂时不足不会把每日目标永久降小。 */
    private fun resolvePlan(date: String, target: Int, ensureTomorrow: Boolean, exclude: List<Long>): Map<String, Any?>? = owner.transaction {
        require(owner.validDate(date) && target >= 0) { "计划日期或每日数量无效" }
        var plan = one("SELECT * FROM plans WHERE date=? AND deleted_at IS NULL", date)
        if (plan == null && target == 0) return@transaction null
        val planId = plan?.long("id") ?: owner.insert("plans", mapOf("date" to date))
        val excluded = exclude.toHashSet()
        val members = rows("SELECT p.*,w.deleted_at AS word_deleted_at FROM plan_words p JOIN words w ON w.id=p.word_id WHERE p.plan_id=? AND p.deleted_at IS NULL ORDER BY p.id", planId)
        // 还能留用的成员：单词没被删、也不在本次排除名单里。
        val alive = members.filter { it["word_deleted_at"] == null && it.long("word_id") !in excluded }
        // 目标数量变小（用户把「每日复习」调小）时，按 40/60 的配额从两层里各留一部分。
        // 《功能描述.md》只写了「多了要删」，没规定删哪些；这里按计划本身的构成来删——
        // 计划就是「难词 40% + 久词 60%」的池子，削减后保持同样的比例才不会换口味。
        // 生活化解释：计划成员写进数据库的顺序是「先难词、后久词」，以前削减时直接
        // 从头留够数量，砍掉的全是排在后面的久词——把每日复习从 50 改回 15，剩下的
        // 15 个就全是难词，看起来就像「规则里的 60% 久词一次都没出现」。
        val hardAlive = alive.filter { it.int("word_type") == WordsDatabase.LAYER_HARD }
        val staleAlive = alive.filter { it.int("word_type") == WordsDatabase.LAYER_STALE }
        val hardQuota = minOf(hardAlive.size, minOf(ceil(target * 0.4).toInt(), target))
        val staleQuota = minOf(staleAlive.size, target - hardQuota)
        val kept = mutableListOf<Map<String, Any?>>()
        kept.addAll(hardAlive.take(hardQuota))
        kept.addAll(staleAlive.take(staleQuota))
        // 某一层不足时用另一层的剩余成员补满，削减后不会凭空空出几个位置。
        for (member in hardAlive.drop(hardQuota) + staleAlive.drop(staleQuota)) {
            if (kept.size >= target) break
            kept.add(member)
        }
        val keptIds = kept.map { it.long("id") }.toHashSet()
        for (member in members) {
            if (member.long("id") !in keptIds)
                owner.update("plan_words", member.long("id"), mapOf("deleted_at" to System.currentTimeMillis()))
        }
        val missing = target - kept.size
        if (missing > 0) {
            val blocked = exclude + kept.map { it.long("word_id") }
            val hard = owner.pickWords(ceil(missing * 0.4).toInt(), blocked, WordsDatabase.LAYER_HARD)
            val stale = owner.pickWords(missing - hard.size, blocked + hard, WordsDatabase.LAYER_STALE)
            for ((type, ids) in listOf(1 to hard, 2 to stale)) for (id in ids)
                owner.insert("plan_words", mapOf("plan_id" to planId, "word_id" to id, "word_type" to type))
        }
        // 已有的预建计划也维护下一天，且只向前准备一天，避免递归生成无穷日期。
        if (ensureTomorrow && target > 0) {
            val today = rows("SELECT word_id FROM plan_words WHERE plan_id=? AND deleted_at IS NULL ORDER BY id", planId).map { it.long("word_id") }
            resolvePlan(nextDate(date), target, false, today)
        }
        readPlan(date)
    }

    private fun readPlan(date: String): Map<String, Any?>? {
        val plan = one("SELECT * FROM plans WHERE date=? AND deleted_at IS NULL", date) ?: return null
        val members = rows("SELECT * FROM plan_words WHERE plan_id=? AND deleted_at IS NULL ORDER BY id", plan.long("id"))
        val tomorrow = one("SELECT id FROM plans WHERE date=? AND deleted_at IS NULL", nextDate(date))
        val tomorrowIds = if (tomorrow == null) emptyList() else rows("SELECT word_id FROM plan_words WHERE plan_id=? AND deleted_at IS NULL ORDER BY id", tomorrow.long("id")).map { it.long("word_id") }
        // 这些列表是查询结果，实际保存的是 plans / plan_words，不再保存重复的编号数组。
        return plan + mapOf("word_count" to members.size, "today_word_ids" to members.map { it.long("word_id") },
            "tomorrow_word_ids" to tomorrowIds, "hard_word_ids" to members.filter { it.int("word_type") == 1 }.map { it.long("word_id") }, "members" to members)
    }

    private fun createSession(p: Map<*, *>): Map<String, Any?> {
        val timing = StudyOpenTiming.from(p, "repository_create")
        val result = owner.transaction {
            timing?.mark("transaction_started")
            createSessionRows(p, timing)
        }
        // 必须在 transaction 返回后计时：旧日志位于事务内，漏掉最后提交磁盘。
        timing?.mark("transaction_committed")
        timing?.write()
        return result
    }

    private fun createSessionRows(p: Map<*, *>, timing: StudyOpenTiming?): Map<String, Any?> {
        val module = p["module"]?.toString().orEmpty()
        require(module in setOf("listening", "listening_meaning", "meaning_match", "spelling_reinforcement", "meaning_word_choice")) { "未知学习模块" }
        val kind = p.int("kind")
        val date = p["date"].toString()
        require(kind in 1..3 && owner.validDate(date)) { "会话类型或日期无效" }
        val old = activeSession(module, date, kind == 3)
        if (old != null) {
            if (kind != 3) return readSession(old.long("id"))
            abort(old.long("id"))
        }
        val words = (p["words"] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: error("缺少会话词库")
        val paper = (p["groups"] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: error("缺少试卷")
        require(words.isNotEmpty() && paper.isNotEmpty()) { "没有可学习的内容" }
        timing?.mark("existing_session_handled")
        val started = SystemClock.elapsedRealtime()
        val ids = words.map { it.long("id") }.distinct()
        val liveWords = ids.chunked(800).flatMap { chunk -> owner.rows(
            "SELECT id,spelling FROM words WHERE deleted_at IS NULL AND id IN (${marks(chunk.size)})", chunk,
        ) }.associateBy { it.long("id") }
        val liveMeanings = ids.chunked(800).flatMap { chunk -> owner.rows(
            "SELECT id,word_id,definition FROM word_meanings WHERE deleted_at IS NULL AND word_id IN (${marks(chunk.size)})", chunk,
        ) }.associateBy { it.long("id") }
        require(words.all { frozen ->
            val wordId = frozen.long("id")
            val live = liveWords[wordId]
            live != null && live["spelling"] == frozen["spelling"] &&
                ((frozen["meanings"] as? List<*>) ?: emptyList<Any?>()).all meanings@ { raw ->
                    val meaning = raw as? Map<*, *> ?: return@meanings false
                    val actual = liveMeanings[meaning.long("id")]
                    actual != null && actual.long("word_id") == wordId && actual["definition"] == meaning["definition"]
                }
        }) { "词库已发生变化，请重新开始这次练习" }
        val validated = SystemClock.elapsedRealtime()
        timing?.mark("source_validated")
        val id = owner.insert("sessions", mapOf("module" to module, "date" to date, "kind" to kind,
            "status" to 2, "requires_answer" to if (module == "listening") 0 else 1,
            "settlement_status" to if (module == "listening") 2 else 0, "plan_id" to (p["planId"] as? Number)?.toLong()))
        owner.putSetting("session.$id.snapshot", encode(words))
        snapshotCache[id] = WordSnapshot(words)
        timing?.mark("snapshot_saved")
        var firstGroup = 0L
        var questionCount = 0
        owner.batchInserter("session_main_questions", listOf("session_id", "question_no", "phase")).use { mainWriter ->
            owner.batchInserter("session_sub_questions", listOf("main_question_id", "question_no", "question_type", "content_type", "answer_type", "content", "answers", "distractors")).use { questionWriter ->
                owner.batchInserter("session_question_details", listOf("sub_question_id", "word_id", "meaning_id")).use { detailWriter ->
                    owner.writableDatabase.compileStatement("UPDATE session_main_questions SET current_sub_question_id=?,updated_at=? WHERE id=?").use { pointer ->
                        for ((groupIndex, rawGroup) in paper.withIndex()) {
                            val groupId = mainWriter.add(listOf(id, groupIndex + 1, if (groupIndex == 0) 1 else 0))
                            if (firstGroup == 0L) firstGroup = groupId
                            val children = (rawGroup["questions"] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: error("大题缺少小题")
                            require(children.isNotEmpty()) { "大题不能为空" }
                            var firstQuestion = 0L
                            for ((questionIndex, raw) in children.withIndex()) {
                                val correct = strings(raw["answers"])
                                val type = raw.int("question_type")
                                require(type != 100 || correct.size == 1) { "单选题必须有一个答案" }
                                require(type != 200 || correct.size == 2) { "多选题必须有两个答案" }
                                val qid = questionWriter.add(listOf(groupId, questionIndex + 1, type,
                                    raw.int("content_type"), raw.int("answer_type"), strings(raw["content"]),
                                    if (type == 0) null else correct, raw["distractors"]?.let(::strings)))
                                questionCount++
                                if (firstQuestion == 0L) firstQuestion = qid
                                val ds = (raw["details"] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: error("题目缺少考察对象")
                                require(ds.isNotEmpty()) { "题目没有考察对象" }
                                for (detail in ds) detailWriter.add(listOf(qid, detail.long("word_id"), (detail["meaning_id"] as? Number)?.toLong()))
                            }
                            pointer.bindLong(1, firstQuestion)
                            pointer.bindLong(2, System.currentTimeMillis())
                            pointer.bindLong(3, groupId)
                            pointer.executeUpdateDelete()
                        }
                    }
                }
            }
        }
        owner.update("sessions", id, mapOf("current_main_question_id" to firstGroup))
        val inserted = SystemClock.elapsedRealtime()
        timing?.mark("questions_saved")
        val result = readSession(id, words)
        timing?.mark("session_read_back")
        AppLog.i("study_performance", "开局 module=$module words=${words.size} questions=$questionCount 校验=${validated-started}ms 保存=${inserted-validated}ms 读取=${SystemClock.elapsedRealtime()-inserted}ms")
        timing?.mark("existing_log_written")
        return result
    }

    /** 新建时复用已校验的词库；恢复时再读取持久化副本。数据库查询次数不随题数增长。 */
    private fun readSession(id: Long, freshWords: List<Map<*, *>>? = null): Map<String, Any?> {
        val s = session(id)
        val loaded = loadPaper(id)
        val paper = paperForPage(loaded)
        val position = position(s, loaded)
        fun firstDetail(q: Map<String, Any?>) = loaded.detailsByQuestion[q.long("id")]!!.first()
        val items: List<Any?> = when (s["module"]) {
            "listening_meaning" -> loaded.groups.map { firstDetail(loaded.questionsByGroup[it.long("id")]!!.first()).long("word_id") }
            "meaning_match" -> loaded.groups.map { g -> loaded.questionsByGroup[g.long("id")].orEmpty().map { q ->
                firstDetail(q).let { listOf(it.long("word_id"), it.long("meaning_id")) }
            } }
            "meaning_word_choice" -> loaded.questions.map { it.long("id") }
            else -> loaded.questions.map { firstDetail(it).long("word_id") }
        }
        val records = if (freshWords != null) emptyList() else currentAnswers(id).map { a ->
            val q = loaded.questionById[a.long("sub_question_id")]!!
            recordMap(a, q, loaded.detailsByQuestion[q.long("id")].orEmpty())
        }
        return s + mapOf("groups" to paper, "words" to (freshWords ?: snapshot(id)), "records" to records,
            "playback" to if (freshWords != null) null else owner.setting("session.$id.playback"), "items" to items,
            "cursor" to position.first, "total" to position.second, "elapsed" to s.int("elapsed_seconds"), "word_set_id" to s["plan_id"])
    }

    /**
     * 所有模块共用的试卷返回格式，与 Dart 的 SessionMainQuestion /
     * SessionSubQuestion / SessionQuestionDetail 对齐。
     *
     * 数据库仍保存完整行；界面只接收自己使用的字段。每道题的创建时间、删除标记
     * 和每条明细的内部编号不参与页面恢复，不必随几千道题来回传输、重复解析。
     * 新建、继续及重试都经过 readSession，因此只维护这一处字段清单。
     */
    private fun paperForPage(loaded: PaperRows): List<Map<String, Any?>> = loaded.groups.map { g ->
        selectPageFields(g, pageGroupFields).apply {
            put("questions", loaded.questionsByGroup[g.long("id")].orEmpty().map { q ->
                selectPageFields(q, pageQuestionFields).apply {
                    put("content", strings(q["content"]))
                    put("answers", strings(q["answers"]))
                    put("distractors", q["distractors"]?.let(::strings))
                    put("details", loaded.detailsByQuestion[q.long("id")].orEmpty().map { d ->
                        selectPageFields(d, pageDetailFields)
                    })
                }
            })
        }
    }

    /** 每行只建立一个返回对象，避免几千道题再生成临时键值对和中间副本。 */
    private fun selectPageFields(row: Map<String, Any?>, fields: List<String>): MutableMap<String, Any?> =
        LinkedHashMap<String, Any?>(fields.size).apply {
            for (field in fields) put(field, row[field])
        }

    private fun position(s: Map<String, Any?>, loaded: PaperRows): Pair<Int, Int> {
        if (s["module"] == "listening_meaning") {
            return (if (s.int("status") == 1) loaded.groups.size else loaded.groups.count { it.int("phase") == 3 }) to loaded.groups.size
        }
        var done = 0
        for (g in loaded.groups) {
            val qs = loaded.questionsByGroup[g.long("id")].orEmpty()
            done += when {
                s.int("status") == 1 || g.int("phase") in listOf(2, 3) -> qs.size
                g.int("phase") == 1 -> qs.indexOfFirst { it.long("id") == g.long("current_sub_question_id") }.coerceAtLeast(0)
                else -> 0
            }
        }
        return done to loaded.questions.size
    }

    /** 首页和进度保存只需要游标与题量，不加载题目正文、含义和答题记录。 */
    private fun progressGroups(id: Long) = rows(
        "SELECT g.*,COUNT(q.id) AS question_count," +
            "COALESCE(MAX(CASE WHEN q.id=g.current_sub_question_id THEN q.question_no END),1) AS current_no " +
            "FROM session_main_questions g LEFT JOIN session_sub_questions q ON q.main_question_id=g.id AND q.deleted_at IS NULL " +
            "WHERE g.session_id=? AND g.deleted_at IS NULL GROUP BY g.id ORDER BY g.question_no", id,
    )

    private fun position(s: Map<String, Any?>): Pair<Int, Int> {
        val gs = progressGroups(s.long("id"))
        if (s["module"] == "listening_meaning") {
            return (if (s.int("status") == 1) gs.size else gs.count { it.int("phase") == 3 }) to gs.size
        }
        val done = gs.sumOf { g -> when {
            s.int("status") == 1 || g.int("phase") in listOf(2, 3) -> g.int("question_count")
            g.int("phase") == 1 -> (g.int("current_no") - 1).coerceAtLeast(0)
            else -> 0
        } }
        return done to gs.sumOf { it.int("question_count") }
    }

    private fun moduleStates(date: String): List<Map<String, Any?>> =
        listOf("listening_meaning", "meaning_match", "spelling_reinforcement", "meaning_word_choice").mapNotNull { module ->
            val s = latestSession(module, date, false) ?: return@mapNotNull null
            val position = position(s)
            s + mapOf("cursor" to position.first, "total" to position.second,
                "daily_completed" to (one("SELECT id FROM sessions WHERE module=? AND date=? AND kind=1 AND status=1 AND deleted_at IS NULL LIMIT 1", module, date) != null))
        }

    /** 只改本次变化的用时和游标，不逐题重写整份试卷。 */
    private fun saveProgress(p: Map<*, *>): Any? = owner.transaction {
        val id = p.long("id")
        val s = session(id)
        if (s.int("status") != 2) return@transaction null
        var addedSeconds = 0
        for ((key, value) in (p["questionTimes"] as? Map<*, *>) ?: emptyMap<Any?, Any?>()) {
            val qid = key.toString().toLongOrNull() ?: error("用时题号无效")
            val q = question(qid)
            require(group(q.long("main_question_id")).long("session_id") == id) { "用时题号不属于本局" }
            val next = max(q.int("used_seconds"), (value as? Number)?.toInt() ?: 0)
            if (next > q.int("used_seconds")) {
                addedSeconds += next - q.int("used_seconds")
                owner.update("session_sub_questions", qid, mapOf("used_seconds" to next))
            }
        }
        if (p["playback"] is Map<*, *>) owner.putSetting("session.$id.playback", encode(p["playback"]))
        val cursor = p.int("cursor").coerceAtLeast(0)
        var current: Map<String, Any?>? = null
        var currentSubId: Long? = null
        var passedBefore = 1
        var ended = false
        if (s["module"] == "listening_meaning") {
            // 每个单词是一道大题，编号直接对应单词进度，无需遍历其余上千道大题。
            current = one("SELECT * FROM session_main_questions WHERE session_id=? AND deleted_at IS NULL AND question_no<=? ORDER BY question_no DESC LIMIT 1", id, cursor + 1)
            if (current != null) {
                ended = current.int("question_no") <= cursor
                passedBefore = cursor + 1
                currentSubId = current["current_sub_question_id"] as? Long
            }
        } else {
            val gs = progressGroups(id)
            var offset = 0
            for (g in gs) {
                val count = g.int("question_count")
                if (cursor < offset + count) {
                    current = g
                    passedBefore = g.int("question_no")
                    currentSubId = one("SELECT id FROM session_sub_questions WHERE main_question_id=? AND deleted_at IS NULL AND question_no=?", g.long("id"), cursor - offset + 1)?.long("id")
                    break
                }
                offset += count
            }
            if (current == null && gs.isNotEmpty()) {
                current = gs.last()
                currentSubId = current["current_sub_question_id"] as? Long
                passedBefore = current.int("question_no") + 1
                ended = true
            }
        }
        // WHERE phase<>3 保证已经结束的大题不会每次键盘输入都重新写一遍。
        val now = System.currentTimeMillis()
        owner.writableDatabase.execSQL(
            "UPDATE session_main_questions SET phase=3,updated_at=? WHERE session_id=? AND deleted_at IS NULL AND question_no<? AND phase<>3",
            arrayOf<Any>(now, id, passedBefore),
        )
        if (current != null && !ended) {
            val changes = mutableMapOf<String, Any?>()
            val phase = if (current.int("phase") == 2) 2 else 1
            if (phase != current.int("phase")) changes["phase"] = phase
            if (currentSubId != null && currentSubId != current["current_sub_question_id"]) changes["current_sub_question_id"] = currentSubId
            if (changes.isNotEmpty()) owner.update("session_main_questions", current.long("id"), changes)
        }
        val changes = mutableMapOf<String, Any?>()
        if (p.int("elapsed") > s.int("elapsed_seconds")) changes["elapsed_seconds"] = p.int("elapsed")
        if (addedSeconds > 0) changes["answer_seconds"] = s.int("answer_seconds") + addedSeconds
        if (current != null && current.long("id") != s.long("current_main_question_id")) changes["current_main_question_id"] = current.long("id")
        if (changes.isNotEmpty()) owner.update("sessions", id, changes)
        null
    }

    private fun complete(q: Map<String, Any?>, attempt: Int): Boolean = complete(q, answers(q.long("id"), attempt))

    private fun complete(q: Map<String, Any?>, answerRows: List<Map<String, Any?>>): Boolean {
        if (q.int("question_type") == 0) return true
        val correct = answerRows.filter { it.int("is_correct") == 1 }
        if (q.int("question_type") == 400) return correct.isNotEmpty()
        val picked = correct.flatMap { strings(it["answer"]) }.map { normalized(it, q.int("answer_type")) }.toSet()
        return strings(q["answers"]).all { normalized(it, q.int("answer_type")) in picked } && correct.isNotEmpty()
    }

    private fun roundAnswers(groupId: Long, attempt: Int) = rows(
        "SELECT a.* FROM session_question_answers a JOIN session_sub_questions q ON q.id=a.sub_question_id " +
            "WHERE q.main_question_id=? AND a.attempt_no=? AND a.deleted_at IS NULL AND q.deleted_at IS NULL ORDER BY a.id", groupId, attempt,
    )

    private fun normalized(text: String, type: Int) = if (type == 1) text.trim().lowercase(Locale.ROOT) else text.trim()

    private fun submit(p: Map<*, *>): Map<String, Any?> = owner.transaction {
        val sid = p.long("sessionId")
        val s = session(sid)
        require(s.int("status") == 2 && s.int("requires_answer") == 1) { "这局已经结束" }
        val q = question(p.long("questionId"))
        val g = group(q.long("main_question_id"))
        require(g.long("session_id") == sid) { "题目不属于当前会话" }
        val attempt = g.int("retry_count") + 1
        val submitted = strings(p["answers"])
        require(submitted.size == 1) { "每次操作应提交一个实际答案" }
        val old = answers(q.long("id"), attempt)
        // 正确按钮被重复点按或完成回包重试时，复用已有记录。
        old.lastOrNull { it.int("is_correct") == 1 && strings(it["answer"]) == submitted }?.let { return@transaction recordMap(it) }
        require(!complete(q, old)) { "本题已经完成" }
        val chosen = submitted.single()
        val correct = if (q.int("question_type") == 400) {
            val round = questions(g.long("id"))
            val right = round.firstOrNull { strings(it["answers"]).contains(chosen) } ?: error("不属于当前棋盘的含义")
            val consumed = roundAnswers(g.long("id"), attempt).any { it.int("is_correct") == 1 && chosen in strings(it["answer"]) }
            require(!consumed) { "这张含义卡已经连过" }
            normalized(strings(right["content"]).first(), 1) == normalized(strings(q["content"]).first(), 1)
        } else {
            val possible = strings(q["answers"]) + strings(q["distractors"])
            if (q.int("question_type") != 300) require(possible.any { normalized(it, q.int("answer_type")) == normalized(chosen, q.int("answer_type")) }) { "不属于当前题目的候选" }
            strings(q["answers"]).any { normalized(it, q.int("answer_type")) == normalized(chosen, q.int("answer_type")) }
        }
        val answerId = owner.insert("session_question_answers", mapOf("sub_question_id" to q.long("id"), "attempt_no" to attempt, "answer" to submitted, "is_correct" to if (correct) 1 else 0))
        val nextSeconds = max(q.int("used_seconds"), p.int("usedSeconds"))
        if (nextSeconds > q.int("used_seconds")) owner.update("session_sub_questions", q.long("id"), mapOf("used_seconds" to nextSeconds))
        val round = questions(g.long("id"))
        val answered = roundAnswers(g.long("id"), attempt).groupBy { it.long("sub_question_id") }
        val completion = round.associate { it.long("id") to complete(it, answered[it.long("id")].orEmpty()) }
        val done = completion.values.count { it }
        val next = if (s["module"] == "meaning_match") round.getOrNull(done) else round.firstOrNull { completion[it.long("id")] != true }
        owner.update("session_main_questions", g.long("id"), mapOf("phase" to if (done == round.size) 2 else 1,
            "current_sub_question_id" to (next ?: round.last()).long("id")))
        owner.update("sessions", sid, mapOf("current_main_question_id" to g.long("id"),
            "elapsed_seconds" to max(s.int("elapsed_seconds"), p.int("elapsed")),
            "answer_seconds" to s.int("answer_seconds") + nextSeconds - q.int("used_seconds")))
        recordMap(one("SELECT * FROM session_question_answers WHERE id=?", answerId)!!, q, details(q.long("id")))
    }

    private fun recordMap(
        a: Map<String, Any?>,
        q: Map<String, Any?> = question(a.long("sub_question_id")),
        ds: List<Map<String, Any?>> = details(q.long("id")),
    ): Map<String, Any?> {
        return a + mapOf("question_id" to q.long("id"), "group_id" to q.long("main_question_id"),
            "word_id" to ds.first().long("word_id"), "meaning_id" to ds.first()["meaning_id"],
            "target_word_ids" to ds.map { it.long("word_id") }.distinct(),
            "target_meaning_ids" to ds.mapNotNull { (it["meaning_id"] as? Number)?.toLong() }.distinct(),
            "input" to strings(a["answer"]).firstOrNull().orEmpty(), "answers" to strings(a["answer"]), "result" to a.int("is_correct"))
    }

    private fun records(id: Long): List<Map<String, Any?>> {
        val loaded = loadPaper(id)
        return currentAnswers(id).map { a ->
            val q = loaded.questionById[a.long("sub_question_id")]!!
            recordMap(a, q, loaded.detailsByQuestion[q.long("id")].orEmpty())
        }
    }

    private fun retry(sid: Long, gid: Long): Map<String, Any?> = owner.transaction {
        val s = session(sid)
        val g = group(gid)
        require(s["module"] == "listening_meaning" && s.int("status") == 2 && g.long("session_id") == sid && g.int("phase") == 2) { "当前不能重试这个单词" }
        val qs = questions(gid)
        owner.update("session_main_questions", gid, mapOf("retry_count" to g.int("retry_count") + 1, "phase" to 1, "current_sub_question_id" to qs.first().long("id")))
        // 旧遍次保留用于导出，恢复与结算只读取新遍次；旧草稿同步作废。
        for (wordId in qs.flatMap { details(it.long("id")) }.map { it.long("word_id") }.distinct())
            one("SELECT id FROM session_word_settlements WHERE session_id=? AND word_id=? AND apply_status=0 AND deleted_at IS NULL", sid, wordId)?.let {
                owner.update("session_word_settlements", it.long("id"), mapOf("deleted_at" to System.currentTimeMillis()))
            }
        readSession(sid)
    }

    /** 候选只保存内容；英文按字母、中文按字符编码排序由共用 Dart 组件完成。 */
    private fun saveDistractors(p: Map<*, *>): Any? = owner.transaction {
        val sid = p.long("sessionId")
        val s = session(sid)
        require(s.int("status") == 2) { "会话已经结束" }
        val q = question(p.long("questionId"))
        require(group(q.long("main_question_id")).long("session_id") == sid) { "题目不属于当前会话" }
        val distractors = strings(p["distractors"])
        val correct = strings(q["answers"])
        val keys = (correct + distractors).map { normalized(it, q.int("answer_type")) }
        require(keys.size == 4 && keys.toSet().size == 4) { "选择题必须有四个不同候选" }
        owner.update("session_sub_questions", q.long("id"), mapOf("distractors" to distractors))
        val base = baseSnapshot(sid)
        val targets = details(q.long("id")).map { it.long("word_id") }.toSet()
        for (raw in (p["sources"] as? List<*>) ?: emptyList<Any?>()) {
            val source = raw as? Map<*, *> ?: error("混淆来源格式无效")
            val wordId = source.long("word_id")
            require(wordId in targets) { "混淆来源不属于当前题目" }
            val word = base.byWord[wordId] ?: error("混淆来源不属于会话")
            val meaningId = (source["meaning_id"] as? Number)?.toLong()
            val confusions = strings(source["confusions"])
            if (meaningId == null) {
                owner.putSetting("session.$sid.confusions.word.$wordId", encode(confusions))
                val current = one("SELECT spelling FROM words WHERE id=? AND deleted_at IS NULL", wordId)
                if (current?.get("spelling") == word["spelling"]) owner.saveWordConfusions(wordId, confusions)
            } else {
                val meaning = base.meanings[meaningId] ?: error("混淆含义不属于会话")
                require(meaning.first == wordId) { "混淆含义不属于这个单词" }
                owner.putSetting("session.$sid.confusions.meaning.$meaningId", encode(confusions))
                val current = one("SELECT definition FROM word_meanings WHERE id=? AND word_id=? AND deleted_at IS NULL", meaningId, wordId)
                if (current?.get("definition") == meaning.second["definition"]) owner.saveMeaningConfusions(meaningId, confusions)
            }
        }
        null
    }

    private fun wordQuestions(sid: Long, wordId: Long) = rows("SELECT DISTINCT q.*,g.retry_count FROM session_question_details d JOIN session_sub_questions q ON q.id=d.sub_question_id JOIN session_main_questions g ON g.id=q.main_question_id WHERE d.word_id=? AND g.session_id=? AND d.deleted_at IS NULL AND g.deleted_at IS NULL AND q.deleted_at IS NULL ORDER BY g.question_no,q.question_no", wordId, sid)
    private fun history(wordId: Long) = rows("SELECT * FROM session_word_settlements WHERE word_id=? AND apply_status=1 AND deleted_at IS NULL ORDER BY updated_at DESC,id DESC", wordId)
    private fun difficulty(wordId: Long) = one("SELECT difficulty FROM words WHERE id=?", wordId)?.long("difficulty") ?: 0L

    /**
     * 生成或更新某个单词的结算草稿（只写草稿，暂不改动难度）。
     *
     * [partial] 为 true 时用于跨天收尾：只看已经答过的小题，一条没答的词不结算。
     * 正常流程（用户答完整局点「完成」）保持严格口径，必须整词答完才允许结算。
     */
    private fun prepare(sid: Long, wordId: Long, partial: Boolean = false): Map<String, Any?> {
        val s = session(sid)
        require(s.int("settlement_status") == 0 && s.int("requires_answer") == 1 && s.int("status") in listOf(1, 2)) { "会话无需重新结算" }
        val qs = wordQuestions(sid, wordId)
        val answered = rows("SELECT DISTINCT a.* FROM session_question_details d JOIN session_sub_questions q ON q.id=d.sub_question_id " +
            "JOIN session_main_questions g ON g.id=q.main_question_id JOIN session_question_answers a ON a.sub_question_id=q.id " +
            "WHERE d.word_id=? AND g.session_id=? AND a.attempt_no=g.retry_count+1 " +
            "AND d.deleted_at IS NULL AND a.deleted_at IS NULL AND q.deleted_at IS NULL AND g.deleted_at IS NULL ORDER BY a.id", wordId, sid)
            .groupBy { it.long("sub_question_id") }
        if (partial) {
            // 跨天收尾：这个词至少答过一道小题才有资格结算，否则跳过、难度不动。
            require(qs.isNotEmpty() && answered.isNotEmpty()) { "这个词还没有任何作答" }
        } else {
            require(qs.isNotEmpty() && qs.all { complete(it, answered[it.long("id")].orEmpty()) }) { "这个词尚未完成全部题目" }
        }
        // 判对口径：整局答完时看这个词的全部小题；跨天收尾只看已经答过的那部分——
        // 例如一个词有 10 条释义只答到第 5 条，就按这 5 条判对错（全对才算对）。
        val correct = if (partial) {
            answered.values.all { answersOfQuestion -> answersOfQuestion.all { it.int("is_correct") == 1 } }
        } else {
            qs.all { q -> answered[q.long("id")].orEmpty().all { it.int("is_correct") == 1 } }
        }
        val previous = history(wordId)
        val streak = if (correct) previous.takeWhile { it.int("is_correct") == 1 }.size + 1 else 0
        val suggestion = if (!correct) 1 else if (streak >= owner.settingInt("streakToEasier", 5).coerceAtLeast(1)) -1 else 0
        val before = difficulty(wordId)
        val old = one("SELECT * FROM session_word_settlements WHERE session_id=? AND word_id=? AND deleted_at IS NULL", sid, wordId)
        require(old == null || old.int("apply_status") == 0) { "单词已经结算" }
        val manual = old?.int("operation") == 2
        val adjustment = if (manual) old.int("adjustment") else suggestion
        val fields = mapOf("apply_status" to 0, "session_id" to sid, "word_id" to wordId, "date" to s["date"],
            "is_correct" to if (correct) 1 else 0, "difficulty_before" to before,
            "difficulty_after" to (before + adjustment).coerceAtLeast(0), "suggested_adjustment" to suggestion,
            "adjustment" to adjustment, "operation" to if (manual) 2 else 1)
        if (old == null) owner.insert("session_word_settlements", fields) else owner.update("session_word_settlements", old.long("id"), fields)
        return mapOf("is_correct" to correct, "streak" to streak, "difficulty_before" to before,
            "difficulty_after" to (before + adjustment).coerceAtLeast(0), "suggested_adjustment" to suggestion,
            "reviewed_at" to null, "adjustment" to adjustment, "operation" to if (manual) 2 else 1,
            "used_time" to qs.sumOf { it.int("used_seconds") }, "recent_results" to (previous.take(4).asReversed().map { it.int("is_correct") } + if (correct) 1 else 0))
    }

    private fun settlementRows(sid: Long): List<Map<String, Any?>> = rows("SELECT * FROM session_word_settlements WHERE session_id=? AND deleted_at IS NULL ORDER BY id", sid).map { row ->
        val previous = history(row.long("word_id")).filter { it.long("id") != row.long("id") }
        row + mapOf("used_time" to wordQuestions(sid, row.long("word_id")).sumOf { it.int("used_seconds") },
            "streak" to if (row.int("is_correct") == 1) previous.takeWhile { it.int("is_correct") == 1 }.size + 1 else 0,
            "recent_results" to (previous.take(4).asReversed().map { it.int("is_correct") } + row.int("is_correct")))
    }

    private fun adjust(p: Map<*, *>): Any? = owner.transaction {
        val sid = p.long("sessionId")
        val wordId = p.long("wordId")
        val adjustment = p.int("adjustment")
        require(adjustment in -1..1 && session(sid).int("settlement_status") == 0) { "无法调整结算" }
        val row = one("SELECT * FROM session_word_settlements WHERE session_id=? AND word_id=? AND apply_status=0 AND deleted_at IS NULL", sid, wordId) ?: error("结算草稿不存在")
        owner.update("session_word_settlements", row.long("id"), mapOf("adjustment" to adjustment,
            "difficulty_after" to (row.long("difficulty_before") + adjustment).coerceAtLeast(0), "operation" to 2))
        null
    }

    private fun finish(p: Map<*, *>): Any? = owner.transaction {
        val sid = p.long("id")
        val s = session(sid)
        if (s.int("status") == 1) return@transaction null
        require(s.int("status") == 2) { "这局已经中断，不能标记为完成" }
        val status = p.int("status")
        if (status == 3 || status == 0) {
            abort(sid, status)
            return@transaction null
        }
        require(status == 1) { "无效的完成状态" }
        if (s.int("requires_answer") == 1) {
            val paper = loadPaper(sid)
            val answered = currentAnswers(sid).groupBy { it.long("sub_question_id") }
            require(paper.questions.all { complete(it, answered[it.long("id")].orEmpty()) }) { "还有题目没有完成，不能结算" }
            for (wordId in paper.details.map { it.long("word_id") }.distinct()) prepare(sid, wordId)
        }
        for (g in groups(sid)) owner.update("session_main_questions", g.long("id"), mapOf("phase" to 3))
        owner.update("sessions", sid, mapOf("status" to 1,
            "elapsed_seconds" to max(s.int("elapsed_seconds"), p.int("elapsed")),
            "answer_seconds" to allQuestions(sid).sumOf { it.int("used_seconds") }))
        null
    }

    private fun finalize(sid: Long): Int = owner.transaction {
        val s = session(sid)
        // 已落实允许幂等重试；未完成或已中断必须报错，不能把“没执行”当作成功。
        if (s.int("settlement_status") == 1 && s.int("status") == 1) return@transaction 0
        require(s.int("status") == 1 && s.int("settlement_status") == 0) { "本局尚未完成或已经中断，不能提交结算" }
        val drafts = rows("SELECT * FROM session_word_settlements WHERE session_id=? AND apply_status=0 AND deleted_at IS NULL ORDER BY id", sid)
        require(drafts.isNotEmpty()) { "已完成会话缺少结算草稿" }
        for (row in drafts) {
            val before = difficulty(row.long("word_id"))
            val after = (before + row.int("adjustment")).coerceAtLeast(0)
            // 删除词仍保留历史成绩，但不会被结算重新恢复到词库中。
            if (one("SELECT id FROM words WHERE id=? AND deleted_at IS NULL", row.long("word_id")) != null) {
                val values = mutableMapOf<String, Any?>("difficulty" to after)
                if (s.int("kind") == 1) values["reviewed_at"] = System.currentTimeMillis()
                owner.update("words", row.long("word_id"), values)
            }
            owner.update("session_word_settlements", row.long("id"), mapOf("apply_status" to 1,
                "difficulty_before" to before, "difficulty_after" to after, "adjustment" to after - before))
        }
        owner.update("sessions", sid, mapOf("settlement_status" to 1))
        drafts.size
    }

    private fun abort(sid: Long, status: Int = 3) {
        owner.update("sessions", sid, mapOf("status" to status, "settlement_status" to 2))
        val now = System.currentTimeMillis()
        owner.writableDatabase.execSQL("UPDATE session_word_settlements SET deleted_at=?,updated_at=? WHERE session_id=? AND apply_status=0 AND deleted_at IS NULL", arrayOf(now, now, sid))
    }
    private fun abortWhere(where: String, args: List<Any?>): Int = owner.transaction {
        val selected = owner.rows("SELECT id FROM sessions WHERE status=2 AND deleted_at IS NULL AND ($where)", args)
        for (s in selected) abort(s.long("id"))
        selected.size
    }

    /**
     * 跨天收尾：把昨天及更早还挂在「进行中」的会话收掉，返回收尾的局数。
     *
     * 生活化解释：昨天做到一半退出去了，今天再打开 App，那一局已经没有意义
     * ——今天有今天的词库。收尾分两种走法：
     * - 已经作答过的：按「已答小题」当场结算并落实难度，不弹结算页，用户不必回来确认；
     * - 一条答案都没答过的：没有任何结算依据，直接中断，难度保持不动。
     * 以前这里一律中断，用户如果还停在昨天的答题页上，接着答就会一路保存失败。
     */
    private fun closeStale(date: String): Int {
        // 日期格式必须先挡住：写错日期会让下面的条件匹配到全部会话。
        require(owner.validDate(date)) { "收尾日期无效" }
        val stale = owner.rows("SELECT id FROM sessions WHERE status=2 AND deleted_at IS NULL AND date<>?", listOf(date))
        var closed = 0
        for (row in stale) {
            val sid = row.long("id")
            try {
                // 一局一个事务：某一局收尾失败时整体回滚，其它局照常收掉，
                // 也不会把「收了一半」的会话留在库里。
                owner.transaction { closeStaleSession(sid) }
                closed++
            } catch (error: Throwable) {
                // 收尾属于启动维护动作，失败只写日志；这一局保持原样，下次启动再收。
                AppLog.e("study_settlement", "跨天收尾失败 session=$sid：${error.message ?: error.javaClass.simpleName}")
            }
        }
        return closed
    }

    /** 收尾一局跨天会话：有作答的按已答情况结算，一条答案都没有的直接中断。 */
    private fun closeStaleSession(sid: Long) {
        val s = session(sid)
        // 随身听这类不需要作答的会话没有结算可言，保持原来的中断做法。
        if (s.int("requires_answer") != 1) {
            abort(sid)
            return
        }
        val wordIds = answeredWordIds(sid)
        // 一条答案都没有：没有可结算的依据，难度不能凭空空降一个变化。
        if (wordIds.isEmpty()) {
            abort(sid)
            return
        }
        // 只给「答过的小题」写草稿；没答完的词也算数，不必等它答全。
        for (wordId in wordIds) prepare(sid, wordId, partial = true)
        // 与正常完成走同一套收尾：收掉全部大题、补齐实际答题用时，再落实难度。
        for (g in groups(sid)) owner.update("session_main_questions", g.long("id"), mapOf("phase" to 3))
        owner.update("sessions", sid, mapOf("status" to 1,
            "answer_seconds" to allQuestions(sid).sumOf { it.int("used_seconds") }))
        finalize(sid)
    }

    /** 本局当前遍次里已经留下作答记录的单词编号，按编号升序。 */
    private fun answeredWordIds(sid: Long) = rows(
        "SELECT DISTINCT d.word_id FROM session_question_details d " +
            "JOIN session_sub_questions q ON q.id=d.sub_question_id " +
            "JOIN session_main_questions g ON g.id=q.main_question_id " +
            "JOIN session_question_answers a ON a.sub_question_id=q.id " +
            "WHERE g.session_id=? AND a.attempt_no=g.retry_count+1 AND d.deleted_at IS NULL " +
            "AND q.deleted_at IS NULL AND g.deleted_at IS NULL AND a.deleted_at IS NULL ORDER BY d.word_id", sid,
    ).map { it.long("word_id") }.distinct()

    private fun reviewedIds(date: String) = rows("SELECT DISTINCT word_id FROM session_word_settlements WHERE apply_status=1 AND deleted_at IS NULL AND date=? ORDER BY word_id", date).map { it.long("word_id") }
    private fun dailyCounts(since: String?) = rows("SELECT date,COUNT(DISTINCT word_id) AS count FROM session_word_settlements WHERE apply_status=1 AND deleted_at IS NULL AND date>=? GROUP BY date ORDER BY date", since ?: "0000-01-01")

    // 曲线（复习时间）用：会话表每天的累计复习时长（秒），取自 elapsed_seconds 按日期汇总。
    private fun dailyDurations(since: String?) = rows("SELECT date,SUM(elapsed_seconds) AS count FROM sessions WHERE deleted_at IS NULL AND date>=? GROUP BY date ORDER BY date", since ?: "0000-01-01")

    /** 导入时额外核对“编号存在但属于别局/别词”的关联错误。 */
    fun validateImportedData() {
        // 设置也必须能被页面重新读取；否则事务成功后才在 Flutter 解析时失败，
        // 错误备份已经替换掉原数据，下一次启动还会反复遇到同一个错误。
        one("SELECT value FROM settings WHERE key=? AND deleted_at IS NULL", WordsDatabase.LISTENING_PLAYBACK_KEY)?.let { row ->
            val playback = decode(row["value"].toString()) as? Map<*, *> ?: error("随身听播放状态必须是对象")
            val ids = playback["word_ids"] as? List<*> ?: error("随身听缺少单词编号列表")
            require(ids.all { (it is Int || it is Long) && (it as Number).toLong() > 0 }) { "随身听单词编号必须是正整数" }
            require(ids.map { (it as Number).toLong() }.distinct().size == ids.size) { "随身听单词编号不能重复" }
        }
        require(rows("SELECT d.id FROM session_question_details d JOIN word_meanings m ON m.id=d.meaning_id WHERE m.word_id<>d.word_id LIMIT 1").isEmpty()) { "题目含义不属于指定单词" }
        require(rows("SELECT s.id FROM sessions s JOIN session_main_questions g ON g.id=s.current_main_question_id WHERE g.session_id<>s.id LIMIT 1").isEmpty()) { "会话当前大题不属于本局" }
        require(rows("SELECT g.id FROM session_main_questions g JOIN session_sub_questions q ON q.id=g.current_sub_question_id WHERE q.main_question_id<>g.id LIMIT 1").isEmpty()) { "大题当前小题不属于本题" }
        require(rows("SELECT x.id FROM session_word_settlements x JOIN sessions s ON s.id=x.session_id WHERE x.date<>s.date LIMIT 1").isEmpty()) { "结算归属日期与会话不一致" }
        require(rows("SELECT x.id FROM session_word_settlements x WHERE x.deleted_at IS NULL AND NOT EXISTS (" +
            "SELECT 1 FROM session_question_details d JOIN session_sub_questions q ON q.id=d.sub_question_id " +
            "JOIN session_main_questions g ON g.id=q.main_question_id WHERE g.session_id=x.session_id AND d.word_id=x.word_id) LIMIT 1").isEmpty()) { "结算单词不属于本局试卷" }
        require(rows("SELECT a.id FROM session_question_answers a JOIN session_sub_questions q ON q.id=a.sub_question_id JOIN session_main_questions g ON g.id=q.main_question_id WHERE a.attempt_no>g.retry_count+1 LIMIT 1").isEmpty()) { "答题遍次超过大题重试次数" }
        require(rows("SELECT x.id FROM session_word_settlements x JOIN sessions s ON s.id=x.session_id WHERE x.apply_status=1 AND (s.status<>1 OR s.settlement_status<>1) AND x.deleted_at IS NULL LIMIT 1").isEmpty()) { "已落实结算必须属于已完成且已结算的会话" }
        for (s in rows("SELECT * FROM sessions WHERE deleted_at IS NULL")) {
            require(s["module"] in setOf("listening", "listening_meaning", "meaning_match", "spelling_reinforcement", "meaning_word_choice")) { "备份含未知学习模块" }
            val paper = groups(s.long("id"))
            require(paper.isNotEmpty() && paper.map { it.int("question_no") } == (1..paper.size).toList()) { "大题编号必须从一连续递增" }
            for (g in paper) {
                val children = questions(g.long("id"))
                require(children.isNotEmpty() && children.map { it.int("question_no") } == (1..children.size).toList()) { "小题编号必须从一连续递增" }
                for (q in children) {
                    require(strings(q["content"]).size == 1 && details(q.long("id")).isNotEmpty()) { "题目缺少内容或考察对象" }
                }
            }
            // 外键只能证明编号在资料库里存在，不能证明它也在开局时的内容副本里。
            // 先校验原数组，避免 filterIsInstance 或字典覆盖悄悄吞掉格式错误及重复编号。
            val rawSnapshot = owner.setting("session.${s.long("id")}.snapshot")
            require(rawSnapshot is List<*> && rawSnapshot.all { it is Map<*, *> }) { "会话词库快照必须是单词对象数组" }
            val words = snapshot(s.long("id"))
            require(words.isNotEmpty() && words.all { it.long("id") > 0 && it["spelling"] is String && it["spelling"].toString().isNotBlank() && it["meanings"] is List<*> }) { "会话词库快照格式错误" }
            val ids = mutableSetOf<Long>()
            val meaningOwners = mutableMapOf<Long, Long>()
            for (word in words) {
                val wordId = word.long("id")
                require(word["id"] is Int || word["id"] is Long) { "会话快照单词编号必须是整数" }
                require(ids.add(wordId)) { "会话快照的单词编号重复" }
                for (raw in word["meanings"] as List<*>) {
                    val meaning = raw as? Map<*, *> ?: error("会话快照含义格式错误")
                    val meaningId = meaning.long("id")
                    require(meaning["id"] is Int || meaning["id"] is Long) { "会话快照含义编号必须是整数" }
                    require(meaningId > 0 && meaning["definition"] is String && meaning["definition"].toString().isNotBlank()) { "会话快照含义缺少编号或正文" }
                    require(meaningOwners.put(meaningId, wordId) == null) { "会话快照的含义编号重复" }
                }
            }
            for (detail in loadPaper(s.long("id")).details) {
                val wordId = detail.long("word_id")
                require(wordId in ids) { "会话快照缺少考察单词" }
                val meaningId = (detail["meaning_id"] as? Number)?.toLong()
                require(meaningId == null || meaningOwners[meaningId] == wordId) { "会话快照缺少考察含义或含义属于其他单词" }
            }
        }
        for (q in rows("SELECT * FROM session_sub_questions WHERE question_type IN (100,200) AND deleted_at IS NULL")) {
            val correct = strings(q["answers"])
            require(correct.size == if (q.int("question_type") == 100) 1 else 2) { "选择题答案数量错误" }
            if (q["distractors"] != null) {
                val candidates = (correct + strings(q["distractors"])).map { normalized(it, q.int("answer_type")) }
                require(candidates.size == 4 && candidates.toSet().size == 4) { "选择题候选数量错误" }
            }
        }
    }
}
