#!/bin/bash
# ============================================================
#  VPOT MSI Automated Test - for Git Bash / WSL on Windows
#  Usage:  bash test-msi.sh
#  Requirements: test-msi.ps1 and vpot-setup-1.1.5-zh-CN.msi
#                in the same folder
#  Logs: %TEMP%\vpot-test\install.log / repair.log / uninstall.log
# ============================================================
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "=============================================="
echo " VPOT MSI Automated Test"
echo " Test: silent install -> repair -> uninstall"
echo " Logs: \$TEMP/vpot-test/"
echo "=============================================="

[ -f test-msi.ps1 ] || { echo "[ERROR] test-msi.ps1 not found"; exit 1; }
[ -f vpot-setup-1.1.5-zh-CN.msi ] || { echo "[ERROR] vpot-setup-1.1.5-zh-CN.msi not found"; exit 1; }

# Prefer Windows powershell from Git Bash, fall back to WSL powershell.exe
if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "test-msi.ps1"
else
    powershell -NoProfile -ExecutionPolicy Bypass -File "test-msi.ps1"
fi

echo "=============================================="
echo " Test finished. See output above and logs in %TEMP%/vpot-test/"
echo "=============================================="
