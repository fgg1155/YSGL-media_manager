# FFmpeg 下载脚本
# 此脚本会下载 FFmpeg 并将其放置到正确的位置

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FFmpeg 下载脚本" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$ffmpegDir = "assets\ffmpeg"
$ffmpegZip = "ffmpeg-essentials.zip"
$ffmpegUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"

# 创建目录
if (-not (Test-Path $ffmpegDir)) {
    New-Item -ItemType Directory -Force -Path $ffmpegDir | Out-Null
    Write-Host "✓ 创建目录: $ffmpegDir" -ForegroundColor Green
}

Write-Host ""
Write-Host "正在下载 FFmpeg (约 70MB)..." -ForegroundColor Yellow
Write-Host "下载地址: $ffmpegUrl" -ForegroundColor Gray
Write-Host ""

try {
    # 下载 FFmpeg
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $ffmpegUrl -OutFile $ffmpegZip -TimeoutSec 600
    Write-Host "✓ 下载完成" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "正在解压..." -ForegroundColor Yellow
    
    # 解压
    Expand-Archive -Path $ffmpegZip -DestinationPath "temp_ffmpeg" -Force
    
    # 查找 ffmpeg.exe
    $ffmpegExe = Get-ChildItem -Path "temp_ffmpeg" -Filter "ffmpeg.exe" -Recurse | Select-Object -First 1
    
    if ($ffmpegExe) {
        # 复制到目标目录
        Copy-Item -Path $ffmpegExe.FullName -Destination "$ffmpegDir\ffmpeg.exe" -Force
        Write-Host "✓ FFmpeg 已安装到: $ffmpegDir\ffmpeg.exe" -ForegroundColor Green
        
        # 获取文件大小
        $fileSize = (Get-Item "$ffmpegDir\ffmpeg.exe").Length / 1MB
        Write-Host "  文件大小: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Gray
    } else {
        Write-Host "✗ 未找到 ffmpeg.exe" -ForegroundColor Red
        exit 1
    }
    
    # 清理临时文件
    Write-Host ""
    Write-Host "清理临时文件..." -ForegroundColor Yellow
    Remove-Item -Path $ffmpegZip -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "temp_ffmpeg" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "✓ 清理完成" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "FFmpeg 安装成功！" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "现在可以运行应用了:" -ForegroundColor Yellow
    Write-Host "  flutter run -d windows" -ForegroundColor White
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "✗ 下载失败: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "请尝试以下方法:" -ForegroundColor Yellow
    Write-Host "1. 检查网络连接" -ForegroundColor White
    Write-Host "2. 手动下载 FFmpeg:" -ForegroundColor White
    Write-Host "   下载地址: https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" -ForegroundColor Gray
    Write-Host "3. 解压后将 ffmpeg.exe 复制到: $ffmpegDir\" -ForegroundColor White
    Write-Host ""
    exit 1
}
