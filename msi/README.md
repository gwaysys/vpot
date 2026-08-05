# VPOT MSI 安装包

基于 [go-msi](https://github.com/mat007/go-msi)(WiX Toolset 3.10+)构建的 VPOT
Windows MSI 安装程序。

**MSI 是纯文件提取器**:只把 3 个文件装到 `C:\Program Files\VPOT`,**不执行任何
安装/卸载钩子**(避免未签名 exe 被 Defender 拦截、执行时序等整条执行链问题):

| 文件 | 用途 |
| --- | --- |
| `install-windows.cmd` | 完整安装向导:检测 WSL/Docker → 引导下载 → `docker compose up` → 打开服务页 |
| `docker-compose.yaml` | 容器编排(host 网络,镜像 `docker.lib10.cn/library/vpot:v1.1.5`) |
| `readme.txt` | 首次启动设置说明 |

安装完成后,**用户手动**从开始菜单运行 **VPOT** 快捷方式(指向
`install-windows.cmd`)完成部署。

## 安装界面(三步说明)

安装向导在"欢迎"与"选择安装目录"之间插入 3 个说明对话框,告知用户
WSL / Docker / 手动运行方式(文本全部来自语言包,支持国际化):

1. **第 1 步 / 3:安装 WSL** —— 给出两个下载地址:
   - 官方:https://aka.ms/wsl
   - 国内镜像(推荐):https://lib10.cn/download/wsl.2.7.11.0.x64.msi
2. **第 2 步 / 3:安装 Docker** —— Docker Desktop 官网:
   https://www.docker.com/products/docker-desktop/
3. **第 3 步 / 3:运行安装向导** —— 说明安装完成后手动运行开始菜单
   **VPOT**(install-windows.cmd)完成环境检测与容器部署。

## 目录结构

```
msi/
├── templates/            # go-msi 模板(仓库维护,见下方说明)
│   ├── product.wxs       # 主模板:Product 加 Codepage="65001"(UTF-8)
│   ├── InfoDialogs.wxs   # 三步说明对话框(文本用 !(loc.xxx))
│   ├── WixUI_HK.wxs      # 安装 UI 对话框集(含说明对话框的跳转链)
│   ├── LicenseAgreementDlg_HK.wxs
│   └── loc/              # 语言包(wxl)
│       ├── zh-CN.wxl     # 简体中文(默认)
│       └── en-US.wxl     # 英文
├── wix.json              # go-msi 配置(files / shortcuts,无 hooks)
├── build.ps1             # Windows 构建脚本(go-msi make,支持 -Culture)
├── build-msi-docker.sh   # Linux(Docker 容器)构建脚本(推荐)
├── docker/               # 容器内构建脚本与镜像
│   ├── Dockerfile        # wine32 + WiX 3.11 + wine-mono x86 + go-msi
│   └── build.sh          # 容器内执行:go-msi make + wine 兼容修补
└── README.md
```

> `install-windows.cmd`、`docker-compose.yaml`、`readme.txt` 不入仓库,
> 构建时由 build 脚本从 `../picoclaw-docker/` 复制到本目录后一起打包。

**模板来源**:`templates/` 为 go-msi
[`v0.0.0-20200224144923-4783d3eea8eb`](https://github.com/mat007/go-msi/tree/4783d3eea8eb/templates)
的模板副本(MIT 许可),在其基础上:
- `product.wxs` 的 `<Product>` 增加 `Codepage="65001"`;
- 新增 `InfoDialogs.wxs`(三步说明对话框)与 `loc/{zh-CN,en-US}.wxl`
  (语言包,`<String>` 用元素文本,WiX 3.11 schema 不接受 `Value` 属性;
  `Codepage="65001"` 使中文可写入 MSI 数据库);
- `WixUI_HK.wxs` 将三个说明对话框插入对话框跳转链。

三个构建脚本均优先使用本目录模板。

## 构建

### Linux(推荐:Docker 容器编译完整 MSI)

无需在本机安装 wine/WiX,一切在容器内完成:

```sh
./build-msi-docker.sh                  # 一键生成双语 MSI(zh-CN + en-US,版本默认 1.1.5)
./build-msi-docker.sh 1.2.0            # 指定版本,仍生成双语 MSI
./build-msi-docker.sh 1.2.0 en-US      # 只生成指定语言
```

产物:`vpot-setup-<版本>-<culture>.msi`(默认 `zh-CN` + `en-US` 两个,
如 `vpot-setup-1.1.5-zh-CN.msi`、`vpot-setup-1.1.5-en-US.msi`)。

流程:构建镜像(`msi/docker/Dockerfile`,内含 wine+wine32、WiX 3.11、
wine-mono x86、go-msi)→ 容器内 `go-msi make` → wine 兼容修补:
go-msi 生成的 `build.bat` 缺 `-loc`(语言包)与 `-sval`(wine 下跳过 MSI
验证),注入后重跑 `light` → 产出 MSI。

首次构建镜像需下载 wine + WiX + wine-mono,较慢;网络受限时可覆盖下载源:

```sh
WIX_URL=<镜像> WINE_MONO_URL=<镜像> ./build-msi-docker.sh
```

> 说明:`candle.exe`/`light.exe` 是 32 位 .NET 程序,镜像使用 `wine32` +
> `WINEARCH=win32` 纯 32 位 prefix + wine-mono x86;`-loc` 是 `light` 的
> 参数(`candle` 不支持),`!(loc.xxx)` 由 light 链接时展开。

### Windows(完整构建 MSI)

前置要求:

- Go 1.21+(https://go.dev/dl/)
- go-msi:`go install github.com/mat007/go-msi@latest`
- WiX Toolset 3.10+(`choco install wixtoolset`,或 https://wixtoolset.org/docs/wix3/)
- 确认 `candle`、`light` 在 `PATH` 中

构建:

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
# 或指定版本号与语言:
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Version 1.2.0 -Culture en-US
```

产物:`vpot-setup-<version>-<culture>.msi`。构建脚本会先复制仓库模板
(含语言包)到 go-msi 的模板目录;若 go-msi make 因 `!(loc.xxx)` 未展开失败,
自动向中间 `build.bat` 注入 `-loc` 后重跑。

> 说明:`wix.json` 已包含 `upgrade-code`,无需再执行 `go-msi set-guid`;
> 若重新生成 upgrade-code,请先 `go-msi set-guid` 再构建。

## 安装

双击 MSI 以管理员权限安装(默认安装到 `C:\Program Files\VPOT`):

- 安装向导展示三步说明(见上文);
- 安装完成 **不会自动弹出任何窗口**(纯文件提取);
- 开始菜单生成 **VPOT** 快捷方式(指向 `install-windows.cmd`),**手动运行**
  完成环境检测与容器部署:检测 WSL / Docker → 缺失则引导下载 →
  `docker compose up -d` → 打开 `https://127.0.0.1:18800`;
- 数据目录默认在 **`我的文档\VPOT`**,compose 的 `./data` 卷落在此目录下,
  避免 Program Files 的写入权限限制。

## 卸载

通过"控制面板 → 程序和功能"(或"设置 → 应用")卸载 VPOT。MSI 无卸载钩子,
只删除安装目录与开始菜单快捷方式;以下内容**不会被自动移除**,需用户手工处理:

1. VPOT 容器与镜像:`docker compose down`(删除 `我的文档\VPOT` 数据目录可一并清理);
2. Docker Desktop:可能已被其他应用使用,通过"程序和功能"或
   `winget uninstall --id Docker.DockerDesktop` 卸载;
3. WSL:可能已被其他应用使用(且 Docker Desktop 依赖 WSL2),通过
   `wsl --unregister <发行版名>` 与 `optionalfeatures` 卸载。

## 注意事项

- `install-windows.cmd` 是批处理脚本,不涉及未签名 exe;若 Windows 提示
  "Windows 已保护你的电脑",点"更多信息 → 仍要运行"即可(可右键 →
  属性 → 解除锁定)。
- `docker-compose.yaml` 使用 `network_mode: "host"` 与镜像
  `docker.lib10.cn/library/vpot:v1.1.5`;Windows Docker Desktop 对 host 网络
  模式支持有限,若 `docker compose up` 失败,请查看输出中的具体错误。
- 镜像源 `docker.lib10.cn` 为内网/加速域名,拉取失败时请确认网络可达。
- 首次启动页面需设置密码;模型接入步骤见 `readme.txt`。
