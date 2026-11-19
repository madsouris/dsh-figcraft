@echo off
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0figcraft-session.ps1" down %*
exit /b %ERRORLEVEL%
