@echo off
setlocal enabledelayedexpansion
:: ============================================================
::    VPOT Docker 安装脚本（Windows 批处理版本）
:: ============================================================
:: 要求：Windows 10+ 64位 或 Windows 11
:: 请以管理员身份运行以安装 Docker Desktop

set "ScriptDir=%~dp0"
set "ComposeFile=%ScriptDir%docker-compose.yaml"

echo ========================================
echo     VPOT Docker 安装脚本
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
    echo     请启动 Docker Desktop，然后重新运行此脚本。
    pause
    exit /b 1
)

call :StartVpotContainers
if %ERRORLEVEL% neq 0 (
    exit /b 1
)

echo.
echo ========================================
echo   VPOT 部署完成！
echo   服务地址：http://localhost:18800
echo ========================================
start "" "http://localhost:18800"
pause
exit /b 0

:: -------------------------------------------------------------------
:: Step 1: Detect Docker
:: -------------------------------------------------------------------
:TestDockerInstalled
    echo [*] 正在检查 Docker 安装状态...
    where docker >nul 2>&1
    if %ERRORLEVEL% equ 0 (
        for /f "tokens=*" %%i in ('docker --version 2^>^&1') do echo     %%i
        exit /b 0
    )
    echo     未找到 Docker。
    exit /b 1

:TestDockerRunning
    echo [*] 正在检查 Docker 守护进程是否运行...
    docker info >nul 2>&1
    if %ERRORLEVEL% equ 0 (
        echo     Docker 守护进程正在运行。
        exit /b 0
    )
    echo     Docker 守护进程未运行。
    exit /b 1

:: -------------------------------------------------------------------
:: Step 2: Install Docker
:: -------------------------------------------------------------------
:InvokeDockerInstall
    echo [*] Docker 未安装，正在开始安装...
    echo.
    call :InstallDockerWinget
    if %ERRORLEVEL% neq 0 (
        call :InstallDockerManual
    )

    echo.
    echo ========================================
    echo   Docker 安装已启动。
    echo   您可能需要：
    echo     - 注销并重新登录
    echo     - 或重启计算机
    echo   然后重新运行此脚本以继续。
    echo ========================================
    pause
    exit /b 0

:InstallDockerWinget
    echo [*] 正在尝试通过 winget 安装 Docker Desktop...
    where winget >nul 2>&1
    if %ERRORLEVEL% neq 0 (
        echo     winget 未找到。
        exit /b 1
    )
    echo     正在安装 Docker Desktop（可能需要几分钟）...
    winget install --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements --silent
    exit /b %ERRORLEVEL%

:InstallDockerManual
    echo ========================================
    echo   需要手动安装 Docker
    echo ========================================
    echo.
    echo   Docker Desktop 无法自动安装。
    echo   请从以下地址下载并安装：
    echo     https://docs.docker.com/desktop/install/windows-install/
    echo.
    echo   安装并重启后，重新运行此脚本。
    echo.
    start "" "https://docs.docker.com/desktop/install/windows-install/"
    exit /b 1

:: -------------------------------------------------------------------
:: Step 3: Start containers
:: -------------------------------------------------------------------
:StartVpotContainers
    echo [*] 正在启动 VPOT 容器...
    echo     Compose 文件：%ComposeFile%

    if not exist "%ComposeFile%" (
        echo     错误：未找到 Compose 文件：%ComposeFile%
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
        echo     错误：未找到 docker compose 插件或 docker-compose。
        echo     请确认 Docker Desktop 已安装并正在运行。
        pause
        exit /b 1
    )

    :: Check and clean up any existing vpot container to avoid name conflict
    echo     正在检查已存在的 vpot 容器...
    docker ps -a --format "{{.Names}}" 2>nul | findstr /b /e "vpot" >nul
    if !ERRORLEVEL! equ 0 (
        echo     发现已存在的 vpot 容器，正在移除...
        docker rm -f vpot >nul 2>&1
        if !ERRORLEVEL! neq 0 (
            echo     错误：无法移除已存在的 vpot 容器。
            echo     请手动运行以下命令后重试：
            echo       docker rm -f vpot
            pause
            exit /b 1
        )
        echo     旧 vpot 容器已成功移除。
    )

    echo     正在运行：!composeCmd! -f "%ComposeFile%" up -d
    !composeCmd! -f "%ComposeFile%" up -d

    if !ERRORLEVEL! neq 0 (
        echo.
        echo     =============================================
        echo       错误：docker compose 执行失败。
        echo       退出代码：!ERRORLEVEL!
        echo       请检查上方输出以了解详情。
        echo     =============================================
        echo.
        pause
        exit /b 1
    )

    echo     容器启动成功。
    exit /b 0
