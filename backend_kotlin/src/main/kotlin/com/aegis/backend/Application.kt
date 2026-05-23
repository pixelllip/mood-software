package com.aegis.backend

import com.aegis.backend.core.AiAgent
import com.aegis.backend.core.EnvConfig
import com.aegis.backend.tools.score_management.StudentScoreService
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.plugins.cors.routing.CORS
import io.ktor.server.plugins.statuspages.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

// ========== 数据模型 ==========

@Serializable
data class ChatRequest(val prompt: String? = null, val history: List<Map<String, String>>? = null)

@Serializable
data class PingResponse(val status: String, val message: String)

@Serializable
data class ErrorResponse(val error: String)

@Serializable
data class AddScoreRequest(
    val id: String? = null,
    val student_id: String? = null,
    val name: String? = null,
    val scores: List<Map<String, Double>>? = null
)

@Serializable
data class DeleteScoreRequest(val id: String? = null, val name: String? = null)

@Serializable
data class ScheduleRequest(
    val tasks: String? = null,
    val city: String? = null,
    val origin: String? = null,
    val destination: String? = null,
    val date: String? = null,
    val study_weaknesses: List<String>? = null
)

@Serializable
data class ScheduleResponse(
    val summary: String,
    val itinerary: String,
    val from_cache: Boolean? = null
)

@Serializable
data class QueryResponse(
    val name: String? = null,
    val scores: Map<String, Double>? = null,
    val error: String? = null
)

@Serializable
data class AddResponse(val message: String)

@Serializable
data class DeleteResponse(val message: String)

// ========== JSON 解析器 ==========
private val json = Json { 
    prettyPrint = true
    ignoreUnknownKeys = true
    isLenient = true
}

fun main(args: Array<String>) {
    // 端口优先级: 命令行参数 > 环境变量 > config.json > 8080
    val portFromArgs = args.firstOrNull { it.startsWith("--port=") }
        ?.removePrefix("--port=")
        ?.toIntOrNull()
    val portFromEnv = System.getenv("SERVER_PORT")?.toIntOrNull()
    val port = portFromArgs ?: portFromEnv ?: EnvConfig.port

    println(">>> Kotlin 后端启动中...")
    println(">>> 端口: $port${if (portFromArgs != null) " (来自命令行)" else if (portFromEnv != null) " (来自环境变量)" else " (来自 config.json)"}")
    println(">>> 数据路径: ${EnvConfig.basePath}")
    println(">>> config.json: ${File(EnvConfig.basePath, "config.json").absolutePath}")
    println(">>> Backlog 目录: ${File(EnvConfig.basePath, "Backlog").absolutePath}")
    println(">>> PID: ${ProcessHandle.current().pid()}")

    embeddedServer(Netty, port = port, module = Application::module).start(wait = true)
}

fun Application.module() {
    install(ContentNegotiation) {
        json(json)
    }

    install(CORS) {
        anyHost()
        allowHeader(HttpHeaders.ContentType)
        allowHeader(HttpHeaders.Authorization)
        allowMethod(HttpMethod.Options)
        allowMethod(HttpMethod.Get)
        allowMethod(HttpMethod.Post)
        allowMethod(HttpMethod.Delete)
    }

    install(StatusPages) {
        exception<Throwable> { call, cause ->
            call.respondText(
                text = "{\"error\":\"${cause.message?.replace("\"", "'") ?: "Internal error"}\"}",
                contentType = ContentType.Application.Json,
                status = HttpStatusCode.InternalServerError
            )
        }
    }

    // 初始化
    val agent = AiAgent()
    val scoreService = StudentScoreService()

    routing {
        // GET /ping - 健康检查
        get("/ping") {
            println(">>> 收到 ping 请求")
            call.respond(PingResponse(status = "ok", message = "Backend is running!"))
        }

        // POST /chat - 聊天接口（流式）
        post("/chat") {
            println(">>> 收到聊天请求")
            val data = try {
                call.receive<ChatRequest>()
            } catch (e: Exception) {
                call.respond(ErrorResponse(error = "No valid JSON data"))
                return@post
            }

            val prompt = data.prompt
            if (prompt.isNullOrBlank()) {
                call.respond(ErrorResponse(error = "No prompt provided"))
                return@post
            }

            println(">>> 用户消息: $prompt")

            // 如果传入了历史消息，加载到 backlog（跳过 system，且不 resetPath 防止重复文件）
            if (data.history != null && data.history.isNotEmpty()) {
                agent.backlog.messages.clear()
                data.history.forEach { msg ->
                    val role = msg["role"] ?: "user"
                    val content = msg["content"] ?: ""
                    when (role) {
                        "user" -> agent.backlog.appendUserText(content)
                        "assistant" -> agent.backlog.appendAssistantText(content)
                        // "system" 跳过，不存入 backlog
                    }
                }
                // 沿用已有 path，追加到同一个文件；首次对话则新建 path
                if (!agent.backlog.hasPath) {
                    agent.backlog.resetPath()
                }
            }

            // 收集完整回复后一次性返回（先确保存档功能正常）
            println(">>> 正在调用 AI ...")
            val reply = StringBuilder()
            agent.streamChat(prompt) { chunk ->
                reply.append(chunk)
            }
            val replyText = reply.toString()
            println(">>> AI 回复完成 (${replyText.length} 字符)")
            call.respondText(
                text = replyText,
                contentType = ContentType.Text.Plain.withCharset(Charsets.UTF_8)
            )
        }

        // GET /query - 查询成绩
        get("/query") {
            val studentId = call.request.queryParameters["id"]
            val name = call.request.queryParameters["name"]
            println(">>> 查询请求: id=$studentId, name=$name")

            scoreService.loadData()
            val results = scoreService.queryStudents(studentId = studentId, name = name)

            if (results.isNotEmpty()) {
                val student = results[0]
                call.respond(QueryResponse(
                    name = student.name,
                    scores = student.scores
                ))
            } else {
                call.respond(QueryResponse(error = "Student not found"))
            }
        }

        // POST /add - 添加成绩
        post("/add") {
            val data = try {
                call.receive<AddScoreRequest>()
            } catch (e: Exception) {
                call.respond(ErrorResponse(error = "No valid JSON data"))
                return@post
            }

            val studentId = data.student_id ?: data.id ?: ""
            val name = data.name ?: ""
            val formattedScores = mutableMapOf<String, Double>()
            data.scores?.forEach { map ->
                map.forEach { (k, v) -> formattedScores[k] = v }
            }

            val msg = scoreService.addScore(studentId, name, formattedScores)
            call.respond(AddResponse(message = msg))
        }

        // DELETE /delete - 删除学生
        delete("/delete") {
            val studentId = call.request.queryParameters["id"]
            val name = call.request.queryParameters["name"]
            val success = scoreService.deleteStudent(studentId = studentId, name = name)
            if (success) {
                call.respond(DeleteResponse(message = "Deleted successfully"))
            } else {
                call.respond(ErrorResponse(error = "Failed to delete"))
            }
        }

        // POST /schedule - 日程规划
        post("/schedule") {
            val startTime = System.currentTimeMillis()
            try {
                val data = try {
                    call.receive<ScheduleRequest>()
                } catch (e: Exception) {
                    call.respond(ErrorResponse(error = "No valid JSON data"))
                    return@post
                }

                val tasksText = data.tasks ?: ""
                val city = data.city ?: "440100"
                val origin = data.origin
                val destination = data.destination
                val targetDate = data.date ?: "今日"
                val studyWeaknesses = data.study_weaknesses ?: emptyList()

                println(">>> 开始生成日程: $targetDate, 任务长度: ${tasksText.length}")
                val organizer = agent.tool.taskOrganizerService

                // 如果任务为空且没有学习弱点，尝试加载缓存
                if (tasksText.isBlank() && studyWeaknesses.isEmpty()) {
                    val savedContent = organizer.loadItinerary(targetDate)
                    if (savedContent != null) {
                        val lines = savedContent.lines().filter { it.isNotBlank() }
                        val summary = if (lines.isNotEmpty()) {
                            lines[0].replace("#", "").trim()
                        } else "已加载历史日程规划"
                        call.respond(ScheduleResponse(
                            summary = summary,
                            itinerary = savedContent,
                            from_cache = true
                        ))
                        return@post
                    } else if (targetDate != "今日") {
                        call.respond(ScheduleResponse(
                            summary = "",
                            itinerary = "📅 $targetDate 暂无存档，请在上方输入任务后点击生成。"
                        ))
                        return@post
                    }
                }

                // 1. 获取天气
                println("[${(System.currentTimeMillis() - startTime) / 1000.0}s] 正在请求天气...")
                val weatherRaw = agent.tool.getWeather(city)
                @Suppress("UNCHECKED_CAST")
                val weatherSummary = if (weatherRaw is Map<*, *>) {
                    organizer.summarizeWeather(weatherRaw as Map<String, Any>)
                } else {
                    com.aegis.backend.tools.task.WeatherSummary(weather = "未知")
                }
                val weatherInfo = "状况: ${weatherSummary.weather}, 温度: ${weatherSummary.temperature}°C, 风力: ${weatherSummary.wind ?: "未知"}"

                // 2. 获取路况
                println("[${(System.currentTimeMillis() - startTime) / 1000.0}s] 正在请求路况...")
                var trafficInfo = "路况未知"
                if (!origin.isNullOrBlank() && !destination.isNullOrBlank()) {
                    val tRes = agent.tool.getTraffic(origin, destination)
                    if (tRes != null) {
                        trafficInfo = "等级: ${tRes["traffic_level"] ?: "未知"}, 预计耗时: ${tRes["duration_sec"] ?: "未知"}秒"
                    }
                }

                val studyAdviceSection = if (studyWeaknesses.isNotEmpty()) {
                    val studyList = studyWeaknesses.joinToString(", ")
                    "\n【学习情况参考】：该学生薄弱学科：$studyList。请在日程中合理插入复习时间。\n"
                } else ""

                // 3. AI 规划
                println("[${(System.currentTimeMillis() - startTime) / 1000.0}s] 正在调用 AI 规划...")

                val prompt = """
                    你是一个集成了天气和交通信息的智能日程规划专家。请为用户生成一份日程规划。
                    【选定日期】：$targetDate
                    【环境参考数据】：天气: $weatherInfo; 交通: $trafficInfo
                    $studyAdviceSection
                    【待办任务】：$tasksText
                    
                    【输出要求】：
                    请严格按以下 JSON 格式返回，不要包含任何其他文字：
                    {
                      "summary": "一句话总结今日行程重点（30字以内）",
                      "detail": "完整的详细日程，包含：1. 今日天气与出行综述。2. 使用 Markdown 表格展示日程安排（列：时间、任务、地点、环境建议）。3. 结尾温馨提醒。"
                    }
                """.trimIndent()

                val apiKey = EnvConfig.activeApiKey
                val scheduleJson = JSONObject().apply {
                    put("model", EnvConfig.activeModel)
                    put("messages", listOf(
                        mapOf("role" to "user", "content" to prompt)
                    ))
                    put("temperature", 0.7)
                }

                val chatUrl = "${EnvConfig.activeBaseUrl}/chat/completions"
                val request = Request.Builder()
                    .url(chatUrl)
                    .addHeader("Authorization", "Bearer $apiKey")
                    .addHeader("Content-Type", "application/json")
                    .post(scheduleJson.toString().toRequestBody("application/json".toMediaType()))
                    .build()

                val httpClient = OkHttpClient.Builder()
                    .connectTimeout(60, TimeUnit.SECONDS)
                    .readTimeout(60, TimeUnit.SECONDS)
                    .build()

                val response = httpClient.newCall(request).execute()
                val body = response.body?.string() ?: throw Exception("AI 规划无响应")

                val respJson = JSONObject(body)
                val rawRes = respJson
                    .optJSONArray("choices")
                    ?.optJSONObject(0)
                    ?.optJSONObject("message")
                    ?.optString("content", "") ?: throw Exception("AI 规划返回为空")

                // 解析返回的 JSON
                var finalRes = rawRes.trim()
                if (finalRes.startsWith("```")) {
                    finalRes = finalRes.split("\n", limit = 2).getOrElse(1) { finalRes }
                        .split("\n").dropLast(1).joinToString("\n").trim()
                    if (finalRes.endsWith("```")) finalRes = finalRes.dropLast(3).trim()
                }

                val resData = try {
                    JSONObject(finalRes)
                } catch (_: Exception) {
                    null
                }

                val summary = resData?.optString("summary", "今日日程已准备就绪") ?: "今日日程规划"
                val detail = resData?.optString("detail", finalRes) ?: finalRes

                println("[${(System.currentTimeMillis() - startTime) / 1000.0}s] 生成成功！")

                organizer.saveItinerary(targetDate, detail)
                call.respond(ScheduleResponse(summary = summary, itinerary = detail))

            } catch (e: Exception) {
                println(">>> 日程规划接口报错: ${e.message}")
                e.printStackTrace()
                call.respond(ErrorResponse(error = e.message ?: "Unknown error"))
            }
        }

        // ========== 历史记录 ==========

        // GET /history/dates - 获取有记录的日期列表（支持 sort=asc|desc）
        get("/history/dates") {
            val sortOrder = call.request.queryParameters["sort"] ?: "desc"
            val backlogDir = File(EnvConfig.basePath, "Backlog")
            val dates = if (backlogDir.exists()) {
                val list = backlogDir.listFiles()
                    ?.filter { it.isDirectory }
                    ?.map { it.name }
                    ?: emptyList()
                if (sortOrder == "asc") list.sorted() else list.sortedDescending()
            } else emptyList()
            println(">>> 历史日期列表 (sort=$sortOrder): $dates")
            call.respond(dates)
        }

        // GET /history/list?date=YYYY-MM-DD&start_time=HH:MM&end_time=HH:MM - 获取指定日期的对话记录
        get("/history/list") {
            val dateStr = call.request.queryParameters["date"]
            if (dateStr.isNullOrBlank()) {
                call.respond(mapOf<String, Any>())
                return@get
            }
            val startTime = call.request.queryParameters["start_time"]
            val endTime = call.request.queryParameters["end_time"]
            val results = agent.backlog.loadBacklog(dateStr, startTime = startTime, endTime = endTime)
            println(">>> 加载历史记录: $dateStr, ${results.size} 条")
            call.respond(results)
        }

        // GET /history/range?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD&sort=asc|desc&start_time=HH:MM&end_time=HH:MM
        get("/history/range") {
            val startDate = call.request.queryParameters["start_date"]
            val endDate = call.request.queryParameters["end_date"]
            val sortOrder = call.request.queryParameters["sort"] ?: "desc"
            val startTime = call.request.queryParameters["start_time"]
            val endTime = call.request.queryParameters["end_time"]

            if (startDate.isNullOrBlank() || endDate.isNullOrBlank()) {
                call.respond(mapOf<String, Any>())
                return@get
            }

            val backlogDir = File(EnvConfig.basePath, "Backlog")
            if (!backlogDir.exists()) {
                call.respond(mapOf<String, Any>())
                return@get
            }

            val allDates = backlogDir.listFiles()
                ?.filter { it.isDirectory }
                ?.map { it.name }
                ?.filter { it >= startDate && it <= endDate }
                ?: emptyList()

            val sortedDates = if (sortOrder == "asc") allDates.sorted() else allDates.sortedDescending()

            val results = mutableMapOf<String, Any>()
            for (dateStr in sortedDates) {
                val dayResults = agent.backlog.loadBacklog(dateStr, startTime = startTime, endTime = endTime)
                results.putAll(dayResults)
            }
            println(">>> 加载历史记录范围: $startDate ~ $endDate (sort=$sortOrder), ${results.size} 条")
            call.respond(results)
        }
    }
}