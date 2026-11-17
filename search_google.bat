@echo off
setlocal
set "QUERY=%*"
if "%QUERY%"=="" (
    echo Usage: search_google.bat ^<query^>
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0search_chrome.ps1" -Query "%QUERY%"
