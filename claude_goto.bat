@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\goto_folder.ps1" -Index "%1" -App claude
