@echo off
rem ============================================================
rem  VPOT MSI Automated Test - double-click to run (as admin)
rem  Requirements: test-msi.ps1 and vpot-setup-1.1.5-zh-CN.msi
rem                must be in the same folder as this file
rem  Logs: %TEMP%\vpot-test\install.log / repair.log / uninstall.log
rem ============================================================
cd /d "%~dp0"

echo.
echo  ==========================================
echo   VPOT MSI Automated Test
echo  ==========================================
echo   Test: silent install -^> repair -^> uninstall
echo   Check: exit codes, D:\vpot files, registry,
echo          start menu shortcut, MSI error codes
echo   Logs:  %TEMP%\vpot-test\
echo  ==========================================
echo.

if not exist "%~dp0test-msi.ps1" (
    echo [ERROR] test-msi.ps1 not found in %~dp0
    pause
    exit /b 1
)
if not exist "%~dp0vpot-setup-1.1.5-zh-CN.msi" (
    echo [ERROR] vpot-setup-1.1.5-zh-CN.msi not found in %~dp0
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0test-msi.ps1"

echo.
echo  ==========================================
echo   Test finished. See output above and
echo   logs in %TEMP%\vpot-test\
echo  ==========================================
echo.
pause
