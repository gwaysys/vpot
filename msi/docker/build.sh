#!/bin/bash
# 容器内构建脚本(由 Dockerfile ENTRYPOINT 调用)。
# 用 go-msi 生成 MSI(WixUI 标准向导界面)。
# 用法: build.sh <msi 文件名> <版本号>
# 环境: CULTURE=zh-CN|en-US(语言包)
set -euo pipefail
export WINEDEBUG=-all WINEARCH=win32 WINEPREFIX=/root/.wine32

MSI_FILE="${1:?缺少 msi 文件名参数}"
VERSION="${2:?缺少版本号参数}"
CULTURE="${CULTURE:-zh-CN}"
TPL="$(dirname "$(command -v go-msi)")/templates"

# 数据库码页:中文用 936(GBK,MSI UI 正确渲染),英文用 1252
if [ "$CULTURE" = "en-US" ]; then CODEPAGE="1252"; else CODEPAGE="936"; fi
# go-msi 模板硬编码 Codepage=65001,按语言渲染(否则与 wxl 码页不一致)
sed -i "s/Codepage=\"65001\"/Codepage=\"$CODEPAGE\"/" "$TPL/product.wxs"

echo "==> go-msi set-guid(固化 GUID)"
go-msi set-guid --path wix.json >/dev/null 2>&1 || true

echo "==> go-msi make -> $MSI_FILE"
if go-msi make --msi "$MSI_FILE" --version "$VERSION" --arch amd64 --path wix.json --keep; then
    echo "go-msi make 成功"
else
    # go-msi 生成的 build.bat 缺 -loc(语言包)与 wine 所需的 -sval:
    #   - light 需要 -loc 展开 $(loc.xxx)/!(loc.xxx) 国际化字符串
    #   - wine 下 light 需要 -sval 跳过 MSI 验证(否则 LGHT0216)
    # 另外 WiX 按系统 ANSI 码页读 wxl(不看 XML 声明):
    #   中文必须 GBK 编码 + LANG=zh_CN.GB2312,否则 UTF-8 中文被按 1252 读 → 乱码
    echo "wine 兼容修补:注入 -sval 与 -loc($CULTURE) 后重跑 build.bat..."
    OUT="$(ls -dt /tmp/go-msi* 2>/dev/null | head -1)"
    [ -n "$OUT" ] || { echo "错误:未找到 go-msi 中间目录" >&2; exit 1; }
    [ -f "$OUT/build.bat" ] || { echo "错误:中间目录无 build.bat(make 失败原因更早,请查看上方输出)" >&2; exit 1; }
    WXL="Z:/build/templates/loc/$CULTURE.wxl"
    if [ "$CULTURE" = "zh-CN" ]; then
        export LANG=zh_CN.GB2312 LC_ALL=zh_CN.GB2312
        iconv -f UTF-8 -t GBK /build/templates/loc/zh-CN.wxl > "$OUT/zh-CN.gbk.wxl"
        sed -i 's|<?xml version="1.0" encoding="UTF-8"?>|<?xml version="1.0" encoding="GB2312"?>|' "$OUT/zh-CN.gbk.wxl"
        WXL="Z:/tmp/$(basename "$OUT")/zh-CN.gbk.wxl"
    fi
    sed -i "s|^light |light -sval -loc \"$WXL\" |" "$OUT/build.bat"
    (cd "$OUT" && xvfb-run -a wine cmd /c build.bat) || { echo "错误:重跑 build.bat 失败" >&2; exit 1; }
fi

# 等待 wine 后台进程(wineserver)退出,避免 docker run 结束时残留/卡住
wineserver -w 2>/dev/null || true

echo "构建完成: /build/$MSI_FILE"
