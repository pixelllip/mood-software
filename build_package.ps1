# build_package.ps1 - Build AI Agent Flutter app with backend Fat JAR
# Usage:
#   .\build_package.ps1 -Target windows    # Build Windows
#   .\build_package.ps1 -Target android    # Build Android
#   .\build_package.ps1 -Target all        # Build both

param(
    [ValidateSet("windows", "android", "all")]
    [string]$Target = "windows"
)

$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$jarDir = "$rootDir\backend_kotlin\build\libs"
$jarFile = "$jarDir\ai_agent_backend.jar"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  AI Agent Build Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================
# Step 1: Build backend Fat JAR
# ============================================
Write-Host "[1/3] Building backend Fat JAR..." -ForegroundColor Yellow
Push-Location "$rootDir\backend_kotlin"
try {
    if ($IsLinux -or $IsMacOS) {
        & ./gradlew buildFatJar
    } else {
        & ./gradlew.bat buildFatJar
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Gradle build failed (exit code: $LASTEXITCODE)"
    }
    Write-Host "  [OK] Backend Fat JAR: $jarFile" -ForegroundColor Green
} finally {
    Pop-Location
}

# ============================================
# Step 2: Get Flutter version
# ============================================
Write-Host "[2/3] Getting Flutter version..." -ForegroundColor Yellow
$pubspec = Get-Content "$rootDir\pubspec.yaml" -Raw
$versionMatch = [regex]::Match($pubspec, 'version:\s*([\d\.\+\w]+)')
$version = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { "1.0.0" }
Write-Host "  Version: $version" -ForegroundColor Gray

# ============================================
# Step 3: Build Flutter by target
# ============================================
function Build-Windows {
    Write-Host "[3/3] Building Flutter Windows..." -ForegroundColor Yellow

    Push-Location $rootDir
    try {
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "Flutter Windows build failed" }
    } finally {
        Pop-Location
    }

    # Copy JAR to output
    # 新版本 Flutter 输出在 build\windows\x64\runner\Release\
    $outputDir = "$rootDir\build\windows\x64\runner\Release\backend"
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    Copy-Item $jarFile -Destination "$outputDir\ai_agent_backend.jar" -Force

    Write-Host "  [OK] JAR copied to: $outputDir\ai_agent_backend.jar" -ForegroundColor Green
    Write-Host ""
    Write-Host "Output: $rootDir\build\windows\x64\runner\Release\" -ForegroundColor Cyan
    Write-Host "  Exe: 星火学伴.exe" -ForegroundColor Cyan
    Write-Host "  JAR: backend\ai_agent_backend.jar" -ForegroundColor Cyan
}

function Build-Android {
    Write-Host "[3/3] Building Flutter Android..." -ForegroundColor Yellow

    Push-Location $rootDir
    try {
        flutter build apk --release
        if ($LASTEXITCODE -ne 0) { throw "Flutter Android build failed" }
    } finally {
        Pop-Location
    }

    Write-Host ""
    Write-Host "Output: $rootDir\build\app\outputs\flutter-apk\" -ForegroundColor Cyan
    Write-Host "  APK: app-release.apk" -ForegroundColor Cyan
}

# Run target
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
Write-Host "  [Done] Build complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
