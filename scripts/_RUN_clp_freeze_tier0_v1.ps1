param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$RepoRoot)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function EnsureDir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ EnsureDir $dir }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [System.IO.File]::WriteAllText($Path,$t,(New-Object System.Text.UTF8Encoding($false)))
}

function ReadUtf8NoBom([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  return [System.IO.File]::ReadAllText($Path,(New-Object System.Text.UTF8Encoding($false)))
}

function ParseGateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSE_GATE_MISSING: " + $Path) }
  $tokens = $null
  $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errs)
  if($errs -and $errs.Count -gt 0){
    $msg = ($errs | ForEach-Object { $_.ToString() }) -join "`n"
    Die ("PARSE_GATE_FAIL: " + $Path + "`n" + $msg)
  }
}

function Sha256HexBytes([byte[]]$Bytes){
  if($null -eq $Bytes){ $Bytes = @() }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try{
    $h = $sha.ComputeHash([byte[]]$Bytes)
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    while($i -lt $h.Length){ [void]$sb.Append($h[$i].ToString("x2")); $i++ }
    return $sb.ToString()
  } finally {
    $sha.Dispose()
  }
}

function Sha256HexFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  return (Sha256HexBytes ([System.IO.File]::ReadAllBytes($Path)))
}

function QuoteArg([string]$s){
  if($null -eq $s){ return '""' }
  if($s -match '[\s"`]'){
    return '"' + ($s -replace '"','\"') + '"'
  }
  return $s
}

function RunChildCapture([string]$PSExe,[string]$ScriptPath,[hashtable]$ArgMap,[string]$OutStd,[string]$OutErr){
  if(-not (Test-Path -LiteralPath $PSExe -PathType Leaf)){ Die ("MISSING_POWERSHELL_EXE: " + $PSExe) }
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){ Die ("MISSING_SCRIPT: " + $ScriptPath) }
  $argList = New-Object System.Collections.Generic.List[string]
  [void]$argList.Add("-NoProfile")
  [void]$argList.Add("-NonInteractive")
  [void]$argList.Add("-ExecutionPolicy")
  [void]$argList.Add("Bypass")
  [void]$argList.Add("-File")
  [void]$argList.Add($ScriptPath)
  $keys = @(@($ArgMap.Keys) | Sort-Object)
  foreach($k in $keys){
    [void]$argList.Add("-" + [string]$k)
    [void]$argList.Add([string]$ArgMap[$k])
  }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $PSExe
  $psi.Arguments = (@($argList.ToArray()) | ForEach-Object { QuoteArg $_ }) -join " "
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  if(-not $p.Start()){ Die ("CHILD_START_FAIL: " + $ScriptPath) }
  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  $code = [int]$p.ExitCode
  $p.Dispose()
  WriteUtf8NoBomLf $OutStd ($stdout + "")
  WriteUtf8NoBomLf $OutErr ($stderr + "")
  return @{ ExitCode = $code; Stdout = $stdout; Stderr = $stderr }
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){ Die ("MISSING_REPOROOT: " + $RepoRoot) }
$PSExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$Selftest = Join-Path $RepoRoot "scripts\_selftest_clp_v1.ps1"
$SelfPath = $PSCommandPath
ParseGateFile $Selftest
ParseGateFile $SelfPath

$tmp1o = Join-Path $env:TEMP ("clp_freeze_run1_" + [guid]::NewGuid().ToString("n") + ".out.log")
$tmp1e = Join-Path $env:TEMP ("clp_freeze_run1_" + [guid]::NewGuid().ToString("n") + ".err.log")
$tmp2o = Join-Path $env:TEMP ("clp_freeze_run2_" + [guid]::NewGuid().ToString("n") + ".out.log")
$tmp2e = Join-Path $env:TEMP ("clp_freeze_run2_" + [guid]::NewGuid().ToString("n") + ".err.log")

Write-Host "RUN 1" -ForegroundColor Yellow
$r1 = RunChildCapture $PSExe $Selftest @{ RepoRoot = $RepoRoot } $tmp1o $tmp1e
if($r1.ExitCode -ne 0){ Die ("FREEZE_FAIL_RUN1_EXIT: " + $r1.ExitCode + "`n" + $r1.Stderr) }
$out1 = ($r1.Stdout -replace "`r","").Trim()
Write-Host $out1

Write-Host "RUN 2" -ForegroundColor Yellow
$r2 = RunChildCapture $PSExe $Selftest @{ RepoRoot = $RepoRoot } $tmp2o $tmp2e
if($r2.ExitCode -ne 0){ Die ("FREEZE_FAIL_RUN2_EXIT: " + $r2.ExitCode + "`n" + $r2.Stderr) }
$out2 = ($r2.Stdout -replace "`r","").Trim()
Write-Host $out2

$m1 = [regex]::Match($out1,'root_hash=([0-9a-f]{64})')
$m2 = [regex]::Match($out2,'root_hash=([0-9a-f]{64})')
if(-not $m1.Success){ Die "FREEZE_FAIL_RUN1_ROOT_HASH_MISSING" }
if(-not $m2.Success){ Die "FREEZE_FAIL_RUN2_ROOT_HASH_MISSING" }
$root1 = [string]$m1.Groups[1].Value
$root2 = [string]$m2.Groups[1].Value
if($root1 -ne $root2){ Die ("FREEZE_FAIL_ROOT_HASH_MISMATCH: run1=" + $root1 + " run2=" + $root2) }
if($out1 -ne $out2){ Die "FREEZE_FAIL_STDOUT_MISMATCH" }

$FreezeDir = Join-Path (Join-Path $RepoRoot "proofs\receipts\clp_freeze") $root1
EnsureDir $FreezeDir
WriteUtf8NoBomLf (Join-Path $FreezeDir "run1_stdout.log") $r1.Stdout
WriteUtf8NoBomLf (Join-Path $FreezeDir "run1_stderr.log") $r1.Stderr
WriteUtf8NoBomLf (Join-Path $FreezeDir "run2_stdout.log") $r2.Stdout
WriteUtf8NoBomLf (Join-Path $FreezeDir "run2_stderr.log") $r2.Stderr
WriteUtf8NoBomLf (Join-Path $FreezeDir "root_hash.txt") $root1
WriteUtf8NoBomLf (Join-Path $FreezeDir "freeze_result.json") ('{"schema":"clp.freeze.result.v1","ok":true,"root_hash":"' + $root1 + '"}')

$files = @("freeze_result.json","root_hash.txt","run1_stderr.log","run1_stdout.log","run2_stderr.log","run2_stdout.log")
$lines = New-Object System.Collections.Generic.List[string]
foreach($f in @($files | Sort-Object)){
  $p = Join-Path $FreezeDir $f
  $h = Sha256HexFile $p
  [void]$lines.Add(($h + "  " + $f))
}
WriteUtf8NoBomLf (Join-Path $FreezeDir "sha256sums.txt") ((@($lines.ToArray()) -join "`n") + "`n")

Write-Host ""
Write-Host "CLP_TIER0_FREEZE_OK" -ForegroundColor Green
Write-Host ("ROOT_HASH=" + $root1) -ForegroundColor Green
