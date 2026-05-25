# build_package.ps1 - Build AI Agent Flutter app with backend Fat JAR
# Usage:
#   .\build_package.ps1 -Target windows    # Build Windows
#   .\build_package.ps1 -Target android    # Build Android
#   .\build_package.ps1 -Target linux      # Build Linux
#   .\build_package.ps1 -Target macos      # Build macOS
#   .\build_package.ps1 -Target ios        # Build iOS (仅 macOS 宿主)
#   .\build_package.ps1 -Target all        # Build all platforms
#   .\build_package.ps1 -Target desktop    # Build all desktop platforms (windows+linux+macos)

param(
    [ValidateSet("windows", "android", "linux", "macos", "ios", "all", "desktop")]
    [string]$Target = "windows"
)

$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$jarDir = "$rootDir\backend_kotlin\build\libs"
$jarFile = "$jarDir\ai_agent_backend.jar"

# ---------- 需要 JAR 后端的平台 ----------
$needsJar = @("windows", "linux", "macos")

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  AI Agent Build Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================
# Step 1: Build backend Fat JAR (仅桌面端需要)
# ============================================
if ($Target -in $needsJar -or $Target -eq "all" -or $Target -eq "desktop") {
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
} else {
    Write-Host "[1/3] Skipping backend JAR (not needed for $Target)" -ForegroundColor Gray
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

function Build-Linux {
    Write-Host "[3/3] Building Flutter Linux..." -ForegroundColor Yellow

    Push-Location $rootDir
    try {
        flutter build linux --release
        if ($LASTEXITCODE -ne 0) { throw "Flutter Linux build failed" }
    } finally {
        Pop-Location
    }

    # Copy JAR to output
    $outputDir = "$rootDir\build\linux\x64\release\bundle\backend"
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    Copy-Item $jarFile -Destination "$outputDir\ai_agent_backend.jar" -Force

    Write-Host "  [OK] JAR copied to: $outputDir\ai_agent_backend.jar" -ForegroundColor Green
    Write-Host ""
    Write-Host "Output: $rootDir\build\linux\x64\release\bundle\" -ForegroundColor Cyan
    Write-Host "  Binary: 星火学伴 (ELF)" -ForegroundColor Cyan
    Write-Host "  JAR:    backend/ai_agent_backend.jar" -ForegroundColor Cyan
}

function Build-MacOS {
    Write-Host "[3/3] Building Flutter macOS..." -ForegroundColor Yellow

    Push-Location $rootDir
    try {
        flutter build macos --release
        if ($LASTEXITCODE -ne 0) { throw "Flutter macOS build failed" }
    } finally {
        Pop-Location
    }

    # Copy JAR into the .app bundle's Resources folder
    $appBundle = Get-ChildItem "$rootDir\build\macos\Build\Products\Release\*.app" -Directory | Select-Object -First 1
    if ($appBundle) {
        $resourcesDir = "$($appBundle.FullName)\Contents\Resources\backend"
        if (-not (Test-Path $resourcesDir)) {
            New-Item -ItemType Directory -Path $resourcesDir -Force | Out-Null
        }
        Copy-Item $jarFile -Destination "$resourcesDir\ai_agent_backend.jar" -Force
        Write-Host "  [OK] JAR copied to: $resourcesDir\ai_agent_backend.jar" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Could not find .app bundle, JAR not copied" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Output: $rootDir\build\macos\Build\Products\Release\" -ForegroundColor Cyan
    Write-Host "  App:  星火学伴.app" -ForegroundColor Cyan
    Write-Host "  JAR:  backend/ai_agent_backend.jar (inside .app bundle)" -ForegroundColor Cyan
}

function Build-iOS {
    Write-Host "[3/3] Building Flutter iOS..." -ForegroundColor Yellow

    # iOS 构建只能在 macOS 上执行
    if (-not $IsMacOS) {
        Write-Host "  [ERROR] iOS builds are only supported on macOS." -ForegroundColor Red
        Write-Host "  Please run this script on a macOS machine." -ForegroundColor Red
        return
    }

    Push-Location $rootDir
    try {
        # 先验证 iOS 环境
        flutter precache --ios

        # 构建 iOS 产物 (Archive)
        Write-Host "  Building iOS release (this may take a while)..." -ForegroundColor Gray
        flutter build ios --release --no-codesign
        if ($LASTEXITCODE -ne 0) { throw "Flutter iOS build failed" }

        Write-Host ""
        Write-Host "Output: $rootDir\build\ios\iphoneos\Runner.app\" -ForegroundColor Cyan
        Write-Host "  App: Runner.app" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  [TIP] To produce an IPA for distribution, run:" -ForegroundColor Yellow
        Write-Host "    flutter build ipa --release" -ForegroundColor Yellow
        Write-Host "  (requires valid Apple Developer certificate & provisioning profile)" -ForegroundColor Yellow
    } finally {
        Pop-Location
    }
}

function Build-Desktop {
    Write-Host "--- Building Desktop Platforms ---" -ForegroundColor Magenta
    Build-Windows
    Write-Host ""
    Build-Linux
    Write-Host ""
    Build-MacOS
}

# Run target
switch ($Target) {
    "windows" { Build-Windows }
    "android" { Build-Android }
    "linux"   { Build-Linux }
    "macos"   { Build-MacOS }
    "ios"     { Build-iOS }
    "desktop" { Build-Desktop }
    "all" {
        Write-Host "--- Building ALL Platforms ---" -ForegroundColor Magenta
        Build-Windows
        Write-Host ""
        Build-Linux
        Write-Host ""
        Build-MacOS
        Write-Host ""
        Build-Android
        Write-Host ""
        Build-iOS
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  [Done] Build complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
