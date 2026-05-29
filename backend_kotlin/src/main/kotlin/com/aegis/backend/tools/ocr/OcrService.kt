package com.aegis.backend.tools.ocr

import com.aegis.backend.core.EnvConfig
import net.sourceforge.tess4j.Tesseract
import net.sourceforge.tess4j.util.ImageHelper
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.URLDecoder
import java.util.Base64
import java.util.concurrent.TimeUnit
import javax.imageio.ImageIO

/**
 * OCR 识别结果
 */
data class OcrResult(
    val text: String,              // 识别文本（含内联 LaTeX 公式）
    val formulaSource: String? = null, // 来源: "ai" / null
    val error: String? = null         // 错误信息
)

/**
 * 混合 OCR 服务
 * - 普通文本：使用 Tesseract OCR (chi_sim+eng)
 * - 数学公式(本地)：Tesseract + equ.traineddata 识别基础公式符号
 * - 数学公式(AI增强)：通过 AI Vision API 识别复杂公式（可选，需网络）
 */
class OcrService {

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(60, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .build()

    private val tessClient: Tesseract? by lazy {
        try {
            val tess = Tesseract()
            val tessdataPath = findTessdataPath()
            if (tessdataPath != null) {
                tess.setDatapath(tessdataPath)

                // 检查必需的训练数据文件是否存在
                val engExists = File(tessdataPath, "eng.traineddata").exists()
                val chiSimExists = File(tessdataPath, "chi_sim.traineddata").exists()

                if (!engExists && !chiSimExists) {
                    println("[OCR] ⚠️ tessdata 目录缺少 eng.traineddata 或 chi_sim.traineddata，Tesseract 文本识别不可用")
                    println("[OCR] 请下载: https://github.com/tesseract-ocr/tessdata/")
                    // 仍然返回非 null 的 Tesseract 实例，AI 兜底会处理
                }

                val languages = buildString {
                    var first = true
                    if (chiSimExists) { append("chi_sim"); first = false }
                    if (engExists) { if (!first) append("+"); append("eng"); first = false }
                    if (first) append("eng") // 兜底，即使文件不存在也设置
                }
                tess.setLanguage(languages)
                tess.setPageSegMode(6)
                println("[OCR] Tesseract 初始化成功, datapath: $tessdataPath, lang: $languages")
                tess
            } else {
                println("[OCR] ⚠️ 未找到 tessdata 目录，Tesseract OCR 不可用")
                null
            }
        } catch (e: Exception) {
            println("[OCR] ❌ Tesseract 初始化失败: ${e.message}")
            null
        }
    }

    /**
     * 获取 tessdata 目录中缺失的文件列表
     */
    private fun getMissingTessdataFiles(): List<String> {
        val tessdataPath = findTessdataPath() ?: return listOf("tessdata 目录未找到")
        val missing = mutableListOf<String>()
        if (!File(tessdataPath, "eng.traineddata").exists()) missing.add("eng.traineddata")
        if (!File(tessdataPath, "chi_sim.traineddata").exists()) missing.add("chi_sim.traineddata")
        return missing
    }

    /**
     * 查找 tessdata 目录
     */
    private fun findTessdataPath(): String? {
        // 0. 直接检查已知的源码 resources 路径（开发环境）
        val sourcePath = File("backend_kotlin/src/main/resources/tessdata")
        if (sourcePath.exists()) return sourcePath.absolutePath

        val sourcePath2 = File("src/main/resources/tessdata")
        if (sourcePath2.exists()) return sourcePath2.absolutePath

        // 1. 类路径 resources（打包成 JAR 后使用）
        try {
            val resourceUrl = OcrService::class.java.getResource("/tessdata")
            if (resourceUrl != null) {
                // Windows 下 getResource 返回 file:/C:/... 格式
                val path = resourceUrl.path?.replace("/", File.separator)
                    ?.removePrefix(File.separator) // 去掉开头的 /
                    ?.let { if (it.startsWith(":")) it.substring(1) else it } // 处理 file:/C: 情况
                if (path != null) {
                    val f = File(path)
                    if (f.exists()) return f.absolutePath
                    // 尝试 URL 解码（处理空格等）
                    try {
                        val decoded = java.net.URLDecoder.decode(path, "UTF-8")
                        val fd = File(decoded)
                        if (fd.exists()) return fd.absolutePath
                    } catch (_: Exception) {}
                }
            }
        } catch (_: Exception) {}

        // 2. 从当前目录开始向上查找 tessdata
        var currentDir = File(".").absoluteFile
        repeat(5) { // 最多向上找5层
            val candidate = File(currentDir, "tessdata")
            if (candidate.exists()) return candidate.absolutePath
            // 也检查 resources/tessdata
            val resCandidate = File(currentDir, "src/main/resources/tessdata")
            if (resCandidate.exists()) return resCandidate.absolutePath
            currentDir = currentDir.parentFile ?: return@repeat
        }

        // 3. 上一级目录下的 tessdata
        val parentDir = File(".").absoluteFile.parentFile
        if (parentDir != null) {
            var candidate = File(parentDir, "tessdata")
            if (candidate.exists()) return candidate.absolutePath
            candidate = File(parentDir, "src/main/resources/tessdata")
            if (candidate.exists()) return candidate.absolutePath
        }

        // 4. 用户主目录下的 tessdata
        val userHome = System.getProperty("user.home")
        var candidate = File(userHome, "tessdata")
        if (candidate.exists()) return candidate.absolutePath

        return null
    }

    /**
     * 执行 OCR 识别
     * @param imageBase64 图片的 Base64 编码
     * @param enableFormulaAI 是否启用 AI 公式识别（可选）
     * @return OCR 识别结果
     */
    fun recognize(imageBase64: String, enableFormulaAI: Boolean = true): OcrResult {
        // 将 Base64 解码为图片文件
        val tempFile = saveBase64ToTempFile(imageBase64) ?: return OcrResult(
            text = "",
            error = "无法解码图片数据"
        )

        return try {
            val image = ImageIO.read(tempFile)
            if (image == null) {
                return OcrResult(text = "", error = "无法读取图片格式")
            }

            // ===== 预处理：灰度 + 放大 + 二值化 =====
            var processed = image
            try {
                processed = ImageHelper.convertImageToGrayscale(image)
                processed = ImageHelper.getScaledInstance(
                    processed,
                    processed.width * 2,
                    processed.height * 2
                )
                processed = ImageHelper.convertImageToBinary(processed)
            } catch (_: Exception) {
                processed = image // 预处理失败则用原图
            }

            // ===== 第一步：Tesseract 普通文本 OCR (chi_sim+eng) =====
            val tesseractText = tessClient?.let { tess ->
                try {
                    val result = tess.doOCR(processed)
                    println("[OCR] Tesseract 文本识别完成: ${result.length} 字符")
                    result.trim()
                } catch (e: Exception) {
                    val msg = e.message ?: ""
                    println("[OCR] Tesseract 文本识别失败: $msg")
                    // 检测是否因缺少语言文件而失败
                    val missingFiles = getMissingTessdataFiles()
                    if (missingFiles.isNotEmpty()) {
                        "[Tesseract 需要补充训练数据: ${missingFiles.joinToString(", ")}]"
                    } else {
                        // fallback: 用原图再试一次
                        try {
                            tess.doOCR(image).trim()
                        } catch (e2: Exception) {
                            "[Tesseract 识别失败: ${e2.message}]"
                        }
                    }
                }
            } ?: ""

            // ===== 第二步（AI优先）：AI 识别（完整文本 + 内联LaTeX公式） =====
            var aiText: String? = null
            var formulaSource: String? = null

            // AI 始终调用（Tesseract 中英混合识别能力太差）
            if (enableFormulaAI) {
                val aiResponse = recognizeWithAI(imageBase64)
                if (aiResponse != null && aiResponse.isNotBlank() && !aiResponse.equals("无", ignoreCase = true)) {
                    aiText = aiResponse
                    formulaSource = "ai"
                    println("[OCR] AI 识别完成: ${aiText.length} 字符")
                }
            }

            // 决定最终输出的 text：优先用 AI 识别的文本（更准确），否则用 Tesseract
            val finalText = if (!aiText.isNullOrBlank()) aiText
                           else tesseractText

            OcrResult(
                text = finalText,
                formulaSource = formulaSource,
                error = if (finalText.isBlank()) "未识别到任何文本" else null
            )
        } catch (e: Exception) {
            println("[OCR] 识别异常: ${e.message}")
            OcrResult(text = "", error = "OCR 识别异常: ${e.message}")
        } finally {
            // 清理临时文件
            if (tempFile.exists()) tempFile.delete()
        }
    }

    /**
     * 使用 Tesseract equ 进行本地公式识别
     * equ.traineddata 是 Tesseract 专用的数学公式训练数据，
     * 能识别等号、分数、积分、求和等基础数学符号。
     */
    private fun recognizeFormulaLocal(image: java.awt.image.BufferedImage, processed: java.awt.image.BufferedImage): String? {
        val tessdataPath = findTessdataPath() ?: return null
        val equFile = File(tessdataPath, "equ.traineddata")
        if (!equFile.exists()) {
            println("[OCR-equ] ⚠️ equ.traineddata 不存在，跳过本地公式识别")
            return null
        }

        return try {
            val equTess = Tesseract()
            equTess.setDatapath(tessdataPath)
            equTess.setLanguage("equ")
            equTess.setPageSegMode(6) // 假设统一文本块

            // 先用二值化图识别
            val result = equTess.doOCR(processed)
            val cleaned = result.trim()
            if (cleaned.length > 3 && cleaned.any { it in "+-=×÷∑∫√πθαβγμ∞Δ" }) {
                return cleaned
            }

            // 如果结果太短或无数学符号，用原图再试
            val result2 = equTess.doOCR(image).trim()
            if (result2.length > 3 && result2.any { it in "+-=×÷∑∫√πθαβγμ∞Δ" }) {
                return result2
            }

            null // 未识别出有效公式
        } catch (e: Exception) {
            println("[OCR-equ] 本地公式识别失败: ${e.message}")
            null
        }
    }

    /**
     * 使用 AI Vision API 进行图片识别（文字 + 公式）
     * 返回 AI 原始响应，由调用方解析 【文字内容】 和 【数学公式】
     */
    private fun recognizeWithAI(imageBase64: String): String? {
        val apiKey = EnvConfig.activeApiKey
        val baseUrl = EnvConfig.activeBaseUrl
        val model = EnvConfig.activeModel

        if (apiKey.isBlank() || baseUrl.isBlank() || model.isBlank()) {
            println("[OCR-AI] ⚠️ AI 配置不完整，跳过公式识别")
            return null
        }

        try {
            val chatUrl = "$baseUrl/chat/completions"

            val requestBody = JSONObject().apply {
                put("model", model)
                put("messages", listOf(
                    mapOf(
                        "role" to "user",
                        "content" to listOf(
                            mapOf(
                                "type" to "text",
                                "text" to "请识别这张图片中的所有文字。如果包含数学公式，请用 LaTeX 格式（$...$）内嵌在原位输出。直接输出完整文本，不要添加额外说明。"
                            ),
                            mapOf(
                                "type" to "image_url",
                                "image_url" to mapOf(
                                    "url" to "data:image/png;base64,$imageBase64"
                                )
                            )
                        )
                    )
                ))
                put("max_tokens", 4096)
                put("temperature", 0.1)
            }

            val request = Request.Builder()
                .url(chatUrl)
                .addHeader("Authorization", "Bearer $apiKey")
                .addHeader("Content-Type", "application/json")
                .post(requestBody.toString().toRequestBody("application/json".toMediaType()))
                .build()

            val response = httpClient.newCall(request).execute()
            val body = response.body?.string() ?: return null

            val json = JSONObject(body)
            val content = json
                .optJSONArray("choices")
                ?.optJSONObject(0)
                ?.optJSONObject("message")
                ?.optString("content", "")
                ?.trim()

            if (content.isNullOrBlank()) return null
            println("[OCR-AI] AI 识别完成: ${content.length} 字符")
            return content
        } catch (e: Exception) {
            println("[OCR-AI] AI 公式识别失败: ${e.message}")
            return null
        }
    }

    /**
     * 将 Base64 图片保存到临时文件
     */
    private fun saveBase64ToTempFile(base64: String): File? {
        return try {
            val cleanBase64 = base64
                .replace("data:image/png;base64,", "")
                .replace("data:image/jpeg;base64,", "")
                .replace("data:image/jpg;base64,", "")
                .replace("data:image/gif;base64,", "")
                .replace("data:image/webp;base64,", "")
                .replace("data:image/bmp;base64,", "")
                .trim()

            val imageBytes = Base64.getDecoder().decode(cleanBase64)
            val tempFile = File.createTempFile("ocr_", ".png")
            FileOutputStream(tempFile).use { fos ->
                fos.write(imageBytes)
            }
            tempFile
        } catch (e: Exception) {
            println("[OCR] Base64 解码失败: ${e.message}")
            null
        }
    }

    /**
     * 检查 OCR 环境是否就绪
     */
    fun checkEnvironment(): Map<String, Any> {
        val tessReady = tessClient != null
        val aiConfigured = EnvConfig.activeApiKey.isNotBlank()
        val tessdataPath = findTessdataPath()

        return mapOf(
            "tesseract_available" to tessReady,
            "ai_configured" to aiConfigured,
            "tessdata_path" to (tessdataPath ?: "未找到"),
            "capabilities" to buildString {
                if (tessReady) append("普通文本OCR ")
                if (aiConfigured) append("AI文字+公式识别")
                if (isEmpty()) append("不可用")
            }.trim(),
            "status" to when {
                tessReady && aiConfigured -> "ready"
                tessReady -> "ready (仅普通文本)"
                aiConfigured -> "partial (仅AI模式可用)"
                else -> "unavailable"
            }
        )
    }
}
