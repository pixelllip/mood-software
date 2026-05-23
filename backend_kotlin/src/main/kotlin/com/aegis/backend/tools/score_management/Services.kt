package com.aegis.backend.tools.score_management

import com.aegis.backend.core.EnvConfig
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
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

    fun loadData() {
        try {
            if (!dataFile.exists()) {
                students = mutableListOf()
                return
            }
            val text = dataFile.readText(Charsets.UTF_8)
            students = json.decodeFromString<List<StudentData>>(text).toMutableList()
        } catch (_: Exception) {
            students = mutableListOf()
        }
    }

    fun saveData() {
        dataFile.parentFile.mkdirs()
        dataFile.writeText(json.encodeToString(students), Charsets.UTF_8)
    }

    fun addScore(studentId: String, name: String, scores: Map<String, Double>): String {
        val existing = students.find { it.student_id == studentId }
        return if (existing != null) {
            val merged = existing.scores.toMutableMap()
            merged.putAll(scores)
            val idx = students.indexOf(existing)
            students[idx] = existing.copy(name = name, scores = merged)
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

    fun queryStudents(studentId: String? = null, name: String? = null): List<StudentData> {
        loadData() // 确保最新数据
        return when {
            studentId != null -> students.filter { it.student_id == studentId }
            name != null -> students.filter { name.lowercase() in it.name.lowercase() }
            else -> emptyList()
        }
    }
}
