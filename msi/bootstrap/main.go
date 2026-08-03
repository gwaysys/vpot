// VPOT bootstrap:Windows 安装/启动引导程序。
//
// 功能(与 picoclaw-docker/install-windows.cmd 对应的四步流程):
//  1. 检查 WSL 是否可用,缺失则引导安装(交互选择 A/B);
//  2. 检查 Docker 是否安装,缺失则引导安装(交互选择 A/B);
//  3. 检测 Docker 是否运行,未运行则尝试启动 Docker Desktop 并等待就绪;
//  4. 基于 docker-compose.yaml 拉取 vpot 镜像并启动容器,随后打开浏览器访问
//     https://127.0.0.1:18800。
//
// 卸载模式(vpot-bootstrap.exe -uninstall,由 MSI 卸载钩子调用):
//
//	清理 VPOT 自身的容器与数据;Docker/WSL 可能被其他应用使用,
//	仅提示并引导用户手工卸载,不自动移除。
//
// 工作目录:安装向导第 1 步选择(默认 我的文档\VPOT,可修改),
// 持久化在 %LOCALAPPDATA%\VPOT\config.ini;compose 文件与 data 卷
// 落在该目录,避免 Program Files 的 ACL 问题。
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const (
	wslDownloadURL    = "https://lib10.cn/download/wsl.2.7.11.0.x64.msi"
	dockerDownloadURL = "https://www.docker.com/products/docker-desktop/"
	appURL            = "https://127.0.0.1:18800"

	composeFileName = "docker-compose.yaml"
	workSubDir      = "VPOT"            // %LOCALAPPDATA%\VPOT
	maxDockerWait   = 180 * time.Second // 等待 Docker 就绪的最长时间
)

var reader = bufio.NewReader(os.Stdin)

func main() {
	// -uninstall:MSI 卸载钩子调用,引导手工卸载(无需提升权限)
	if len(os.Args) > 1 && os.Args[1] == "-uninstall" {
		runUninstall()
		return
	}

	printBanner()

	// wsl --install / winget 需要管理员权限,MSI 或普通双击启动时以
	// 非提升身份运行,这里检测并请求 UAC 提升(与 install-windows.cmd 的
	// :EnsureAdmin 一致),提升后新窗口自动继续。
	ensureAdmin()

	workDir := chooseWorkDir()

	if !step1WSL() {
		fmt.Println()
		fmt.Println("  WSL 未就绪,VPOT 无法继续。请安装/重启后重新运行本向导。")
		waitEnter("  按任意键退出...")
		os.Exit(1)
	}
	if !step2DockerInstall() {
		fmt.Println()
		fmt.Println("  Docker 未安装,VPOT 无法继续。请安装后重新运行本向导。")
		waitEnter("  按任意键退出...")
		os.Exit(1)
	}
	if !step3DockerRunning() {
		fmt.Println()
		fmt.Println("  Docker 未能启动,VPOT 无法继续。请手动启动 Docker Desktop 后重新运行本向导。")
		waitEnter("  按任意键退出...")
		os.Exit(1)
	}
	if !step4ComposeUp(workDir) {
		fmt.Println()
		fmt.Println("  容器启动失败,请根据上方错误信息处理后重试。")
		waitEnter("  按任意键退出...")
		os.Exit(1)
	}

	fmt.Println()
	fmt.Println("========================================")
	fmt.Println("  VPOT 部署完成!")
	fmt.Println("  服务地址: " + appURL)
	fmt.Println("========================================")
	openURL(appURL)
	waitEnter("  按任意键退出...")
}

func printBanner() {
	fmt.Println("========================================")
	fmt.Println("   VPOT 安装/启动向导")
	fmt.Println("   环境检测 → 依赖安装 → 容器启动")
	fmt.Println("========================================")
	fmt.Println()
}

// runUninstall 卸载引导模式。仅清理 VPOT 自身的容器与数据目录;
// Docker / WSL 等系统组件可能已被其他应用使用,只做提示并引导用户
// 手工卸载,绝不自动移除。
func runUninstall() {
	fmt.Println("========================================")
	fmt.Println("   VPOT 卸载向导")
	fmt.Println("   引导手工卸载,不会自动移除系统组件")
	fmt.Println("========================================")
	fmt.Println()

	// 第 1 步:清理 VPOT 自身的容器(数据在数据目录中,不受影响)
	fmt.Println("------ 第 1 步:清理 VPOT 容器 ------")
	if dockerInstalled() {
		if dockerRunning() {
			removeOldContainer()
		} else {
			fmt.Println("  Docker 未运行,跳过容器清理(数据保留在数据目录中)。")
		}
	} else {
		fmt.Println("  未检测到 Docker,跳过。")
	}

	// 第 2 步:数据目录(优先读配置,未配置时回退到 我的文档\VPOT)
	dataDir := loadWorkDir()
	if dataDir == "" {
		dataDir = filepath.Join(documentsDir(), workSubDir)
	}
	if _, err := os.Stat(dataDir); err == nil {
		fmt.Println()
		fmt.Println("------ 第 2 步:VPOT 数据目录 ------")
		fmt.Printf("  数据目录: %s\n", dataDir)
		fmt.Println("  其中包含对话记录、模型配置等数据,删除后不可恢复。")
		fmt.Println("  ----------------------------------------")
		fmt.Println("    [A] 保留数据(推荐)")
		fmt.Println("    [B] 删除数据(不可恢复)")
		fmt.Println("  ----------------------------------------")
		if !promptChoiceDefault(true) { // 无法读取输入时默认保留(A)
			fmt.Println("  数据删除后不可恢复,请输入 DELETE 确认删除:")
			confirm, _ := reader.ReadString('\n')
			if strings.ToUpper(strings.TrimSpace(confirm)) != "DELETE" {
				fmt.Println("  已取消删除,数据目录保留。")
			} else if !safeToDelete(dataDir) {
				fmt.Println("  该目录不符合安全删除条件(可能为系统/用户目录或缺少 VPOT 标记),")
				fmt.Println("  已取消删除。请手动删除: " + dataDir)
			} else {
				fmt.Println("  正在删除数据目录...")
				if err := os.RemoveAll(dataDir); err != nil {
					fmt.Println("  删除失败(可能被占用):", err)
				} else {
					fmt.Println("  数据目录已删除。")
					// 同步清理配置残留;若 dataDir 在 cfgDir 内部则已被 RemoveAll 覆盖
					cfgDir := filepath.Join(os.Getenv("LocalAppData"), workSubDir)
					if rel, err := filepath.Rel(cfgDir, dataDir); err != nil || strings.HasPrefix(rel, "..") {
						os.RemoveAll(cfgDir)
					}
				}
			}
		} else {
			fmt.Println("  已保留数据目录。如需手动删除,请删除上述路径。")
		}
	}

	// 第 3 步:Docker Desktop 引导(仅提示,不自动卸载)
	if dockerInstalled() {
		fmt.Println()
		fmt.Println("------ 第 3 步:Docker Desktop ------")
		fmt.Println("  检测到 Docker Desktop。")
		fmt.Println("  它可能是随 VPOT 安装的,但也可能已被其他应用使用,")
		fmt.Println("  是否卸载由您自行决定,本向导不会自动卸载。")
		fmt.Println("  手工卸载方式:")
		fmt.Println("    1) 按 Win+R 输入 appwiz.cpl 回车,在\"程序和功能\"中")
		fmt.Println("       找到 Docker Desktop,右键选择\"卸载\";")
		fmt.Println("    2) 或在命令提示符执行: winget uninstall --id Docker.DockerDesktop")
		fmt.Println("  ----------------------------------------")
		fmt.Println("    [A] 打开\"程序和功能\"(appwiz.cpl)")
		fmt.Println("    [B] 跳过,稍后自行处理")
		fmt.Println("  ----------------------------------------")
		if promptChoiceDefault(false) { // 无法读取输入时默认跳过(B)
			if err := openControlPanel("appwiz.cpl"); err != nil {
				fmt.Println("  打开失败:", err)
				fmt.Println("  请手动按 Win+R 输入 appwiz.cpl 回车。")
			} else {
				fmt.Println("  已打开\"程序和功能\"窗口。")
			}
		}
	}

	// 第 4 步:WSL 引导(仅提示,不自动卸载)
	if wslInstalled() {
		fmt.Println()
		fmt.Println("------ 第 4 步:WSL ------")
		fmt.Println("  检测到 WSL(适用于 Linux 的 Windows 子系统)。")
		fmt.Println("  警告:WSL 可能已被其他应用使用;Docker Desktop(WSL2 后端)")
		fmt.Println("  也依赖 WSL,请先卸载 Docker 再考虑移除 WSL。")
		fmt.Println("  是否卸载由您自行决定,本向导不会自动卸载。")
		fmt.Println("  手工卸载方式:")
		fmt.Println("    1) 删除 Linux 发行版: wsl --unregister <发行版名>")
		fmt.Println("    2) 关闭 WSL 功能:按 Win+R 输入 optionalfeatures 回车,")
		fmt.Println("       取消勾选\"适用于 Linux 的 Windows 子系统\",重启后生效")
		fmt.Println("  ----------------------------------------")
		fmt.Println("    [A] 打开\"启用或关闭 Windows 功能\"(optionalfeatures)")
		fmt.Println("    [B] 跳过,稍后自行处理")
		fmt.Println("  ----------------------------------------")
		if promptChoiceDefault(false) { // 无法读取输入时默认跳过(B)
			if err := runCmd("optionalfeatures"); err != nil {
				fmt.Println("  打开失败:", err)
				fmt.Println("  请手动按 Win+R 输入 optionalfeatures 回车。")
			} else {
				fmt.Println("  已打开\"Windows 功能\"窗口。")
			}
		}
	}

	fmt.Println()
	fmt.Println("========================================")
	fmt.Println("  VPOT 卸载引导完成。")
	fmt.Println("  感谢使用 VPOT!")
	fmt.Println("========================================")
	waitEnter("  按任意键退出...")
}

// ---------- 数据目录选择 ----------

// chooseWorkDir 引导用户确认/修改 VPOT 数据目录(默认 我的文档\VPOT),
// 选择结果持久化到 config.ini,返回最终目录。
func chooseWorkDir() string {
	fmt.Println("========================================")
	fmt.Println("  第 1 步 / 5:选择 VPOT 数据目录")
	fmt.Println("========================================")
	defaultDir := filepath.Join(documentsDir(), workSubDir)
	current := loadWorkDir()
	for {
		if current == "" {
			fmt.Printf("  默认目录: %s\n", defaultDir)
			fmt.Println("  (对话记录、模型配置等数据将保存在此目录下)")
			fmt.Println("  ----------------------------------------")
			fmt.Println("    [A] 使用默认目录")
			fmt.Println("    [B] 自定义目录")
			fmt.Println("  ----------------------------------------")
			if promptChoiceDefault(true) { // 无法读取输入时默认用默认目录
				current = defaultDir
			} else {
				current = inputDir(defaultDir)
			}
		} else {
			fmt.Printf("  当前目录: %s\n", current)
			fmt.Println("  ----------------------------------------")
			fmt.Println("    [A] 保持当前目录")
			fmt.Println("    [B] 修改目录")
			fmt.Println("  ----------------------------------------")
			if promptChoiceDefault(true) {
				// 保持
			} else {
				current = inputDir(current)
			}
		}
		current = filepath.Clean(os.ExpandEnv(current))
		abs, err := filepath.Abs(current)
		if err != nil {
			fmt.Println("  路径无效:", err, "请重新选择。")
			current = ""
			continue
		}
		current = abs
		if err := os.MkdirAll(current, 0755); err != nil {
			fmt.Println("  目录不可用:", err, "请重新选择。")
			current = ""
			continue
		}
		break
	}
	if err := saveWorkDir(current); err != nil {
		fmt.Println("  警告:保存目录配置失败:", err)
	}
	fmt.Printf("  [OK] 数据目录: %s\n", current)
	return current
}

// inputDir 提示用户输入数据目录;直接回车时回退到 fallback。
func inputDir(fallback string) string {
	fmt.Printf("  请输入数据目录的绝对路径(支持 %%VAR%% 环境变量,直接回车使用默认 %s):\n  > ", fallback)
	line, _ := reader.ReadString('\n')
	line = strings.TrimSpace(line)
	if line == "" {
		return fallback
	}
	return line
}

// documentsDir 返回"我的文档"实际路径(兼容 OneDrive 重定向),失败时回退。
func documentsDir() string {
	out, err := exec.Command("powershell", "-NoProfile", "-Command",
		"[Environment]::GetFolderPath('MyDocuments')").Output()
	if err == nil {
		if p := strings.TrimSpace(string(out)); p != "" {
			return p
		}
	}
	if home := os.Getenv("USERPROFILE"); home != "" {
		return filepath.Join(home, "Documents")
	}
	return os.Getenv("LocalAppData")
}

// safeToDelete 校验目录可安全删除:拒绝盘符根、系统目录、用户目录,
// 并要求目录内含 compose 文件(VPOT 工作目录标记),防止误删其他数据。
func safeToDelete(dir string) bool {
	abs, err := filepath.Abs(dir)
	if err != nil {
		return false
	}
	abs = filepath.Clean(abs)
	vol := filepath.VolumeName(abs)
	if strings.EqualFold(abs, vol+string(filepath.Separator)) {
		return false // 盘符根
	}
	for _, f := range []string{
		os.Getenv("SystemRoot"),
		os.Getenv("USERPROFILE"),
		os.Getenv("LocalAppData"),
		documentsDir(),
	} {
		if f != "" && strings.EqualFold(abs, filepath.Clean(f)) {
			return false
		}
	}
	// 只删除带 VPOT 标记(同步过 compose 文件)的目录
	if _, err := os.Stat(filepath.Join(abs, composeFileName)); err != nil {
		return false
	}
	return true
}

// configPath 配置文件的固定位置(不随数据目录移动)。
func configPath() string {
	return filepath.Join(os.Getenv("LocalAppData"), workSubDir, "config.ini")
}

func loadWorkDir() string {
	data, err := os.ReadFile(configPath())
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if rest, ok := strings.CutPrefix(line, "workdir="); ok {
			return strings.TrimSpace(rest)
		}
	}
	return ""
}

func saveWorkDir(dir string) error {
	if err := os.MkdirAll(filepath.Dir(configPath()), 0755); err != nil {
		return err
	}
	return os.WriteFile(configPath(), []byte("workdir="+dir+"\n"), 0644)
}

// ---------- 第 1 步:WSL ----------

func step1WSL() bool {
	fmt.Println("========================================")
	fmt.Println("  第 2 步 / 5:检查 WSL(Windows Subsystem for Linux)")
	fmt.Println("========================================")
	if wslInstalled() {
		fmt.Println("  [OK] WSL 已安装。")
		return true
	}
	fmt.Println("  [!!] 未检测到可用的 WSL。")
	fmt.Println("  ----------------------------------------")
	fmt.Println("    [A] 自动安装(wsl --install)")
	fmt.Println("    [B] 手动下载(打开浏览器下载安装包)")
	fmt.Println("  ----------------------------------------")
	if promptChoice() {
		fmt.Println("  正在执行 wsl --install,此过程会启用相关 Windows 功能并安装 Linux 发行版...")
		if err := runCmd("wsl", "--install"); err != nil {
			fmt.Println("  自动安装失败,打开手动下载页面...")
			openURL(wslDownloadURL)
			fmt.Println("  请下载并运行安装包,如有提示请重启系统,然后重新运行本向导。")
			return false
		}
		fmt.Println("  wsl --install 已执行。")
		fmt.Println("  若系统提示需要重启,请重启后重新运行本向导。")
		return wslInstalled()
	}
	fmt.Println("  正在打开 WSL 下载页面...")
	openURL(wslDownloadURL)
	fmt.Println("  请下载并运行安装包;如有提示请重启系统。")
	waitEnter("  安装完成后按任意键继续...")
	if wslInstalled() {
		fmt.Println("  [OK] WSL 已就绪。")
		return true
	}
	fmt.Println("  WSL 仍不可用。若刚完成安装,可能需要重启系统后再运行本向导。")
	return false
}

func wslInstalled() bool {
	if err := exec.Command("wsl", "--status").Run(); err == nil {
		return true
	}
	if err := exec.Command("wsl", "--list", "--quiet").Run(); err == nil {
		return true
	}
	return false
}

// ---------- 第 2 步:Docker 安装 ----------

func step2DockerInstall() bool {
	fmt.Println()
	fmt.Println("========================================")
	fmt.Println("  第 3 步 / 5:检查 Docker")
	fmt.Println("========================================")
	if dockerInstalled() {
		fmt.Println("  [OK] Docker 已安装。")
		return true
	}
	fmt.Println("  [!!] 未检测到 Docker。")
	fmt.Println("  ----------------------------------------")
	fmt.Println("    [A] 自动安装(winget 安装 Docker Desktop)")
	fmt.Println("    [B] 手动下载(打开浏览器下载 Docker Desktop)")
	fmt.Println("  ----------------------------------------")
	if promptChoice() {
		if exec.Command("winget", "--version").Run() != nil {
			fmt.Println("  未找到 winget,改为打开手动下载页面...")
			openURL(dockerDownloadURL)
			fmt.Println("  请下载并安装 Docker Desktop,然后重新运行本向导。")
			return false
		}
		fmt.Println("  正在通过 winget 安装 Docker Desktop(可能需要数分钟)...")
		if err := runCmd("winget", "install", "--id", "Docker.DockerDesktop",
			"--accept-source-agreements", "--accept-package-agreements", "--silent"); err != nil {
			fmt.Println("  winget 安装失败,打开手动下载页面...")
			openURL(dockerDownloadURL)
			fmt.Println("  请下载并安装 Docker Desktop,然后重新运行本向导。")
			return false
		}
		fmt.Println("  [OK] Docker Desktop 安装成功。")
		fmt.Println("  如系统提示,请注销后重新登录或重启系统,然后重新运行本向导。")
		return true
	}
	fmt.Println("  正在打开 Docker Desktop 下载页面...")
	openURL(dockerDownloadURL)
	fmt.Println("  请下载并安装 Docker Desktop;如有提示请重启或注销后重新登录。")
	waitEnter("  安装完成后按任意键继续...")
	if dockerInstalled() {
		fmt.Println("  [OK] Docker 已就绪。")
		return true
	}
	fmt.Println("  Docker 仍未检测到,请确认安装完成后重新运行本向导。")
	return false
}

func dockerInstalled() bool {
	return dockerCmd("--version").Run() == nil
}

// ---------- 第 3 步:Docker 运行状态 ----------

func step3DockerRunning() bool {
	fmt.Println()
	fmt.Println("========================================")
	fmt.Println("  第 4 步 / 5:检查 Docker 是否运行")
	fmt.Println("========================================")
	if dockerRunning() {
		fmt.Println("  [OK] Docker 正在运行。")
		return true
	}
	fmt.Println("  [!!] Docker 未运行,尝试启动 Docker Desktop...")
	startDockerDesktop()
	if waitForDocker(maxDockerWait) {
		fmt.Println("  [OK] Docker 已就绪。")
		return true
	}
	fmt.Println("  等待超时:Docker 仍未就绪。")
	fmt.Println("  请手动启动 Docker Desktop,待其状态变为 Running 后重新运行本向导。")
	return false
}

func dockerRunning() bool {
	return dockerCmd("info").Run() == nil
}

func startDockerDesktop() {
	candidates := []string{
		filepath.Join(os.Getenv("ProgramFiles"), "Docker", "Docker", "Docker Desktop.exe"),
		filepath.Join(os.Getenv("LocalAppData"), "Docker", "Docker Desktop.exe"),
	}
	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			fmt.Println("  启动 " + p)
			if err := exec.Command(p).Start(); err != nil {
				fmt.Println("  启动 Docker Desktop 失败:", err)
				return
			}
			return
		}
	}
	fmt.Println("  未找到 Docker Desktop 可执行文件,请手动启动。")
}

func waitForDocker(timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if dockerRunning() {
			return true
		}
		fmt.Println("  等待 Docker 启动...")
		time.Sleep(2 * time.Second)
	}
	return dockerRunning()
}

// ---------- 第 4 步:拉取镜像并启动容器 ----------

func step4ComposeUp(workDir string) bool {
	fmt.Println()
	fmt.Println("========================================")
	fmt.Println("  第 5 步 / 5:拉取 vpot 镜像并启动容器")
	fmt.Println("========================================")

	if err := prepareWorkDir(workDir); err != nil {
		fmt.Println("  准备运行目录失败:", err)
		return false
	}
	fmt.Println("  运行目录: " + workDir)

	if !removeOldContainer() {
		return false
	}

	compose, args, err := pickComposeCmd()
	if err != nil {
		fmt.Println("  ", err)
		return false
	}
	fmt.Printf("  执行: %s -f %s up -d\n", compose, composeFileName)
	cmd := exec.Command(compose, append(args, "-f", composeFileName, "up", "-d")...)
	cmd.Dir = workDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Println("  docker compose 执行失败:", err)
		return false
	}
	fmt.Println("  容器启动成功。")
	return true
}

// prepareWorkDir 把 compose 文件从安装目录同步到数据目录 workDir,
// 保证 data 卷(./data)落在用户可写目录(Program Files 下容器内无法写入)。
func prepareWorkDir(workDir string) error {
	exePath, err := os.Executable()
	if err != nil {
		return err
	}
	srcDir := filepath.Dir(exePath)
	if err := os.MkdirAll(workDir, 0755); err != nil {
		return err
	}
	for _, name := range []string{composeFileName, "readme.txt"} {
		src := filepath.Join(srcDir, name)
		data, err := os.ReadFile(src)
		if err != nil {
			continue // 源文件缺失时跳过(如用户单独拷贝 exe)
		}
		dst := filepath.Join(workDir, name)
		old, _ := os.ReadFile(dst)
		if !bytes.Equal(old, data) {
			if err := os.WriteFile(dst, data, 0644); err != nil {
				return err
			}
		}
	}
	return nil
}

func removeOldContainer() bool {
	out, err := dockerCmd("ps", "-a", "--format", "{{.Names}}").Output()
	if err != nil {
		fmt.Println("  查询容器列表失败:", err)
		return false
	}
	found := false
	for _, name := range strings.Split(string(out), "\n") {
		if strings.TrimSpace(name) == "vpot" {
			found = true
			break
		}
	}
	if !found {
		return true
	}
	fmt.Println("  发现已存在的 vpot 容器,先移除...")
	if err := runDocker("rm", "-f", "vpot"); err != nil {
		fmt.Println("  移除旧容器失败,请手动执行: docker rm -f vpot")
		return false
	}
	return true
}

func pickComposeCmd() (string, []string, error) {
	if p := dockerPath(); p != "" {
		if exec.Command(p, "compose", "version").Run() == nil {
			return p, []string{"compose"}, nil
		}
	}
	if exec.Command("docker-compose", "version").Run() == nil {
		return "docker-compose", nil, nil
	}
	return "", nil, fmt.Errorf("未找到 docker compose 或 docker-compose,请确认 Docker Desktop 已安装并运行")
}

// ---------- 通用工具 ----------

// isAdmin 通过 net session 探测当前进程是否具有管理员权限。
func isAdmin() bool {
	return exec.Command("net", "session").Run() == nil
}

// ensureAdmin 无管理员权限时通过 UAC 提升重启自身,然后退出当前进程。
func ensureAdmin() {
	if isAdmin() {
		return
	}
	fmt.Println("  需要管理员权限,正在请求提升(UAC)...")
	fmt.Println("  请在 UAC 弹窗中点击 \"是\" 继续。")
	exe, err := os.Executable()
	if err != nil {
		fmt.Println("  无法获取自身路径:", err)
		os.Exit(1)
	}
	if err := relaunchElevated(exe); err != nil {
		fmt.Println("  提升未获授权。请右键点击本程序,选择 \"以管理员身份运行\" 后重试。")
		os.Exit(1)
	}
	fmt.Println("  提升请求已发出,原窗口将退出...")
	os.Exit(0)
}

func promptChoice() bool {
	// 安装流程默认 A/B:无法读取输入时返回 false(走 B 手动下载分支,安全侧)
	return promptChoiceDefault(false)
}

// promptChoiceDefault 交互 A/B 选择;无法读取输入(EOF/非交互)时返回 defA。
func promptChoiceDefault(defA bool) bool {
	for {
		fmt.Print("  您的选择 (A/B): ")
		line, err := reader.ReadString('\n')
		if err != nil {
			fmt.Println("  输入读取失败(非交互环境)。")
			if defA {
				fmt.Println("  已按默认选择 A。")
			} else {
				fmt.Println("  已按默认选择 B。")
			}
			return defA
		}
		switch strings.ToUpper(strings.TrimSpace(line)) {
		case "A":
			return true
		case "B":
			return false
		}
		fmt.Println("  无效输入,请输入 A 或 B。")
	}
}

func waitEnter(msg string) {
	fmt.Print(msg)
	reader.ReadString('\n')
}

func runCmd(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	return cmd.Run()
}

// dockerPath 返回可用的 docker 可执行文件路径:优先 PATH,其次回退到
// Docker Desktop 安装目录。winget 安装 Docker 后当前进程的 PATH 不会
// 刷新,回退路径可避免误判"Docker 未安装"。
func dockerPath() string {
	if p, err := exec.LookPath("docker"); err == nil {
		return p
	}
	for _, p := range dockerCandidates() {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

func dockerCandidates() []string {
	return []string{
		filepath.Join(os.Getenv("ProgramFiles"), "Docker", "Docker", "resources", "bin", "docker.exe"),
		filepath.Join(os.Getenv("LocalAppData"), "Docker", "Docker", "resources", "bin", "docker.exe"),
		filepath.Join(os.Getenv("LocalAppData"), "Docker", "resources", "bin", "docker.exe"),
	}
}

func dockerCmd(args ...string) *exec.Cmd {
	if p := dockerPath(); p != "" {
		return exec.Command(p, args...)
	}
	return exec.Command("docker", args...) // PATH 无 docker 时让错误自然浮现
}

func runDocker(args ...string) error {
	cmd := dockerCmd(args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	return cmd.Run()
}

func openURL(url string) {
	// cmd /c start "" url :打开默认浏览器(与 install-windows.cmd 一致)
	exec.Command("cmd", "/c", "start", `""`, url).Start()
}

// openControlPanel 通过 control.exe 打开控制面板项(如 appwiz.cpl)。
func openControlPanel(item string) error {
	return exec.Command("control", item).Run()
}
