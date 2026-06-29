<#
.SYNOPSIS
    VPOT Docker deployment script for Windows
.DESCRIPTION
    Checks for Docker, installs it if missing, then starts containers
    via docker compose using docker-compose.yaml.tpl
.NOTES
    Requires: Windows 10+ 64-bit (Pro/Enterprise/Education for Hyper-V)
             or Windows 11
    Run as Administrator for Docker Desktop installation
#>

#Requires -Version 5.1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ComposeFile = Join-Path $ScriptDir "docker-compose.yaml.tpl"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "    VPOT Docker Install Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# -------------------------------------------------------------------
# Step 1: Detect Docker
# -------------------------------------------------------------------
function Test-DockerInstalled {
    Write-Host "[*] Checking Docker installation..." -ForegroundColor Yellow
    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if ($docker) {
        $version = docker --version 2>&1
        Write-Host "    $version" -ForegroundColor Green
        return $true
    }
    Write-Host "    Docker not found." -ForegroundColor Red
    return $false
}

function Test-DockerRunning {
    Write-Host "[*] Checking if Docker daemon is running..." -ForegroundColor Yellow
    $result = docker info 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    Docker daemon is running." -ForegroundColor Green
        return $true
    }
    Write-Host "    Docker daemon is NOT running: $result" -ForegroundColor Red
    return $false
}

# -------------------------------------------------------------------
# Step 2: Install Docker
# -------------------------------------------------------------------
function Install-DockerWinget {
    Write-Host "[*] Attempting to install Docker Desktop via winget..." -ForegroundColor Yellow
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "winget not found. Please install Docker Desktop manually from https://docs.docker.com/desktop/install/windows-install/"
    }
    Write-Host "    Installing Docker Desktop (this may take several minutes)..." -ForegroundColor Yellow
    winget install --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements --silent 2>&1 | Write-Host
}

function Install-DockerManual {
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  Manual Docker Installation Required" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Docker Desktop could not be installed automatically."
    Write-Host "  Please download and install it from:"
    Write-Host "    https://docs.docker.com/desktop/install/windows-install/"
    Write-Host ""
    Write-Host "  After installation and reboot, re-run this script."
    Write-Host ""
    Start-Process "https://docs.docker.com/desktop/install/windows-install/"
    exit 1
}

function Invoke-DockerInstall {
    Write-Host "[*] Docker is not installed. Starting installation..." -ForegroundColor Yellow
    Write-Host ""
    try {
        Install-DockerWinget
    } catch {
        Write-Host "    winget install failed: $_" -ForegroundColor Red
        Install-DockerManual
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Docker installation initiated." -ForegroundColor Cyan
    Write-Host "  You may need to:" -ForegroundColor Cyan
    Write-Host "    - Log out and log back in" -ForegroundColor Cyan
    Write-Host "    - OR reboot your machine" -ForegroundColor Cyan
    Write-Host "  Then re-run this script to continue." -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    exit 0
}

# -------------------------------------------------------------------
# Step 3: Start containers
# -------------------------------------------------------------------
function Start-VpotContainers {
    Write-Host "[*] Starting VPOT containers..." -ForegroundColor Yellow
    Write-Host "    Compose file: $ComposeFile" -ForegroundColor Gray

    if (-not (Test-Path $ComposeFile)) {
        Write-Host "    ERROR: Compose file not found at $ComposeFile" -ForegroundColor Red
        exit 1
    }

    # Prefer docker compose (v2 plugin), fall back to docker-compose (v1)
    $composeCmd = $null
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        docker compose version 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $composeCmd = { docker compose -f $ComposeFile up -d }
        }
    }
    if (-not $composeCmd) {
        $dc = Get-Command docker-compose -ErrorAction SilentlyContinue
        if ($dc) {
            $composeCmd = { docker-compose -f $ComposeFile up -d }
        }
    }

    if (-not $composeCmd) {
        Write-Host "    ERROR: docker compose plugin nor docker-compose found." -ForegroundColor Red
        Write-Host "    Make sure Docker Desktop is installed and running." -ForegroundColor Red
        exit 1
    }

    Write-Host "    Running: docker compose -f $ComposeFile up -d" -ForegroundColor Gray
    & $composeCmd 2>&1 | Write-Host

    if ($LASTEXITCODE -ne 0) {
        Write-Host "    ERROR: docker compose failed (exit code $LASTEXITCODE)." -ForegroundColor Red
        exit 1
    }

    Write-Host "    Containers started successfully." -ForegroundColor Green
}

# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------
function Main {
    # Check Docker
    if (-not (Test-DockerInstalled)) {
        Invoke-DockerInstall
    }

    # Check daemon
    if (-not (Test-DockerRunning)) {
        Write-Host ""
        Write-Host "    Please start Docker Desktop, then re-run this script." -ForegroundColor Yellow
        exit 1
    }

    # Start
    Start-VpotContainers

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  VPOT deployment complete!" -ForegroundColor Cyan
    Write-Host "  Service available at: http://localhost:18800" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

Main
