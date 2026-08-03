//go:build !windows

package main

import "fmt"

// relaunchElevated 仅 Windows 需要;其他平台仅用于保证编译通过。
func relaunchElevated(exe string) error {
	return fmt.Errorf("relaunchElevated 仅支持 Windows")
}
