# VPOT MSI 构建镜像:wine(32 位)+ WiX 3.11 + wine-mono(x86)+ go-msi
#
# candle.exe / light.exe 是 32 位 .NET 程序,因此:
#   - 安装 wine32(i386)
#   - 使用 WINEARCH=win32 纯 32 位 prefix(避开 wine 8 实验性 wow64 的坑)
#   - 安装 wine-mono x86(32 位 .NET 运行时)
#
# wix311-binaries.zip 与 wine-mono-x86.msi 由宿主机脚本 build-msi-docker.sh
# 注入构建上下文(优先本地缓存,否则在宿主机下载),此处直接 COPY。
FROM debian:12

# 1) 使用 USTC 镜像源 + wine + wine32(i386)+ 工具
RUN rm -f /etc/apt/sources.list.d/debian.sources \
    && printf '%s\n' \
        'deb http://mirrors.ustc.edu.cn/debian/ bookworm main non-free non-free-firmware contrib' \
        'deb http://mirrors.ustc.edu.cn/debian-security/ bookworm-security main' \
        'deb http://mirrors.ustc.edu.cn/debian/ bookworm-updates main non-free non-free-firmware contrib' \
        'deb http://mirrors.ustc.edu.cn/debian/ bookworm-backports main non-free non-free-firmware contrib' \
        > /etc/apt/sources.list \
    && dpkg --add-architecture i386 \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
         wine wine32:i386 unzip ca-certificates xvfb xauth \
    && rm -rf /var/lib/apt/lists/*

# 2) WiX 3.11(wix311-binaries.zip,免安装)
COPY wix311-binaries.zip /opt/wix311.zip
RUN mkdir -p /opt/wix \
    && unzip -q /opt/wix311.zip -d /opt/wix \
    && rm -f /opt/wix311.zip

# 3) wine-mono x86(32 位 .NET 运行时,candle/light 依赖)
COPY wine-mono-x86.msi /opt/wine-mono-x86.msi

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
