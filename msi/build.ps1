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
#   powershell -ExecutionPolicy Bypass -File .\build.ps1 -Version 1.2.0 -Culture en-US
param(
    [string]$Version = "1.1.5",
    [string]$Culture = "zh-CN",
    [string]$MsiName = ""
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "==> 1/2 复制 install-windows.cmd、docker-compose.yaml 与 readme.txt"
Copy-Item -Force ..\picoclaw-docker\install-windows.cmd .
Copy-Item -Force ..\picoclaw-docker\docker-compose.yaml .
Copy-Item -Force ..\picoclaw-docker\readme.txt .

Write-Host "==> 2/2 生成 MSI(Culture=$Culture)"
# 优先使用仓库模板(msi/templates/,含说明对话框与 loc 语言包),复制到 go-msi 模板目录
$GoBin = Join-Path (go env GOPATH) "bin"
$TemplatesSrc = Join-Path $PSScriptRoot "templates"
if (Test-Path $TemplatesSrc) {
    $TemplatesDst = Join-Path $GoBin "templates"
    if (Test-Path $TemplatesDst) { Remove-Item -Recurse -Force $TemplatesDst }
    Copy-Item -Recurse -Force $TemplatesSrc $TemplatesDst
}
if (-not $MsiName) { $MsiName = "vpot-setup-$Version-$Culture.msi" }
go-msi make --msi $MsiName --version $Version --arch amd64 --path wix.json --keep
if ($LASTEXITCODE -ne 0) {
    # go-msi 生成的 build.bat 不含 -loc(语言包),candle 展开 $(loc.xxx) 失败;
    # 对中间 build.bat 注入 -loc 后重跑(Windows 上无需 -sval)
    Write-Host "修补:注入 -loc($Culture) 到 build.bat 后重跑..."
    $out = Get-ChildItem $env:TEMP -Directory -Filter "go-msi*" |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $out) { throw "未找到 go-msi 中间目录" }
    $wxl = Join-Path $PSScriptRoot "templates\loc\$Culture.wxl"
    if (-not (Test-Path $wxl)) { throw "语言包不存在: $wxl" }
    $bat = Join-Path $out.FullName "build.bat"
    $content = Get-Content $bat
    $content = $content -replace '^candle ', "candle -loc `"$wxl`" "
    $content = $content -replace '^light ', "light -loc `"$wxl`" "
    Set-Content -Path $bat -Value $content -Encoding ASCII
    Push-Location $out.FullName
    cmd /c build.bat
    $code = $LASTEXITCODE
    Pop-Location
    if ($code -ne 0) { throw "重跑 build.bat 失败(exit $code)" }
    if (-not (Test-Path (Join-Path $PSScriptRoot $MsiName))) {
        # light 输出相对 out 的路径,产物落在脚本目录
        Copy-Item -Force (Join-Path $out.FullName $MsiName) $PSScriptRoot
    }
}

Write-Host ""
Write-Host "MSI 已生成: $PSScriptRoot\$MsiName"
