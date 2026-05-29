@file:OptIn(kotlinx.serialization.InternalSerializationApi::class)

package com.aegis.backend

import com.aegis.backend.core.AiAgent
import com.aegis.backend.core.EnvConfig
import com.aegis.backend.tools.score_management.StudentScoreService
import com.aegis.backend.tools.score_management.StudentData
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
import kotlinx.serialization.SerialName
import kotlinx.serialization.encodeToString
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
    val error: String? = null,
    val students: List<StudentData>? = null
)

@Serializable
data class AddResponse(val message: String)

@Serializable
data class DeleteResponse(val message: String)

@Serializable
data class OcrRequest(
    val image: String = "",
    @kotlinx.serialization.SerialName("enable_formula")
    val enableFormula: Boolean = true
)

@Serializable
data class EncouragementRequest(
    val grade: String = "不合格",
    @kotlinx.serialization.SerialName("student_name")
    val studentName: String = "同学",
    @kotlinx.serialization.SerialName("matched_count")
    val matchedCount: Int = 0,
    @kotlinx.serialization.SerialName("completed_schedules")
    val completedSchedules: Int = 0,
    @kotlinx.serialization.SerialName("total_schedules")
    val totalSchedules: Int = 0
)

@Serializable
data class StudyQueryRequest(
    @kotlinx.serialization.SerialName("start_date")
    val startDate: String = "",
    @kotlinx.serialization.SerialName("end_date")
    val endDate: String = "",
    val keywords: String = ""
)

@Serializable
data class StudySummaryRequest(
    val date: String = "",
    @kotlinx.serialization.SerialName("matched_count")
    val matchedCount: Int = 0,
    @kotlinx.serialization.SerialName("total_schedules")
    val totalSchedules: Int = 0,
    @kotlinx.serialization.SerialName("completed_schedules")
    val completedSchedules: Int = 0
)

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
            val errorMsg = cause.message ?: "Internal error"
            val errorJson = json.encodeToString(ErrorResponse(error = errorMsg))
            call.respondText(
                text = errorJson,
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
            } catch (_: Exception) {
                call.respond(ErrorResponse(error = "No valid JSON data"))
                return@post
            }

            val prompt = data.prompt
            if (prompt.isNullOrBlank()) {
                call.respond(ErrorResponse(error = "No prompt provided"))
                return@post
            }

            println(">>> 用户消息: $prompt")

            // 如果传入了历史消息，加载到 backlog（不 resetPath 防止重复文件）
            if (data.history != null && data.history.isNotEmpty()) {
                agent.backlog.messages.clear()
                data.history.forEach { msg ->
                    val role = msg["role"] ?: "user"
                    val content = msg["content"] ?: ""
                    when (role) {
                        "user" -> agent.backlog.appendUserText(content)
                        "assistant" -> agent.backlog.appendAssistantText(content)
                        "system" -> agent.backlog.appendSystemText(content)
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
                if (results.size == 1) {
                    val student = results[0]
                    call.respond(QueryResponse(
                        name = student.name,
                        scores = student.scores
                    ))
                } else {
                    call.respond(QueryResponse(students = results))
                }
            } else {
                call.respond(QueryResponse(error = "Student not found"))
            }
        }

        // POST /add - 添加成绩
        post("/add") {
            try {
                val data = call.receive<AddScoreRequest>()
                val studentId = data.student_id ?: data.id ?: ""
                val name = data.name ?: ""
                val formattedScores = mutableMapOf<String, Double>()
                data.scores?.forEach { map ->
                    map.forEach { (k, v) -> formattedScores[k] = v }
                }
                val msg = scoreService.addScore(studentId, name, formattedScores)
                call.respond(AddResponse(message = msg))
            } catch (e: Exception) {
                println(">>> /add 异常: ${e.message}")
                call.respond(ErrorResponse(error = "提交失败: ${e.message}"))
            }
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

        // DELETE /delete/subject - 删除单科成绩
        delete("/delete/subject") {
            val studentId = call.request.queryParameters["id"] ?: ""
            val subject = call.request.queryParameters["subject"] ?: ""
            if (studentId.isBlank() || subject.isBlank()) {
                call.respond(ErrorResponse(error = "id and subject are required"))
                return@delete
            }
            val success = scoreService.deleteSubjectScore(studentId = studentId, subject = subject)
            if (success) {
                call.respond(DeleteResponse(message = "Subject deleted successfully"))
            } else {
                call.respond(ErrorResponse(error = "Failed to delete subject"))
            }
        }

        // POST /schedule - 日程规划
        post("/schedule") {
            val startTime = System.currentTimeMillis()
            try {
                val data = try {
                    call.receive<ScheduleRequest>()
                } catch (_: Exception) {
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
            val isSingleDay = startDate == endDate

            val results = mutableMapOf<String, Any>()
            for (dateStr in sortedDates) {
                // 时间过滤逻辑：
                //   - 起始日期：只限制 ≥ startTime
                //   - 结束日期：只限制 ≤ endTime
                //   - 中间日期：不限制时间
                val dayStartTime = when {
                    isSingleDay -> startTime
                    dateStr == startDate -> startTime
                    else -> null
                }
                val dayEndTime = when {
                    isSingleDay -> endTime
                    dateStr == endDate -> endTime
                    else -> null
                }
                val dayResults = agent.backlog.loadBacklog(dateStr, startTime = dayStartTime, endTime = dayEndTime)
                results.putAll(dayResults)
            }
            println(">>> 加载历史记录范围: $startDate ~ $endDate (sort=$sortOrder), ${results.size} 条")
            call.respond(results)
        }

        // ========== OCR 识别 ==========

        // POST /api/ocr - OCR 识别（Base64 图片）
        post("/api/ocr") {
            try {
                val data = call.receive<OcrRequest>()
                val imageBase64 = data.image
                val enableFormula = data.enableFormula

                if (imageBase64.isBlank()) {
                    call.respond(ErrorResponse(error = "请提供图片数据（Base64编码）"))
                    return@post
                }

                println(">>> OCR 请求: 图片大小=${imageBase64.length}字符, 启用公式识别=$enableFormula")

                val ocrService = com.aegis.backend.tools.ocr.OcrService()
                val result = ocrService.recognize(imageBase64, enableFormulaAI = enableFormula)

                call.respond(mapOf(
                    "text" to result.text,
                    "formula_source" to (result.formulaSource ?: ""),
                    "error" to (result.error ?: "")
                ))
            } catch (e: Exception) {
                println(">>> OCR 接口报错: ${e.message}")
                call.respond(ErrorResponse(error = "OCR 识别失败: ${e.message}"))
            }
        }

        // GET /api/ocr/check - 检查 OCR 环境
        get("/api/ocr/check") {
            val ocrService = com.aegis.backend.tools.ocr.OcrService()
            val envInfo = ocrService.checkEnvironment()
            call.respond(envInfo)
        }

        // ========== 学习分析 API ==========

        // POST /api/study/encouragement - AI 生成鼓励语
        post("/api/study/encouragement") {
            try {
                val body = call.receive<EncouragementRequest>()
                val grade = body.grade
                val studentName = body.studentName
                val matchedCount = body.matchedCount
                val completedSchedules = body.completedSchedules
                val totalSchedules = body.totalSchedules

                println(">>> 学习分析 - 生成鼓励语: grade=$grade, student=$studentName")

                // 使用 AI 生成鼓励语
                val apiKey = EnvConfig.activeApiKey
                val baseUrl = EnvConfig.activeBaseUrl
                val model = EnvConfig.activeModel

                if (apiKey.isBlank() || baseUrl.isBlank()) {
                    // 回退到本地规则
                    val encouragement = generateLocalEncouragement(
                        grade = grade,
                        studentName = studentName,
                        matchedCount = matchedCount,
                        completedSchedules = completedSchedules,
                        totalSchedules = totalSchedules
                    )
                    call.respond(mapOf("encouragement" to encouragement))
                    return@post
                }

                val chatUrl = "$baseUrl/chat/completions"
                val scheduleRate = if (totalSchedules > 0) completedSchedules.toDouble() / totalSchedules else 0.0

                val prompt = """
                    你是一个温暖、鼓励人的学习导师。请根据以下学生学习数据，生成一段30-100字的鼓励语。
                    
                    学生姓名：$studentName
                    等级：$grade
                    今日学习相关提问：$matchedCount 次
                    日程完成：$completedSchedules / $totalSchedules（完成率 ${(scheduleRate * 100).toInt()}%）
                    
                    等级说明：
                    - 优秀：学习非常积极
                    - 良好：学习状态不错
                    - 合格：还需更多努力
                    - 不合格：几乎没有学习记录
                    
                    请直接输出鼓励语，不要包含任何其他文字。
                """.trimIndent()

                val requestBody = JSONObject().apply {
                    put("model", model)
                    put("messages", listOf(
                        mapOf("role" to "user", "content" to prompt)
                    ))
                    put("temperature", 0.7)
                }

                val request = Request.Builder()
                    .url(chatUrl)
                    .addHeader("Authorization", "Bearer $apiKey")
                    .addHeader("Content-Type", "application/json")
                    .post(requestBody.toString().toRequestBody("application/json".toMediaType()))
                    .build()

                val client = OkHttpClient.Builder()
                    .connectTimeout(30, TimeUnit.SECONDS)
                    .readTimeout(60, TimeUnit.SECONDS)
                    .build()

                val response = client.newCall(request).execute()
                val respBody = response.body?.string() ?: throw Exception("AI 无响应")
                val respJson = JSONObject(respBody)
                val encouragement = respJson
                    .optJSONArray("choices")
                    ?.optJSONObject(0)
                    ?.optJSONObject("message")
                    ?.optString("content", "")
                    ?.trim()

                if (encouragement.isNullOrBlank()) {
                    throw Exception("AI 返回为空")
                }

                call.respond(mapOf("encouragement" to encouragement))
            } catch (e: Exception) {
                println(">>> 鼓励语生成失败: ${e.message}")
                // 回退到本地规则
                call.respond(mapOf(
                    "encouragement" to "同学，今天的努力是明天的基石，继续加油！",
                    "fallback" to true
                ))
            }
        }

        // POST /api/study/query - 关键词匹配对话记录查询
        post("/api/study/query") {
            try {
                val body = call.receive<StudyQueryRequest>()
                val startDate = body.startDate
                val endDate = body.endDate
                val keywordsRaw = body.keywords

                if (startDate.isBlank() || endDate.isBlank()) {
                    call.respond(ErrorResponse(error = "请提供 start_date 和 end_date"))
                    return@post
                }

                val keywords = keywordsRaw.split(",").map { it.trim() }.filter { it.isNotBlank() }
                if (keywords.isEmpty()) {
                    call.respond(emptyList<Any>())
                    return@post
                }

                println(">>> 学习分析 - 查询记录: $startDate ~ $endDate, 关键词=$keywords")

                val backlogDir = File(EnvConfig.basePath, "Backlog")
                if (!backlogDir.exists()) {
                    call.respond(emptyList<Any>())
                    return@post
                }

                val results = mutableListOf<Map<String, Any>>()
                val dateDirs = backlogDir.listFiles()
                    ?.filter { it.isDirectory && it.name >= startDate && it.name <= endDate }
                    ?.sorted() ?: emptyList()

                for (dateDir in dateDirs) {
                    val dateStr = dateDir.name
                    val files = dateDir.listFiles()
                        ?.filter { it.name.endsWith(".json") }
                        ?.sorted() ?: emptyList()

                    for (file in files) {
                        try {
                            val content = file.readText(Charsets.UTF_8)
                            val json = JSONObject(content)
                            val messages = json.optJSONArray("messages")
                            val summary = json.optString("summary", "")

                            if (messages == null) continue

                            var userMsg: String? = null
                            for (i in 0 until messages.length()) {
                                val msg = messages.getJSONObject(i)
                                val role = msg.optString("role", "")
                                val text = msg.optString("content", "")

                                if (role == "user") {
                                    userMsg = text
                                } else if (role == "assistant" && userMsg != null) {
                                    val matchedKws = keywords.filter { text.contains(it) }
                                    if (matchedKws.isNotEmpty()) {
                                        val timeStr = file.nameWithoutExtension
                                        results.add(mapOf(
                                            "date" to dateStr,
                                            "time" to timeStr,
                                            "summary" to summary,
                                            "user_message" to userMsg,
                                            "ai_response" to text,
                                            "matched_keywords" to matchedKws
                                        ))
                                    }
                                    userMsg = null
                                }
                            }
                        } catch (_: Exception) { }
                    }
                }

                println(">>> 查询完成: ${results.size} 条匹配记录")
                call.respond(results)
            } catch (e: Exception) {
                println(">>> 学习分析查询失败: ${e.message}")
                call.respond(ErrorResponse(error = "查询失败: ${e.message}"))
            }
        }

        // POST /api/study/summary - 学习总结生成
        post("/api/study/summary") {
            try {
                val body = call.receive<StudySummaryRequest>()
                val date = body.date
                val matchedCount = body.matchedCount
                val totalSchedules = body.totalSchedules
                val completedSchedules = body.completedSchedules

                if (date.isBlank()) {
                    call.respond(ErrorResponse(error = "请提供 date"))
                    return@post
                }

                println(">>> 学习分析 - 生成总结: date=$date, matched=$matchedCount")

                val scheduleRate = if (totalSchedules > 0) completedSchedules.toDouble() / totalSchedules else 1.0

                // 评分算法（与前端一致）
                var score = 0.0
                if (matchedCount >= 20) score += 50
                else if (matchedCount >= 10) score += 40
                else if (matchedCount >= 5) score += 30
                else if (matchedCount >= 3) score += 20
                else if (matchedCount >= 1) score += 10

                score += scheduleRate * 50

                val grade = when {
                    score >= 85 -> "优秀"
                    score >= 65 -> "良好"
                    score >= 45 -> "合格"
                    else -> "不合格"
                }

                call.respond(mapOf(
                    "date" to date,
                    "matched_count" to matchedCount,
                    "total_schedules" to totalSchedules,
                    "completed_schedules" to completedSchedules,
                    "grade" to grade,
                    "score" to score
                ))
            } catch (e: Exception) {
                println(">>> 学习总结生成失败: ${e.message}")
                call.respond(ErrorResponse(error = "生成失败: ${e.message}"))
            }
        }
    }
}

/**
 * 本地规则生成鼓励语（备用方案）
 */
private fun generateLocalEncouragement(
    grade: String,
    studentName: String,
    matchedCount: Int,
    completedSchedules: Int,
    totalSchedules: Int
): String {
    val scheduleRate = if (totalSchedules > 0) completedSchedules.toDouble() / totalSchedules else 0.0
    return when (grade) {
        "优秀" -> {
            if (scheduleRate >= 0.8) "${studentName}同学，今天你真是太棒了！不仅积极提问学习(${matchedCount}条匹配)，还高效完成了日程计划，继续保持这种优秀的状态！"
            else "${studentName}同学，你今天的学习热情让人感动！提出了${matchedCount}个与学习相关的问题，继续保持，卓越就在前方！"
        }
        "良好" -> "${studentName}同学，今天表现不错哦！有${matchedCount}条学习相关的对话记录，整体状态良好。明天再加把劲，争取更上一层楼！"
        "合格" -> "${studentName}同学，今天的学习状态还可以，有${matchedCount}条匹配记录。学习是一场马拉松，贵在坚持！"
        else -> "${studentName}同学，今天似乎没有留下学习记录呢。学习需要持之以恒，即使每天只学一点点，长期积累也会有惊人的效果。一起加油吧！"
    }
}