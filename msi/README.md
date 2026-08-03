# VPOT MSI 安装包

基于 [go-msi](https://github.com/mat007/go-msi)(WiX Toolset 3.10+)构建的 VPOT
Windows MSI 安装程序。安装完成后自动弹出引导窗口,按四步完成环境检测与容器部署:

1. **检查 WSL**:缺失则引导安装(交互选择 `A` 自动安装 / `B` 手动下载);
2. **检查 Docker**:缺失则引导安装(交互选择 `A` winget 自动安装 / `B` 手动下载);
3. **检测 Docker 是否运行**:未运行则自动启动 Docker Desktop 并等待就绪;
4. **拉取镜像并启动**:基于 `docker-compose.yaml` 执行 `docker compose up -d`,
   成功后自动打开浏览器访问 `https://127.0.0.1:18800`。

## 目录结构

```
msi/
├── bootstrap/            # Go 引导程序(vpot-bootstrap.exe 源码,纯标准库)
│   ├── go.mod
│   ├── main.go           # 四步引导逻辑(与 install-windows.cmd 对应)
│   └── console_windows.go# Windows 控制台 UTF-8 支持(避免中文乱码)
├── wix.json              # go-msi 配置(files / shortcuts / hooks)
├── build.ps1             # Windows 完整构建脚本(go build + go-msi make)
├── Makefile              # Linux/macOS 交叉编译 exe + 准备打包文件
└── README.md
```

> `docker-compose.yaml` 与 `readme.txt` 不打入仓库,构建时由
> Makefile / build.ps1 从 `../picoclaw-docker/` 复制到本目录后一起打包。

## 构建

### Linux(推荐:Docker 容器编译完整 MSI)

无需在本机安装 wine/WiX,一切在容器内完成:

```sh
# 依赖:已安装并启动 docker、go、wget
./build-msi-docker.sh            # 默认版本 1.1.5
./build-msi-docker.sh 1.2.0      # 指定版本
```

流程:宿主机交叉编译 `vpot-bootstrap.exe` → 构建镜像
(`msi/docker/Dockerfile`,内含 wine+wine32、WiX 3.11、wine-mono x86、go-msi)
→ 容器内 `go-msi make` → 产物 `vpot-setup-<版本>.msi`。

首次构建镜像需下载 wine + WiX + wine-mono,较慢;网络受限时可覆盖下载源:

```sh
WIX_URL=<镜像> WINE_MONO_URL=<镜像> ./build-msi-docker.sh
```

> 说明:`candle.exe`/`light.exe` 是 32 位 .NET 程序,镜像使用 `wine32` +
> `WINEARCH=win32` 纯 32 位 prefix + wine-mono x86,已验证可行。

### Linux/macOS(仅交叉编译 bootstrap.exe)

```sh
make bootstrap          # 产出 vpot-bootstrap.exe 并复制 compose/readme
```

生成的 `.msi` 仍需在 Windows 上完成(见下)。

### Windows(完整构建 MSI)

前置要求:

- Go 1.21+(https://go.dev/dl/)
- go-msi:`go install github.com/mat007/go-msi@latest`
- WiX Toolset 3.10+(`choco install wixtoolset`,或 https://wixtoolset.org/docs/wix3/)
- 确认 `candle`、`light` 在 `PATH` 中

构建:

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
# 或指定版本号:
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Version 1.2.0
```

产物:`vpot-setup-<version>.msi`。

> 说明:`wix.json` 已包含 `upgrade-code`,无需再执行 `go-msi set-guid`;
> 若重新生成 upgrade-code,请先 `go-msi set-guid` 再构建。

## 安装

双击 MSI 以管理员权限安装(默认安装到 `C:\Program Files\lib10\VPOT`):

- 安装完成后自动弹出 VPOT 引导窗口执行四步流程(go-msi 的 install hook
  固定排在 `InstallFiles` 之后执行,此时 `vpot-bootstrap.exe` 已落盘);
- 开始菜单生成 **VPOT** 快捷方式,可随时重新运行引导(环境修复/再次启动);
- 数据目录默认在 **`我的文档\VPOT`**(`C:\Users\<用户名>\Documents\VPOT`,
  兼容 OneDrive 重定向),安装引导第 1 步可修改;选择结果保存在
  `%LOCALAPPDATA%\VPOT\config.ini`,重跑向导可再次修改。
  compose 的 `./data` 卷落在此目录下,避免 Program Files 的写入权限限制。

## 卸载

通过"控制面板 → 程序和功能"(或"设置 → 应用")卸载 VPOT。卸载时自动弹出
**VPOT 卸载向导**,仅做引导、**不会自动移除系统组件**(卸载向导由 go-msi 的
uninstall hook 触发,排在 `InstallValidate` 之前、早于 `RemoveFiles`,
此时引导程序仍在磁盘上):

1. 清理 VPOT 自身容器;数据目录(默认 `我的文档\VPOT`,以 config.ini 记录为准)
   由用户确认是否删除(需输入 `DELETE` 二次确认);
2. 检测到 Docker Desktop 时提示:它可能已被其他应用使用,引导通过
   "程序和功能"或 `winget uninstall --id Docker.DockerDesktop` 手工卸载;
3. 检测到 WSL 时提示:可能已被其他应用使用(且 Docker Desktop 依赖 WSL2),
   引导通过 `wsl --unregister <发行版名>` 与 `optionalfeatures` 手工卸载。

## 注意事项

- `docker-compose.yaml` 使用 `network_mode: "host"` 与镜像
  `docker.lib10.cn/library/vpot:v1.1.5`;Windows Docker Desktop 对 host 网络
  模式支持有限,若 `docker compose up` 失败,请查看输出中的具体错误。
- 镜像源 `docker.lib10.cn` 为内网/加速域名,拉取失败时请确认网络可达。
- 首次启动页面需设置密码;模型接入步骤见 `readme.txt`。
