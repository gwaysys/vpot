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
if go-msi make --msi "$MSI_FILE" --version "$VERSION" --arch amd64 --path wix.json --keep; then
    echo "go-msi make 成功"
else
    # go-msi 生成的 build.bat 不含 -loc(语言包)与 wine 所需的 -sval:
    #   - candle 需要 -loc 展开 $(loc.xxx) 国际化字符串
    #   - wine 下 light 需要 -sval 跳过 MSI 验证(否则 LGHT0216)
    # 对中间 build.bat 注入参数后重跑(仅容器/wine 场景,Windows 构建不受影响)
    echo "wine 兼容修补:注入 -loc(${CULTURE:-zh-CN}) 与 -sval 后重跑 build.bat..."
    OUT="$(ls -dt /tmp/go-msi* 2>/dev/null | head -1)"
    [ -n "$OUT" ] || { echo "错误:未找到 go-msi 中间目录" >&2; exit 1; }
    CULTURE="${CULTURE:-zh-CN}"
    WXL="Z:\\build\\templates\\loc\\$CULTURE.wxl"
    sed -i "s|^candle |candle -loc \"$WXL\" |" "$OUT/build.bat"
    sed -i "s|^light |light -sval -loc \"$WXL\" |" "$OUT/build.bat"
    (cd "$OUT" && xvfb-run -a wine cmd /c build.bat) || { echo "错误:重跑 build.bat 失败" >&2; exit 1; }
fi

# 等待 wine 后台进程(wineserver)退出,避免 docker run 结束时残留/卡住
wineserver -w 2>/dev/null || true

echo "构建完成: /build/$MSI_FILE"
