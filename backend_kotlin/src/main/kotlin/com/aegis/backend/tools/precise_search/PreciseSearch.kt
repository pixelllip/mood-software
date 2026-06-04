package com.aegis.backend.tools.precise_search
import com.aegis.backend.core.ChatMessage
import com.aegis.backend.core.EnvConfig
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * 精准搜索 - 接收关键词 → AI 扩展联想词 → JSON 文件匹配 → 返回结果
 */
class PreciseSearch {
    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private val json = Json { ignoreUnknownKeys = true }

    /** 关键词扩展缓存，每个关键词只调用一次 AI */
    private val keywordCache = KeywordCache()

    companion object {
        /** 内置学科→知识点映射，作为 AI 扩展的兜底补充 */
        private val SUBJECT_TOPICS: Map<String, List<String>> = mapOf(
            "语文" to listOf("文言文", "古诗", "古诗词", "阅读理解", "作文", "写作", "文学常识", "现代文"),
            "数学" to listOf("代数", "几何", "函数", "方程", "三角函数", "概率", "统计"),
            "英语" to listOf("词汇", "单词", "语法", "阅读理解", "听力", "作文", "写作", "翻译"),
            "物理" to listOf("力学", "运动学", "电学", "光学", "热学", "能量", "加速度"),
            "化学" to listOf("元素", "方程式", "化学反应", "周期表", "酸碱", "氧化还原"),
            "历史" to listOf("古代史", "近代史", "世界史", "中国史", "历史事件", "朝代"),
            "地理" to listOf("气候", "地形", "地图", "人口", "区域地理", "自然地理"),
            "生物" to listOf("细胞", "遗传", "进化", "生态系统", "人体", "植物", "动物")
        )

        /** 反向查找：知识点→所属学科 */
        private val TOPIC_TO_SUBJECT: Map<String, String> by lazy {
            val map = mutableMapOf<String, String>()
            for ((subject, topics) in SUBJECT_TOPICS) {
                for (topic in topics) {
                    map[topic] = subject
                }
            }
            map
        }
    }

    /**
     * 主入口：搜索关键词并返回匹配结果（纯文本格式，供 AI Agent 内部使用）
     * @param keyword 用户输入的关键词
     * @return 格式化的搜索结果字符串
     */
    fun search(keyword: String): String {
        val result = searchInternal(keyword)
        val sb = StringBuilder()
        sb.appendLine("🔍 原始词: $keyword")
        sb.appendLine("📝 联想词: ${result.expandedWords.joinToString(", ")}")
        sb.appendLine()

        if (result.matches.isEmpty()) {
            sb.appendLine("未找到匹配记录")
        } else {
            result.matches.forEach { fileMatches ->
                sb.appendLine("📁 文件: ${fileMatches.filePath}")
                fileMatches.sentences.forEach { sentence ->
                    sb.appendLine("   [${sentence.role}] ${sentence.content}")
                }
                sb.appendLine()
            }
        }
        sb.appendLine("✅ 共找到 ${result.totalMatches} 条匹配记录")
        return sb.toString()
    }

    /**
     * 搜索并返回结构化 JSON 数据（供独立 API 使用）
     * @param keyword 用户输入的关键词
     * @return 搜索结果的 JSON 字符串
     */
    fun searchJson(keyword: String): String {
        val result = searchInternal(keyword)
        val output = JsonOutput(
            keyword = keyword,
            expanded_words = ExpandedWords(
                original = keyword,
                related = result.expandedWords.filter { it != keyword },
                all = result.expandedWords
            ),
            total_matches = result.totalMatches,
            files = result.matches.map { fileMatch ->
                JsonFileMatch(
                    file_path = fileMatch.filePath,
                    file_name = File(fileMatch.filePath).name,
                    match_count = fileMatch.sentences.size,
                    sentences = fileMatch.sentences
                )
            }
        )
        return json.encodeToString(output)
    }

    /**
     * 搜索核心逻辑，返回结构化数据
     */
    private fun searchInternal(keyword: String): SearchResult {
        val expandedWords = expandKeywords(keyword)
        val fileMatches = mutableListOf<FileMatch>()
        var totalMatches = 0

        val backlogDir = File(EnvConfig.basePath, "Backlog")
        if (!backlogDir.exists() || !backlogDir.isDirectory) {
            return SearchResult(expandedWords, emptyList(), 0)
        }

        backlogDir.walkTopDown()
            .filter { it.isFile && it.extension == "json" && !it.name.endsWith(".meta.json") }
            .forEach { jsonFile ->
                try {
                    val jsonContent = jsonFile.readText(Charsets.UTF_8)
                    val messages = json.decodeFromString<List<ChatMessage>>(jsonContent)

                    val matches = messages.filter { msg ->
                        expandedWords.any { word ->
                            msg.content.contains(word, ignoreCase = true)
                        }
                    }

                    if (matches.isNotEmpty()) {
                        fileMatches.add(FileMatch(
                            filePath = jsonFile.absolutePath,
                            sentences = matches
                        ))
                        totalMatches += matches.size
                    }
                } catch (_: Exception) { }
            }

        return SearchResult(expandedWords, fileMatches, totalMatches)
    }

    // ========== 内部数据结构 ==========
    @Serializable
    data class FileMatch(val filePath: String, val sentences: List<ChatMessage>)
    @Serializable
    data class SearchResult(
        val expandedWords: List<String>,
        val matches: List<FileMatch>,
        val totalMatches: Int
    )

    /** searchJson() 专用输出结构 */
    @Serializable
    data class JsonOutput(
        val keyword: String,
        val expanded_words: ExpandedWords,
        val total_matches: Int,
        val files: List<JsonFileMatch>
    )
    @Serializable
    data class ExpandedWords(val original: String, val related: List<String>, val all: List<String>)
    @Serializable
    data class JsonFileMatch(
        val file_path: String,
        val file_name: String,
        val match_count: Int,
        val sentences: List<ChatMessage>
    )

    /**
     * 调用 AI（OpenAI 兼容模式）扩展联想词
     * 使用设置中启用的 AI 配置（config.json 中的 AI_CONFIGS）
     * 每个关键词只调用一次 AI，结果缓存在文件中
     */
    fun expandKeywords(keyword: String): List<String> {
        // 1️⃣ 查缓存
        val cached = keywordCache.get(keyword)
        if (cached != null) {
            println("📦 关键词缓存命中: $keyword → $cached")
            return cached
        }

        // 跳过姓名、学号等非学习词的 AI 扩展
        if (keyword.length < 2 ||                                               // 过短（单个字符很可能是姓氏）
            keyword.all { it.isDigit() || it == '.' }                          // 纯数字/学号
        ) {
            val skipMsg = "⏭️ 跳过非学习词: $keyword"
            println(skipMsg)
            val fallback = supplementWithHardcoded(keyword)
            keywordCache.put(keyword, fallback)
            return (listOf(keyword) + fallback).distinct()
        }

        val apiKey = EnvConfig.activeApiKey
        val baseUrl = EnvConfig.activeBaseUrl
        val model = EnvConfig.activeModel

        if (apiKey.isBlank() || baseUrl.isBlank()) {
            println("⚠️ 未配置 API Key，仅使用硬编码映射")
            val fallback = supplementWithHardcoded(keyword)
            keywordCache.put(keyword, fallback)
            return fallback
        }

        val prompt = """
            你是一个关键词扩展助手，用于在学习分析系统中搜索对话记录。请将用户输入的学习关键词扩展为 5-8 个相关词。
            
            规则：
            1. 如果输入是**具体知识点/课文/题目**（如"小石潭记"），请包含其**所属学科/类别**（如"语文"）
            2. 如果输入是**学科/类别**（如"语文"），请包含**该学科下的典型知识点**（如"小石潭记,文言文,古诗"）
            3. 同时包含**同义词、近义词、相关术语**
            4. 只返回词语列表，用逗号分隔，不要有任何其他内容或格式
            
            用户输入：$keyword
            
            示例1：
            输入：小石潭记
            输出：小石潭记,柳宗元,唐代散文,山水游记,文言文,语文,古代文学
            
            示例2：
            输入：勾股定理
            输出：勾股定理,毕达哥拉斯定理,直角三角形,数学,几何,平方和,三角函数
            
            示例3：
            输入：英语
            输出：英语,英文,词汇,语法,阅读理解,听力,作文,语言
        """.trimIndent()

        val requestBody = JSONObject().apply {
            put("model", model)
            put("messages", listOf(
                mapOf("role" to "user", "content" to prompt)
            ))
            put("temperature", 0.3)
            put("max_tokens", 150)
        }

        // 2️⃣ 调用 AI 扩展
        val aiWords = try {
            val request = Request.Builder()
                .url("$baseUrl/chat/completions")
                .addHeader("Authorization", "Bearer $apiKey")
                .addHeader("Content-Type", "application/json")
                .post(requestBody.toString().toRequestBody("application/json".toMediaType()))
                .build()

            val response = client.newCall(request).execute()
            val body = response.body?.string()
            if (body == null) {
                emptyList()
            } else {
                val json = JSONObject(body)
                val text = json.optJSONArray("choices")
                    ?.optJSONObject(0)
                    ?.optJSONObject("message")
                    ?.optString("content", "")?.trim()

                if (text.isNullOrBlank()) {
                    emptyList()
                } else {
                    text.split(",", "，")
                        .map { it.trim() }
                        .filter { it.isNotBlank() }
                }
            }
        } catch (e: Exception) {
            println("⚠️ 联想词扩展失败: ${e.message}")
            emptyList()
        }

        // 3️⃣ 补充硬编码学科映射（无论 AI 是否成功都执行）
        val supplement = supplementWithHardcoded(keyword)

        // 合并 AI 结果 + 硬编码补充 + 原始词
        val result = (listOf(keyword) + aiWords + supplement)
            .distinct()
            .take(12)

        // 4️⃣ 写入缓存
        keywordCache.put(keyword, result)
        if (aiWords.isNotEmpty()) {
            println("💾 关键词缓存已保存: $keyword → $result")
        } else {
            println("📌 使用硬编码映射: $keyword → $result")
        }

        return result
    }

    /**
     * 硬编码学科映射补充 — 无论 AI 是否可用都生效
     * - 如果 keyword 是学科名（如"数学"），返回该学科下的知识点
     * - 如果 keyword 是知识点（如"函数"），返回其所属学科名（"数学"）
     */
    /**
     * 从对话记录中发现疑似学习关键词
     * 扫描最近 N 天的 backlog，用 AI 提取可能的学习科目/知识点
     * @param days 扫描最近几天的对话
     * @return 发现的关键词列表
     */
    fun discoverKeywords(days: Int = 7): List<String> {
        val backlogDir = File(EnvConfig.basePath, "Backlog")
        if (!backlogDir.exists()) return emptyList()

        val cutoff = java.time.LocalDate.now().minusDays(days.toLong())
        val dateDirs = backlogDir.listFiles()
            ?.filter { it.isDirectory }
            ?.filter { dir ->
                try {
                    java.time.LocalDate.parse(dir.name) >= cutoff
                } catch (_: Exception) { false }
            }
            ?.sortedDescending()
            ?: emptyList()

        if (dateDirs.isEmpty()) return emptyList()

        // 收集最近对话中 user 提出的问题
        val questions = mutableListOf<String>()
        for (dateDir in dateDirs.take(3)) { // 最多取3天，避免消息太长
            val files = dateDir.listFiles()
                ?.filter { it.name.endsWith(".json") && !it.name.endsWith(".meta.json") }
                ?.sortedDescending()
                ?.take(5) // 每天最多5条
                ?: emptyList()

            for (file in files) {
                try {
                    val messages = json.decodeFromString<List<ChatMessage>>(file.readText(Charsets.UTF_8))
                    messages.filter { it.role == "user" }
                        .map { it.content.take(100) }
                        .let { questions.addAll(it) }
                } catch (_: Exception) { }
            }
        }

        if (questions.isEmpty()) return emptyList()

        // 去重后交给 AI 提取关键词
        val uniqueQuestions = questions.distinct().take(15) // 最多15条

        val apiKey = EnvConfig.activeApiKey
        val baseUrl = EnvConfig.activeBaseUrl
        val model = EnvConfig.activeModel
        if (apiKey.isBlank() || baseUrl.isBlank()) return emptyList()

        val prompt = """
            你是一个学习关键词发现助手。以下是一些学生向 AI 提出的问题，请从中分析出该学生正在学习的**科目/知识点**。
            
            要求：
            1. 只返回关键词列表，用逗号分隔，不要任何其他文字
            2. 每个关键词应是一个独立的学习科目或知识点（如"数学"、"英语"、"小石潭记"、"勾股定理"）
            3. 不要包含明显非学习类的内容（如问候语、闲聊等）
            4. 如果无法从问题中判断学习内容，只返回一个"无"
            
            学生的问题：
            ${uniqueQuestions.joinToString("\n---\n")}
        """.trimIndent()

        return try {
            val requestBody = JSONObject().apply {
                put("model", model)
                put("messages", listOf(mapOf("role" to "user", "content" to prompt)))
                put("temperature", 0.3)
                put("max_tokens", 200)
            }

            val request = Request.Builder()
                .url("$baseUrl/chat/completions")
                .addHeader("Authorization", "Bearer $apiKey")
                .addHeader("Content-Type", "application/json")
                .post(requestBody.toString().toRequestBody("application/json".toMediaType()))
                .build()

            val response = client.newCall(request).execute()
            val body = response.body?.string() ?: return emptyList()
            val respJson = JSONObject(body)
            val text = respJson.optJSONArray("choices")
                ?.optJSONObject(0)
                ?.optJSONObject("message")
                ?.optString("content", "")?.trim() ?: return emptyList()

            if (text == "无" || text.isBlank()) return emptyList()

            text.split(",", "，")
                .map { it.trim() }
                .filter { it.isNotBlank() && it.length >= 2 }
                .distinct()
        } catch (e: Exception) {
            println("⚠️ 关键词发现失败: ${e.message}")
            emptyList()
        }
    }

    /**
     * 将发现的新关键词自动关联到已有缓存的学科中
     * 例如发现"小石潭记" → 自动追加到"语文"的扩展列表里，以后搜"语文"也能搜到
     */
    fun integrateDiscoveredKeywords(discovered: List<String>) {
        if (discovered.isEmpty()) return
        println("🔄 正在关联 ${discovered.size} 个新关键词到已有学科...")

        for (newKw in discovered) {
            // 1. 扩展新关键词（同时写入缓存）
            val expanded = expandKeywords(newKw)
            println("  📎 $newKw → $expanded")

            // 2. 检查扩展结果中是否有已缓存的学科名
            val cachedKeys = keywordCache.getAllKeys()
            for (term in expanded) {
                if (term == newKw) continue
                // 命中硬编码学科映射 或 已在缓存中 → 将新关键词关联到该学科
                if (SUBJECT_TOPICS.containsKey(term) || cachedKeys.contains(term)) {
                    keywordCache.mergeInto(term, listOf(newKw))
                }
            }

            // 3. 反向：如果新关键词是某个学科的知识点，关联到该学科
            TOPIC_TO_SUBJECT[newKw]?.let { subject ->
                keywordCache.mergeInto(subject, listOf(newKw))
            }
        }
        println("✅ 关键词关联完成")
    }

    private fun supplementWithHardcoded(keyword: String): List<String> {
        val result = mutableSetOf<String>()
        SUBJECT_TOPICS[keyword]?.let { result.addAll(it) }
        TOPIC_TO_SUBJECT[keyword]?.let { result.add(it) }
        return result.toList()
    }
}

// ========== 关键词扩展缓存 ==========

/**
 * 关键词扩展缓存：每个关键词只需调用一次 AI，结果保存在文件中
 * 文件位置：{BASE_PATH}/Backlog/keyword_cache.json
 */
class KeywordCache {
    private val json = Json { prettyPrint = true; ignoreUnknownKeys = true }

    /** 缓存格式版本，修改扩展逻辑时递增以自动清空旧缓存 */
    companion object {
        private const val CACHE_VERSION = 2
    }

    private val cacheFile: File by lazy {
        File(EnvConfig.basePath, "Backlog/keyword_cache.json")
    }

    @Serializable
    private data class CacheData(
        val version: Int = 0,
        val expansions: Map<String, List<String>> = emptyMap()
    )

    /** 从文件加载缓存（版本不匹配时返回空） */
    private fun load(): CacheData {
        return try {
            if (cacheFile.exists()) {
                val data = json.decodeFromString<CacheData>(cacheFile.readText(Charsets.UTF_8))
                if (data.version == CACHE_VERSION) data else {
                    println("📦 缓存版本不匹配(当前v$CACHE_VERSION, 缓存v${data.version})，已自动清空")
                    CacheData()
                }
            } else CacheData()
        } catch (_: Exception) {
            CacheData()
        }
    }

    /** 写入文件 */
    private fun save(data: CacheData) {
        try {
            cacheFile.parentFile?.mkdirs()
            cacheFile.writeText(json.encodeToString(data), Charsets.UTF_8)
        } catch (_: Exception) { }
    }

    /** 获取关键词的扩展结果，未缓存返回 null */
    fun get(keyword: String): List<String>? {
        return load().expansions[keyword]
    }

    /** 存入关键词的扩展结果 */
    fun put(keyword: String, expanded: List<String>) {
        val data = load()
        val updated = data.expansions.toMutableMap().apply {
            put(keyword, expanded)
        }
        save(CacheData(version = CACHE_VERSION, expansions = updated))
    }

    /** 获取所有已缓存的关键词 */
    fun getAllKeys(): Set<String> {
        return load().expansions.keys
    }

    /** 向已有条目的扩展列表中追加新词 */
    fun mergeInto(keyword: String, newWords: List<String>) {
        val data = load()
        val existing = data.expansions[keyword] ?: return
        val merged = (existing + newWords).distinct()
        if (merged.size > existing.size) {
            val updated = data.expansions.toMutableMap().apply {
                put(keyword, merged)
            }
            save(CacheData(version = CACHE_VERSION, expansions = updated))
            println("🔗 已关联: $keyword ← $newWords")
        }
    }
}

/**
 * 测试入口 — 直接运行此文件即可测试搜索功能，无需启动后端服务器
 */
fun main() {
    print("请输入搜索关键词: ")
    val keyword = readlnOrNull()?.trim() ?: return
    if (keyword.isBlank()) {
        println("关键词不能为空")
        return
    }

    println("\n" + "=".repeat(60))
    println("🧪 测试 PreciseSearch")
    println("=".repeat(60))

    val searcher = PreciseSearch()

    // 测试纯文本输出（AI Agent 内部使用格式）
    println("\n【1️⃣ 纯文本格式 (search)】")
    println("-".repeat(40))
    val textResult = searcher.search(keyword)
    println(textResult)

    // 测试 JSON 输出（独立 API 格式）
    println("\n【2️⃣ JSON 格式 (searchJson)】")
    println("-".repeat(40))
    val jsonResult = searcher.searchJson(keyword)
    println(jsonResult)

    println("=".repeat(60))
    println("✅ 测试完成")
}