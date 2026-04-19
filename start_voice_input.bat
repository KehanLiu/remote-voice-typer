@echo off
setlocal
cd /d "%~dp0"
echo Starting Voice Input launcher...
echo.
powershell -NoExit -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0start_voice_input.ps1'"
endlocal
