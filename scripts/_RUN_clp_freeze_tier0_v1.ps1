param(
  [Parameter(Mandatory=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$RepoRoot
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){
  throw $m
}

function ReadText([string]$p){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    Die ("MISSING_FILE: " + $p)
  }
  return [System.IO.File]::ReadAllText($p,(New-Object System.Text.UTF8Encoding($false)))
}

$PSExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

$Selftest = Join-Path $RepoRoot "scripts\_selftest_clp_v1.ps1"

if(-not (Test-Path -LiteralPath $Selftest -PathType Leaf)){
  Die ("MISSING_SELFTEST: " + $Selftest)
}

Write-Host "RUN 1" -ForegroundColor Cyan

$out1 = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File $Selftest `
  -RepoRoot $RepoRoot

Write-Host $out1

if($out1 -notmatch "SELFTEST_CLP_OK"){
  Die "RUN1_NOT_GREEN"
}

$root1 = ($out1 -split "root_hash=")[1].Split(" ")[0]

Write-Host "RUN 2" -ForegroundColor Cyan

$out2 = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File $Selftest `
  -RepoRoot $RepoRoot

Write-Host $out2

if($out2 -notmatch "SELFTEST_CLP_OK"){
  Die "RUN2_NOT_GREEN"
}

$root2 = ($out2 -split "root_hash=")[1].Split(" ")[0]

if($root1 -ne $root2){
  Die ("ROOT_HASH_MISMATCH: " + $root1 + " vs " + $root2)
}

$dir1 = Join-Path $RepoRoot ("proofs\receipts\clp_selftest\" + $root1)
$dir2 = Join-Path $RepoRoot ("proofs\receipts\clp_selftest\" + $root2)

$sum1 = Join-Path $dir1 "sha256sums.txt"
$sum2 = Join-Path $dir2 "sha256sums.txt"

$t1 = ReadText $sum1
$t2 = ReadText $sum2

if($t1 -ne $t2){
  Die "SHA256SUMS_MISMATCH"
}

Write-Host ""
Write-Host "CLP_TIER0_FREEZE_OK" -ForegroundColor Green
Write-Host ("ROOT_HASH=" + $root1) -ForegroundColor Green