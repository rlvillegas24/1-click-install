@echo off
setlocal

:: ── Re-launch as Administrator if not already elevated ────────────────────────
net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    powershell.exe -Command "Start-Process -FilePath '%~f0' -Verb RunAs -Wait"
    exit /b
)

:: ── Run the PowerShell installer (bypass execution policy for this process) ───
set "SCRIPT=%~dp0install.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"

if %ERRORLEVEL% neq 0 (
    echo.
    echo [!] Installation finished with errors. See output above.
    pause
)
endlocal
