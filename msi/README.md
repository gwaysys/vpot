# VPOT MSI 安装包

基于 **WiX Toolset 3.11**(直接调用 `candle`/`light`,无 go-msi、无 WixUI 扩展)
构建的 VPOT Windows MSI 安装程序,体积 **约 40KB**(纯手写 UI,无扩展资源)。

**MSI 是纯文件提取器**:只把 3 个文件装到默认目录 **`D:\vpot`**(安装时可改),
**不执行任何安装/卸载钩子**:

| 文件 | 用途 |
| --- | --- |
| `install-image.cmd` | 部署向导:检查 docker 运行 → `docker compose up -d` → 打开服务页 |
| `docker-compose.yaml` | 容器编排(host 网络,镜像 `docker.lib10.cn/library/vpot:v1.1.5`) |
| `readme.txt` | 首次启动设置说明 |

安装完成后,**用户手动**从开始菜单运行 **VPOT** 快捷方式(指向
`install-image.cmd`)完成部署。

## 安装界面(纯手写,无扩展)

向导对话框全部在 `.wxs` 中手写(WiX 3 核心元素,不依赖 WixUIExtension,
因此 MSI 极小),文本全部通过 `!(loc.xxx)` 从语言包(wxl)取值:

1. **欢迎** → 2. **第 1 步 / 3:安装 WSL**(官方 https://aka.ms/wsl +
   国内镜像 https://lib10.cn/download/wsl.2.7.11.0.x64.msi)→
   3. **第 2 步 / 3:安装 Docker**(官网
   https://www.docker.com/products/docker-desktop/)→
   4. **第 3 步 / 3:运行安装向导**(安装完成后手动运行开始菜单 VPOT)→
   5. **选择安装位置**(默认 `D:\vpot`,可编辑)→ 进度 → 完成

## 目录结构

```
msi/
├── templates/            # WiX 源模板(仓库维护)
│   ├── product.wxs       # 产品定义:固定 GUID、默认 D:\vpot、3 文件组件、快捷方式
│   ├── dialogs.wxs       # 标准对话框(欢迎/安装目录/进度/完成)+ Publish 跳转链
│   ├── InfoDialogs.wxs   # 三步说明对话框(WSL/Docker/运行向导)
│   └── loc/              # 语言包(wxl)
│       ├── zh-CN.wxl     # 简体中文(默认)
│       └── en-US.wxl     # 英文
├── build-msi.sh          # Linux(Docker 容器)构建脚本(推荐)
├── docker/               # 容器内构建脚本与镜像
│   ├── Dockerfile        # wine32 + WiX 3.11 + wine-mono x86(无 go-msi)
│   └── build.sh          # 容器内执行:sed 渲染 → candle → light
└── README.md
```

> `install-image.cmd`、`docker-compose.yaml`、`readme.txt` 不入仓库,
> 构建时由 build 脚本从 `../vpot-docker/` 复制到本目录后一起打包。

**体积说明**:MSI 体积与打包器无关。此前约 500KB 是因为依赖
WixUIExtension(其对话框/位图库资源较大);当前全部对话框手写、
无位图、无扩展,体积降至约 40KB。

## 构建

### Linux(推荐:Docker 容器编译完整 MSI)

无需在本机安装 wine/WiX,一切在容器内完成(宿主机只需 `docker`、`wget`):

```sh
./build-msi.sh                  # 一键生成双语 MSI(zh-CN + en-US,版本默认 1.1.5)
./build-msi.sh 1.2.0            # 指定版本,仍生成双语 MSI
./build-msi.sh 1.2.0 en-US      # 只生成指定语言
```

产物:`vpot-setup-<版本>-<culture>.msi`(默认 `zh-CN` + `en-US` 两个,
如 `vpot-setup-1.1.5-zh-CN.msi` 约 41KB)。

流程:构建镜像(`msi/docker/Dockerfile`:wine+wine32、WiX 3.11、
wine-mono x86)→ 容器内 `build.sh`:`sed` 渲染 `product.wxs` 的
`@VERSION@/@UPGRADE_CODE@` → `candle -arch x64` 编译 3 个 wxs →
`light -sval -loc <wxl>` 链接 → 产出 MSI。

首次构建镜像需下载 wine + WiX + wine-mono,较慢;网络受限时可覆盖下载源:

```sh
WIX_URL=<镜像> WINE_MONO_URL=<镜像> ./build-msi.sh
```

> 说明:`candle.exe`/`light.exe` 是 32 位 .NET 程序,镜像使用 `wine32` +
> `WINEARCH=win32` 纯 32 位 prefix + wine-mono x86;`-loc` 是 `light` 的
> 参数,`!(loc.xxx)` 由 light 链接时展开。

## 安装

双击 MSI 以管理员权限安装(默认安装到 **`D:\vpot`**,可在向导中修改):

- 安装向导展示欢迎与三步说明(见上文);
- 安装完成 **不会自动弹出任何窗口**(纯文件提取);
- 开始菜单生成 **VPOT** 快捷方式(指向 `install-image.cmd`),**手动运行**
  完成部署:检查 docker 是否运行(未运行则提示启动后重试)→
  `docker compose up -d` → 打开 `https://127.0.0.1:18800`;
- 数据目录默认在 **`我的文档\VPOT`**,compose 的 `./data` 卷落在此目录下。

> 若目标机器无 D: 盘,请在"选择安装位置"页面改为其他盘符(如
> `C:\vpot`),或在安装前确认 D: 盘存在。

## 卸载

通过"控制面板 → 程序和功能"(或"设置 → 应用")卸载 VPOT。MSI 无卸载钩子,
只删除安装目录与开始菜单快捷方式;以下内容**不会被自动移除**,需用户手工处理:

1. VPOT 容器与镜像:`docker compose down`(删除 `我的文档\VPOT` 数据目录可一并清理);
2. Docker Desktop:可能已被其他应用使用,通过"程序和功能"或
   `winget uninstall --id Docker.DockerDesktop` 卸载;
3. WSL:可能已被其他应用使用(且 Docker Desktop 依赖 WSL2),通过
   `wsl --unregister <发行版名>` 与 `optionalfeatures` 卸载。

## 注意事项

- `install-image.cmd` 是批处理脚本,不涉及未签名 exe;若 Windows 提示
  "Windows 已保护你的电脑",点"更多信息 → 仍要运行"即可(可右键 →
  属性 → 解除锁定)。
- `docker-compose.yaml` 使用 `network_mode: "host"` 与镜像
  `docker.lib10.cn/library/vpot:v1.1.5`;Windows Docker Desktop 对 host 网络
  模式支持有限,若 `docker compose up` 失败,请查看输出中的具体错误。
- 镜像源 `docker.lib10.cn` 为内网/加速域名,拉取失败时请确认网络可达。
- 首次启动页面需设置密码;模型接入步骤见 `readme.txt`。
