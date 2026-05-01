@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%ssh-manager.ps1"
set "HIDDEN_VBS=%SCRIPT_DIR%run-hidden.vbs"

if /I "%~1" NEQ "-console" (
  if exist "%HIDDEN_VBS%" (
    wscript.exe "%HIDDEN_VBS%"
    exit /b 0
  )
)

if not exist "%PS_SCRIPT%" (
  echo [ERROR] File not found: "%PS_SCRIPT%"
  pause
  exit /b 1
)

echo [INFO] Starting SSH Key Manager...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  echo [ERROR] Application exited with code %EXIT_CODE%
  echo Check ssh-manager.log in this folder for details.
  pause
)

exit /b %EXIT_CODE%
