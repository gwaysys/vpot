# VPOT MSI 构建镜像:wine(32 位)+ WiX 3.11 + wine-mono(x86)+ go-msi
#
# candle.exe / light.exe 是 32 位 .NET 程序,因此:
#   - 安装 wine32(i386)
#   - 使用 WINEARCH=win32 纯 32 位 prefix(避开 wine 8 实验性 wow64 的坑)
#   - 安装 wine-mono x86(32 位 .NET 运行时)
#
# 网络较慢时可覆盖下载源:
#   docker build --build-arg WIX_URL=<镜像> --build-arg WINE_MONO_URL=<镜像> ...
FROM debian:12

ARG WIX_URL=https://github.com/wixtoolset/wix3/releases/download/wix3112rtm/wix311-binaries.zip
ARG WINE_MONO_URL=https://dl.winehq.org/wine/wine-mono/8.0.0/wine-mono-8.0.0-x86.msi

# 1) wine + wine32(i386)+ 工具
RUN dpkg --add-architecture i386 && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
         wine wine32:i386 wget ca-certificates xvfb \
    && rm -rf /var/lib/apt/lists/*

# 2) WiX 3.11(wix311-binaries.zip,免安装)
RUN mkdir -p /opt/wix \
    && wget -q -O /opt/wix311.zip "$WIX_URL" \
    && unzip -q /opt/wix311.zip -d /opt/wix \
    && rm -f /opt/wix311.zip

# 3) wine-mono x86(32 位 .NET 运行时,candle/light 依赖)
RUN wget -q -O /opt/wine-mono-x86.msi "$WINE_MONO_URL"

# 4) go-msi 二进制 + 模板(由宿主机脚本 build-msi-docker.sh 注入构建上下文)
COPY go-msi /usr/local/bin/go-msi
COPY templates /usr/local/bin/templates

# 5) cmd.exe wrapper(go-msi 内部执行 cmd.exe /C build.bat)
RUN printf '#!/bin/sh\nexec wine cmd.exe "$@"\n' > /usr/local/bin/cmd.exe \
    && chmod +x /usr/local/bin/cmd.exe

# 6) 初始化 32 位 wine prefix + 安装 wine-mono
ENV WINEDEBUG=-all WINEARCH=win32 WINEPREFIX=/root/.wine32
RUN xvfb-run -a wineboot -u || true \
    && xvfb-run -a wine msiexec /i /opt/wine-mono-x86.msi /quiet || true

# 7) Windows PATH 加入 Z:\opt\wix(go-msi 生成的 build.bat 用裸命令 candle/light)
RUN xvfb-run -a wine reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' \
        /v Path /t REG_EXPAND_SZ \
        /d 'C:\windows\system32;C:\windows;Z:\opt\wix' /f || true

WORKDIR /build
ENTRYPOINT ["/build/docker/build.sh"]
