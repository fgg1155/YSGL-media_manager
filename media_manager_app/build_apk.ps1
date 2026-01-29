# Android APK 构建脚本
# 解决 Gradle 插件兼容性问题

Write-Host "开始构建 Android APK..." -ForegroundColor Green

# 1. 清理构建缓存
Write-Host "`n[1/4] 清理构建缓存..." -ForegroundColor Yellow
flutter clean
if ($LASTEXITCODE -ne 0) {
    Write-Host "清理失败！" -ForegroundColor Red
    exit 1
}

# 2. 获取依赖
Write-Host "`n[2/4] 获取依赖..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "获取依赖失败！" -ForegroundColor Red
    exit 1
}

# 3. 构建 APK
Write-Host "`n[3/4] 构建 Release APK..." -ForegroundColor Yellow
flutter build apk --release --no-tree-shake-icons
if ($LASTEXITCODE -ne 0) {
    Write-Host "构建失败！" -ForegroundColor Red
    Write-Host "`n尝试使用 debug 模式构建..." -ForegroundColor Yellow
    flutter build apk --debug
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Debug 构建也失败！" -ForegroundColor Red
        exit 1
    }
}

# 4. 显示构建结果
Write-Host "`n[4/4] 构建完成！" -ForegroundColor Green
$apkPath = "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apkPath) {
    $apkSize = (Get-Item $apkPath).Length / 1MB
    $roundedSize = [math]::Round($apkSize, 2)
    Write-Host "APK 位置: $apkPath" -ForegroundColor Cyan
    Write-Host "APK 大小: $roundedSize MB" -ForegroundColor Cyan
} else {
    Write-Host "未找到 APK 文件！" -ForegroundColor Red
    exit 1
}

Write-Host "`n✅ 构建成功！" -ForegroundColor Green
