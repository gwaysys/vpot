# VPOT MSI 构建镜像:wine(32 位)+ WiX 3.11 + wine-mono(x86)
#
# candle.exe / light.exe 是 32 位 .NET 程序,因此:
#   - 安装 wine32(i386)
#   - 使用 WINEARCH=win32 纯 32 位 prefix(避开 wine 8 实验性 wow64 的坑)
#   - 安装 wine-mono x86(32 位 .NET 运行时)
#
# wix311-binaries.zip 与 wine-mono-x86.msi 由宿主机脚本 build-msi.sh
# 注入构建上下文(优先本地缓存,否则在宿主机下载),此处直接 COPY。
# 构建时模板与源文件通过 -v msi/:/build 挂载,容器内直接 candle + light。
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
         wine wine32:i386 unzip ca-certificates xvfb xauth locales \
    && rm -rf /var/lib/apt/lists/*

# 生成 zh_CN.GB2312 locale:light 按系统 ANSI 码页读取 wxl(不看 XML 声明),
# 中文必须 GBK 编码 + ANSI=936,否则 UTF-8 中文被按 1252 读取 → 乱码
RUN localedef -i zh_CN -f GB2312 zh_CN.GB2312 2>/dev/null || true

# 2) WiX 3.11(wix311-binaries.zip,免安装)
COPY wix311-binaries.zip /opt/wix311.zip
RUN mkdir -p /opt/wix \
    && unzip -q /opt/wix311.zip -d /opt/wix \
    && rm -f /opt/wix311.zip

# 3) wine-mono x86(32 位 .NET 运行时,candle/light 依赖)
COPY wine-mono-x86.msi /opt/wine-mono-x86.msi

# 4) 初始化 32 位 wine prefix + 安装 wine-mono
ENV WINEDEBUG=-all WINEARCH=win32 WINEPREFIX=/root/.wine32
RUN xvfb-run -a wineboot -u || true \
    && xvfb-run -a wine msiexec /i /opt/wine-mono-x86.msi /quiet || true

WORKDIR /build
ENTRYPOINT ["/build/docker/build.sh"]
