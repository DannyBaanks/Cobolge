<#
.SYNOPSIS
    Test runner for Cobolge Malbolge engine.
.DESCRIPTION
    Runs gate test (full 48 steps), step-17 snapshot test, and resume test.
    Verifies byte-exact output and SHA-256 of snapshot against canonical fixtures.
.REQUIREMENTS
    - GnuCOBOL 3.2+ in PATH (or COB_CONFIG_DIR set)
    - Built cobolge.exe in bin/
#>

param(
    [string]$CobolConfigDir = 'C:\msys64\ucrt64\share\gnucobol\config',
    [string]$MsysBin = 'C:\msys64\ucrt64\bin',
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

# Setup environment
$env:COB_CONFIG_DIR = $CobolConfigDir
$env:Path = "$MsysBin;$env:Path"

$root = "C:\Development\ISyCo Git\Cobolge"
$exe = "$root\bin\cobolge.exe"
$fixtures = "$root\tests\fixtures"
$prog = "$fixtures\hello_classic.mal"
$tmp = "$env:TEMP\opencode\cob_test_$(Get-Random)"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

# Quote exe and arguments for cmd /c
$quotedExe = "`"$exe`""
$quotedProg = "`"$prog`""
$quotedSnap17 = "`"$tmp\snap17.json`""
$quote = [char]34

function Check-Output {
    param([string]$File, [string]$ExpectedHex)
    $actual = [System.IO.File]::ReadAllBytes($File)
    $expected = $ExpectedHex -split ' ' | ForEach-Object { [byte]("0x$_") }
    $same = $actual.Length -eq $expected.Length
    if ($same) {
        for ($i = 0; $i -lt $actual.Length; $i++) {
            if ($actual[$i] -ne $expected[$i]) { $same = $false; break }
        }
    }
    if (-not $same) {
        throw "Output mismatch. Got: $(($actual | ForEach-Object { '{0:x2}' -f $_ }) -join ' ')"
    }
}

function Check-Report {
    param([string]$File, [string]$Expected)
    $report = Get-Content $File -Raw | Select-String -Pattern '\{"final"' | Select-Object -First 1
    $line = if ($report) { $report.Line.Trim() } else { 'NULL' }
    if ($line -ne $Expected.Trim()) {
        throw "Report mismatch. Got: $line"
    }
}

function Check-SnapSha {
    param([string]$File, [string]$Expected)
    $sha = (Get-FileHash $File -Algorithm SHA256).Hash.ToUpper()
    if ($sha -ne $Expected.ToUpper()) {
        throw "Snapshot SHA mismatch. Got: $sha"
    }
}

$allPass = $true

# Test 1: Gate (full run, 48 steps)
Write-Host "=== Gate (48 steps) ===" -ForegroundColor Cyan
try {
    $cmd = $quotedExe + " " + $quotedProg + " --json"
    $outFile = $tmp + "\gate.out"
    $errFile = $tmp + "\gate.err"
    cmd /c ($cmd + ' 1> ' + $quote + $outFile + $quote + ' 2> ' + $quote + $errFile + $quote)
    if ($LASTEXITCODE -ne 0) { throw "Exit code: $LASTEXITCODE" }
    Check-Output $outFile '48 65 6c 6c 6f 2c 20 77 6f 72 6c 64 2e 0a'
    Check-Report $errFile '{"final":{"a":19758,"c":85,"d":63},"halt_reason":"VInstruction","output_len":13,"status":"HALTED","steps":48}'
    Write-Host "  PASS" -ForegroundColor Green
} catch { Write-Host "  FAIL: $_" -ForegroundColor Red; $allPass = $false }

# Test 2: Step-17 snapshot
Write-Host "=== Step-17 snapshot ===" -ForegroundColor Cyan
try {
    $cmd = $quotedExe + " " + $quotedProg + " 17 --json --snapshot-out " + $quotedSnap17
    $outFile = $tmp + "\snap.out"
    $errFile = $tmp + "\snap.err"
    cmd /c ($cmd + ' 1> ' + $quote + $outFile + $quote + ' 2> ' + $quote + $errFile + $quote)
    if ($LASTEXITCODE -ne 0) { throw "Exit code: $LASTEXITCODE" }
    Check-Output $outFile '48 65 6c 6c 6f 0a'
    Check-Report $errFile '{"final":{"a":40,"c":17,"d":57},"halt_reason":"StepsExhausted","output_len":5,"status":"TIMEOUT","steps":17}'
    Check-SnapSha ($tmp + "\snap17.json") '29372AAD12CAA5AFD340328D6C9AFB51408A3A60A477BDA94A671A0DD79A2FE4'
    Write-Host "  PASS" -ForegroundColor Green
} catch { Write-Host "  FAIL: $_" -ForegroundColor Red; $allPass = $false }

# Test 3: Resume from step-17 snapshot
Write-Host "=== Resume from step-17 ===" -ForegroundColor Cyan
try {
    $cmd = $quotedExe + " --resume " + $quotedSnap17 + " --json"
    $outFile = $tmp + "\resume.out"
    $errFile = $tmp + "\resume.err"
    cmd /c ($cmd + ' 1> ' + $quote + $outFile + $quote + ' 2> ' + $quote + $errFile + $quote)
    if ($LASTEXITCODE -ne 0) { throw "Exit code: $LASTEXITCODE" }
    Check-Output $outFile '48 65 6c 6c 6f 2c 20 77 6f 72 6c 64 2e 0a'
    Check-Report $errFile '{"final":{"a":19758,"c":85,"d":63},"halt_reason":"VInstruction","output_len":13,"status":"HALTED","steps":48}'
    Write-Host "  PASS" -ForegroundColor Green
} catch { Write-Host "  FAIL: $_" -ForegroundColor Red; $allPass = $false }

# Cleanup
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

if ($allPass) {
    Write-Host "`nALL TESTS PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nSOME TESTS FAILED" -ForegroundColor Red
    exit 1
}
