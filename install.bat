@echo off
setlocal

set "REPO_PS=https://raw.githubusercontent.com/lmmagbuhos/1-click-install/main/install.ps1"

:: ── Allow locally created scripts for future PowerShell launches ─────────────
powershell.exe -NoProfile -Command "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force"

:: ── Resolve install.ps1 source:
::   1) script directory (batch + script together)
::   2) current directory (legacy/alternate invocation)
::   3) GitHub repo raw file (works even when local files are elsewhere)
set "SCRIPT_FROM_REMOTE=0"
if exist "%~dp0install.ps1" (
    set "SCRIPT=%~dp0install.ps1"
) else if exist "%CD%\install.ps1" (
    set "SCRIPT=%CD%\install.ps1"
) else (
    set "SCRIPT=%TEMP%\install.ps1"
    set "SCRIPT_FROM_REMOTE=1"
    powershell.exe -NoProfile -Command "Invoke-WebRequest -Uri '%REPO_PS%' -OutFile '%SCRIPT%' -UseBasicParsing"
)

if not exist "%SCRIPT%" (
    echo.
    echo [!] install.ps1 not found.
    echo.
    echo Put install.ps1 beside install.bat, or run from folder containing install.ps1.
    echo Or ensure network access to:
    echo     %REPO_PS%
    pause
    exit /b 1
)

:: ── Run the PowerShell installer (bypass execution policy for this process) ───
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "BAT_ERROR=%ERRORLEVEL%"
if "%SCRIPT_FROM_REMOTE%"=="1" if exist "%SCRIPT%" del /q "%SCRIPT%" 2>nul

if %BAT_ERROR% neq 0 (
    echo.
    echo [!] Installation finished with errors. See output above.
    pause
    exit /b %BAT_ERROR%
)
endlocal
exit /b 0
