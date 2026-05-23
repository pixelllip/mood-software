package com.academic.aegis

import android.content.Intent
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val BACKEND_CHANNEL = "com.academic.aegis/backend"
    private val PERM_CHANNEL = "com.academic.aegis/permission"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 后端通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKEND_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startBackend" -> {
                    val port = call.argument<Int>("port") ?: 8080
                    Log.d("MainActivity", "收到 startBackend 请求 (端口: $port)")
                    Log.d("MainActivity", "Android 模式：使用直连 AI API，跳过本地后端")
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 权限通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkStoragePermission" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        Environment.isExternalStorageManager()
                    } else {
                        true // API < 30 不需要 MANAGE_EXTERNAL_STORAGE
                    }
                    result.success(granted)
                }
                "openStoragePermissionSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                                data = android.net.Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                        } else {
                            // API < 30 直接打开应用详情页
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = android.net.Uri.fromParts("package", packageName, null)
                            }
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "打开权限设置失败: ${e.message}")
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
