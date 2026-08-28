@echo off
setlocal
rem Process-only Bypass. This does not change the persistent execution policy.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0OpenClaw-XQ-Diagnose.ps1" %*
exit /b %ERRORLEVEL%
