#!/bin/bash
# 容器内构建脚本(由 Dockerfile ENTRYPOINT 调用)。
# 用法: build.sh <msi 文件名> <版本号>
set -euo pipefail
export WINEDEBUG=-all WINEARCH=win32 WINEPREFIX=/root/.wine32

MSI_FILE="${1:?缺少 msi 文件名参数}"
VERSION="${2:?缺少版本号参数}"

echo "==> 验证 candle.exe(wine 环境)"
CANDLE_OUT="$(xvfb-run -a wine 'Z:\opt\wix\candle.exe' -h 2>&1 || true)"
if ! echo "$CANDLE_OUT" | grep -qi "wix toolset\|windows installer\|usage:"; then
    echo "candle 无法运行,收集诊断信息:"
    echo "--- candle -h 输出(前 30 行)---"
    echo "$CANDLE_OUT" | head -30
    echo "--- wine 版本 ---"
    wine --version 2>&1 || true
    echo "--- 32 位 wine 目录 ---"
    ls /usr/lib/wine/i386-windows 2>/dev/null | head -5 || echo "无 /usr/lib/wine/i386-windows"
    echo "--- mono 安装情况 ---"
    ls /root/.wine32/drive_c/windows/mono 2>/dev/null || echo "wine-mono 未安装"
    echo "尝试重新安装 wine-mono..."
    if [ -f /opt/wine-mono-x86.msi ]; then
        xvfb-run -a wine msiexec /i /opt/wine-mono-x86.msi /quiet 2>&1 | tail -5 || true
        wineserver -w 2>/dev/null || true
        CANDLE_OUT2="$(xvfb-run -a wine 'Z:\opt\wix\candle.exe' -h 2>&1 || true)"
        if echo "$CANDLE_OUT2" | grep -qi "wix toolset\|windows installer\|usage:"; then
            echo "wine-mono 重装后 candle 运行正常"
        else
            echo "--- 重装后 candle -h 输出(前 30 行)---"
            echo "$CANDLE_OUT2" | head -30
            echo "错误:candle 仍无法运行" >&2
            exit 1
        fi
    else
        echo "错误:镜像内缺少 /opt/wine-mono-x86.msi" >&2
        exit 1
    fi
fi
echo "candle 运行正常"

echo "==> go-msi set-guid(固化 GUID)"
go-msi set-guid --path wix.json >/dev/null 2>&1 || true

echo "==> go-msi make -> $MSI_FILE"
go-msi make --msi "$MSI_FILE" --version "$VERSION" --arch amd64 --path wix.json

# 等待 wine 后台进程(wineserver)退出,避免 docker run 结束时残留/卡住
wineserver -w 2>/dev/null || true

echo "构建完成: /build/$MSI_FILE"
