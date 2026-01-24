@echo off
REM Media Scraper Plugin Launcher
REM 启动 Python 插件主程序

REM 获取脚本所在目录
set SCRIPT_DIR=%~dp0

REM 切换到插件目录
cd /d "%SCRIPT_DIR%"

REM 运行 Python 插件（使用 run_plugin.py 以正确加载依赖）
python run_plugin.py
