package com.aegis.backend.core

import com.aegis.backend.tools.toMap
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter

/**
 * 对话历史记录管理 (Backlog)
 */
class Backlog {
    var messages: MutableList<ChatMessage> = mutableListOf()
    lateinit var path: File
    private val json = Json { prettyPrint = true; ignoreUnknownKeys = true }

    /** 标记 path 是否已设置（用于外部判断，避免 ::path.isInitialized 跨对象问题） */
    val hasPath: Boolean get() = this::path.isInitialized

    constructor() {
        // path 会在第一次 writeText 时根据当前时间设置
    }

    constructor(text: List<ChatMessage>?) {
        messages = text?.toMutableList() ?: mutableListOf()
    }

    fun appendUserText(text: String) {
        messages.add(ChatMessage(role = "user", content = text))
    }

    fun appendAssistantText(text: String) {
        messages.add(ChatMessage(role = "assistant", content = text))
    }

    fun getText(): List<ChatMessage> = messages

    fun resetPath() {
        val dateStr = LocalDate.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd"))
        val timeStr = LocalTime.now().format(DateTimeFormatter.ofPattern("HH-mm-ss"))
        val backlogDir = File(EnvConfig.basePath, "Backlog/$dateStr")
        backlogDir.mkdirs()
        path = File(backlogDir, "$timeStr.json")
    }

    fun writeText() {
        try {
            if (!::path.isInitialized) resetPath()
            // 确保父目录存在
            path.parentFile?.mkdirs()
            path.writeText(json.encodeToString(messages), Charsets.UTF_8)
            saveSummary()
            println(">>> backlog 已保存: ${path.absolutePath} (${messages.size} 条消息)")
        } catch (e: Exception) {
            println(">>> backlog 保存失败: ${e.message}")
        }
    }

    private fun saveSummary() {
        if (messages.isEmpty()) return
        val firstUserMsg = messages.firstOrNull { it.role == "user" }?.content ?: ""
        val summary = if (firstUserMsg.length > 20) firstUserMsg.take(20) else firstUserMsg
        val metaPath = File(path.parent, path.nameWithoutExtension + ".meta.json")
        val metaData = SummaryMeta(summary = summary)
        metaPath.writeText(json.encodeToString(metaData), Charsets.UTF_8)
    }

    /**
     * 从文件名 HH-MM-SS.json 中提取时间字符串 HH:MM
     */
    private fun timeFromFilename(filename: String): String? {
        return try {
            val name = filename.removeSuffix(".json")
            val parts = name.split("-")
            if (parts.size >= 2) {
                "${parts[0].padStart(2, '0')}:${parts[1].padStart(2, '0')}"
            } else null
        } catch (_: Exception) { null }
    }

    fun loadBacklog(targetDate: String, startTime: String? = null, endTime: String? = null): Map<String, ChatHistoryResult> {
        val results = mutableMapOf<String, ChatHistoryResult>()
        val backlogDir = File(EnvConfig.basePath, "Backlog/$targetDate")
        if (!backlogDir.exists()) return results

        backlogDir.listFiles { f -> f.extension == "json" && !f.name.endsWith(".meta.json") }?.forEach { jsonFile ->
            try {
                // 时间范围过滤
                if (startTime != null || endTime != null) {
                    val fileTime = timeFromFilename(jsonFile.name)
                    if (fileTime != null) {
                        if (startTime != null && fileTime < startTime) return@forEach
                        if (endTime != null && fileTime > endTime) return@forEach
                    }
                }

                val rawMessages = json.decodeFromString<List<ChatMessage>>(jsonFile.readText(Charsets.UTF_8))
                val filtered = rawMessages.filter { it.role != "system" }
                val metaFile = File(jsonFile.parent, jsonFile.nameWithoutExtension + ".meta.json")
                val summary = if (metaFile.exists()) {
                    try {
                        json.decodeFromString<SummaryMeta>(metaFile.readText(Charsets.UTF_8)).summary
                    } catch (_: Exception) { "" }
                } else ""
                results[jsonFile.name] = ChatHistoryResult(messages = filtered, summary = summary)
            } catch (_: Exception) { }
        }
        return results
    }

    @Serializable
    data class ChatMessage(val role: String, val content: String)

    @Serializable
    data class SummaryMeta(val summary: String)

    @Serializable
    data class ChatHistoryResult(val messages: List<ChatMessage>, val summary: String)
}

/**
 * 指令文件管理 (Instructions)
 */
class Instructions {
    var content: String = ""
    lateinit var path: File

    init {
        loadInstructions()
    }

    private fun loadInstructions() {
        val libPath = File(EnvConfig.basePath, "lib/instructions.txt")
        val rootPath = File(EnvConfig.basePath, "instructions.txt")

        val targetFile = if (libPath.exists()) libPath else rootPath
        path = targetFile

        if (targetFile.exists()) {
            content = targetFile.readText(Charsets.UTF_8)
            println("已加载指令: ${targetFile.absolutePath}")
        } else {
            println("警告：未找到指令文件 ${targetFile.absolutePath}")
            content = ""
        }
    }

    fun writeInstructions(newInstructions: String) {
        path.writeText(newInstructions, Charsets.UTF_8)
        content = newInstructions
        println("已更新指令: ${path.absolutePath}")
    }
}

/**
 * AI 配置项数据类
 */
data class AiConfigItem(
    val name: String,
    val baseUrl: String,
    val apiKey: String,
    val model: String,
    val enabled: Boolean = false
)

/**
 * 环境配置，唯一从 Documents/Academic Aegis/config.json 读取
 * 不存在则自动生成模板
 */
object EnvConfig {
    // ========== 唯一路径 ==========
    private val configDir: String by lazy {
        val userHome = System.getProperty("user.home")
        "$userHome/Documents/Academic Aegis"
    }

    private val configFile: File by lazy {
        File(configDir, "config.json")
    }

    // 缓存
    private var _loaded = false
    private var _config: Map<String, Any> = emptyMap()

    // ========== 公开配置项 ==========
    val basePath: String by lazy { ensureLoaded(); (_config["BASE_PATH"] as? String) ?: configDir }

    val port: Int by lazy {
        ensureLoaded()
        (_config["SERVER_PORT"] as? Number)?.toInt()
            ?: (_config["PORT"] as? Number)?.toInt()
            ?: 8080
    }

    val openaiApiKey: String by lazy { ensureLoaded(); (_config["OPENAI_API_KEY"] as? String) ?: "" }

    val gaodeApiKey: String by lazy { ensureLoaded(); (_config["Gaode_API_Key"] as? String) ?: "" }

    val dashscopeApiKey: String by lazy { ensureLoaded(); (_config["DASHSCOPE_API_KEY"] as? String) ?: "" }

    val studentId: String by lazy { ensureLoaded(); (_config["STUDENT_ID"] as? String) ?: "" }

    val studentName: String by lazy { ensureLoaded(); (_config["STUDENT_NAME"] as? String) ?: "" }

    // ========== AI_CONFIGS 支持 ==========
    val aiConfigs: List<AiConfigItem> by lazy {
        ensureLoaded()
        parseAiConfigs(_config["AI_CONFIGS"])
    }

    /** 获取已启用的 AI 配置 */
    val enabledAiConfig: AiConfigItem? by lazy {
        aiConfigs.firstOrNull { it.enabled }
    }

    /** 兼容旧版：如果有 AI_CONFIGS 则用启用的，否则回退到旧字段 */
    val activeApiKey: String by lazy {
        enabledAiConfig?.apiKey?.takeIf { it.isNotBlank() }
            ?: openaiApiKey.ifBlank { dashscopeApiKey }
    }

    val activeBaseUrl: String by lazy {
        enabledAiConfig?.baseUrl?.takeIf { it.isNotBlank() }
            ?: "https://dashscope.aliyuncs.com/compatible-mode/v1"
    }

    val activeModel: String by lazy {
        enabledAiConfig?.model?.takeIf { it.isNotBlank() }
            ?: "qwen3.5-flash"
    }

    private fun parseAiConfigs(raw: Any?): List<AiConfigItem> {
        if (raw !is List<*>) return emptyList()
        return raw.mapNotNull { item ->
            if (item !is Map<*, *>) return@mapNotNull null
            try {
                AiConfigItem(
                    name = (item["name"] as? String) ?: "",
                    baseUrl = (item["base_url"] as? String) ?: "",
                    apiKey = (item["api_key"] as? String) ?: "",
                    model = (item["model"] as? String) ?: "",
                    enabled = (item["enabled"] as? Boolean) ?: false
                )
            } catch (_: Exception) { null }
        }
    }

    // ========== 加载逻辑 ==========
    private fun ensureLoaded() {
        if (_loaded) return
        _loaded = true

        if (!configFile.exists()) {
            generateTemplate()
        }
        _config = readConfigFile(configFile)
    }

    private fun generateTemplate() {
        println(">>> 未检测到 config.json，正在生成模板: ${configFile.absolutePath}")
        configFile.parentFile.mkdirs()
        val template = """{
  "BASE_PATH": "$configDir",
  "STUDENT_ID": "",
  "STUDENT_NAME": "",
  "Gaode_API_Key": "",
  "SERVER_PORT": 8080,
  "AI_CONFIGS": [
    {
      "name": "阿里云通义千问",
      "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
      "api_key": "",
      "model": "qwen-plus",
      "enabled": true
    }
  ]
}"""
        configFile.writeText(template, Charsets.UTF_8)
        println(">>> 模板已生成，请编辑 $configFile 填入配置后重启后端")
    }

    @Suppress("UNCHECKED_CAST")
    private fun readConfigFile(file: File): Map<String, Any> {
        return try {
            val text = file.readText(Charsets.UTF_8)
            val json = org.json.JSONObject(text)
            json.toMap()
        } catch (_: Exception) {
            emptyMap()
        }
    }
}
