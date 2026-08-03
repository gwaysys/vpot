// VPOT bootstrap:Windows 安装/启动引导程序。
//
// 功能(与 picoclaw-docker/install-windows.cmd 对应的四步流程):
//  1. 检查 WSL 是否可用,缺失则引导安装(交互选择 A/B);
//  2. 检查 Docker 是否安装,缺失则引导安装(交互选择 A/B);
//  3. 检测 Docker 是否运行,未运行则尝试启动 Docker Desktop 并等待就绪;
//  4. 基于 docker-compose.yaml 拉取 vpot 镜像并启动容器,随后打开浏览器访问
//     https://127.0.0.1:18800。
//
// 工作目录:compose 文件会被同步到 %LOCALAPPDATA%\VPOT 下再执行,
// 使 data 卷(./data)落在用户可写目录,避免 Program Files 的 ACL 问题。
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
	printBanner()

	// wsl --install / winget 需要管理员权限,MSI 或普通双击启动时以
	// 非提升身份运行,这里检测并请求 UAC 提升(与 install-windows.cmd 的
	// :EnsureAdmin 一致),提升后新窗口自动继续。
	ensureAdmin()

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
	if !step4ComposeUp() {
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

// ---------- 第 1 步:WSL ----------

func step1WSL() bool {
	fmt.Println("========================================")
	fmt.Println("  第 1 步 / 4:检查 WSL(Windows Subsystem for Linux)")
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
	fmt.Println("  第 2 步 / 4:检查 Docker")
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
	fmt.Println("  第 3 步 / 4:检查 Docker 是否运行")
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

func step4ComposeUp() bool {
	fmt.Println()
	fmt.Println("========================================")
	fmt.Println("  第 4 步 / 4:拉取 vpot 镜像并启动容器")
	fmt.Println("========================================")

	workDir, err := prepareWorkDir()
	if err != nil {
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

// prepareWorkDir 把 compose 文件从安装目录同步到 %LOCALAPPDATA%\VPOT,
// 保证 data 卷落在用户可写目录(Program Files 下容器内无法写入)。
func prepareWorkDir() (string, error) {
	exePath, err := os.Executable()
	if err != nil {
		return "", err
	}
	srcDir := filepath.Dir(exePath)
	workDir := filepath.Join(os.Getenv("LocalAppData"), workSubDir)
	if err := os.MkdirAll(workDir, 0755); err != nil {
		return "", err
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
				return "", err
			}
		}
	}
	return workDir, nil
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
	for {
		fmt.Print("  您的选择 (A/B): ")
		line, err := reader.ReadString('\n')
		if err != nil {
			fmt.Println("  输入读取失败(非交互环境),将默认打开手动下载页面。")
			return false
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
