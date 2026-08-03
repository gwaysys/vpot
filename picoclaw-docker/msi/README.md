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

## 构建

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
- 运行数据写入 `%LOCALAPPDATA%\VPOT\data`(compose 的 `./data` 卷落在该目录,
  避免 Program Files 的写入权限限制)。

## 注意事项

- `docker-compose.yaml` 使用 `network_mode: "host"` 与镜像
  `docker.lib10.cn/library/vpot:v1.1.5`;Windows Docker Desktop 对 host 网络
  模式支持有限,若 `docker compose up` 失败,请查看输出中的具体错误。
- 镜像源 `docker.lib10.cn` 为内网/加速域名,拉取失败时请确认网络可达。
- 首次启动页面需设置密码;模型接入步骤见 `readme.txt`。
