@echo off
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0src\Update-RebasedChinese.ps1"
pause
