@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
:: ============================================================
::    VPOT Install Script for Windows (bilingual)
::    中英双语:开始时选择语言 / Language selected at startup
:: ============================================================
set "ScriptDir=%~dp0"
set "ComposeFile=%ScriptDir%docker-compose.yaml"

echo ========================================
echo          VPOT Install Script
echo ========================================
echo.
echo    1. 中文 (Chinese)
echo    2. English
echo.
choice /c 12 /n /m "  Select language / 请选择语言 (1=中文, 2=English) [1]: "
if errorlevel 2 (set "LANG=en") else (set "LANG=zh")

:: ---------------- 按语言设置消息 ----------------
if "!LANG!"=="zh" (
    set "M_CHECK_DOCKER=[*] 正在检查 Docker 运行状态..."
    set "M_DOCKER_RUNNING=    Docker 正在运行。"
    set "M_DOCKER_NOT_RUNNING=    Docker 未在运行。"
    set "M_RETRY=    请先启动 Docker Desktop,然后按任意键重新检查..."
    set "M_START=[*] 正在启动 VPOT 容器..."
    set "M_COMPOSE_FILE=    编排文件: !ComposeFile!"
    set "M_COMPOSE_NOTFOUND=    错误: 找不到编排文件 !ComposeFile!"
    set "M_NO_COMPOSE=    错误: 未找到 docker compose 或 docker-compose。"
    set "M_NO_COMPOSE_HINT=    请确认 Docker Desktop 已安装并正在运行。"
    set "M_CHECK_OLD=    正在检查已存在的 vpot 容器..."
    set "M_OLD_FOUND=    发现已存在的 vpot 容器,正在移除..."
    set "M_OLD_REMOVED=    旧 vpot 容器已移除。"
    set "M_OLD_FAIL=    错误: 移除旧 vpot 容器失败,请手动执行: docker rm -f vpot"
    set "M_RUNNING=    执行: !composeCmd! -f "!ComposeFile!" up -d"
    set "M_UP_FAIL=    错误: docker compose 执行失败(exit code !ERRORLEVEL!),请查看上方输出。"
    set "M_UP_OK=    容器启动成功。"
    set "M_COMPLETE_TITLE=VPOT 部署完成!"
    set "M_SERVICE_URL=服务地址:"
    set "M_ANYKEY=按任意键退出..."
) else (
    set "M_CHECK_DOCKER=[*] Checking if Docker daemon is running..."
    set "M_DOCKER_RUNNING=    Docker daemon is running."
    set "M_DOCKER_NOT_RUNNING=    Docker daemon is NOT running."
    set "M_RETRY=    Start Docker Desktop, then press any key to retry..."
    set "M_START=[*] Starting VPOT containers..."
    set "M_COMPOSE_FILE=    Compose file: !ComposeFile!"
    set "M_COMPOSE_NOTFOUND=    ERROR: Compose file not found at !ComposeFile!"
    set "M_NO_COMPOSE=    ERROR: Neither docker compose nor docker-compose found."
    set "M_NO_COMPOSE_HINT=    Make sure Docker Desktop is installed and running."
    set "M_CHECK_OLD=    Checking for existing vpot container..."
    set "M_OLD_FOUND=    Existing vpot container found, removing it..."
    set "M_OLD_REMOVED=    Old vpot container removed successfully."
    set "M_OLD_FAIL=    ERROR: Failed to remove existing vpot container. Run manually: docker rm -f vpot"
    set "M_RUNNING=    Running: !composeCmd! -f "!ComposeFile!" up -d"
    set "M_UP_FAIL=    ERROR: docker compose failed (exit code !ERRORLEVEL!). Check the output above."
    set "M_UP_OK=    Containers started successfully."
    set "M_COMPLETE_TITLE=VPOT deployment complete!"
    set "M_SERVICE_URL=Service available at:"
    set "M_ANYKEY=Press any key to exit..."
)

echo.
echo !M_CHECK_DOCKER!

:: ---------------- Docker 运行检查(任意键重试) ----------------
:retry_docker
docker info >nul 2>&1
if errorlevel 1 (
    echo.
    echo     !M_DOCKER_NOT_RUNNING!
    echo     !M_RETRY!
    echo.
    pause >nul
    goto retry_docker
)
echo     !M_DOCKER_RUNNING!

:: ---------------- 启动容器 ----------------
call :StartVpotContainers
if errorlevel 1 (
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================
echo   !M_COMPLETE_TITLE!
echo   !M_SERVICE_URL! http://localhost:18800
echo ========================================
start "" "http://localhost:18800"
echo.
echo !M_ANYKEY!
pause >nul
exit /b 0

:: -------------------------------------------------------------------
:: Start VPOT containers (compose plugin detection, cleanup, up -d)
:: -------------------------------------------------------------------
:StartVpotContainers
    echo     !M_COMPOSE_FILE!
    if not exist "!ComposeFile!" (
        echo     !M_COMPOSE_NOTFOUND!
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
        echo.
        echo     !M_NO_COMPOSE!
        echo     !M_NO_COMPOSE_HINT!
        exit /b 1
    )
    :: 消息在 composeCmd 确定后重设(避免空展开)
    if "!LANG!"=="zh" (
        set "M_RUNNING=    执行: !composeCmd! -f "!ComposeFile!" up -d"
    ) else (
        set "M_RUNNING=    Running: !composeCmd! -f "!ComposeFile!" up -d"
    )

    :: Check and clean up any existing vpot container to avoid name conflict
    echo     !M_CHECK_OLD!
    docker ps -a --format "{{.Names}}" 2>nul | findstr /b /e "vpot" >nul
    if !ERRORLEVEL! equ 0 (
        echo     !M_OLD_FOUND!
        docker rm -f vpot >nul 2>&1
        if !ERRORLEVEL! neq 0 (
            echo.
            echo     !M_OLD_FAIL!
            exit /b 1
        )
        echo     !M_OLD_REMOVED!
    )

    echo.
    echo     !M_RUNNING!
    !composeCmd! -f "!ComposeFile!" up -d
    if !ERRORLEVEL! neq 0 (
        echo.
        echo     !M_UP_FAIL!
        exit /b 1
    )
    echo     !M_UP_OK!
    exit /b 0
