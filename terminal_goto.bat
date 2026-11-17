@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0goto_folder.ps1" -Index "%1" -App terminal
