@echo off
chcp 65001 >nul

:: 获取脚本所在目录
set "SCRIPT_DIR=%~dp0"
set "GAME_DIR=%SCRIPT_DIR%Windows-UZDoom-Nightly"
set "EXE_PATH=%GAME_DIR%\uzdoom.exe"

if not exist "%EXE_PATH%" (
    echo 【错误】未找到: %EXE_PATH%
    exit /b 1
)

:: 切换到游戏目录，确保相对路径正确
cd /d "%GAME_DIR%"

:: 使用 start /B 或 start "" 启动
:: /B 表示不创建新窗口（如果游戏是控制台程序）
:: 对于 GUI 程序（如游戏），直接用 start "" 即可
start "" "uzdoom.exe"

:: 立即退出，不等待
exit /b 0