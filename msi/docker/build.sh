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

echo "==> 渲染 product.wxs(@VERSION@/@UPGRADE_CODE@/@CODEPAGE@)"
# 在容器内临时目录编译,避免中间产物(wixobj/wixpdb/product.gen.*)污染 /build
rm -rf /tmp/work && mkdir -p /tmp/work && cd /tmp/work
cp -f /build/install-windows.cmd /build/docker-compose.yaml /build/readme.txt .
# 数据库码页:中文用 936(GBK,MSI UI 正确渲染),英文用 1252
if [ "$CULTURE" = "en-US" ]; then CODEPAGE="1252"; else CODEPAGE="936"; fi
sed -e "s/@VERSION@/$VERSION/g" -e "s/@UPGRADE_CODE@/$UPGRADE_CODE/g" -e "s/@CODEPAGE@/$CODEPAGE/g" /build/templates/product.wxs > product.gen.wxs
cp -f /build/templates/dialogs.wxs /build/templates/InfoDialogs.wxs .

# 语言包:WiX 按系统 ANSI 码页读取 wxl(不看 XML 声明)。
# 中文必须 GBK 编码 + wine ANSI=936,否则 UTF-8 中文被按 1252 读 → 乱码。
# 英文(全 ASCII)无歧义,直接用 UTF-8 wxl。
WXL="Z:/build/templates/loc/$CULTURE.wxl"
if [ "$CULTURE" = "zh-CN" ]; then
    export LANG=zh_CN.GB2312 LC_ALL=zh_CN.GB2312
    iconv -f UTF-8 -t GBK /build/templates/loc/zh-CN.wxl > zh-CN.gbk.wxl
    sed -i 's|<?xml version="1.0" encoding="UTF-8"?>|<?xml version="1.0" encoding="GB2312"?>|' zh-CN.gbk.wxl
    WXL="Z:/tmp/work/zh-CN.gbk.wxl"
fi

echo "==> candle 编译(3 个 wxs)"
xvfb-run -a wine "$WIX\candle.exe" -arch x64 product.gen.wxs dialogs.wxs InfoDialogs.wxs

echo "==> light 链接(语言包: $CULTURE)"
xvfb-run -a wine "$WIX\light.exe" -sval -spdb -loc "$WXL" \
    -out "Z:/build/$MSI_FILE" product.gen.wixobj dialogs.wixobj InfoDialogs.wixobj

# 等待 wine 后台进程(wineserver)退出,避免 docker run 结束时残留/卡住
wineserver -w 2>/dev/null || true

echo "构建完成: /build/$MSI_FILE"
