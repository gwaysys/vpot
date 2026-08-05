# launch.ps1 - VPOT 自愈启动脚本(MSI install/uninstall hook 调用)
#
# 背景:未签名的 vpot-bootstrap.exe 可能被 Windows Defender 实时保护误删,
# 导致安装钩子启动时文件不存在(弹"Windows找不到文件")。本脚本:
#   1) 等待 vpot-bootstrap.exe 就位(最长 10 秒,容忍安装事务/AV 延迟);
#   2) 缺失时(安装模式):提升(UAC)添加 Defender 目录排除,再用
#      msiexec /fa 修复从 MSI 缓存重新提取文件,再等待;
#   3) 就位后启动:Start-Process(install 无参;uninstall 追加 -uninstall);
#   4) 仍失败:静默退出(不弹 Windows 错误窗,用户可从开始菜单重试)。
#
# 用法(由 wix.json hooks 调用):
#   powershell -NoProfile -ExecutionPolicy Bypass -File "[INSTALLDIR]launch.ps1" \
#       -InstallDir "[INSTALLDIR]" -ProductCode "[ProductCode]" [-Uninstall]

param(
    [string]$InstallDir,
    [string]$ProductCode,
    [switch]$Uninstall
)

$ErrorActionPreference = 'SilentlyContinue'
$exe = Join-Path $InstallDir 'vpot-bootstrap.exe'

function Wait-Exe([int]$Seconds) {
    for ($i = 0; $i -lt ($Seconds * 2); $i++) {
        if (Test-Path -LiteralPath $exe) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return (Test-Path -LiteralPath $exe)
}

# 1) 等待文件就位
if (Wait-Exe 10) {
    if ($Uninstall) { Start-Process -FilePath $exe -ArgumentList @('-uninstall') }
    else { Start-Process -FilePath $exe }
    exit 0
}

# 2) 文件缺失(疑似被 Defender 删除):仅安装模式尝试自愈
if (-not $Uninstall -and $ProductCode) {
    # 2a) 添加 Defender 排除(需提升;失败忽略,尝试 2b 后文件可能仍被删)
    try { Add-MpPreference -ExclusionPath $InstallDir -ErrorAction Stop } catch {}

    # 2b) 通过 msiexec 修复重新提取文件(提升;用户拒绝 UAC 则无法恢复)
    Start-Process -FilePath 'msiexec' `
        -ArgumentList @('/fa', $ProductCode, '/qn') `
        -Verb RunAs -Wait -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 1
    if (Wait-Exe 10) {
        Start-Process -FilePath $exe
        exit 0
    }
}

# 3) 仍失败:静默退出
exit 1
