#!/usr/bin/env bash
# build-msi.sh - 在 Linux 上使用 wine + WiX 3.11 + go-msi 构建 VPOT MSI 安装包
#
# 原理:go-msi 生成 build.bat 后用 cmd.exe /C 执行,内部以裸命令调用
#   candle / light(不指定 --bin 时靠 PATH 查找)。本脚本:
#   1) 把 WiX 3.11 放入 wine 的 C:\wix 并加入 Windows PATH;
#   2) 用 wrapper cmd.exe(wine cmd.exe)桥接 go-msi 的 cmd.exe 调用;
#   3) 用 wine-mono 支撑 candle/light(.NET 程序)运行;
#   4) go-msi 模板从 Go module cache 取(go install 不携带模板)。
#
# 依赖(需手动安装一次):
#   sudo apt install wine           # wine 7+(含 wine64)
#   go                              # Go 工具链(>=1.21)
#   wget unzip
#
# 用法:
#   ./build-msi.sh [版本号,默认 1.1.5]
#
# 产物: ./vpot-setup-<版本>.msi

set -euo pipefail

VERSION="${1:-1.1.5}"
MSI_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$MSI_DIR/.." && pwd)"

CACHE_DIR="${VPOT_WIX_CACHE:-$HOME/.cache/vpot-wix}"
WIX_DIR="$CACHE_DIR/wix311"
WIX_ZIP="$CACHE_DIR/wix311-binaries.zip"
WIX_URL="${WIX_URL:-https://mirror.ghproxy.com/https://github.com/wixtoolset/wix3/releases/download/wix3112rtm/wix311-binaries.zip}"
WINE_MONO_MSI="$CACHE_DIR/wine-mono-8.0.0-x86_64.msi"
WINE_MONO_URL="${WINE_MONO_URL:-https://dl.winehq.org/wine/wine-mono/8.0.0/wine-mono-8.0.0-x86_64.msi}"

WINE_PREFIX="${WINEPREFIX:-$HOME/.wine}"
GO_BIN="$(go env GOPATH)/bin"
GO_MSI="$GO_BIN/go-msi"

step() { echo; echo "==> $*"; }
die() { echo; echo "错误: $*" >&2; exit 1; }

command -v wine >/dev/null 2>&1 || die "未找到 wine,请先安装: sudo apt install wine"
command -v go >/dev/null 2>&1 || die "未找到 go,请先安装 Go 工具链"
command -v unzip >/dev/null 2>&1 || die "未找到 unzip"
command -v wget >/dev/null 2>&1 || command -v curl >/dev/null 2>&1 || die "需要 wget 或 curl"
if [ -z "${DISPLAY:-}" ] && ! command -v xvfb-run >/dev/null 2>&1; then
    echo "提示:当前无图形环境(DISPLAY 为空),若 wine 报显示相关错误,请执行: sudo apt install xvfb"
fi

# ---------- 1. WiX 3.11(wix311-binaries.zip,免安装) ----------
if [ ! -f "$WIX_DIR/candle.exe" ]; then
    step "准备 WiX 3.11"
    mkdir -p "$CACHE_DIR"
    if [ ! -f "$WIX_ZIP" ]; then
        echo "下载 $WIX_URL"
        if ! wget -q --tries=3 -T 120 -O "$WIX_ZIP" "$WIX_URL"; then
            rm -f "$WIX_ZIP"
            die "下载 WiX 失败。请手动下载 wix311-binaries.zip 放到 $WIX_ZIP,或设置 WIX_URL 环境变量指定镜像"
        fi
    fi
    mkdir -p "$WIX_DIR"
    unzip -o -q "$WIX_ZIP" -d "$WIX_DIR"
fi

# ---------- 2. wine prefix 初始化 ----------
export WINEDEBUG=-all
if [ ! -d "$WINE_PREFIX/drive_c" ]; then
    step "初始化 wine prefix($WINE_PREFIX)"
    wineboot -u >/dev/null 2>&1 || true
fi

# ---------- 3. 把 WiX 放入 wine 的 C:\wix 并加入 Windows PATH ----------
step "配置 wine: C:\\wix + Windows PATH"
WIN_WIX="$WINE_PREFIX/drive_c/wix"
rm -rf "$WIN_WIX"
cp -r "$WIX_DIR" "$WIN_WIX"
wine reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' \
    /v Path /t REG_EXPAND_SZ \
    /d 'C:\windows\system32;C:\windows;C:\wix' /f >/dev/null 2>&1 || true

# ---------- 4. 验证 candle(.NET)可运行,必要时安装 wine-mono ----------
# 注意:wine 在缺 wine32/显示驱动时失败也返回 0,必须检查输出内容而非退出码。
step "验证 candle.exe(需要 wine32 + wine-mono/.NET)"
if ! wine "$WIN_WIX/candle.exe" -h 2>&1 | grep -qi "windows installer\|wix toolset\|usage:"; then
    echo "candle 无法运行。请先确认已安装 32 位 wine 支持:"
    echo "    sudo dpkg --add-architecture i386 && sudo apt update && sudo apt install -y wine32:i386"
    echo "尝试安装 wine-mono(.NET 运行时)..."
    if [ ! -f "$WINE_MONO_MSI" ]; then
        if ! wget -q --tries=3 -T 120 -O "$WINE_MONO_MSI" "$WINE_MONO_URL"; then
            rm -f "$WINE_MONO_MSI"
            die "下载 wine-mono 失败。请手动下载 wine-mono-8.0.0-x86_64.msi 放到 $WINE_MONO_MSI"
        fi
    fi
    wine msiexec /i "$WINE_MONO_MSI" /quiet >/dev/null 2>&1 || true
    if ! wine "$WIN_WIX/candle.exe" -h 2>&1 | grep -qi "windows installer\|wix toolset\|usage:"; then
        die "candle 仍无法运行。请安装 wine32 后重试: sudo dpkg --add-architecture i386 && sudo apt update && sudo apt install -y wine32:i386"
    fi
fi
echo "candle 运行正常"

# ---------- 5. cmd.exe wrapper(go-msi 内部执行 cmd.exe /C build.bat) ----------
step "配置 cmd.exe wrapper"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/cmd.exe" <<'EOF'
#!/bin/sh
export WINEDEBUG=-all
exec wine cmd.exe "$@"
EOF
chmod +x "$BIN_DIR/cmd.exe"
export PATH="$BIN_DIR:$PATH"

# ---------- 6. go-msi + 模板(go install 不带模板,从 module cache 取) ----------
if [ ! -x "$GO_MSI" ]; then
    step "安装 go-msi"
    go install github.com/mat007/go-msi@latest
fi
if [ ! -d "$GO_BIN/templates" ]; then
    step "准备 go-msi 模板"
    GO_MSI_SRC="$(ls -d "$(go env GOMODCACHE)/github.com/mat007/go-msi@*" 2>/dev/null | head -1 || true)"
    [ -n "$GO_MSI_SRC" ] || die "未找到 go-msi 源码(module cache),请先执行: go install github.com/mat007/go-msi@latest"
    cp -r "$GO_MSI_SRC/templates" "$GO_BIN/"
fi

# ---------- 7. 构建 bootstrap + 准备打包文件 ----------
step "构建 vpot-bootstrap.exe(交叉编译)"
(cd "$MSI_DIR/bootstrap" && GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o ../vpot-bootstrap.exe .)
cp -f "$REPO_ROOT/picoclaw-docker/docker-compose.yaml" "$MSI_DIR/"
cp -f "$REPO_ROOT/picoclaw-docker/readme.txt" "$MSI_DIR/"

# ---------- 8. 固化 GUID 并生成 MSI ----------
step "go-msi set-guid(固化组件 GUID,保持升级兼容)"
"$GO_MSI" set-guid --path wix.json >/dev/null 2>&1 || true

step "go-msi make -> vpot-setup-$VERSION.msi"
cd "$MSI_DIR"
"$GO_MSI" make --msi "vpot-setup-$VERSION.msi" --version "$VERSION" --arch amd64 --path wix.json

echo
echo "=============================================="
echo "  构建完成: $MSI_DIR/vpot-setup-$VERSION.msi"
echo "=============================================="
