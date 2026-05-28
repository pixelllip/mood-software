package com.aegis.backend.tools.search

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.runBlocking
import java.io.File

data class ChatMessage(val role: String, val content: String)

class SimpleChatSearch(private val apiKey: String) {

    /**
     * 搜索主流程：输入词 → 大模型扩展 → 遍历JSON匹配
     */
    suspend fun search(keyword: String, backlogDir: File) {
        // 1. 调用千问扩展同义词
        val expandedWords = expandWithQwen(keyword)
        println("🔍 原始词: $keyword")
        println("📝 扩展词: ${expandedWords.joinToString(", ")}\n")

        // 2. 遍历所有JSON文件进行匹配
        var totalMatches = 0

        backlogDir.walkTopDown()
            .filter { it.isFile && it.extension == "json" }
            .forEach { jsonFile ->
                try {
                    val jsonContent = jsonFile.readText(Charsets.UTF_8)
                    val type = object : com.google.gson.reflect.TypeToken<List<ChatMessage>>() {}.type
                    val messages: List<ChatMessage> = Gson().fromJson(jsonContent, type)

                    // 匹配：content 包含任意扩展词
                    val matches = messages.filter { msg ->
                        expandedWords.any { word ->
                            msg.content.contains(word, ignoreCase = true)
                        }
                    }

                    if (matches.isNotEmpty()) {
                        println("📁 文件: ${jsonFile.absolutePath}")
                        matches.forEach { msg ->
                            println("   [${msg.role}] ${msg.content}")
                            totalMatches++
                        }
                        println()
                    }
                } catch (e: Exception) {
                    println("解析失败: ${jsonFile.name} - ${e.message}")
                }
            }

        println("✅ 共找到 $totalMatches 条匹配记录")
    }

    /**
     * 调用千问API扩展同义词
     */
    private suspend fun expandWithQwen(query: String): List<String> {
        val prompt = """
            将用户输入的词扩展为3-5个近义词或相关词，只返回词语列表，用逗号分隔，不要有其他内容。
            
            用户输入：$query
            
            示例输出：天气,气候,气温,天象
        """.trimIndent()

        return try {
            // 复用你的 DashScope API 调用逻辑
            val response = callDashScopeAPI(
                apiKey = apiKey,
                messages = listOf(mapOf("role" to "user", "content" to prompt)),
                temperature = 0.3
            )

            // 解析：去除空格，按逗号分割
            response
                .split(",", "，")
                .map { it.trim() }
                .filter { it.isNotBlank() }
                .take(5)
                .toSet()  // 去重
                .toList()

        } catch (e: Exception) {
            println("⚠️ 大模型扩展失败: ${e.message}，使用原始词")
            listOf(query)  // 降级：只用原始词
        }
    }
}

// 使用示例
fun main() = runBlocking {
    val apiKey = "sk-your-dashscope-api-key"  // 从登录时获取
    val searcher = SimpleChatSearch(apiKey)
    val backlogDir = File("C:\\Users\\MR\\Documents\\Academic Aegis\\Backlog")

    print("请输入搜索词: ")
    val input = readlnOrNull() ?: return@runBlocking

    searcher.search(input, backlogDir)
}