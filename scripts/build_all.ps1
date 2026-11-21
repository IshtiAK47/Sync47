<#
.SYNOPSIS
    Sync47 Automated Monorepo Build Script
    Builds sync47_core, sync47_pc, and sync47_android.
#>

param(
    [switch]$SkipTests = $false,
    [switch]$AndroidOnly = $false,
    [switch]$WindowsOnly = $false
)

$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent $PSScriptRoot

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   Sync47 Monorepo Automated Builder" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Root Directory: $rootDir"

# 1. Verify Core Package
if (-not $SkipTests) {
    Write-Host "`n[1/3] Testing sync47_core..." -ForegroundColor Yellow
    Push-Location "$rootDir\packages\sync47_core"
    try {
        dart analyze
        dart test
        Write-Host "✓ sync47_core passed all tests and analysis." -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

# 2. Build sync47_pc
if (-not $AndroidOnly) {
    Write-Host "`n[2/3] Building sync47_pc Windows Release..." -ForegroundColor Yellow
    Push-Location "$rootDir\apps\sync47_pc"
    try {
        flutter analyze
        if (-not $SkipTests) {
            flutter test
        }

        Write-Host "Compiling Windows Release binary..." -ForegroundColor Cyan
        flutter build windows --release
        $pcExe = "$rootDir\apps\sync47_pc\build\windows\x64\runner\Release\sync47_pc.exe"
        if (Test-Path $pcExe) {
            Write-Host "✓ Windows Release Binary: $pcExe" -ForegroundColor Green
        }
    } finally {
        Pop-Location
    }
}

# 3. Build sync47_android
if (-not $WindowsOnly) {
    Write-Host "`n[3/3] Building sync47_android Release APK..." -ForegroundColor Yellow
    Push-Location "$rootDir\apps\sync47_android"
    try {
        flutter analyze
        if (-not $SkipTests) {
            flutter test
            Push-Location "android"
            try {
                .\gradlew.bat :app:testDebugUnitTest
            } finally {
                Pop-Location
            }
        }

        Write-Host "Compiling Android Release APK..." -ForegroundColor Cyan
        flutter build apk --release

        $apkPath = "$rootDir\apps\sync47_android\build\app\outputs\flutter-apk\app-release.apk"
        if (Test-Path $apkPath) {
            Write-Host "✓ Android Release APK: $apkPath" -ForegroundColor Green
        }
    } finally {
        Pop-Location
    }
}

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "   Sync47 Monorepo Build Succeeded!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
