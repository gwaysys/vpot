#!/usr/bin/env bash
# build-msi-docker.sh - 用 Docker 容器编译 VPOT MSI 安装包
#
# 镜像内容:wine(wine32,32 位 prefix)+ WiX 3.11 + wine-mono(x86)
# 宿主机只需:docker、wget
#
# 用法:
#   ./build-msi-docker.sh            # 一键生成双语 MSI(zh-CN + en-US,版本默认 1.1.5)
#   ./build-msi-docker.sh 1.2.0      # 指定版本,仍生成双语 MSI
#   ./build-msi-docker.sh 1.2.0 en-US# 只生成指定语言
#
# 产物: ./vpot-setup-<版本>-<语言>.msi(zh-CN + en-US 两个)
#
# 网络较慢时可覆盖下载源(镜像构建阶段):
#   WIX_URL=... WINE_MONO_URL=... ./build-msi-docker.sh
set -euo pipefail

VERSION="${1:-1.1.5}"
# 默认一键生成双语;显式传第 2 个参数则只构建该语言
if [ -n "${2:-}" ]; then
    CULTURES=("$2")
else
    CULTURES=("zh-CN" "en-US")
fi
MSI_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$MSI_DIR/.." && pwd)"
CTX="$MSI_DIR/docker"
IMAGE="${VPOT_MSI_IMAGE:-vpot-msi-builder}"

step() { echo; echo "==> $*"; }
die() { echo "错误: $*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "未找到 docker,请先安装并启动: https://docs.docker.com/engine/install/debian/"

# docker 权限:当前用户可直连则用 docker,否则自动带 sudo(需输入密码)
DOCKER="sudo docker"
if docker info >/dev/null 2>&1; then
    DOCKER="docker"
fi
$DOCKER info >/dev/null 2>&1 || die "docker daemon 不可用,请先启动 Docker 服务(sudo systemctl start docker)"
command -v wget >/dev/null 2>&1 || die "未找到 wget,请先安装(如: sudo apt install wget)"
command -v go >/dev/null 2>&1 || die "未找到 go,请先安装 Go 工具链"

# go-msi 二进制:未安装则自动安装
GO_MSI="$(go env GOPATH)/bin/go-msi"
if [ ! -x "$GO_MSI" ]; then
    echo "go-msi 未安装,自动安装..."
    go install github.com/mat007/go-msi@latest
    [ -x "$GO_MSI" ] || die "go-msi 安装失败"
fi

# 1. 动态生成打包配置(files = vpot-docker 全量文件,后续目录内容变更自动包含)
step "生成打包配置 wix.gen.json"
PKG_SRC="$REPO_ROOT/vpot-docker"
python3 - "$MSI_DIR/wix.json" "$MSI_DIR/wix.gen.json" "$PKG_SRC" <<'PYEOF'
import json, os, sys
cfg_path, out_path, pkg_dir = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = json.load(open(cfg_path, encoding='utf-8'))
files = []
for name in sorted(os.listdir(pkg_dir)):
    if os.path.isfile(os.path.join(pkg_dir, name)):
        files.append({"path": f"../pkg/{name}"})
cfg["files"] = files
json.dump(cfg, open(out_path, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
print(f"打包文件 {len(files)} 个: " + ", ".join(f["path"] for f in files))
PYEOF

# 2. 准备构建上下文(go-msi 二进制 + 模板 + WiX + wine-mono,Dockerfile 直接 COPY)
step "准备构建上下文"
mkdir -p "$CTX"

cp -f "$GO_MSI" "$CTX/go-msi"
rm -rf "$CTX/templates"
cp -r "$MSI_DIR/templates" "$CTX/templates"
chmod -R u+w "$CTX/templates"

# WiX 3.11 zip 与 wine-mono:优先复用本地缓存(~/.cache/vpot-wix/),
# 没有才下载并写入缓存(下次编译直接复用,勿手动清理缓存)
CACHE_DIR="$HOME/.cache/vpot-wix"
mkdir -p "$CACHE_DIR"

WIX_ZIP="$CACHE_DIR/wix311-binaries.zip"
# 存在且大于 10MB 才视为有效缓存(wix311 完整约 34MB)
if [ ! -s "$WIX_ZIP" ] || [ "$(stat -c%s "$WIX_ZIP" 2>/dev/null || echo 0)" -lt 10000000 ]; then
    echo "未找到有效 wix311 缓存,下载 ${WIX_URL:-https://github.com/wixtoolset/wix3/releases/download/wix3112rtm/wix311-binaries.zip}"
    rm -f "$WIX_ZIP"
    wget -c -q --tries=3 -T 180 -O "$WIX_ZIP" \
        "${WIX_URL:-https://github.com/wixtoolset/wix3/releases/download/wix3112rtm/wix311-binaries.zip}" \
        || die "下载 WiX 失败,可设置 WIX_URL 指定镜像,或手动下载 wix311-binaries.zip 放到 $WIX_ZIP"
    [ "$(stat -c%s "$WIX_ZIP")" -gt 10000000 ] || die "wix311 下载不完整,请删除 $WIX_ZIP 后重试或换 WIX_URL 镜像"
fi
cp -f "$WIX_ZIP" "$CTX/wix311-binaries.zip"

MONO_MSI="$CACHE_DIR/wine-mono-8.0.0-x86.msi"
# 存在且大于 5MB 才视为有效缓存(wine-mono x86 完整约 50MB+)
if [ ! -s "$MONO_MSI" ] || [ "$(stat -c%s "$MONO_MSI" 2>/dev/null || echo 0)" -lt 5000000 ]; then
    echo "未找到有效 wine-mono 缓存,下载 ${WINE_MONO_URL:-https://dl.winehq.org/wine/wine-mono/8.0.0/wine-mono-8.0.0-x86.msi}"
    rm -f "$MONO_MSI"
    wget -c -q --tries=3 -T 180 -O "$MONO_MSI" \
        "${WINE_MONO_URL:-https://dl.winehq.org/wine/wine-mono/8.0.0/wine-mono-8.0.0-x86.msi}" \
        || die "下载 wine-mono 失败,可设置 WINE_MONO_URL 指定镜像,或手动下载 wine-mono-8.0.0-x86.msi 放到 $MONO_MSI"
    [ "$(stat -c%s "$MONO_MSI")" -gt 5000000 ] || die "wine-mono 下载不完整,请删除 $MONO_MSI 后重试或换 WINE_MONO_URL 镜像"
fi
cp -f "$MONO_MSI" "$CTX/wine-mono-x86.msi"

# 3. 构建镜像(首次较慢:wine + WiX + wine-mono 下载安装)
step "构建镜像 $IMAGE(首次需下载 wine + WiX + wine-mono,耗时较长)"
$DOCKER build -t "$IMAGE" "$CTX"

# 4. 容器内编译(每个 culture 一次;镜像已构建,直接复用)
for CULTURE in "${CULTURES[@]}"; do
    step "容器内编译 -> vpot-setup-$VERSION-$CULTURE.msi"
    $DOCKER run --rm -e CULTURE="$CULTURE" -e WIX_JSON="wix.gen.json" \
        -v "$MSI_DIR":/build -v "$PKG_SRC":/pkg \
        "$IMAGE" "vpot-setup-$VERSION-$CULTURE.msi" "$VERSION"

    # 5. 修复产物属主(容器内以 root 写入,文件归 root 所有)
    if [ -f "$MSI_DIR/vpot-setup-$VERSION-$CULTURE.msi" ]; then
        sudo chown "$(id -u):$(id -g)" "$MSI_DIR/vpot-setup-$VERSION-$CULTURE.msi" 2>/dev/null || true
    fi
done

# 6. 清理临时打包配置
rm -f "$MSI_DIR/wix.gen.json"

echo
echo "=============================================="
echo "  构建完成:"
for CULTURE in "${CULTURES[@]}"; do
    echo "    - $MSI_DIR/vpot-setup-$VERSION-$CULTURE.msi"
done
echo "=============================================="
