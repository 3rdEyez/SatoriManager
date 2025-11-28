# SatoriManager React Native 项目一键初始化脚本 (Windows)
# 使用方法: .\init.ps1

$ErrorActionPreference = "Stop"

Write-Host "🚀 SatoriManager React Native 项目初始化..." -ForegroundColor Cyan
Write-Host ""

# 检查 Node.js
try {
    $nodeVersion = node -v
    $versionNumber = [int]($nodeVersion -replace 'v(\d+)\..*', '$1')
    if ($versionNumber -lt 18) {
        Write-Host "❌ Node.js 版本过低，需要 18+，当前: $nodeVersion" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Node.js: $nodeVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ Node.js 未安装，请先安装 Node.js 18+" -ForegroundColor Red
    exit 1
}

# 检查 pnpm
try {
    $pnpmVersion = pnpm -v
    Write-Host "✅ pnpm: $pnpmVersion" -ForegroundColor Green
} catch {
    Write-Host "📦 安装 pnpm..." -ForegroundColor Yellow
    npm install -g pnpm
    Write-Host "✅ pnpm 安装完成" -ForegroundColor Green
}

# 安装依赖
Write-Host ""
Write-Host "📦 安装项目依赖..." -ForegroundColor Yellow
pnpm install

# 检查 Android 配置
Write-Host ""
Write-Host "🤖 检查 Android 配置..." -ForegroundColor Yellow

$androidHome = $env:ANDROID_HOME
if ([string]::IsNullOrEmpty($androidHome)) {
    $localPropsPath = "android/local.properties"
    if (-not (Test-Path $localPropsPath)) {
        Write-Host "⚠️  ANDROID_HOME 环境变量未设置" -ForegroundColor Yellow
        Write-Host "   请设置 Android SDK 路径:" -ForegroundColor Yellow

        # 尝试自动检测常见位置
        $possiblePaths = @(
            "$env:LOCALAPPDATA\Android\Sdk",
            "$env:USERPROFILE\AppData\Local\Android\Sdk",
            "C:\Android\Sdk"
        )

        foreach ($path in $possiblePaths) {
            if (Test-Path $path) {
                Write-Host "   发现可能的 SDK 路径: $path" -ForegroundColor Cyan

                # 创建 local.properties
                if (-not (Test-Path "android")) {
                    New-Item -ItemType Directory -Path "android" -Force | Out-Null
                }
                $sdkPath = $path -replace '\\', '/'
                "sdk.dir=$sdkPath" | Out-File -FilePath $localPropsPath -Encoding UTF8
                Write-Host "   已创建 android/local.properties" -ForegroundColor Green
                break
            }
        }
    }
} else {
    Write-Host "✅ ANDROID_HOME: $androidHome" -ForegroundColor Green
}

# 检查 Java
try {
    $javaVersion = java -version 2>&1 | Select-String "version"
    Write-Host "✅ Java: $javaVersion" -ForegroundColor Green
} catch {
    Write-Host "⚠️  Java 未安装，运行 Android 需要 JDK 17+" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "✅ 初始化完成!" -ForegroundColor Green
Write-Host ""
Write-Host "📱 启动开发服务器:" -ForegroundColor White
Write-Host "   pnpm start" -ForegroundColor Yellow
Write-Host ""
Write-Host "🤖 运行 Android:" -ForegroundColor White
Write-Host "   pnpm android" -ForegroundColor Yellow
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
