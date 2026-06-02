import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.File

data class ChatMessage(val role: String, val content: String)

fun main() {
    val backlogDir = File("C:\\Users\\MR\\Documents\\Academic Aegis\\Backlog")
    val keyword = "天气"  // 要搜索的关键词

    println("搜索关键词: $keyword")
    println("扫描目录: ${backlogDir.absolutePath}\n")

    var totalMatches = 0

    backlogDir.walkTopDown()
        .filter { it.isFile && it.extension == "json" }
        .forEach { jsonFile ->
            try {
                val jsonContent = jsonFile.readText(Charsets.UTF_8)
                val type = object : TypeToken<List<com.aegis.backend.tools.search.ChatMessage>>() {}.type
                val messages: List<com.aegis.backend.tools.search.ChatMessage> = Gson().fromJson(jsonContent, type)

                // 精确匹配：content 包含关键词
                val matches = messages.filter { it.content.contains(keyword, ignoreCase = true) }

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

    println("共找到 $totalMatches 条匹配记录")
}