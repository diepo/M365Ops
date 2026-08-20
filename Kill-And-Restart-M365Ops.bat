@echo off
title M365Ops - Termina e riavvia
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Kill-And-Restart-M365Ops.ps1"
echo.
pause
