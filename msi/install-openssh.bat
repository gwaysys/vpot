@echo off
rem ============================================================
rem  VPOT MSI test helper: install & start OpenSSH Server
rem  Double-click to run (auto-elevates via UAC).
rem  After success, connect from Linux:
rem      ssh <username>@10.0.2.104
rem ============================================================
setlocal

rem ---- [0] self-elevate to Administrator ----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
cd /d "%~dp0"

echo ============================================
echo   OpenSSH Server installer (for remote MSI test)
echo ============================================
echo.

rem ---- [1/5] check admin rights ----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Admin rights required.
    echo         Right-click this file and choose "Run as administrator".
    echo.
    pause
    exit /b 1
)
echo [1/5] Admin rights OK

rem ---- [2/5] install OpenSSH Server capability ----
echo [2/5] Installing OpenSSH Server (may take 1-2 minutes)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0" >nul 2>&1
if %errorlevel% neq 0 (
    echo [..] Add-WindowsCapability failed, retrying with DISM...
    dism /online /add-capability /capabilityname:OpenSSH.Server~~~~0.0.1.0 >nul 2>&1
)
sc query sshd >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] OpenSSH Server install failed.
    echo         Check Windows features or run: Get-WindowsCapability -Online ^| where Name -like 'OpenSSH*'
    echo.
    pause
    exit /b 1
)
echo [2/5] OpenSSH Server installed

rem ---- [3/5] start service + auto start ----
echo [3/5] Starting sshd service...
net start sshd >nul 2>&1
sc config sshd start= auto >nul 2>&1
echo [3/5] sshd service started (auto-start enabled)

rem ---- [4/5] firewall rule for port 22 ----
echo [4/5] Adding firewall rule for TCP 22...
powershell -NoProfile -Command "New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22" >nul 2>&1
echo [4/5] Firewall rule added

rem ---- [5/5] verify ----
echo [5/5] Verifying service state:
sc query sshd | findstr /i "STATE"

echo.
echo ============================================
echo   DONE. Connect from Linux:
echo     ssh <username>@10.0.2.104
echo   (username = the account you use on this machine,
echo    e.g. administrator)
echo ============================================
echo.
pause
endlocal
