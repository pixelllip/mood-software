package com.aegis.backend.tools.task

import com.aegis.backend.core.EnvConfig
import com.aegis.backend.tools.AgentTools
import java.io.File

data class TaskItem(
    val title: String,
    val timeHint: String? = null,
    val isOutdoor: Boolean? = null,
    val destination: String? = null,
    val flexible: Boolean = true
)

data class WeatherSummary(
    val weather: String,
    val temperature: Double? = null,
    val humidity: Double? = null,
    val wind: String? = null
)

data class TrafficSummary(
    val durationSec: Long? = null,
    val trafficLevel: String = "unknown",
    val tmcsStatusCounts: Map<String, Int>? = null
)

class TaskOrganizer(private val tools: AgentTools) {

    fun parseTasksText(text: String): List<TaskItem> {
        val tasks = mutableListOf<TaskItem>()
        text.lines().forEach { raw ->
            val line = raw.trim()
            if (line.isBlank()) return@forEach

            var timeHint: String? = null
            var isOutdoor: Boolean? = null
            var modifiedLine = line
            val lowered = line.lowercase()

            when {
                listOf("早上", "上午", "早晨").any { it in line } -> timeHint = "早上"
                listOf("中午", "午间", "下午").any { it in line } -> timeHint = "中午"
                listOf("晚上", "夜间", "傍晚").any { it in line } -> timeHint = "晚上"
            }

            if ("@outdoor" in lowered || "户外" in line || "出门" in line) {
                isOutdoor = true
                modifiedLine = modifiedLine.replace("@outdoor", "", ignoreCase = true).trim()
            } else if ("@indoor" in lowered || "室内" in line || "在办公" in line) {
                isOutdoor = false
                modifiedLine = modifiedLine.replace("@indoor", "", ignoreCase = true).trim()
            }

            tasks.add(TaskItem(title = modifiedLine, timeHint = timeHint, isOutdoor = isOutdoor))
        }
        return tasks
    }

    fun summarizeWeather(amapWeatherJson: Map<String, Any>): WeatherSummary {
        val lives = (amapWeatherJson["lives"] as? List<*>)?.filterIsInstance<Map<String, Any>>() ?: emptyList()
        if (lives.isEmpty()) return WeatherSummary(weather = "unknown")

        val live = lives[0]
        val weather = live["weather"] as? String ?: "unknown"
        val temp = (live["temperature"] as? String)?.toDoubleOrNull()
        val hum = (live["humidity"] as? String)?.toDoubleOrNull()
        val windDir = live["winddirection"] as? String ?: ""
        val windPow = live["windpower"] as? String ?: ""
        val wind = if (windDir.isNotBlank() || windPow.isNotBlank()) "$windDir$windPow" else null

        return WeatherSummary(weather = weather, temperature = temp, humidity = hum, wind = wind)
    }

    fun weatherRiskFlags(w: WeatherSummary): Map<String, Boolean> {
        val weather = w.weather.orEmpty()
        val rainy = listOf("雨", "雷", "阵雨").any { it in weather }
        val snowy = "雪" in weather
        val foggy = listOf("雾", "霾", "尘", "沙").any { it in weather }
        val temp = w.temperature
        val hot = temp != null && temp >= 34.0
        val veryHot = temp != null && temp >= 38.0
        val cold = temp != null && temp <= 5.0
        val veryCold = temp != null && temp <= -5.0

        return mapOf(
            "rainy" to rainy, "snowy" to snowy, "foggy" to foggy,
            "hot" to hot, "very_hot" to veryHot,
            "cold" to cold, "very_cold" to veryCold
        )
    }

    fun decideTodayPlan(
        tasks: List<TaskItem>,
        weather: WeatherSummary,
        traffic: TrafficSummary
    ): Pair<List<TaskItem>, List<String>> {
        val flags = weatherRiskFlags(weather)
        val notes = mutableListOf<String>()

        if (weather.weather != "unknown") {
            notes.add("天气：${weather.weather}${weather.temperature?.let { " ${it}°C" } ?: ""}")
        }
        if (traffic.trafficLevel != "unknown") {
            notes.add("路况：${traffic.trafficLevel}")
        }

        fun score(t: TaskItem): Double {
            var s = 0.0
            // 降水影响
            if (flags["rainy"] == true || flags["snowy"] == true) {
                if (t.isOutdoor == true) s -= 6.0
                if (t.isOutdoor == false) s += 1.5
            }
            // 极端气温
            if (flags["very_hot"] == true || flags["very_cold"] == true) {
                if (t.isOutdoor == true) s -= 8.0
            } else if (flags["hot"] == true) {
                if (t.isOutdoor == true && (t.timeHint == null || t.timeHint == "中午")) s -= 4.0
            } else if (flags["cold"] == true) {
                if (t.isOutdoor == true) s -= 2.0
            }
            // 能见度
            if (flags["foggy"] == true) {
                if (t.isOutdoor == true) s -= 3.0
                if (t.destination != null) s -= 2.0
            }
            // 路况
            when (traffic.trafficLevel) {
                "congested" -> {
                    if (t.destination != null || t.isOutdoor == true) s -= 3.0
                    if (t.flexible) s += 1.0
                }
                "good" -> {
                    if (t.destination != null) s += 1.0
                }
            }
            // 时间约束
            if (t.timeHint != null) s += 0.5
            return s
        }

        // 按评分排序
        val sortedTasks = tasks.sortedByDescending { score(it) }

        // 生成建议
        if (flags["rainy"] == true) notes.add("建议：今日有雨，出门请备好雨具，尽量安排室内活动。")
        if (flags["snowy"] == true) notes.add("建议：有降雪，路面湿滑，建议减少不必要的户外行程。")
        if (flags["very_hot"] == true) notes.add("建议：气温极高，谨防中暑，尽量留在室内空调环境。")
        else if (flags["hot"] == true) notes.add("建议：天气炎热，午后尽量避免高强度户外运动。")
        if (flags["foggy"] == true) notes.add("建议：空气质量欠佳或能见度低，建议佩戴口罩，驾驶注意安全。")
        if (traffic.trafficLevel == "congested") notes.add("建议：当前路况拥堵，建议避开高峰期或搭乘公共交通。")

        return Pair(sortedTasks, notes)
    }

    fun buildPlanText(tasks: List<TaskItem>, notes: List<String>): String {
        val lines = mutableListOf<String>()

        if (notes.isNotEmpty()) {
            lines.add("【环境提醒】")
            notes.forEach { lines.add("• $it") }
            lines.add("")
        }

        if (tasks.isEmpty()) {
            lines.add("📅 今日暂无待办事项。")
            return lines.joinToString("\n").trim()
        }

        val buckets = mapOf(
            "早上" to mutableListOf<TaskItem>(),
            "中午" to mutableListOf(),
            "晚上" to mutableListOf(),
            "全天/未指定" to mutableListOf()
        )
        tasks.forEach { t ->
            val key = if (t.timeHint in listOf("早上", "中午", "晚上")) t.timeHint else "全天/未指定"
            buckets[key]?.add(t)
        }

        lines.add("📅 今日行程规划建议：")
        listOf("早上", "中午", "晚上", "全天/未指定").forEach { key ->
            val bucket = buckets[key] ?: return@forEach
            if (bucket.isEmpty()) return@forEach
            lines.add("\n[$key]")
            bucket.forEachIndexed { i, t ->
                val tag = when (t.isOutdoor) {
                    true -> " 📍户外"
                    false -> " 🏠室内"
                    null -> ""
                }
                lines.add("${i + 1}. ${t.title}$tag")
            }
        }

        return lines.joinToString("\n").trim()
    }

    fun generateTodayItinerary(
        tasksText: String,
        cityAdcode: String,
        origin: String? = null,
        destination: String? = null
    ): String {
        val tasks = parseTasksText(tasksText)
        if (tasks.isEmpty()) return "请输入您的任务列表。例如：\n早上 跑步 @outdoor\n中午 办公 @indoor"

        val weatherJson = tools.getWeather(cityAdcode) ?: return "无法获取天气信息"
        @Suppress("UNCHECKED_CAST")
        val weather = summarizeWeather(weatherJson as Map<String, Any>)

        var traffic = TrafficSummary()
        if (origin != null && destination != null) {
            val trafficRaw = tools.getTraffic(origin, destination)
            if (trafficRaw != null) {
                @Suppress("UNCHECKED_CAST")
                val tMap = trafficRaw as Map<String, Any>
                traffic = TrafficSummary(
                    durationSec = (tMap["duration_sec"] as? Number)?.toLong(),
                    trafficLevel = tMap["traffic_level"] as? String ?: "unknown"
                )
            }
        }

        val (planned, notes) = decideTodayPlan(tasks, weather, traffic)
        return buildPlanText(planned, notes)
    }

    fun saveItinerary(dateStr: String, content: String) {
        val scheduleDir = File(EnvConfig.basePath, "Schedule")
        scheduleDir.mkdirs()
        val safeDate = dateStr.replace(" ", "_").replace("/", "-").replace(":", "-")
        File(scheduleDir, "$safeDate.md").writeText(content, Charsets.UTF_8)
    }

    fun loadItinerary(dateStr: String): String? {
        val safeDate = dateStr.replace(" ", "_").replace("/", "-").replace(":", "-")
        val file = File(EnvConfig.basePath, "Schedule/$safeDate.md")
        return if (file.exists()) file.readText(Charsets.UTF_8) else null
    }
}
