#!/bin/bash
# 容器内构建脚本(由 Dockerfile ENTRYPOINT 调用)。
# 直接调用 WiX candle/light,不再使用 go-msi。
# 用法: build.sh <msi 文件名> <版本号>
# 环境: CULTURE=zh-CN|en-US(语言包)
set -euo pipefail
export WINEDEBUG=-all WINEARCH=win32 WINEPREFIX=/root/.wine32

MSI_FILE="${1:?缺少 msi 文件名参数}"
VERSION="${2:?缺少版本号参数}"
CULTURE="${CULTURE:-zh-CN}"
UPGRADE_CODE="0364aa07-e538-4290-b1fb-fba6403c9e2e"
WIX="Z:\opt\wix"

cd /build

echo "==> 渲染 product.wxs(@VERSION@/@UPGRADE_CODE@)"
sed -e "s/@VERSION@/$VERSION/g" -e "s/@UPGRADE_CODE@/$UPGRADE_CODE/g" templates/product.wxs > product.gen.wxs

echo "==> candle 编译(3 个 wxs)"
xvfb-run -a wine "$WIX\candle.exe" -arch x64 product.gen.wxs templates/dialogs.wxs templates/InfoDialogs.wxs

echo "==> light 链接(语言包: $CULTURE)"
xvfb-run -a wine "$WIX\light.exe" -sval -loc "Z:/build/templates/loc/$CULTURE.wxl" \
    -out "Z:/build/$MSI_FILE" product.gen.wixobj dialogs.wixobj InfoDialogs.wixobj

# 等待 wine 后台进程(wineserver)退出,避免 docker run 结束时残留/卡住
wineserver -w 2>/dev/null || true

echo "构建完成: /build/$MSI_FILE"
