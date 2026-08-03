//go:build windows

package main

import (
	"fmt"
	"syscall"
	"unsafe"
)

// init 将控制台代码页切换为 UTF-8(65001),保证中文输出在 Windows 命令
// 行窗口(cmd 默认 GBK/代码页 936)中不乱码。
func init() {
	kernel32 := syscall.NewLazyDLL("kernel32.dll")
	kernel32.NewProc("SetConsoleOutputCP").Call(65001)
	kernel32.NewProc("SetConsoleCP").Call(65001)
}

// relaunchElevated 通过 ShellExecuteW 以 runas 动词(触发 UAC)启动 exe,
// 避免 PowerShell 字符串拼接带来的引号/注入问题。返回 nil 表示请求已发出。
func relaunchElevated(exe string) error {
	shell32 := syscall.NewLazyDLL("shell32.dll")
	proc := shell32.NewProc("ShellExecuteW")
	verb, _ := syscall.UTF16PtrFromString("runas")
	path, _ := syscall.UTF16PtrFromString(exe)
	const swShownormal = 1
	r, _, _ := proc.Call(
		0, // hwnd
		uintptr(unsafe.Pointer(verb)),
		uintptr(unsafe.Pointer(path)),
		0, // parameters
		0, // directory
		swShownormal,
	)
	if r <= 32 { // ShellExecute 约定:返回值 <= 32 表示失败
		return fmt.Errorf("ShellExecuteW 返回 %d", r)
	}
	return nil
}
