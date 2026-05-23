package com.aegis.backend.tools

import com.aegis.backend.core.Backlog
import com.aegis.backend.core.EnvConfig
import com.aegis.backend.tools.score_management.StudentScoreService
import com.aegis.backend.tools.task.TaskOrganizer
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Agent 工具集 - 封装所有可调用工具
 */
class AgentTools {
    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    val scoreService = StudentScoreService()
    val taskOrganizerService = TaskOrganizer(this)

    /**
     * 获取天气信息
     */
    fun getWeather(adcode: String = ""): Any? {
        val targetCity = adcode.ifBlank { return null }
        val apiKey = EnvConfig.gaodeApiKey
        if (apiKey.isBlank()) {
            println("没有配置 Gaode_API_Key")
            return null
        }
        val url = "https://restapi.amap.com/v3/weather/weatherInfo?city=$targetCity&key=$apiKey"
        return try {
            val request = Request.Builder().url(url).get().build()
            val response = client.newCall(request).execute()
            val body = response.body?.string()
            if (body != null) JSONObject(body).toMap() else null
        } catch (e: Exception) {
            println("获取天气失败: ${e.message}")
            null
        }
    }

    /**
     * 获取路况信息
     */
    fun getTraffic(origin: String, destination: String, strategy: Int = 0): Map<String, Any?>? {
        val apiKey = EnvConfig.gaodeApiKey
        if (apiKey.isBlank()) {
            println("❌ 环境变量缺失：Gaode_API_Key")
            return null
        }
        if (origin.isBlank() || destination.isBlank()) return null

        val url = "https://restapi.amap.com/v3/direction/driving" +
                "?origin=$origin&destination=$destination&strategy=$strategy&extensions=all&key=$apiKey"

        return try {
            val request = Request.Builder().url(url).get().build()
            val response = client.newCall(request).execute()
            val body = response.body?.string() ?: return null
            val raw = JSONObject(body)

            var durationSec: Long? = null
            val tmcsStatusCounts = mutableMapOf<String, Int>()
            var trafficLevel = "unknown"

            val route = raw.optJSONObject("route")
            val paths = route?.optJSONArray("paths")
            if (paths != null && paths.length() > 0) {
                val path = paths.getJSONObject(0)
                durationSec = path.optLong("duration", -1).takeIf { it >= 0 }
                val steps = path.optJSONArray("steps")
                if (steps != null) {
                    for (i in 0 until steps.length()) {
                        val step = steps.getJSONObject(i)
                        val tmcs = step.optJSONArray("tmcs")
                        if (tmcs != null) {
                            for (j in 0 until tmcs.length()) {
                                val status = tmcs.getJSONObject(j).optString("status", "").trim()
                                if (status.isNotBlank()) {
                                    tmcsStatusCounts[status] = tmcsStatusCounts.getOrDefault(status, 0) + 1
                                }
                            }
                        }
                    }
                }
            }

            val bad = (tmcsStatusCounts["严重拥堵"] ?: 0) + (tmcsStatusCounts["拥堵"] ?: 0)
            val mid = tmcsStatusCounts["缓行"] ?: 0
            val good = tmcsStatusCounts["畅通"] ?: 0
            trafficLevel = when {
                bad > 0 -> "congested"
                mid > 0 -> "slow"
                good > 0 -> "good"
                else -> "unknown"
            }

            mapOf(
                "traffic_level" to trafficLevel,
                "duration_sec" to durationSec,
                "tmcs_status_counts" to tmcsStatusCounts,
                "raw" to raw.toMap()
            )
        } catch (e: Exception) {
            println("获取路况失败: ${e.message}")
            null
        }
    }

    /**
     * 通义千问联网搜索
     */
    fun qwenWebsearch(query: String): String {
        val apiKey = EnvConfig.dashscopeApiKey.ifBlank { EnvConfig.openaiApiKey }
        if (apiKey.isBlank()) return "请先在 config.json 中配置 API Key"

        val url = "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation"
        val jsonBody = JSONObject().apply {
            put("model", "qwen3.5-flash")
            put("input", JSONObject().apply {
                put("messages", listOf(
                    mapOf("role" to "user", "content" to query)
                ))
            })
            put("parameters", JSONObject().apply {
                put("enable_search", true)
            })
        }

        return try {
            val request = Request.Builder()
                .url(url)
                .addHeader("Authorization", "Bearer $apiKey")
                .addHeader("Content-Type", "application/json")
                .post(jsonBody.toString().toRequestBody("application/json".toMediaType()))
                .build()
            val response = client.newCall(request).execute()
            val body = response.body?.string() ?: return "搜索失败：无响应"
            val json = JSONObject(body)
            json.optJSONObject("output")?.optString("text", "")?.trim() ?: "搜索失败"
        } catch (e: Exception) {
            "搜索失败：${e.message}"
        }
    }

    /**
     * 查询学生成绩
     */
    fun queryScore(studentId: String? = null, name: String? = null): List<Map<String, Any>> {
        return scoreService.queryStudents(studentId = studentId, name = name).map { it ->
            mapOf(
                "student_id" to it.student_id,
                "name" to it.name,
                "scores" to it.scores
            )
        }
    }

    /**
     * 录入/更新成绩
     */
    fun addScore(studentId: String, name: String, scores: Map<String, Double>): String {
        return scoreService.addScore(studentId, name, scores)
    }

    /**
     * 删除学生
     */
    fun deleteScore(studentId: String? = null, name: String? = null): String {
        val success = scoreService.deleteStudent(studentId = studentId, name = name)
        return if (success) "删除成功" else "未找到对应学生或删除失败"
    }

    /**
     * 获取本地对话记录
     */
    fun getLocalBacklog(backlog: Backlog) {
        println(backlog.getText())
    }

    /**
     * 加载对话记录
     */
    fun loadBacklog(backlog: Backlog, targetDate: String): Map<String, Backlog.ChatHistoryResult> {
        return backlog.loadBacklog(targetDate)
    }

    /**
     * 日程规划
     */
    fun taskOrganizer(tasks: List<String>): String {
        val tasksText = tasks.joinToString("\n")
        return taskOrganizerService.generateTodayItinerary(tasksText, cityAdcode = "440100")
    }
}

/**
 * JSONObject 转 Map 的辅助扩展
 */
fun JSONObject.toMap(): Map<String, Any> {
    val map = mutableMapOf<String, Any>()
    this.keys().forEach { key ->
        val value = this[key]
        map[key] = when (value) {
            is JSONObject -> value.toMap()
            is org.json.JSONArray -> {
                (0 until value.length()).map { i ->
                    val item = value[i]
                    if (item is JSONObject) item.toMap() else item
                }
            }
            else -> value
        }
    }
    return map
}
