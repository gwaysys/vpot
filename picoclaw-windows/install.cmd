@echo off
setlocal enabledelayedexpansion
:: ============================================================
::    VPOT Docker Install Script for Windows (batch version)
:: ============================================================
:: Requires: Windows 10+ 64-bit or Windows 11
:: Run as Administrator for Docker Desktop installation

set "ScriptDir=%~dp0"
set "ComposeFile=%ScriptDir%docker-compose.yaml"

echo ========================================
echo     VPOT Docker Install Script
echo ========================================
echo.

:: -------------------------------------------------------------------
:: Main
:: -------------------------------------------------------------------
call :TestDockerInstalled
if %ERRORLEVEL% neq 0 (
    call :InvokeDockerInstall
)

call :TestDockerRunning
if %ERRORLEVEL% neq 0 (
    echo.
    echo     Please start Docker Desktop, then re-run this script.
    pause
    exit /b 1
)

call :StartVpotContainers
if %ERRORLEVEL% neq 0 (
    pause
    exit /b 1
)

echo.
echo ========================================
echo   VPOT deployment complete!
echo   Service available at: http://localhost:18800
echo ========================================
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
:: Step 2: Install Docker
:: -------------------------------------------------------------------
:InvokeDockerInstall
    echo [*] Docker is not installed. Starting installation...
    echo.
    call :InstallDockerWinget
    if %ERRORLEVEL% neq 0 (
        call :InstallDockerManual
    )

    echo.
    echo ========================================
    echo   Docker installation initiated.
    echo   You may need to:
    echo     - Log out and log back in
    echo     - OR reboot your machine
    echo   Then re-run this script to continue.
    echo ========================================
    pause
    exit /b 0

:InstallDockerWinget
    echo [*] Attempting to install Docker Desktop via winget...
    where winget >nul 2>&1
    if %ERRORLEVEL% neq 0 (
        echo     winget not found.
        exit /b 1
    )
    echo     Installing Docker Desktop (this may take several minutes)...
    winget install --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements --silent
    exit /b %ERRORLEVEL%

:InstallDockerManual
    echo ========================================
    echo   Manual Docker Installation Required
    echo ========================================
    echo.
    echo   Docker Desktop could not be installed automatically.
    echo   Please download and install it from:
    echo     https://docs.docker.com/desktop/install/windows-install/
    echo.
    echo   After installation and reboot, re-run this script.
    echo.
    start "" "https://docs.docker.com/desktop/install/windows-install/"
    exit /b 1

:: -------------------------------------------------------------------
:: Step 3: Start containers
:: -------------------------------------------------------------------
:StartVpotContainers
    echo [*] Starting VPOT containers...
    echo     Compose file: %ComposeFile%

    if not exist "%ComposeFile%" (
        echo     ERROR: Compose file not found at %ComposeFile%
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
        exit /b 1
    )

    echo     Running: !composeCmd! -f "%ComposeFile%" up -d
    !composeCmd! -f "%ComposeFile%" up -d

    if !ERRORLEVEL! neq 0 (
        echo     ERROR: docker compose failed (exit code !ERRORLEVEL!).
        exit /b 1
    )

    echo     Containers started successfully.
    exit /b 0
