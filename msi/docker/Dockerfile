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

# 4) go-msi 二进制 + 模板(由宿主机脚本 build-msi.sh 注入构建上下文)
COPY go-msi /usr/local/bin/go-msi
COPY templates /usr/local/bin/templates

# 5) cmd.exe wrapper(go-msi 内部执行 cmd.exe /C build.bat)
# 导出 PATH 含 /opt/wix:wine 会把 Linux PATH 映射为 Windows Z: 风格,
# 使 build.bat 中的裸命令 candle/light 可命中(注册表 PATH 不生效)。
RUN printf '#!/bin/sh\nexport WINEDEBUG=-all\nexport PATH="/opt/wix:$PATH"\nexec wine cmd.exe "$@"\n' > /usr/local/bin/cmd.exe \
    && chmod +x /usr/local/bin/cmd.exe

# 6) 初始化 32 位 wine prefix + 安装 wine-mono
ENV WINEDEBUG=-all WINEARCH=win32 WINEPREFIX=/root/.wine32
RUN xvfb-run -a wineboot -u || true \
    && xvfb-run -a wine msiexec /i /opt/wine-mono-x86.msi /quiet || true

# 7) 把 WiX 全部文件复制进 wine 的 C:\windows\system32(默认 %PATH% 首项)。
#    go-msi 生成的 build.bat 用裸命令 candle/light 查找(wine cmd 不采用
#    Linux PATH 注入与注册表 PATH),复制到 system32 后必然命中;
#    WixUIExtension.dll 等扩展 dll 与 light.exe 同目录,-ext 可正常加载。
RUN cp -r /opt/wix/* /root/.wine32/drive_c/windows/system32/

# 8) Windows PATH 加入 Z:\opt\wix(双保险;实际依赖第 7 步的 system32 复制)
RUN xvfb-run -a wine reg add 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' \
        /v Path /t REG_EXPAND_SZ \
        /d 'C:\windows\system32;C:\windows;Z:\opt\wix' /f || true

WORKDIR /build
ENTRYPOINT ["/build/docker/build.sh"]
