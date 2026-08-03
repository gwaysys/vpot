#!/usr/bin/env bash
# build-msi-docker.sh - 用 Docker 容器编译 VPOT MSI 安装包
#
# 镜像内容:wine(wine32,32 位 prefix)+ WiX 3.11 + wine-mono(x86)+ go-msi
# 宿主机只需:docker、go、wget
#
# 用法:
#   ./build-msi-docker.sh [版本号,默认 1.1.5]
#
# 产物: ./vpot-setup-<版本>.msi
#
# 网络较慢时可覆盖下载源(镜像构建阶段):
#   WIX_URL=... WINE_MONO_URL=... ./build-msi-docker.sh
set -euo pipefail

VERSION="${1:-1.1.5}"
MSI_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$MSI_DIR/.." && pwd)"
CTX="$MSI_DIR/docker"
IMAGE="${VPOT_MSI_IMAGE:-vpot-msi-builder}"

step() { echo; echo "==> $*"; }
die() { echo "错误: $*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "未找到 docker,请先安装并启动: https://docs.docker.com/engine/install/debian/"
docker info >/dev/null 2>&1 || die "docker daemon 不可用,请先启动 Docker 服务"
command -v go >/dev/null 2>&1 || die "未找到 go,请先安装 Go 工具链"

# 1. 交叉编译 bootstrap + 准备打包文件
step "构建 vpot-bootstrap.exe(交叉编译)"
(cd "$MSI_DIR/bootstrap" && GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o ../vpot-bootstrap.exe .)
cp -f "$REPO_ROOT/picoclaw-docker/docker-compose.yaml" "$MSI_DIR/"
cp -f "$REPO_ROOT/picoclaw-docker/readme.txt" "$MSI_DIR/"

# 2. 准备构建上下文(go-msi 二进制 + 模板)
step "准备构建上下文"
GO_MSI="$(go env GOPATH)/bin/go-msi"
if [ ! -x "$GO_MSI" ]; then
    echo "go-msi 未安装,自动安装..."
    go install github.com/mat007/go-msi@latest
fi
mkdir -p "$CTX"
cp -f "$GO_MSI" "$CTX/go-msi"
rm -rf "$CTX/templates"
if [ -d "$(go env GOPATH)/bin/templates" ]; then
    cp -r "$(go env GOPATH)/bin/templates" "$CTX/"
else
    SRC="$(ls -d "$(go env GOMODCACHE)/github.com/mat007/go-msi@*" 2>/dev/null | head -1 || true)"
    [ -n "$SRC" ] || die "未找到 go-msi 模板(module cache),请先执行: go install github.com/mat007/go-msi@latest"
    cp -r "$SRC/templates" "$CTX/"
fi

# 3. 构建镜像(首次较慢:wine + WiX + wine-mono 下载安装)
step "构建镜像 $IMAGE(首次需下载 wine + WiX + wine-mono,耗时较长)"
docker build -t "$IMAGE" "$CTX"

# 4. 容器内编译
step "容器内编译 -> vpot-setup-$VERSION.msi"
docker run --rm -v "$MSI_DIR":/build "$IMAGE" "vpot-setup-$VERSION.msi" "$VERSION"

echo
echo "=============================================="
echo "  构建完成: $MSI_DIR/vpot-setup-$VERSION.msi"
echo "=============================================="
