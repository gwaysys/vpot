#!/bin/bash
# 容器内构建脚本(由 Dockerfile ENTRYPOINT 调用)。
# 用法: build.sh <msi 文件名> <版本号>
set -euo pipefail
export WINEDEBUG=-all WINEARCH=win32 WINEPREFIX=/root/.wine32

MSI_FILE="${1:?缺少 msi 文件名参数}"
VERSION="${2:?缺少版本号参数}"

echo "==> 验证 candle.exe(wine 环境)"
if ! xvfb-run -a wine 'Z:\opt\wix\candle.exe' -h 2>&1 | grep -qi "wix toolset\|windows installer\|usage:"; then
    echo "错误:candle 无法运行(wine 环境异常)" >&2
    exit 1
fi
echo "candle 运行正常"

echo "==> go-msi set-guid(固化 GUID)"
go-msi set-guid --path wix.json >/dev/null 2>&1 || true

echo "==> go-msi make -> $MSI_FILE"
go-msi make --msi "$MSI_FILE" --version "$VERSION" --arch amd64 --path wix.json

echo "构建完成: /build/$MSI_FILE"
