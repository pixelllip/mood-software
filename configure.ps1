<#
.SYNOPSIS
  XingHuo XueBan (ai_agent) Multi-Platform Configuration Tool
.DESCRIPTION
  Interactive script to modify version numbers, app names, package names,
  signing info, copyright, etc. across all platforms.
  Modifications are written directly to config files.

  Usage:
    .\configure.ps1                         # Interactive menu
    .\configure.ps1 -SetVersion 2.0.0+1     # Non-interactive: set version
    .\configure.ps1 -SetAppName "MyApp"      # Non-interactive: set app name
#>

param(
    [switch]$NonInteractive,
    [string]$SetVersion,
    [string]$SetAppName
)

$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ============================================================
# Utility functions
# ============================================================

function Read-CurrentConfig {
    $config = @{}

    # --- pubspec.yaml ---
    $pubspec = Get-Content "$rootDir\pubspec.yaml" -Raw -Encoding UTF8
    $m = [regex]::Match($pubspec, 'version:\s*([\d\.\+]+)')
    $config.version = if ($m.Success) { $m.Groups[1].Value } else { "N/A" }

    # --- Android ---
    $androidGradle = Get-Content "$rootDir\android\app\build.gradle.kts" -Raw -Encoding UTF8
    $m = [regex]::Match($androidGradle, 'applicationId\s*=\s*"([^"]+)"')
    $config.androidAppId = if ($m.Success) { $m.Groups[1].Value } else { "N/A" }
    $m = [regex]::Match($androidGradle, 'namespace\s*=\s*"([^"]+)"')
    $config.androidNamespace = if ($m.Success) { $m.Groups[1].Value } else { "N/A" }
    $m = [regex]::Match($androidGradle, 'minSdk\s*=\s*([^\s}]+)')
    $config.androidMinSdk = if ($m.Success) { $m.Groups[1].Value } else { "N/A" }
    $m = [regex]::Match($androidGradle, 'targetSdk\s*=\s*([^\s}]+)')
    $config.androidTargetSdk = if ($m.Success) { $m.Groups[1].Value } else { "N/A" }
    $m = [regex]::Match($androidGradle, 'compileSdk\s*=\s*([^\s}]+)')
    $config.androidCompileSdk = if ($m.Success) { $m.Groups[1].Value } else { "N/A" }

    $config.androidSigning = "debug (no release signing)"
    if ($androidGradle -match 'signingConfig\s*=\s*signingConfigs\.getByName\("release"\)') {
        $config.androidSigning = "release (configured)"
    }
    elseif ($androidGradle -match 'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)') {
        $config.androidSigning = "debug (no release signing)"
    }

    # --- iOS ---
    $iosPlist = Get-Content "$rootDir\ios\Runner\Info.plist" -Raw -Encoding UTF8
    $m = [regex]::Match($iosPlist, '<key>CFBundleDisplayName</key>\s*<string>([^<]+)</string>')
    $config.iosDisplayName = if ($m.Success) { $m.Groups[1].Value } else { "N/A" }

    # --- macOS ---
    $macAppInfo = Get-Content "$rootDir\macos\Runner\Configs\AppInfo.xcconfig" -Raw -Encoding UTF8
    $m = [regex]::Match($macAppInfo, 'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(.+)$')
    $config.macBundleId = if ($m.Success) { $m.Groups[1].Value.Trim() } else { "N/A" }
    $m = [regex]::Match($macAppInfo, 'PRODUCT_NAME\s*=\s*(.+)$')
    $config.macProductName = if ($m.Success) { $m.Groups[1].Value.Trim() } else { "N/A" }
    $m = [regex]::Match($macAppInfo, 'PRODUCT_COPYRIGHT\s*=\s*(.+)$')
    $config.macCopyright = if ($m.Success) { $m.Groups[1].Value.Trim() } else { "N/A" }

    # --- Windows ---
    $winRc = Get-Content "$rootDir\windows\runner\Runner.rc" -Raw -Encoding UTF8
    $m = [regex]::Match($winRc, '"CompanyName",\s*"([^"]+)"')
    $config.winCompany = if ($m.Success) { $m.Groups[1].Value } else { "N/A" }
    $m = [regex]::Match($winRc, '"FileDescription",\s*"([^"]+)"')
    $config.winFileDesc = if ($m.Success) { $m.Groups[1].Value } else { "N/A" }
    $m = [regex]::Match($winRc, '"LegalCopyright",\s*"([^"]+)"')
    $config.winCopyright = if ($m.Success) { $m.Groups[1].Value } else { "N/A" }
    $m = [regex]::Match($winRc, '"OriginalFilename",\s*"([^"]+)"')
    $config.winOriginalName = if ($m.Success) { $m.Groups[1].Value } else { "N/A" }
    $m = [regex]::Match($winRc, '"ProductName",\s*"([^"]+)"')
    $config.winProductName = if ($m.Success) { $m.Groups[1].Value } else { "N/A" }

    # --- Linux ---
    $linuxCmake = Get-Content "$rootDir\linux\CMakeLists.txt" -Raw -Encoding UTF8
    $m = [regex]::Match($linuxCmake, 'set\(APPLICATION_ID\s+"([^"]+)"\)')
    $config.linuxAppId = if ($m.Success) { $m.Groups[1].Value } else { "N/A" }
    $m = [regex]::Match($linuxCmake, 'set\(BINARY_NAME\s+"([^"]+)"\)')
    $config.linuxBinName = if ($m.Success) { $m.Groups[1].Value } else { "N/A" }

    # --- Web ---
    $manifest = Get-Content "$rootDir\web\manifest.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    $config.webName = $manifest.name
    $config.webShortName = $manifest.short_name
    $config.webDescription = $manifest.description

    $webIndex = Get-Content "$rootDir\web\index.html" -Raw -Encoding UTF8
    $m = [regex]::Match($webIndex, '<title>([^<]+)</title>')
    $config.webTitle = if ($m.Success) { $m.Groups[1].Value } else { "N/A" }

    return $config
}

function Show-CurrentConfig {
    param($config)

    Write-Host ""
    Write-Host ("=" * 50) -ForegroundColor Cyan
    Write-Host "  CURRENT CONFIG OVERVIEW" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan

    Write-Host ""
    Write-Host "  [Version]" -ForegroundColor Yellow
    Write-Host "    App version:          $($config.version)" -ForegroundColor White

    Write-Host ""
    Write-Host "  [Android]" -ForegroundColor Yellow
    Write-Host "    applicationId:        $($config.androidAppId)" -ForegroundColor White
    Write-Host "    namespace:            $($config.androidNamespace)" -ForegroundColor White
    Write-Host "    compileSdk:           $($config.androidCompileSdk)" -ForegroundColor White
    Write-Host "    minSdk:               $($config.androidMinSdk)" -ForegroundColor White
    Write-Host "    targetSdk:            $($config.androidTargetSdk)" -ForegroundColor White
    Write-Host "    signing:              $($config.androidSigning)" -ForegroundColor White

    Write-Host ""
    Write-Host "  [iOS]" -ForegroundColor Yellow
    Write-Host "    DisplayName:          $($config.iosDisplayName)" -ForegroundColor White

    Write-Host ""
    Write-Host "  [macOS]" -ForegroundColor Yellow
    Write-Host "    PRODUCT_NAME:         $($config.macProductName)" -ForegroundColor White
    Write-Host "    Bundle ID:            $($config.macBundleId)" -ForegroundColor White
    Write-Host "    Copyright:            $($config.macCopyright)" -ForegroundColor White

    Write-Host ""
    Write-Host "  [Windows]" -ForegroundColor Yellow
    Write-Host "    CompanyName:          $($config.winCompany)" -ForegroundColor White
    Write-Host "    FileDescription:      $($config.winFileDesc)" -ForegroundColor White
    Write-Host "    ProductName:          $($config.winProductName)" -ForegroundColor White
    Write-Host "    OriginalFilename:     $($config.winOriginalName)" -ForegroundColor White
    Write-Host "    LegalCopyright:       $($config.winCopyright)" -ForegroundColor White

    Write-Host ""
    Write-Host "  [Linux]" -ForegroundColor Yellow
    Write-Host "    APPLICATION_ID:       $($config.linuxAppId)" -ForegroundColor White
    Write-Host "    BINARY_NAME:          $($config.linuxBinName)" -ForegroundColor White

    Write-Host ""
    Write-Host "  [Web]" -ForegroundColor Yellow
    Write-Host "    name:                 $($config.webName)" -ForegroundColor White
    Write-Host "    short_name:           $($config.webShortName)" -ForegroundColor White
    Write-Host "    description:          $($config.webDescription)" -ForegroundColor White
    Write-Host "    title:                $($config.webTitle)" -ForegroundColor White
    Write-Host ""
}

# ============================================================
# File update helper
# ============================================================

function Update-File {
    param(
        [string]$FilePath,
        [string]$Pattern,
        [string]$Replacement,
        [string]$Label
    )
    $content = Get-Content $FilePath -Raw -Encoding UTF8
    if ($content -match $Pattern) {
        $content = $content -replace $Pattern, $Replacement
        Set-Content $FilePath -Value $content -NoNewline -Encoding UTF8
        Write-Host "  [OK] $Label updated" -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "  [WARN] Could not match pattern for $Label, please edit $FilePath manually" -ForegroundColor Yellow
        return $false
    }
}

# ============================================================
# Platform modification functions
# ============================================================

function Set-AppVersion {
    $current = Read-CurrentConfig
    Write-Host "Current version: " -NoNewline
    Write-Host $current.version -ForegroundColor Green
    $newVersion = Read-Host "Enter new version (format: x.y.z+build, empty to skip)"
    if ([string]::IsNullOrWhiteSpace($newVersion)) {
        Write-Host "  [SKIP] No input, skipped" -ForegroundColor Gray
        return
    }
    Update-File -FilePath "$rootDir\pubspec.yaml" `
        -Pattern '(?m)(^version:\s*).*' `
        -Replacement ('${1}' + $newVersion) `
        -Label "version"
}

function Set-AndroidConfig {
    Write-Host ""
    Write-Host "--- Android Config ---" -ForegroundColor Yellow
    $file = "$rootDir\android\app\build.gradle.kts"
    $current = Read-CurrentConfig

    Write-Host "Current applicationId: " -NoNewline
    Write-Host $current.androidAppId -ForegroundColor Green
    $newId = Read-Host "New applicationId (empty to skip)"
    if (-not [string]::IsNullOrWhiteSpace($newId)) {
        Update-File -FilePath $file -Pattern '(?<=applicationId\s*=\s*")[^"]+' -Replacement $newId -Label "applicationId"
    }

    Write-Host "Current namespace: " -NoNewline
    Write-Host $current.androidNamespace -ForegroundColor Green
    $newNs = Read-Host "New namespace (empty to skip)"
    if (-not [string]::IsNullOrWhiteSpace($newNs)) {
        Update-File -FilePath $file -Pattern '(?<=namespace\s*=\s*")[^"]+' -Replacement $newNs -Label "namespace"
    }

    Write-Host "Current compileSdk=$($current.androidCompileSdk), minSdk=$($current.androidMinSdk), targetSdk=$($current.androidTargetSdk)"
    $newCompile = Read-Host "compileSdk (empty to keep)"
    $newMin = Read-Host "minSdk (empty to keep)"
    $newTarget = Read-Host "targetSdk (empty to keep)"
    if (-not [string]::IsNullOrWhiteSpace($newCompile)) {
        Update-File -FilePath $file -Pattern '(?<=compileSdk\s*=\s*)[^\s\r\n}]+' -Replacement $newCompile -Label "compileSdk"
    }
    if (-not [string]::IsNullOrWhiteSpace($newMin)) {
        Update-File -FilePath $file -Pattern '(?<=minSdk\s*=\s*)[^\s\r\n}]+' -Replacement $newMin -Label "minSdk"
    }
    if (-not [string]::IsNullOrWhiteSpace($newTarget)) {
        Update-File -FilePath $file -Pattern '(?<=targetSdk\s*=\s*)[^\s\r\n}]+' -Replacement $newTarget -Label "targetSdk"
    }
}

function Set-AndroidSigning {
    Write-Host ""
    Write-Host "--- Android Signing Config ---" -ForegroundColor Yellow
    Write-Host "This will configure release signing. You need a .jks or .keystore file ready." -ForegroundColor Gray
    Write-Host ""

    $file = "$rootDir\android\app\build.gradle.kts"
    $content = Get-Content $file -Raw -Encoding UTF8

    $setupSigning = Read-Host "Configure release signing? (y/n, default n)"
    if ($setupSigning -ne "y") {
        Write-Host "  [SKIP] Signing config skipped" -ForegroundColor Gray
        return
    }

    $keystorePath = Read-Host "Keystore file path (relative to android/app/, e.g. my-release-key.jks)"
    if ([string]::IsNullOrWhiteSpace($keystorePath)) {
        Write-Host "  [SKIP] No path entered" -ForegroundColor Gray
        return
    }
    $storePassword = Read-Host "storePassword"
    $keyAlias = Read-Host "keyAlias"
    $keyPassword = Read-Host "keyPassword"

    if ($content -match 'signingConfigs') {
        Write-Host "  [WARN] signingConfigs already exists, please manually edit $file" -ForegroundColor Yellow
    }
    else {
        $signingBlock = @"

android {
    signingConfigs {
        release {
            storeFile = file("$keystorePath")
            storePassword = "$storePassword"
            keyAlias = "$keyAlias"
            keyPassword = "$keyPassword"
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
"@
        $content += $signingBlock
        Set-Content $file -Value $content -NoNewline -Encoding UTF8
        Write-Host "  [OK] Release signing config written" -ForegroundColor Green

        $propFile = "$rootDir\android\key.properties"
        @"
storePassword=$storePassword
keyPassword=$keyPassword
keyAlias=$keyAlias
storeFile=$keystorePath
"@ | Set-Content $propFile -Encoding UTF8
        Write-Host "  [OK] android/key.properties generated" -ForegroundColor Green
    }
}

function Set-iOSDisplayName {
    Write-Host ""
    Write-Host "--- iOS Display Name ---" -ForegroundColor Yellow
    $current = Read-CurrentConfig
    Write-Host "Current CFBundleDisplayName: " -NoNewline
    Write-Host $current.iosDisplayName -ForegroundColor Green
    $newName = Read-Host "New display name (empty to skip)"
    if (-not [string]::IsNullOrWhiteSpace($newName)) {
        Update-File -FilePath "$rootDir\ios\Runner\Info.plist" `
            -Pattern '(?<=<key>CFBundleDisplayName</key>\s*<string>)[^<]+' `
            -Replacement $newName `
            -Label "iOS display name"
    }
}

function Set-macOSConfig {
    Write-Host ""
    Write-Host "--- macOS Config ---" -ForegroundColor Yellow
    $file = "$rootDir\macos\Runner\Configs\AppInfo.xcconfig"
    $current = Read-CurrentConfig

    Write-Host "Current PRODUCT_NAME: " -NoNewline
    Write-Host $current.macProductName -ForegroundColor Green
    $newName = Read-Host "New PRODUCT_NAME (empty to skip)"
    if (-not [string]::IsNullOrWhiteSpace($newName)) {
        Update-File -FilePath $file -Pattern '(?m)(?<=^PRODUCT_NAME\s*=\s*).*' -Replacement $newName -Label "macOS PRODUCT_NAME"
    }

    Write-Host "Current PRODUCT_BUNDLE_IDENTIFIER: " -NoNewline
    Write-Host $current.macBundleId -ForegroundColor Green
    $newBundle = Read-Host "New Bundle ID (empty to skip)"
    if (-not [string]::IsNullOrWhiteSpace($newBundle)) {
        Update-File -FilePath $file -Pattern '(?m)(?<=^PRODUCT_BUNDLE_IDENTIFIER\s*=\s*).*' -Replacement $newBundle -Label "macOS Bundle ID"
    }

    Write-Host "Current PRODUCT_COPYRIGHT: " -NoNewline
    Write-Host $current.macCopyright -ForegroundColor Green
    $newCopyright = Read-Host "New copyright (empty to skip)"
    if (-not [string]::IsNullOrWhiteSpace($newCopyright)) {
        Update-File -FilePath $file -Pattern '(?m)(?<=^PRODUCT_COPYRIGHT\s*=\s*).*' -Replacement $newCopyright -Label "macOS copyright"
    }
}

function Set-WindowsConfig {
    Write-Host ""
    Write-Host "--- Windows Config ---" -ForegroundColor Yellow
    $file = "$rootDir\windows\runner\Runner.rc"
    $current = Read-CurrentConfig

    $fields = @(
        @{Name = "CompanyName"; Label = "CompanyName"; Current = $current.winCompany },
        @{Name = "FileDescription"; Label = "FileDescription"; Current = $current.winFileDesc },
        @{Name = "ProductName"; Label = "ProductName"; Current = $current.winProductName },
        @{Name = "OriginalFilename"; Label = "OriginalFilename"; Current = $current.winOriginalName },
        @{Name = "LegalCopyright"; Label = "LegalCopyright"; Current = $current.winCopyright }
    )

    $content = Get-Content $file -Raw -Encoding UTF8

    foreach ($f in $fields) {
        Write-Host "Current $($f.Label): " -NoNewline
        Write-Host $f.Current -ForegroundColor Green
        $newVal = Read-Host "New value (empty to skip)"
        if (-not [string]::IsNullOrWhiteSpace($newVal)) {
            $pattern = '(?<="' + $f.Name + '",\s*")[^"]+'
            if ($content -match $pattern) {
                $content = $content -replace $pattern, $newVal
                Write-Host "  [OK] $($f.Name) updated" -ForegroundColor Green
            }
            else {
                Write-Host "  [WARN] Could not match $($f.Name), please edit manually" -ForegroundColor Yellow
            }
        }
    }
    Set-Content $file -Value $content -NoNewline -Encoding UTF8
}

function Set-LinuxConfig {
    Write-Host ""
    Write-Host "--- Linux Config ---" -ForegroundColor Yellow
    $file = "$rootDir\linux\CMakeLists.txt"
    $content = Get-Content $file -Raw -Encoding UTF8
    $current = Read-CurrentConfig

    Write-Host "Current APPLICATION_ID: " -NoNewline
    Write-Host $current.linuxAppId -ForegroundColor Green
    $newId = Read-Host "New APPLICATION_ID (e.g. com.example.myapp, empty to skip)"
    if (-not [string]::IsNullOrWhiteSpace($newId)) {
        $content = $content -replace '(?<=set\(APPLICATION_ID\s+")[^"]+', $newId
        Write-Host "  [OK] Linux APPLICATION_ID updated" -ForegroundColor Green
    }

    Write-Host "Current BINARY_NAME: " -NoNewline
    Write-Host $current.linuxBinName -ForegroundColor Green
    $newBin = Read-Host "New BINARY_NAME (executable name, empty to skip)"
    if (-not [string]::IsNullOrWhiteSpace($newBin)) {
        $content = $content -replace '(?<=set\(BINARY_NAME\s+")[^"]+', $newBin
        Write-Host "  [OK] Linux BINARY_NAME updated" -ForegroundColor Green
    }
    Set-Content $file -Value $content -NoNewline -Encoding UTF8
}

function Set-WebConfig {
    Write-Host ""
    Write-Host "--- Web Config ---" -ForegroundColor Yellow
    $current = Read-CurrentConfig

    $manifestFile = "$rootDir\web\manifest.json"
    $manifest = Get-Content $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json

    Write-Host "Current name: " -NoNewline
    Write-Host $current.webName -ForegroundColor Green
    $newName = Read-Host "New name (empty to skip)"
    if (-not [string]::IsNullOrWhiteSpace($newName)) { $manifest.name = $newName }

    Write-Host "Current short_name: " -NoNewline
    Write-Host $current.webShortName -ForegroundColor Green
    $newShort = Read-Host "New short_name (empty to skip)"
    if (-not [string]::IsNullOrWhiteSpace($newShort)) { $manifest.short_name = $newShort }

    Write-Host "Current description: " -NoNewline
    Write-Host $current.webDescription -ForegroundColor Green
    $newDesc = Read-Host "New description (empty to skip)"
    if (-not [string]::IsNullOrWhiteSpace($newDesc)) { $manifest.description = $newDesc }

    $manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestFile -Encoding UTF8
    Write-Host "  [OK] web/manifest.json updated" -ForegroundColor Green

    $indexFile = "$rootDir\web\index.html"
    $indexContent = Get-Content $indexFile -Raw -Encoding UTF8
    Write-Host "Current title: " -NoNewline
    Write-Host $current.webTitle -ForegroundColor Green
    $newTitle = Read-Host "New title (empty to skip)"
    if (-not [string]::IsNullOrWhiteSpace($newTitle)) {
        $indexContent = $indexContent -replace '(?<=<title>)[^<]+(?=</title>)', $newTitle
        Set-Content $indexFile -Value $indexContent -NoNewline -Encoding UTF8
        Write-Host "  [OK] web/index.html title updated" -ForegroundColor Green
    }
}

function Set-IosBundleId {
    Write-Host ""
    Write-Host "--- iOS Bundle ID ---" -ForegroundColor Yellow
    $plistFile = "$rootDir\ios\Runner\Info.plist"
    $content = Get-Content $plistFile -Raw -Encoding UTF8

    $currentBundle = if ($content -match '<key>CFBundleIdentifier</key>\s*<string>([^<]+)</string>') {
        $matches[1]
    }
    else { "N/A" }

    Write-Host "Current CFBundleIdentifier: " -NoNewline
    Write-Host $currentBundle -ForegroundColor Green
    $newBundle = Read-Host "New Bundle ID (empty to skip)"
    if (-not [string]::IsNullOrWhiteSpace($newBundle)) {
        $content = $content -replace '(?<=<key>CFBundleIdentifier</key>\s*<string>)[^<]+', $newBundle
        Set-Content $plistFile -Value $content -NoNewline -Encoding UTF8
        Write-Host "  [OK] iOS CFBundleIdentifier updated" -ForegroundColor Green
    }
}

function Set-AppName {
    Write-Host ""
    Write-Host "--- Set App Name (All Platforms) ---" -ForegroundColor Yellow
    $current = Read-CurrentConfig
    Write-Host "Current names:" -ForegroundColor Gray
    Write-Host "  iOS display name:         $($current.iosDisplayName)"
    Write-Host "  macOS PRODUCT_NAME:       $($current.macProductName)"
    Write-Host "  Windows ProductName:      $($current.winProductName)"
    Write-Host "  Web name:                 $($current.webName)"
    Write-Host "  Web title:                $($current.webTitle)"

    $newName = Read-Host "`nEnter new app name (empty to skip)"
    if ([string]::IsNullOrWhiteSpace($newName)) {
        Write-Host "  [SKIP] Skipped" -ForegroundColor Gray
        return
    }

    Update-File -FilePath "$rootDir\ios\Runner\Info.plist" `
        -Pattern '(?<=<key>CFBundleDisplayName</key>\s*<string>)[^<]+' `
        -Replacement $newName -Label "iOS CFBundleDisplayName"

    Update-File -FilePath "$rootDir\macos\Runner\Configs\AppInfo.xcconfig" `
        -Pattern '(?m)(?<=^PRODUCT_NAME\s*=\s*).*' `
        -Replacement $newName -Label "macOS PRODUCT_NAME"

    Update-File -FilePath "$rootDir\windows\runner\Runner.rc" `
        -Pattern '(?<="ProductName",\s*")[^"]+' `
        -Replacement $newName -Label "Windows ProductName"

    $manifestFile = "$rootDir\web\manifest.json"
    $manifest = Get-Content $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifest.name = $newName
    $manifest.short_name = $newName
    $manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestFile -Encoding UTF8
    Write-Host "  [OK] Web manifest name/short_name updated" -ForegroundColor Green

    Update-File -FilePath "$rootDir\web\index.html" `
        -Pattern '(?<=<title>)[^<]+(?=</title>)' `
        -Replacement $newName -Label "Web title"

    Write-Host ""
    Write-Host "  [DONE] App name updated to: $newName" -ForegroundColor Green
}

function Set-BackendVersion {
    Write-Host ""
    Write-Host "--- Backend (Kotlin) Version ---" -ForegroundColor Yellow
    $file = "$rootDir\backend_kotlin\build.gradle.kts"
    $content = Get-Content $file -Raw -Encoding UTF8

    if ($content -match 'version\s*=\s*"([^"]+)"') {
        Write-Host "Current version: " -NoNewline
        Write-Host $matches[1] -ForegroundColor Green
    }
    else {
        Write-Host "Current: no version field set" -ForegroundColor Gray
    }

    $newVer = Read-Host "New version (empty to skip)"
    if (-not [string]::IsNullOrWhiteSpace($newVer)) {
        if ($content -match 'version\s*=') {
            $content = $content -replace '(?<=version\s*=\s*")[^"]+', $newVer
        }
        else {
            $content = $content -replace '(?<=^plugins)', "version = `"$newVer`"`n`nplugins"
        }
        Set-Content $file -Value $content -NoNewline -Encoding UTF8
        Write-Host "  [OK] Backend version updated to $newVer" -ForegroundColor Green
    }
}

function Open-iOSInXcode {
    Write-Host ""
    Write-Host "--- iOS Signing Config (Xcode) ---" -ForegroundColor Yellow
    Write-Host "iOS Bundle ID, Team, and Provisioning Profile need to be configured in Xcode." -ForegroundColor Gray
    Write-Host ""
    $openXcode = Read-Host "Open iOS project in Xcode? (y/n, default n)"
    if ($openXcode -eq "y") {
        $xcworkspace = "$rootDir\ios\Runner.xcworkspace"
        if (Test-Path $xcworkspace) {
            Write-Host "  [INFO] Opening Xcode..." -ForegroundColor Cyan
            Start-Process "open" -ArgumentList "`"$xcworkspace`"" -NoNewWindow
        }
        else {
            $xcodeproj = "$rootDir\ios\Runner.xcodeproj"
            if (Test-Path $xcodeproj) {
                Start-Process "open" -ArgumentList "`"$xcodeproj`"" -NoNewWindow
            }
            else {
                Write-Host "  [WARN] iOS project not found, please manually open ios/ directory" -ForegroundColor Yellow
            }
        }
    }
}

# ============================================================
# Non-interactive mode
# ============================================================

if ($NonInteractive -or $SetVersion -or $SetAppName) {
    $hasWork = $false
    if ($SetVersion) {
        Update-File -FilePath "$rootDir\pubspec.yaml" `
            -Pattern '(?m)(^version:\s*).*' `
            -Replacement ('${1}' + $SetVersion) `
            -Label "version"
        $hasWork = $true
    }
    if ($SetAppName) {
        Update-File -FilePath "$rootDir\ios\Runner\Info.plist" `
            -Pattern '(?<=<key>CFBundleDisplayName</key>\s*<string>)[^<]+' `
            -Replacement $SetAppName -Label "iOS CFBundleDisplayName"

        Update-File -FilePath "$rootDir\macos\Runner\Configs\AppInfo.xcconfig" `
            -Pattern '(?m)(?<=^PRODUCT_NAME\s*=\s*).*' `
            -Replacement $SetAppName -Label "macOS PRODUCT_NAME"

        Update-File -FilePath "$rootDir\windows\runner\Runner.rc" `
            -Pattern '(?<="ProductName",\s*")[^"]+' `
            -Replacement $SetAppName -Label "Windows ProductName"

        $manifestFile = "$rootDir\web\manifest.json"
        $manifest = Get-Content $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $manifest.name = $SetAppName
        $manifest.short_name = $SetAppName
        $manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestFile -Encoding UTF8
        Write-Host "  [OK] Web manifest name/short_name updated" -ForegroundColor Green

        Update-File -FilePath "$rootDir\web\index.html" `
            -Pattern '(?<=<title>)[^<]+(?=</title>)' `
            -Replacement $SetAppName -Label "Web title"

        $hasWork = $true
    }
    if (-not $hasWork) {
        Write-Host "No operation specified. Usage:" -ForegroundColor Yellow
        Write-Host "  .\configure.ps1 -SetVersion 2.0.0+1" -ForegroundColor White
        Write-Host "  .\configure.ps1 -SetAppName ""My App""" -ForegroundColor White
        Write-Host "  .\configure.ps1                          # Interactive menu" -ForegroundColor White
    }
    return
}

# ============================================================
# Interactive main menu
# ============================================================

function Show-Menu {
    Clear-Host
    Write-Host ("=" * 50) -ForegroundColor Cyan
    Write-Host "  XingHuo XueBan - Multi-Platform Config Tool" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan

    $config = Read-CurrentConfig
    Show-CurrentConfig $config

    Write-Host ("=" * 50) -ForegroundColor Cyan
    Write-Host "  Select option to modify:" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    Write-Host "  1)  Version (pubspec.yaml)" -ForegroundColor White
    Write-Host "  2)  App Name (all platforms)" -ForegroundColor White
    Write-Host "  3)  Android (appId/namespace/SDK)" -ForegroundColor White
    Write-Host "  4)  Android signing (release keystore)" -ForegroundColor White
    Write-Host "  5)  iOS display name" -ForegroundColor White
    Write-Host "  6)  iOS Bundle ID" -ForegroundColor White
    Write-Host "  7)  macOS (name/Bundle ID/copyright)" -ForegroundColor White
    Write-Host "  8)  Windows (company/product/copyright/file)" -ForegroundColor White
    Write-Host "  9)  Linux (APPLICATION_ID/BINARY_NAME)" -ForegroundColor White
    Write-Host "  10) Web (name/description/title)" -ForegroundColor White
    Write-Host "  11) Backend Kotlin version" -ForegroundColor White
    Write-Host "  12) iOS signing (open Xcode)" -ForegroundColor White
    Write-Host "  q)  Quit" -ForegroundColor White
    Write-Host ""
}

# ============================================================
# Entry point
# ============================================================

do {
    Show-Menu
    $choice = Read-Host "Enter option"
    switch ($choice) {
        "1" { Set-AppVersion }
        "2" { Set-AppName }
        "3" { Set-AndroidConfig }
        "4" { Set-AndroidSigning }
        "5" { Set-iOSDisplayName }
        "6" { Set-IosBundleId }
        "7" { Set-macOSConfig }
        "8" { Set-WindowsConfig }
        "9" { Set-LinuxConfig }
        "10" { Set-WebConfig }
        "11" { Set-BackendVersion }
        "12" { Open-iOSInXcode }
        "q" { Write-Host "Goodbye!" -ForegroundColor Cyan; break }
        default { Write-Host "Invalid option, please try again" -ForegroundColor Red }
    }
    if ($choice -ne "q") {
        Write-Host ""
        $null = Read-Host "Press Enter to return to menu..."
    }
} while ($choice -ne "q")
