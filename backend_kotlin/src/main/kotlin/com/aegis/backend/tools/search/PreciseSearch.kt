package com.aegis.backend.tools.search

import com.aegis.backend.core.ChatMessage
import com.aegis.backend.core.EnvConfig
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
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

    companion object {
        private val BACKLOG_DIR = File("C:\\Users\\MR\\Documents\\Academic Aegis\\Backlog")
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
        val json = JSONObject().apply {
            put("keyword", keyword)
            put("expanded_words", JSONObject().apply {
                put("original", keyword)
                put("related", result.expandedWords.filter { it != keyword })
                put("all", result.expandedWords)
            })
            put("total_matches", result.totalMatches)
            put("files", org.json.JSONArray(result.matches.map { fileMatch ->
                JSONObject().apply {
                    put("file_path", fileMatch.filePath)
                    put("file_name", File(fileMatch.filePath).name)
                    put("match_count", fileMatch.sentences.size)
                    put("sentences", org.json.JSONArray(fileMatch.sentences.map { sentence ->
                        JSONObject().apply {
                            put("role", sentence.role)
                            put("content", sentence.content)
                        }
                    }))
                }
            }))
        }
        return json.toString(2)
    }

    /**
     * 搜索核心逻辑，返回结构化数据
     */
    private fun searchInternal(keyword: String): SearchResult {
        val expandedWords = expandKeywords(keyword)
        val fileMatches = mutableListOf<FileMatch>()
        var totalMatches = 0

        if (!BACKLOG_DIR.exists() || !BACKLOG_DIR.isDirectory) {
            return SearchResult(expandedWords, emptyList(), 0)
        }

        BACKLOG_DIR.walkTopDown()
            .filter { it.isFile && it.extension == "json" }
            .forEach { jsonFile ->
                try {
                    val jsonContent = jsonFile.readText(Charsets.UTF_8)
                    val type = object : TypeToken<List<ChatMessage>>() {}.type
                    val messages: List<ChatMessage> = Gson().fromJson(jsonContent, type)

                    val matches = messages.filter { msg ->
                        expandedWords.any { word ->
                            msg.content.contains(word, ignoreCase = true)
                        }
                    }

                    if (matches.isNotEmpty()) {
                        fileMatches.add(FileMatch(
                            filePath = jsonFile.absolutePath,
                            sentences = matches.map { Sentence(it.role, it.content) }
                        ))
                        totalMatches += matches.size
                    }
                } catch (_: Exception) { }
            }

        return SearchResult(expandedWords, fileMatches, totalMatches)
    }

    // ========== 内部数据结构 ==========
    data class Sentence(val role: String, val content: String)
    data class FileMatch(val filePath: String, val sentences: List<Sentence>)
    data class SearchResult(
        val expandedWords: List<String>,
        val matches: List<FileMatch>,
        val totalMatches: Int
    )

    /**
     * 调用 DashScope API (通义千问) 扩展联想词
     */
    private fun expandKeywords(keyword: String): List<String> {
        val apiKey = EnvConfig.dashscopeApiKey.ifBlank { EnvConfig.openaiApiKey }
        if (apiKey.isBlank()) {
            println("⚠️ 未配置 API Key，使用原始词搜索")
            return listOf(keyword)
        }

        val prompt = """
            你是一个关键词扩展助手。请将用户输入的词扩展为 3-5 个近义词、同义词或高度相关的词。
            只返回词语列表，用逗号分隔，不要有任何其他内容或格式。
            
            用户输入：$keyword
            
            示例：
            输入：快乐
            输出：快乐,开心,愉悦,高兴,喜悦
        """.trimIndent()

        val requestBody = JSONObject().apply {
            put("model", "qwen3.5-flash")
            put("input", JSONObject().apply {
                put("messages", listOf(
                    mapOf("role" to "user", "content" to prompt)
                ))
            })
            put("parameters", JSONObject().apply {
                put("temperature", 0.3)
                put("max_tokens", 100)
            })
        }

        return try {
            val request = Request.Builder()
                .url("https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation")
                .addHeader("Authorization", "Bearer $apiKey")
                .addHeader("Content-Type", "application/json")
                .post(requestBody.toString().toRequestBody("application/json".toMediaType()))
                .build()

            val response = client.newCall(request).execute()
            val body = response.body?.string() ?: return listOf(keyword)
            val json = JSONObject(body)
            val text = json.optJSONObject("output")?.optString("text", "")?.trim() ?: return listOf(keyword)

            // 解析：按逗号分割，去重，限制最多5个
            val words = text.split(",", "，")
                .map { it.trim() }
                .filter { it.isNotBlank() }
                .take(5)
                .toSet()
                .toList()

            // 确保原始词也在列表中
            (listOf(keyword) + words).distinct().take(6)
        } catch (e: Exception) {
            println("⚠️ 联想词扩展失败: ${e.message}")
            listOf(keyword) // 降级：只用原始词
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

