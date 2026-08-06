# VPOT MSI test: silent install / repair / remove
# Run: powershell -ExecutionPolicy Bypass -File test-msi.ps1
# Output is ASCII-only to avoid codepage issues.
param([string]$Msi = "vpot-setup-1.1.5-zh-CN.msi")

$ErrorActionPreference = "Continue"
$logDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$msiPath = Join-Path $logDir $Msi
if (-not (Test-Path $msiPath)) { Write-Output "ERROR: MSI not found: $msiPath"; exit 2 }

function Invoke-Msiexec {
    param([string[]]$ArgList, [string]$Log)
    $argStr = $ArgList -join " "
    $p = Start-Process msiexec -ArgumentList $argStr -Wait -PassThru
    Start-Sleep -Seconds 2
    return $p.ExitCode
}

function Get-LogErrors {
    param([string]$Log)
    if (-not (Test-Path $Log)) { return @("no log file") }
    $c = Get-Content $Log -ErrorAction SilentlyContinue
    $errs = @($c | Select-String -Pattern "Return value 3|Error 2707|Error 2814|Error 2867|Error 2868|Error 2896|error 1603|not recognized" | Select-Object -First 5)
    return $errs
}

Write-Output "=============================================="
Write-Output " [1/3] SILENT INSTALL"
Write-Output "=============================================="
$log1 = Join-Path $logDir "install.log"
$code1 = Invoke-Msiexec -ArgList @("/i", "`"$msiPath`"", "/qn", "/l*v", "`"$log1`"") -Log $log1
$dirOK  = Test-Path "D:\vpot"
$regOK  = (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq "VPOT" }) -ne $null
$lnkOK  = Test-Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\VPOT\VPOT.lnk"
Write-Output ("install  exit={0}  D:\vpot={1}  reg={2}  shortcut={3}" -f $code1, $dirOK, $regOK, $lnkOK)
if (Test-Path $log1) {
    $e1 = Get-LogErrors $log1
    if ($e1.Count -gt 0) { Write-Output "  log errors:"; $e1 | ForEach-Object { Write-Output "    $_" } }
    else { Write-Output "  log: no known error patterns" }
} else { Write-Output "  log: MISSING" }

Write-Output ""
Write-Output "=============================================="
Write-Output " [2/3] SILENT REPAIR (REINSTALL=ALL)"
Write-Output "=============================================="
$log2 = Join-Path $logDir "repair.log"
$code2 = Invoke-Msiexec -ArgList @("/i", "`"$msiPath`"", "/qn", "REINSTALL=ALL", "REINSTALLMODE=omus", "/l*v", "`"$log2`"") -Log $log2
Write-Output ("repair  exit={0}" -f $code2)
if (Test-Path $log2) {
    $e2 = Get-LogErrors $log2
    if ($e2.Count -gt 0) { Write-Output "  log errors:"; $e2 | ForEach-Object { Write-Output "    $_" } }
    else { Write-Output "  log: no known error patterns" }
} else { Write-Output "  log: MISSING" }

Write-Output ""
Write-Output "=============================================="
Write-Output " [3/3] SILENT REMOVE"
Write-Output "=============================================="
$log3 = Join-Path $logDir "remove.log"
$code3 = Invoke-Msiexec -ArgList @("/x", "`"$msiPath`"", "/qn", "/l*v", "`"$log3`"") -Log $log3
$dirGone = -not (Test-Path "D:\vpot")
$regGone = (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq "VPOT" }) -eq $null
Write-Output ("remove  exit={0}  D:\vpot removed={1}  reg removed={2}" -f $code3, $dirGone, $regGone)
if (Test-Path $log3) {
    $e3 = Get-LogErrors $log3
    if ($e3.Count -gt 0) { Write-Output "  log errors:"; $e3 | ForEach-Object { Write-Output "    $_" } }
    else { Write-Output "  log: no known error patterns" }
} else { Write-Output "  log: MISSING" }

Write-Output ""
Write-Output "=============================================="
Write-Output " SUMMARY"
Write-Output "  install exit=$code1  repair exit=$code2  remove exit=$code3"
$allOK = ($code1 -eq 0 -and $code2 -eq 0 -and $code3 -eq 0)
Write-Output ("  RESULT: {0}" -f ($(if ($allOK) { "ALL PASS" } else { "CHECK FAILURES" })))
Write-Output "=============================================="
