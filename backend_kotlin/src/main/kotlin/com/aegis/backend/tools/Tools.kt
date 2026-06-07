package com.aegis.backend.tools

import com.aegis.backend.core.Backlog
import com.aegis.backend.core.ChatHistoryResult
import com.aegis.backend.core.EnvConfig
import com.aegis.backend.tools.precise_search.PreciseSearch
import com.aegis.backend.tools.score_management.StudentScoreService
import kotlinx.serialization.json.JsonElement
import com.aegis.backend.tools.task.TaskOrganizer
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
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
    private val preciseSearch = PreciseSearch()

    /**
     * 获取天气信息
     */
    /**
     * 通过高德地理编码 API 将中文地名解析为 adcode（区域编码）
     * 支持省/市/区级单位，例如"汕头"→440500、"濠江区"→440512
     * 高德天气 API 要求使用 adcode，不支持中文城市名直接查询
     */
    private fun getAdcodeByCityName(cityName: String): String? {
        val apiKey = EnvConfig.gaodeApiKey
        if (apiKey.isBlank()) return null
        // 不传 city 参数，让高德自动匹配省市区各级
        val url = "https://restapi.amap.com/v3/geocode/geo?address=$cityName&key=$apiKey"
        return try {
            val request = Request.Builder().url(url).get().build()
            val response = client.newCall(request).execute()
            val body = response.body?.string() ?: return null
            val json = JSONObject(body)
            if (json.optString("status") != "1") {
                println(">>> 高德地理编码API返回失败: ${json.optString("info")} (city=$cityName)")
                return null
            }
            val geocodes = json.optJSONArray("geocodes")
            if (geocodes == null || geocodes.length() == 0) {
                println(">>> 未找到 $cityName 的 adcode")
                return null
            }
            // 取第一个匹配结果的 adcode（区域编码），支持省/市/区各级
            val adcode = geocodes.getJSONObject(0).optString("adcode").ifBlank { null }
            if (adcode != null) {
                println(">>> 地理编码: 「$cityName」→ adcode=$adcode")
            }
            adcode
        } catch (e: Exception) {
            println(">>> 获取adcode失败: ${e.message}")
            null
        }
    }

    fun getWeather(adcode: String = ""): Any? {
        var targetCity = adcode.ifBlank { return null }
        val apiKey = EnvConfig.gaodeApiKey
        if (apiKey.isBlank()) {
            println("没有配置 Gaode_API_Key")
            return null
        }
        // 如果传入了中文城市名（非纯数字），先通过地理编码转换为 adcode
        if (targetCity.any { it in '0'..'9' }.not()) {
            val resolved = getAdcodeByCityName(targetCity)
            if (resolved != null) {
                println(">>> 城市名「$targetCity」→ adcode: $resolved")
                targetCity = resolved
            } else {
                println(">>> 警告：无法解析城市名「$targetCity」，直接传参尝试")
            }
        }
        val url = "https://restapi.amap.com/v3/weather/weatherInfo?city=$targetCity&key=$apiKey"
        return try {
            val request = Request.Builder().url(url).get().build()
            val response = client.newCall(request).execute()
            val body = response.body?.string() ?: return null
            val json = JSONObject(body)
            // 检查高德 API 返回状态：0=失败
            val status = json.optString("status", "0")
            val info = json.optString("info", "")
            if (status != "1") {
                println(">>> 高德天气API返回失败: $info (city=$targetCity)")
                return null
            }
            json.toDeepMap()
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
                "raw" to raw.toDeepMap()
            )
        } catch (e: Exception) {
            println("获取路况失败: ${e.message}")
            null
        }
    }

    /**
     * 联网搜索 — 优先使用 WEB_SEARCH_CONFIG 配置，回退旧版 DashScope 逻辑
     */
    fun webSearch(query: String): String {
        val cfg = EnvConfig.webSearchConfig
        val apiKey = cfg.apiKey.ifBlank {
            EnvConfig.dashscopeApiKey.ifBlank { EnvConfig.openaiApiKey }
        }
        if (apiKey.isBlank()) return "请先在 config.json 中配置 WEB_SEARCH_CONFIG 或 DASHSCOPE_API_KEY"

        val url = cfg.baseUrl.ifBlank {
            "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation"
        }
        val model = cfg.model.ifBlank { "qwen3.5-flash" }

        val jsonBody = JSONObject().apply {
            put("model", model)
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
            // 先检查 API 是否返回了错误
            if (json.has("code")) {
                val code = json.optString("code", "")
                val msg = json.optString("message", "")
                return "搜索失败：[$code] $msg"
            }
            val text = json.optJSONObject("output")?.optString("text", "")?.trim()
            if (text.isNullOrEmpty()) {
                return "搜索失败：API 返回异常\n$body"
            }
            text
        } catch (e: Exception) {
            "搜索失败：${e.message}"
        }
    }

    /**
     * 通义千问联网搜索（旧名兼容，委托到 webSearch）
     */
    fun qwenWebsearch(query: String): String = webSearch(query)

    /**
     * 精准搜索 — 接收关键词，AI 扩展联想词后在 backlog JSON 文件中匹配
     * @param keyword 搜索关键词
     * @return 格式化的搜索结果文本
     */
    fun preciseSearch(keyword: String): String {
        return preciseSearch.search(keyword)
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
    fun addScore(studentId: String, name: String, scores: Map<String, JsonElement>): String {
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
    fun loadBacklog(backlog: Backlog, targetDate: String): Map<String, ChatHistoryResult> {
        return backlog.loadBacklog(targetDate)
    }

    /**
     * 根据IP地址获取地理位置信息（基于高德地图API）
     */
    fun locateIp(ip: String = ""): Any? {
        val apiKey = EnvConfig.gaodeApiKey
        if (apiKey.isBlank()) {
            println("❌ 环境变量缺失：Gaode_API_Key")
            return null
        }

        val url = if (ip.isNotBlank()) {
            "https://restapi.amap.com/v3/ip?key=$apiKey&ip=$ip"
        } else {
            "https://restapi.amap.com/v3/ip?key=$apiKey"
        }

        return try {
            val request = Request.Builder().url(url).get().build()
            val response = client.newCall(request).execute()
            val body = response.body?.string()
            if (body != null) JSONObject(body).toDeepMap() else null
        } catch (e: Exception) {
            println("获取IP定位失败: ${e.message}")
            null
        }
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
 * JSONObject 递归转 Map 的辅助扩展（org.json 内置 toMap() 不会递归转换嵌套对象）
 */
fun JSONObject.toDeepMap(): Map<String, Any> {
    val map = mutableMapOf<String, Any>()
    this.keys().forEach { key ->
        val value = this[key]
        map[key] = when (value) {
            is JSONObject -> value.toDeepMap()
            is org.json.JSONArray -> {
                (0 until value.length()).map { i ->
                    val item = value[i]
                    if (item is JSONObject) item.toDeepMap() else item
                }
            }
            else -> value
        }
    }
    return map
}
