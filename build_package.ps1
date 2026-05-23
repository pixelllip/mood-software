# build_package.ps1 — 一键构建 AI Agent Flutter 应用（含后端 Fat JAR）
# 用法:
#   .\build_package.ps1 -Target windows    # 打包 Windows
#   .\build_package.ps1 -Target android    # 打包 Android
#   .\build_package.ps1 -Target all        # 同时打包两个平台

param(
    [ValidateSet("windows", "android", "all")]
    [string]$Target = "windows"
)

$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$jarDir = "$rootDir\backend_kotlin\build\libs"
$jarFile = "$jarDir\ai_agent_backend.jar"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  AI Agent 一键打包脚本" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================
# 第一步：构建后端 Fat JAR
# ============================================
Write-Host "[1/3] 构建后端 Fat JAR..." -ForegroundColor Yellow
Push-Location "$rootDir\backend_kotlin"
try {
    if ($IsLinux -or $IsMacOS) {
        & ./gradlew buildFatJar
    } else {
        & ./gradlew.bat buildFatJar
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Gradle 构建失败 (exit code: $LASTEXITCODE)"
    }
    Write-Host "  ✅ 后端 Fat JAR 构建成功: $jarFile" -ForegroundColor Green
} finally {
    Pop-Location
}

# ============================================
# 第二步：获取 Flutter 版本号
# ============================================
Write-Host "[2/3] 获取 Flutter 版本信息..." -ForegroundColor Yellow
$pubspec = Get-Content "$rootDir\pubspec.yaml" -Raw
$versionMatch = [regex]::Match($pubspec, 'version:\s*([\d\.\+\w]+)')
$version = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { "1.0.0" }
Write-Host "  版本号: $version" -ForegroundColor Gray

# ============================================
# 第三步：按目标平台打包 Flutter
# ============================================
function Build-Windows {
    Write-Host "[3/3] 构建 Flutter Windows 应用..." -ForegroundColor Yellow

    # 先构建 Flutter
    Push-Location $rootDir
    try {
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "Flutter Windows 构建失败" }
    } finally {
        Pop-Location
    }

    # 复制 JAR 到输出目录
    $outputDir = "$rootDir\build\windows\runner\Release\backend"
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    Copy-Item $jarFile -Destination "$outputDir\ai_agent_backend.jar" -Force

    Write-Host "  ✅ JAR 已复制到: $outputDir\ai_agent_backend.jar" -ForegroundColor Green
    Write-Host ""
    Write-Host "📦 输出位置: $rootDir\build\windows\runner\Release\" -ForegroundColor Cyan
    Write-Host "   可执行文件: ai_agent.exe" -ForegroundColor Cyan
    Write-Host "   后端 JAR: backend\ai_agent_backend.jar" -ForegroundColor Cyan
}

function Build-Android {
    Write-Host "[3/3] 构建 Flutter Android 应用..." -ForegroundColor Yellow

    Push-Location $rootDir
    try {
        flutter build apk --release
        if ($LASTEXITCODE -ne 0) { throw "Flutter Android 构建失败" }
    } finally {
        Pop-Location
    }

    Write-Host ""
    Write-Host "📦 输出位置: $rootDir\build\app\outputs\flutter-apk\" -ForegroundColor Cyan
    Write-Host "   APK 文件: app-release.apk" -ForegroundColor Cyan
    Write-Host "   (Android 使用直连 AI API，无需后端 JAR)" -ForegroundColor Cyan
}

# 执行目标
switch ($Target) {
    "windows" { Build-Windows }
    "android" { Build-Android }
    "all" {
        Build-Windows
        Build-Android
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  🎉 打包完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
