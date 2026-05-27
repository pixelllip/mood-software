@file:OptIn(kotlinx.serialization.InternalSerializationApi::class)

package com.aegis.backend.tools.score_management

import com.aegis.backend.core.EnvConfig
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.json.JSONObject
import java.io.File

@Serializable
data class StudentData(
    val student_id: String,
    val name: String,
    val scores: Map<String, Double> = emptyMap()
)

class StudentScoreService {
    private val json = Json { prettyPrint = true; ignoreUnknownKeys = true }
    private val dataFile: File
    var students: MutableList<StudentData> = mutableListOf()

    constructor(dataFileName: String = "students.json") {
        val scoreDir = File(EnvConfig.basePath, "Score_info")
        scoreDir.mkdirs()
        dataFile = File(scoreDir, dataFileName)
        loadData()
    }

    /** 安全地将任意 score 值转为 Double */
    private fun toDoubleSafe(value: Any?): Double {
        return when (value) {
            is Number -> value.toDouble()
            is String -> value.toDoubleOrNull() ?: 0.0
            else -> 0.0
        }
    }

    /** 从 JSON 安全加载（兼容字符串分数） */
    fun loadData() {
        try {
            if (!dataFile.exists()) {
                students = mutableListOf()
                return
            }
            val text = dataFile.readText(Charsets.UTF_8)
            val rawArray = org.json.JSONArray(text)
            students = mutableListOf()
            for (i in 0 until rawArray.length()) {
                val obj = rawArray.getJSONObject(i)
                val sid = obj.optString("student_id", "")
                val name = obj.optString("name", "")
                val scoresJson = obj.optJSONObject("scores") ?: JSONObject()
                val scores = mutableMapOf<String, Double>()
                for (key in scoresJson.keys()) {
                    scores[key] = toDoubleSafe(scoresJson.get(key))
                }
                students.add(StudentData(student_id = sid, name = name, scores = scores))
            }
        } catch (_: Exception) {
            students = mutableListOf()
        }
    }

    fun saveData() {
        dataFile.parentFile.mkdirs()
        dataFile.writeText(json.encodeToString(students), Charsets.UTF_8)
    }

    fun addScore(studentId: String, name: String, scores: Map<String, Double>): String {
        // 匹配规则：同学号 + 同姓名 → 合并；同学号 + 不同姓名 → 新建
        val existing = students.find { it.student_id == studentId && it.name == name }
        return if (existing != null) {
            val merged = existing.scores.toMutableMap()
            merged.putAll(scores)
            val idx = students.indexOf(existing)
            students[idx] = existing.copy(scores = merged)
            saveData()
            "已为学生 [$name] 更新/合并成绩。"
        } else {
            students.add(StudentData(student_id = studentId, name = name, scores = scores))
            saveData()
            "成功录入新学生：$name"
        }
    }

    fun deleteStudent(studentId: String? = null, name: String? = null): Boolean {
        val initialCount = students.size
        students = if (studentId != null) {
            students.filter { it.student_id != studentId }.toMutableList()
        } else if (name != null) {
            students.filter { it.name != name }.toMutableList()
        } else students

        if (students.size < initialCount) {
            saveData()
            return true
        }
        return false
    }

    fun deleteSubjectScore(studentId: String, subject: String): Boolean {
        val idx = students.indexOfFirst { it.student_id == studentId }
        if (idx < 0) return false

        val existing = students[idx]
        val updatedScores = existing.scores.toMutableMap()
        if (!updatedScores.containsKey(subject)) return false

        updatedScores.remove(subject)
        students[idx] = existing.copy(scores = updatedScores)
        saveData()
        return true
    }

    fun queryStudents(studentId: String? = null, name: String? = null): List<StudentData> {
        loadData() // 确保最新数据

        var result = students.toList()
        if (studentId != null) {
            result = result.filter { it.student_id == studentId }
        }
        if (name != null) {
            result = result.filter { name.lowercase() in it.name.lowercase() }
        }
        return result
    }
}
