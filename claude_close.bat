@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\claude_close.ps1" %*
