@file:OptIn(kotlinx.serialization.InternalSerializationApi::class)

package com.aegis.backend.tools.score_management

import com.aegis.backend.core.EnvConfig
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

// ==================== 数据模型 ====================

/** 考试记录 */
@Serializable
data class ExamRecord(
    val date: String = "",
    val exam_type: String = "日常",
    val semester: String? = null,
    val label: String? = null,
    val scores: Map<String, JsonElement> = emptyMap()
)

/** 学生成绩数据（scores 支持纯数字 和 {score, fullMark, tag} 两种格式） */
@Serializable
data class StudentData(
    val student_id: String,
    val name: String,
    val scores: Map<String, JsonElement> = emptyMap(),
    val exam_records: List<ExamRecord> = emptyList()
)

// ==================== 服务 ====================

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

    /** 从 JsonElement 中提取数值分数 */
    fun extractScore(score: JsonElement?): Double {
        if (score == null) return 0.0
        return when {
            score is JsonPrimitive && score.isString -> score.content.toDoubleOrNull() ?: 0.0
            score is JsonPrimitive -> score.doubleOrNull ?: 0.0
            score is JsonObject -> {
                val s = score["score"]
                extractScore(s)
            }
            else -> 0.0
        }
    }

    /** 从 JSON 安全加载（兼容纯数字和 Map 对象格式） */
    fun loadData() {
        try {
            if (!dataFile.exists()) {
                students = mutableListOf()
                return
            }
            val text = dataFile.readText(Charsets.UTF_8)
            val rawArray = JSONArray(text)
            students = mutableListOf()
            for (i in 0 until rawArray.length()) {
                val obj = rawArray.getJSONObject(i)
                val sid = obj.optString("student_id", "")
                val name = obj.optString("name", "")
                val scoresJson = obj.optJSONObject("scores") ?: JSONObject()
                val scores = mutableMapOf<String, JsonElement>()
                for (key in scoresJson.keys()) {
                    scores[key] = json.parseToJsonElement(scoresJson.get(key).toString())
                }

                // 加载考试记录
                val records = mutableListOf<ExamRecord>()
                if (obj.has("exam_records")) {
                    val recordsArray = obj.getJSONArray("exam_records")
                    for (j in 0 until recordsArray.length()) {
                        val recordObj = recordsArray.getJSONObject(j)
                        val recordScores = mutableMapOf<String, JsonElement>()
                        if (recordObj.has("scores")) {
                            val rs = recordObj.getJSONObject("scores")
                            for (rk in rs.keys()) {
                                recordScores[rk] = json.parseToJsonElement(rs.get(rk).toString())
                            }
                        }
                        records.add(ExamRecord(
                            date = recordObj.optString("date", ""),
                            exam_type = recordObj.optString("exam_type", "日常"),
                            semester = recordObj.optString("semester", null),
                            label = recordObj.optString("label", null),
                            scores = recordScores
                        ))
                    }
                }

                students.add(StudentData(
                    student_id = sid,
                    name = name,
                    scores = scores,
                    exam_records = records
                ))
            }
        } catch (_: Exception) {
            students = mutableListOf()
        }
    }

    fun saveData() {
        dataFile.parentFile.mkdirs()
        dataFile.writeText(json.encodeToString(students), Charsets.UTF_8)
    }

    /** 添加/更新成绩（支持标签，自动创建考试记录） */
    fun addScore(
        studentId: String,
        name: String,
        scores: Map<String, JsonElement>,
        label: String? = null,
        examType: String? = null
    ): String {
        val existing = students.find { it.student_id == studentId && it.name == name }

        // 创建考试记录
        val now = java.time.LocalDateTime.now()
        val dateStr = "${now.year}-${now.monthValue.toString().padStart(2, '0')}-${now.dayOfMonth.toString().padStart(2, '0')} " +
                "${now.hour.toString().padStart(2, '0')}:${now.minute.toString().padStart(2, '0')}"
        val examRecord = ExamRecord(
            date = dateStr,
            exam_type = examType ?: "日常",
            label = label,
            scores = scores
        )

        return if (existing != null) {
            val merged = existing.scores.toMutableMap()
            merged.putAll(scores)
            val idx = students.indexOf(existing)
            students[idx] = existing.copy(
                scores = merged,
                exam_records = existing.exam_records + examRecord
            )
            saveData()
            "已为学生 [$name] 更新/合并成绩。"
        } else {
            students.add(StudentData(
                student_id = studentId,
                name = name,
                scores = scores,
                exam_records = listOf(examRecord)
            ))
            saveData()
            "成功录入新学生：$name"
        }
    }

    /** 更新单科成绩的标签 */
    fun updateSubjectTag(studentId: String, subject: String, tag: String): Boolean {
        val idx = students.indexOfFirst { it.student_id == studentId }
        if (idx < 0) return false

        val existing = students[idx]
        val updatedScores = existing.scores.toMutableMap()
        val oldScore = updatedScores[subject]
        updatedScores[subject] = when {
            oldScore is JsonObject -> {
                val obj = oldScore.toMutableMap()
                obj["tag"] = JsonPrimitive(tag)
                JsonObject(obj)
            }
            oldScore != null -> JsonObject(mapOf(
                "score" to oldScore,
                "tag" to JsonPrimitive(tag)
            ))
            else -> JsonObject(mapOf(
                "score" to JsonPrimitive(0),
                "tag" to JsonPrimitive(tag)
            ))
        }
        students[idx] = existing.copy(scores = updatedScores)
        saveData()
        return true
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
        loadData()

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
