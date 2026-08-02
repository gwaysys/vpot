@echo off
setlocal enabledelayedexpansion
:: ============================================================
::    VPOT Docker Install Script for Windows (batch version)
:: ============================================================
:: Requires: Windows 10+ 64-bit or Windows 11
:: Administrator privileges may be required for automatic installation

set "ScriptDir=%~dp0"
set "ComposeFile=%ScriptDir%docker-compose.yaml"

echo ========================================
echo     VPOT Docker Install Script
echo ========================================
echo.

:: -------------------------------------------------------------------
:: Main
:: -------------------------------------------------------------------
:: Skip the elevation prompt when re-launched elevated after user approval
if /i "%~1"=="/confirmed" set "VPOT_CONFIRMED=1"

call :PlanInstallations
if !ERRORLEVEL! neq 0 (
    if not defined VPOT_CONFIRMED (
        call :EnsureAdmin
        if !ERRORLEVEL! neq 0 (
            echo.
            echo   Please re-run this script as Administrator
            echo   if the elevation was not authorized.
            pause
            exit /b 1
        )
    )
    call :InstallMissingComponents
    if !ERRORLEVEL! neq 0 (
        exit /b 1
    )
)

:retry_docker
call :TestDockerRunning
if %ERRORLEVEL% neq 0 (
    echo.
    echo     Docker is not running. Start Docker Desktop and press any key to retry...
    pause
    goto retry_docker
)

call :StartVpotContainers
if %ERRORLEVEL% neq 0 (
    exit /b 1
)

echo.
echo ========================================
echo   VPOT deployment complete!
echo   Service available at: http://localhost:18800
echo ========================================
start "" "http://localhost:18800"
pause
exit /b 0

:: -------------------------------------------------------------------
:: Step 1: Detect Docker
:: -------------------------------------------------------------------
:TestDockerInstalled
    echo [*] Checking Docker installation...
    where docker >nul 2>&1
    if %ERRORLEVEL% equ 0 (
        for /f "tokens=*" %%i in ('docker --version 2^>^&1') do echo     %%i
        exit /b 0
    )
    echo     Docker not found.
    exit /b 1

:TestDockerRunning
    echo [*] Checking if Docker daemon is running...
    docker info >nul 2>&1
    if %ERRORLEVEL% equ 0 (
        echo     Docker daemon is running.
        exit /b 0
    )
    echo     Docker daemon is NOT running.
    exit /b 1

:: -------------------------------------------------------------------
:: Step 1.1: Plan installs (decide what needs to be installed)
:: -------------------------------------------------------------------
:PlanInstallations
    set "needDocker="
    set "needWsl="
    call :TestDockerInstalled
    if %ERRORLEVEL% neq 0 (
        set "needDocker=1"
        call :TestWslInstalled
        if !ERRORLEVEL! neq 0 (
            set "needWsl=1"
        )
    )
    if defined needDocker exit /b 1
    if defined needWsl exit /b 1
    exit /b 0

:: -------------------------------------------------------------------
:: Step 1.2: Elevate to Administrator via UAC (needed for auto-install)
:: -------------------------------------------------------------------
:EnsureAdmin
    net session >nul 2>&1
    if %ERRORLEVEL% equ 0 (
        echo     Running with Administrator privileges.
        exit /b 0
    )
    echo.
    echo   Administrator privileges required. Requesting elevation...
    echo   Please click "Yes" in the UAC prompt to continue.
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '/confirmed' -Verb RunAs" >nul 2>&1
    exit /b 1

:: -------------------------------------------------------------------
:: Step 2: Install missing components (each confirmed with the user)
:: -------------------------------------------------------------------
:InstallMissingComponents
    if defined needWsl (
        call :InstallComponentWsl
        if !ERRORLEVEL! neq 0 (
            exit /b 1
        )
    )
    if defined needDocker (
        call :InstallComponentDocker
        if !ERRORLEVEL! neq 0 (
            exit /b 1
        )
    )
    exit /b 0

:InstallComponentWsl
    echo.
    echo ========================================
    echo   WSL 2 is not installed.
    echo   ----------------------------------------
    echo     [A] Auto-install via wsl --install
    echo     [B] Download manually (opens browser)
    echo   ----------------------------------------
    set "wslChoice="
    set /p "wslChoice=  Your choice (A/B): "
    if /i "!wslChoice!"=="A" (
        call :InstallWslAuto
        exit /b !ERRORLEVEL!
    )
    call :PromptWslDownload
    exit /b !ERRORLEVEL!

:InstallComponentDocker
    echo.
    echo ========================================
    echo   Docker Desktop is not installed.
    echo   ----------------------------------------
    echo     [A] Auto-install via winget
    echo     [B] Download manually (opens browser)
    echo   ----------------------------------------
    set "dockerChoice="
    set /p "dockerChoice=  Your choice (A/B): "
    if /i "!dockerChoice!"=="A" (
        call :InstallDockerAuto
        exit /b !ERRORLEVEL!
    )
    call :PromptDockerDownload
    exit /b !ERRORLEVEL!

:InstallWslAuto
    echo.
    echo     Installing WSL via wsl --install...
    echo     This enables required Windows features and installs a Linux distribution.
    wsl --install
    if %ERRORLEVEL% neq 0 (
        echo.
        echo     ERROR: wsl --install failed (exit code %ERRORLEVEL%).
        echo     A browser window will open for manual installation.
        call :PromptWslDownload
        exit /b %ERRORLEVEL%
    )
    echo.
    echo     WSL has been installed.
    echo     A REBOOT is required before continuing.
    echo     After reboot, re-run this script.
    pause
    exit /b 1

:InstallDockerAuto
    where winget >nul 2>&1
    if %ERRORLEVEL% neq 0 (
        echo     winget not found. Opening manual download page...
        call :PromptDockerDownload
        exit /b %ERRORLEVEL%
    )
    echo.
    echo     Installing Docker Desktop via winget (this may take several minutes)...
    winget install --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements --silent
    if %ERRORLEVEL% neq 0 (
        echo.
        echo     ERROR: winget install failed (exit code %ERRORLEVEL%).
        echo     A browser window will open for manual installation.
        call :PromptDockerDownload
        exit /b %ERRORLEVEL%
    )
    echo.
    echo     Docker Desktop installed successfully.
    echo     You may need to log out and log back in, or reboot.
    echo     Then re-run this script to continue.
    pause
    exit /b 0

:: -------------------------------------------------------------------
:: Step 2.1: WSL helpers (required by Docker Desktop)
:: -------------------------------------------------------------------
:TestWslInstalled
    echo [*] Checking WSL installation...
    where wsl >nul 2>&1
    if %ERRORLEVEL% neq 0 (
        echo     WSL not found.
        exit /b 1
    )
    wsl --status >nul 2>&1
    if %ERRORLEVEL% equ 0 (
        echo     WSL is installed and ready.
        exit /b 0
    )
    wsl --list --quiet >nul 2>&1
    if %ERRORLEVEL% equ 0 (
        echo     WSL is installed (no distribution configured yet).
        exit /b 0
    )
    echo     WSL is present but not fully installed/configured.
    exit /b 1

:PromptWslDownload
    echo.
    echo ========================================
    echo   WSL 2 is required but not installed.
    echo   A browser window will open to download the
    echo   official WSL update package:
    echo     https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi
    echo   Please download and run it, then reboot if prompted.
    echo ========================================
    echo.
    start "" "https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi"
    echo     Press any key once WSL has been installed...
    pause >nul
    call :TestWslInstalled
    if %ERRORLEVEL% equ 0 (
        echo     WSL detected. Continuing...
        exit /b 0
    )
    echo.
    echo     WSL was not detected yet.
    echo     Please install it (and reboot if prompted), then re-run this script.
    pause
    exit /b 1

:PromptDockerDownload
    echo.
    echo ========================================
    echo   Docker Desktop is not installed.
    echo   A browser window will open to download
    echo   Docker Desktop for Windows:
    echo     https://www.docker.com/products/docker-desktop/
    echo   Please download and install it manually,
    echo   then reboot or log out/back in if prompted.
    echo ========================================
    echo.
    start "" "https://www.docker.com/products/docker-desktop/"
    echo     Press any key once Docker Desktop is installed...
    pause >nul

    call :TestDockerInstalled
    if %ERRORLEVEL% equ 0 (
        echo     Docker Desktop detected. Continuing...
        exit /b 0
    )
    echo.
    echo     Docker Desktop was not detected yet.
    echo     Please install it and re-run this script.
    pause
    exit /b 1

:: -------------------------------------------------------------------
:: Step 3: Start containers
:: -------------------------------------------------------------------
:StartVpotContainers
    echo [*] Starting VPOT containers...
    echo     Compose file: %ComposeFile%

    if not exist "%ComposeFile%" (
        echo     ERROR: Compose file not found at %ComposeFile%
        pause
        exit /b 1
    )

    :: Prefer docker compose (v2 plugin), fall back to docker-compose (v1)
    set "composeCmd="
    docker compose version >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        set "composeCmd=docker compose"
    )
    if "!composeCmd!"=="" (
        where docker-compose >nul 2>&1
        if !ERRORLEVEL! equ 0 (
            set "composeCmd=docker-compose"
        )
    )

    if "!composeCmd!"=="" (
        echo     ERROR: docker compose plugin nor docker-compose found.
        echo     Make sure Docker Desktop is installed and running.
        pause
        exit /b 1
    )

    :: Check and clean up any existing vpot container to avoid name conflict
    echo     Checking for existing vpot container...
    docker ps -a --format "{{.Names}}" 2>nul | findstr /b /e "vpot" >nul
    if !ERRORLEVEL! equ 0 (
        echo     Existing vpot container found, removing it...
        docker rm -f vpot >nul 2>&1
        if !ERRORLEVEL! neq 0 (
            echo     ERROR: Failed to remove existing vpot container.
            echo     Please run the following command manually then retry:
            echo       docker rm -f vpot
            pause
            exit /b 1
        )
        echo     Old vpot container removed successfully.
    )

    echo     Running: !composeCmd! -f "%ComposeFile%" up -d
    !composeCmd! -f "%ComposeFile%" up -d

    if !ERRORLEVEL! neq 0 (
        echo.
        echo     =============================================
        echo       ERROR: docker compose failed.
        echo       Exit code: !ERRORLEVEL!
        echo       Please check the output above for details.
        echo     =============================================
        echo.
        pause
        exit /b 1
    )

    echo     Containers started successfully.
    exit /b 0
