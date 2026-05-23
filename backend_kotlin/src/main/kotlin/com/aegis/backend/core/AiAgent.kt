package com.aegis.backend.core

import com.aegis.backend.tools.AgentTools
import com.aegis.backend.tools.toMap
import kotlinx.serialization.json.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * AI Agent - 核心智能体，处理聊天逻辑
 * 使用 DashScope API (通义千问)
 */
class AiAgent {
    private val client = OkHttpClient.Builder()
        .connectTimeout(60, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .build()

    val backlog = Backlog()
    val tool = AgentTools()
    val instructions = Instructions()
    private val _chatting = AtomicBoolean(false)

    companion object {
        // ⚠️ 根据 TODO.md 要求，所有用到模型的地方都使用 qwen3.5-flash
        private const val MODEL = "qwen3.5-flash"
        private const val BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
        private const val CHAT_URL = "$BASE_URL/chat/completions"
    }

    private fun getApiKey(): String {
        return EnvConfig.openaiApiKey.ifBlank {
            EnvConfig.dashscopeApiKey
        }
    }

    /**
     * 非流式聊天
     */
    fun chat(userInput: String): String {
        backlog.appendUserText(userInput)

        val apiKey = getApiKey()
        if (apiKey.isBlank()) return "请先在 config.json 中配置 OPENAI_API_KEY 或 DASHSCOPE_API_KEY"

        val messages = buildMessageList()
        val requestBody = buildChatRequest(messages, stream = false)

        val request = Request.Builder()
            .url(CHAT_URL)
            .addHeader("Authorization", "Bearer $apiKey")
            .addHeader("Content-Type", "application/json")
            .post(requestBody.toRequestBody("application/json".toMediaType()))
            .build()

        return try {
            val response = client.newCall(request).execute()
            val body = response.body?.string() ?: return "错误：无响应"

            val json = JSONObject(body)
            val choice = json.optJSONArray("choices")?.optJSONObject(0)
            val message = choice?.optJSONObject("message")
            val content = message?.optString("content", "") ?: ""

            // 检查是否有工具调用
            val toolCalls = message?.optJSONArray("tool_calls")
            if (toolCalls != null && toolCalls.length() > 0) {
                handleToolCalls(content, toolCalls, messages)
            } else {
                backlog.appendAssistantText(content)
                backlog.writeText()
                content
            }
        } catch (e: Exception) {
            "错误：${e.message}"
        }
    }

    /**
     * 流式聊天 - 通过回调返回块
     */
    fun streamChat(userInput: String, onChunk: (String) -> Unit): String {
        println(">>> streamChat 开始, 用户输入: ${userInput.take(50)}")
        // 防重复调用
        if (!_chatting.compareAndSet(false, true)) {
            val warn = "正在处理上一条消息，请稍候..."
            println(">>> $warn")
            onChunk(warn)
            return warn
        }
        try {
        // 防重：如果最后一条消息已是同一用户的相同内容，则跳过
        val last = backlog.messages.lastOrNull()
        if (last?.role == "user" && last.content == userInput) {
            println(">>> 检测到重复用户消息，跳过: $userInput")
        } else {
            backlog.appendUserText(userInput)
        }
        println(">>> backlog 当前消息数: ${backlog.messages.size}")

        val apiKey = getApiKey()
        if (apiKey.isBlank()) {
            val errMsg = "请先在 config.json 中配置 API Key"
            onChunk(errMsg)
            return errMsg
        }

        val messages = buildMessageList()
        val requestBody = buildChatRequest(messages, stream = true)

        val request = Request.Builder()
            .url(CHAT_URL)
            .addHeader("Authorization", "Bearer $apiKey")
            .addHeader("Content-Type", "application/json")
            .addHeader("Accept", "text/event-stream")
            .post(requestBody.toRequestBody("application/json".toMediaType()))
            .build()

        val fullReply = StringBuilder()
        val toolCallsCollector = mutableListOf<Map<String, Any>>()

        try {
            val response = client.newCall(request).execute()
            val body = response.body ?: return "错误：无响应"
            val reader = body.charStream().buffered()

            reader.use { r ->
                var line: String?
                while (r.readLine().also { line = it } != null) {
                    val eventLine = line ?: continue
                    if (!eventLine.startsWith("data: ")) continue
                    val data = eventLine.removePrefix("data: ").trim()
                    if (data == "[DONE]") break

                    try {
                        val json = JSONObject(data)
                        val choices = json.optJSONArray("choices")
                        if (choices == null || choices.length() == 0) continue

                        val delta = choices.getJSONObject(0).optJSONObject("delta") ?: continue

                        // 处理文本内容
                        val content = delta.optString("content", "")
                        if (content.isNotBlank()) {
                            fullReply.append(content)
                            onChunk(content)
                        }

                        // 处理工具调用 (流式)
                        val tcArray = delta.optJSONArray("tool_calls")
                        if (tcArray != null) {
                            for (i in 0 until tcArray.length()) {
                                val tc = tcArray.getJSONObject(i)
                                val idx = tc.optInt("index", 0)
                                while (toolCallsCollector.size <= idx) {
                                    toolCallsCollector.add(mapOf(
                                        "id" to "",
                                        "name" to "",
                                        "arguments" to ""
                                    ))
                                }
                                val existing = toolCallsCollector[idx].toMutableMap()
                                if (tc.has("id") && !tc.isNull("id")) {
                                    existing["id"] = tc.getString("id")
                                }
                                val func = tc.optJSONObject("function")
                                if (func != null) {
                                    if (func.has("name") && !func.isNull("name")) {
                                        existing["name"] = func.getString("name")
                                    }
                                    if (func.has("arguments") && !func.isNull("arguments")) {
                                        existing["arguments"] = existing["arguments"].toString() + func.getString("arguments")
                                    }
                                }
                                toolCallsCollector[idx] = existing
                            }
                        }
                    } catch (_: Exception) { }
                }
            }

            // 如果有工具调用，处理它们
            if (toolCallsCollector.isNotEmpty() && toolCallsCollector.any { it["name"].toString().isNotBlank() }) {
                val toolResult = processToolCalls(toolCallsCollector, messages)
                onChunk("\n\n[工具调用结果]\n$toolResult")
                fullReply.append("\n\n[工具调用结果]\n$toolResult")
            }

        } catch (e: Exception) {
            val errMsg = "\n\n错误：${e.message}"
            onChunk(errMsg)
            fullReply.append(errMsg)
        }

        if (fullReply.isNotBlank()) {
            try {
                backlog.appendAssistantText(fullReply.toString())
                backlog.writeText()
                println(">>> 对话已存档: ${backlog.path}")
            } catch (e: Exception) {
                println(">>> 存档失败: ${e.message}")
            }
        } else {
            println(">>> 警告: fullReply 为空，跳过存档")
        }

        return fullReply.toString()
        } finally {
            _chatting.set(false)
        }
    }

    private fun buildMessageList(): MutableList<Map<String, Any>> {
        val systemPrompt = "你是一个集成了一系列本地和线上工具的超级助理。你的名字是星火学伴 AI。\n" +
                "【核心规则】：\n" +
                "1. 当用户询问天气、路况、搜索信息、识别图片、生成图片等需求时，必须直接调用对应的工具，不要回复说你做不到。\n" +
                "2. 如果工具调用需要参数（如城市名），请从用户对话中提取。\n" +
                "3. 你的回答应当简洁、友好且有用。\n" +
                "【当前可用工具】：get_weather, get_traffic, text_to_image, qwen_websearch, image_recognition"

        val messages = mutableListOf<Map<String, Any>>(
            mapOf("role" to "system", "content" to systemPrompt)
        )

        if (instructions.content.isNotBlank()) {
            messages.add(mapOf("role" to "system", "content" to instructions.content))
        }

        messages.addAll(backlog.messages.map { mapOf("role" to it.role, "content" to it.content) })
        return messages
    }

    private fun buildChatRequest(messages: List<Map<String, Any>>, stream: Boolean): String {
        val jsonObj = JSONObject().apply {
            put("model", MODEL)
            put("messages", messages.map { msg ->
                JSONObject(msg)
            })
            put("stream", stream)
            put("temperature", 0.7)
            // 必须传入 tools，否则模型不知道能调用什么工具
            put("tools", buildToolsList())
            put("tool_choice", "auto")
        }
        return jsonObj.toString()
    }

    /** 构建工具定义列表（与 Python 后端一致） */
    private fun buildToolsList(): org.json.JSONArray {
        val toolsArray = org.json.JSONArray()

        // get_weather
        toolsArray.put(JSONObject().apply {
            put("type", "function")
            put("function", JSONObject().apply {
                put("name", "get_weather")
                put("description", "获取指定地区的实时天气信息")
                put("parameters", JSONObject().apply {
                    put("type", "object")
                    put("properties", JSONObject().apply {
                        put("city", JSONObject().apply {
                            put("type", "string")
                            put("description", "城市名称或中国城市编码，如'广州'或'440100'")
                        })
                    })
                    put("required", org.json.JSONArray(listOf("city")))
                })
            })
        })

        // get_traffic
        toolsArray.put(JSONObject().apply {
            put("type", "function")
            put("function", JSONObject().apply {
                put("name", "get_traffic")
                put("description", "获取两点间驾车路况")
                put("parameters", JSONObject().apply {
                    put("type", "object")
                    put("properties", JSONObject().apply {
                        put("origin", JSONObject().apply {
                            put("type", "string")
                            put("description", "起点坐标 'lng,lat'")
                        })
                        put("destination", JSONObject().apply {
                            put("type", "string")
                            put("description", "终点坐标 'lng,lat'")
                        })
                    })
                    put("required", org.json.JSONArray(listOf("origin", "destination")))
                })
            })
        })

        // qwen_websearch
        toolsArray.put(JSONObject().apply {
            put("type", "function")
            put("function", JSONObject().apply {
                put("name", "qwen_websearch")
                put("description", "通义千问联网搜索问答")
                put("parameters", JSONObject().apply {
                    put("type", "object")
                    put("properties", JSONObject().apply {
                        put("query", JSONObject().apply {
                            put("type", "string")
                            put("description", "用户要搜索或提问的问题")
                        })
                    })
                    put("required", org.json.JSONArray(listOf("query")))
                })
            })
        })

        // query_score
        toolsArray.put(JSONObject().apply {
            put("type", "function")
            put("function", JSONObject().apply {
                put("name", "query_score")
                put("description", "查询学生成绩")
                put("parameters", JSONObject().apply {
                    put("type", "object")
                    put("properties", JSONObject().apply {
                        put("student_id", JSONObject().apply {
                            put("type", "string")
                            put("description", "学生ID")
                        })
                        put("name", JSONObject().apply {
                            put("type", "string")
                            put("description", "学生姓名，支持模糊搜索")
                        })
                    })
                })
            })
        })

        return toolsArray
    }

    private fun handleToolCalls(
        content: String,
        toolCalls: org.json.JSONArray,
        messages: MutableList<Map<String, Any>>
    ): String {
        if (toolCalls.length() == 0) {
            backlog.appendAssistantText(content)
            backlog.writeText()
            return content
        }

        // 构建完整消息数组（直接拼 JSON 避免 Map 序列化问题）
        val fullMessages = org.json.JSONArray()
        for (msg in messages) {
            fullMessages.put(JSONObject(msg))
        }

        // 原始 assistant 消息（含 tool_calls）
        fullMessages.put(JSONObject().apply {
            put("role", "assistant")
            put("content", JSONObject.NULL)
            put("tool_calls", toolCalls)
        })

        // 执行工具并加入结果
        for (i in 0 until toolCalls.length()) {
            val tc = toolCalls.getJSONObject(i)
            val func = tc.getJSONObject("function")
            val name = func.getString("name")
            val argsStr = func.optString("arguments", "{}")
            val args = JSONObject(argsStr)

            val result = useTool(name, args)
            fullMessages.put(JSONObject().apply {
                put("role", "tool")
                put("tool_call_id", tc.getString("id"))
                put("content", result)
            })
        }

        // 再次调用模型
        val apiKey = getApiKey()
        val requestJson = JSONObject().apply {
            put("model", MODEL)
            put("messages", fullMessages)
            put("stream", false)
            put("temperature", 0.7)
            put("tools", buildToolsList())
            put("tool_choice", "auto")
        }

        return try {
            val request = Request.Builder()
                .url(CHAT_URL)
                .addHeader("Authorization", "Bearer $apiKey")
                .addHeader("Content-Type", "application/json")
                .post(requestJson.toString().toRequestBody("application/json".toMediaType()))
                .build()

            val response = client.newCall(request).execute()
            val body = response.body?.string() ?: return content
            val json = JSONObject(body)
            val reply = json.optJSONArray("choices")
                ?.optJSONObject(0)
                ?.optJSONObject("message")
                ?.optString("content", "") ?: content

            backlog.appendAssistantText(reply)
            backlog.writeText()
            reply
        } catch (e: Exception) {
            "错误：${e.message}"
        }
    }

    private fun processToolCalls(
        toolCalls: List<Map<String, Any>>,
        messages: MutableList<Map<String, Any>>
    ): String {
        // 1️⃣ 执行工具
        val results = mutableListOf<Pair<String, String>>() // name -> result
        for (tc in toolCalls) {
            val name = tc["name"].toString()
            val argsStr = tc["arguments"].toString()
            if (name.isBlank()) continue

            val args = try { JSONObject(argsStr) } catch (_: Exception) { JSONObject() }
            val result = useTool(name, args)
            results.add(Pair(name, result))
        }

        // 2️⃣ 直接构建最终请求 JSON（含 assistant tool_calls + tool results）
        val apiKey = getApiKey()
        val fullMessages = org.json.JSONArray()

        // 复制原始消息
        for (msg in messages) {
            fullMessages.put(JSONObject(msg))
        }

        // 加入 assistant tool_calls 消息
        val tcArray = org.json.JSONArray()
        for ((i, tc) in toolCalls.withIndex()) {
            if (tc["name"].toString().isBlank()) continue
            tcArray.put(JSONObject().apply {
                put("id", tc["id"].toString().ifBlank { "call_$i" })
                put("type", "function")
                put("function", JSONObject().apply {
                    put("name", tc["name"].toString())
                    put("arguments", tc["arguments"].toString())
                })
            })
        }
        if (tcArray.length() > 0) {
            fullMessages.put(JSONObject().apply {
                put("role", "assistant")
                put("content", JSONObject.NULL)
                put("tool_calls", tcArray)
            })
        }

        // 加入 tool 结果消息
        for ((i, tc) in toolCalls.withIndex()) {
            if (tc["name"].toString().isBlank()) continue
            val result = results.getOrNull(i)?.second ?: continue
            fullMessages.put(JSONObject().apply {
                put("role", "tool")
                put("tool_call_id", tc["id"].toString().ifBlank { "call_$i" })
                put("content", result)
            })
        }

        // 构建最终请求
        val requestJson = JSONObject().apply {
            put("model", MODEL)
            put("messages", fullMessages)
            put("stream", false)
            put("temperature", 0.7)
            put("tools", buildToolsList())
            put("tool_choice", "auto")
        }

        return try {
            val request = Request.Builder()
                .url(CHAT_URL)
                .addHeader("Authorization", "Bearer $apiKey")
                .addHeader("Content-Type", "application/json")
                .post(requestJson.toString().toRequestBody("application/json".toMediaType()))
                .build()

            val response = client.newCall(request).execute()
            val body = response.body?.string() ?: return results.joinToString("\n") { "${it.first}: ${it.second}" }
            println(">>> 工具调用后 AI 回复: ${body.take(300)}")
            val json = JSONObject(body)
            val reply = json.optJSONArray("choices")
                ?.optJSONObject(0)
                ?.optJSONObject("message")
                ?.optString("content", "")
            if (!reply.isNullOrBlank()) reply else results.joinToString("\n") { "${it.first}: ${it.second}" }
        } catch (e: Exception) {
            println(">>> 工具调用后请求失败: ${e.message}")
            results.joinToString("\n") { "${it.first}: ${it.second}" }
        }
    }

    private fun useTool(name: String, args: JSONObject): String {
        return try {
            when (name) {
                "get_local_backlog" -> backlog.getText().toString()
                "get_weather" -> {
                    val city = args.optString("city", args.optString("adcode", ""))
                    tool.getWeather(city)?.toString() ?: "获取天气失败"
                }
                "get_traffic" -> {
                    val origin = args.optString("origin", "")
                    val destination = args.optString("destination", "")
                    val strategy = args.optInt("strategy", 0)
                    tool.getTraffic(origin, destination, strategy)?.toString() ?: "获取路况失败"
                }
                "qwen_websearch" -> {
                    val query = args.optString("query", "")
                    tool.qwenWebsearch(query)
                }
                "query_score" -> {
                    val studentId = args.optString("student_id", args.optString("studentId", ""))
                    val name = args.optString("name", "")
                    tool.queryScore(studentId = studentId.ifBlank { null }, name = name.ifBlank { null }).toString()
                }
                "add_score" -> {
                    val studentId = args.optString("student_id", args.optString("studentId", ""))
                    val name = args.optString("name", "")
                    val scores = mutableMapOf<String, Double>()
                    val scoresObj = args.optJSONObject("scores")
                    if (scoresObj != null) {
                        scoresObj.keys().forEach { key ->
                            scores[key] = scoresObj.getDouble(key)
                        }
                    }
                    tool.addScore(studentId, name, scores)
                }
                "delete_score" -> {
                    val studentId = args.optString("student_id", args.optString("studentId", ""))
                    val name = args.optString("name", "")
                    tool.deleteScore(studentId = studentId.ifBlank { null }, name = name.ifBlank { null })
                }
                "load_backlog" -> {
                    val targetDate = args.optString("target_date", args.optString("targetDate", ""))
                    tool.loadBacklog(backlog, targetDate).toString()
                }
                "text_to_image" -> "文本生成图片功能需要在 Python 环境运行 Stable Diffusion"
                "image_recognition" -> "图像识别功能需要使用百度 API，当前 Kotlin 后端暂未实现"
                else -> "未知工具: $name"
            }
        } catch (e: Exception) {
            "工具调用失败: ${e.message}"
        }
    }
}
