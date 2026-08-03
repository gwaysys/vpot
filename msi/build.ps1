# VPOT MSI 构建脚本(在 Windows 上运行)
#
# 前置要求:
#   - Go(https://go.dev/dl/)
#   - go-msi(go install github.com/mat007/go-msi@latest)
#   - WiX Toolset 3.10+(https://wixtoolset.org/docs/wix3/ 或 choco install wixtoolset)
#   - 首次使用前执行: go-msi set-guid(wix.json 中已有 upgrade-code,可跳过)
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File .\build.ps1
#   powershell -ExecutionPolicy Bypass -File .\build.ps1 -Version 1.2.0
param(
    [string]$Version = "1.1.5",
    [string]$MsiName = ""
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "==> 1/3 构建 vpot-bootstrap.exe"
# go.mod 位于 bootstrap/ 子目录,用 go -C 进入模块目录构建(Go 1.20+)
go -C bootstrap build -trimpath -ldflags "-s -w" -o ..\vpot-bootstrap.exe .
if ($LASTEXITCODE -ne 0) { throw "go build 失败" }

Write-Host "==> 2/3 复制 docker-compose.yaml 与 readme.txt"
Copy-Item -Force ..\picoclaw-docker\docker-compose.yaml .
Copy-Item -Force ..\picoclaw-docker\readme.txt .

Write-Host "==> 3/3 生成 MSI"
if (-not $MsiName) { $MsiName = "vpot-setup-$Version.msi" }
go-msi make --msi $MsiName --version $Version --arch amd64 --path wix.json
if ($LASTEXITCODE -ne 0) { throw "go-msi make 失败" }

Write-Host ""
Write-Host "MSI 已生成: $PSScriptRoot\$MsiName"
