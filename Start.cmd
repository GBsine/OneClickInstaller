@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -WindowStyle Hidden -File "%~dp0OneClickInstaller.ps1"
if errorlevel 1 pause
