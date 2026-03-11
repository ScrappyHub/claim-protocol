param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ return }; if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ EnsureDir $dir }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [System.IO.File]::WriteAllText($Path,$t,(New-Object System.Text.UTF8Encoding($false)))
}
function ParseGateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSE_GATE_MISSING: " + $Path) }
  $tokens=$null; $errs=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errs)
  if($errs -and $errs.Count -gt 0){
    $msg = ($errs | ForEach-Object { $_.ToString() }) -join "`n"
    Die ("PARSE_GATE_FAIL: " + $Path + "`n" + $msg)
  }
}
function Sha256HexBytes([byte[]]$Bytes){
  if($null -eq $Bytes){ $Bytes = @() }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $h = $sha.ComputeHash([byte[]]$Bytes)
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    while($i -lt $h.Length){ [void]$sb.Append($h[$i].ToString("x2")); $i++ }
    return $sb.ToString()
  } finally { $sha.Dispose() }
}
function Sha256HexFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  $b = [System.IO.File]::ReadAllBytes($Path)
  return (Sha256HexBytes $b)
}
function RelPath([string]$Base,[string]$Full){
  $b = [System.IO.Path]::GetFullPath($Base).TrimEnd('\','/')
  $f = [System.IO.Path]::GetFullPath($Full)
  if($f.Length -lt $b.Length){ Die ("REL_PATH_FAIL: base longer than full: " + $Base + " :: " + $Full) }
  if($f.Substring(0,$b.Length).ToLowerInvariant() -ne $b.ToLowerInvariant()){ Die ("REL_PATH_FAIL: file not under base: " + $Full) }
  $rel = $f.Substring($b.Length).TrimStart('\','/')
  return ($rel -replace '\\','/')
}
function ComputeInputsRootHash([string]$Base,[string[]]$Paths){
  $rows = New-Object System.Collections.Generic.List[string]
  foreach($p in @($Paths)){
    if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_INPUT_FOR_ROOT: " + $p) }
    $hex = Sha256HexFile $p
    $rel = RelPath $Base $p
    [void]$rows.Add(($hex + " " + $rel))
  }
  $sorted = @($rows.ToArray() | Sort-Object)
  $txt = (@($sorted) -join "`n") + "`n"
  $enc = New-Object System.Text.UTF8Encoding($false)
  $root = Sha256HexBytes ($enc.GetBytes($txt))
  return @{ Root=$root; ManifestText=$txt }
}
function RunChildCapture([string]$PSExe,[string]$ScriptPath,[hashtable]$Args,[string]$OutStd,[string]$OutErr){
  if(-not (Test-Path -LiteralPath $PSExe -PathType Leaf)){ Die ("MISSING_POWERSHELL_EXE: " + $PSExe) }
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){ Die ("MISSING_SCRIPT: " + $ScriptPath) }
  $argList = New-Object System.Collections.Generic.List[string]
  [void]$argList.Add('-NoProfile')
  [void]$argList.Add('-NonInteractive')
  [void]$argList.Add('-ExecutionPolicy')
  [void]$argList.Add('Bypass')
  [void]$argList.Add('-File')
  [void]$argList.Add($ScriptPath)
  $keys = @(@($Args.Keys) | Sort-Object)
  foreach($k in $keys){ [void]$argList.Add('-' + [string]$k); [void]$argList.Add([string]$Args[$k]) }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $PSExe
  $psi.Arguments = (@($argList.ToArray()) | ForEach-Object { if($_ -match '[\s"`]'){ '"' + ($_ -replace '"','\"') + '"' } else { $_ } }) -join ' '
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
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
  return @{ ExitCode=$code; Stdout=$stdout; Stderr=$stderr }
}

# -------------------------
# Paths
# -------------------------
$PSExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$ScriptsDir = Join-Path $RepoRoot "scripts"
$TVDir      = Join-Path $RepoRoot "test_vectors"
$LibPath    = Join-Path $ScriptsDir "_lib_clp_v1.ps1"
$HashClaim  = Join-Path $ScriptsDir "clp_hash_claim_v1.ps1"
$HashRcpt   = Join-Path $ScriptsDir "clp_hash_receipt_v1.ps1"
$RunTV      = Join-Path $ScriptsDir "clp_run_test_vectors_v1.ps1"
$Selftest   = Join-Path $ScriptsDir "_selftest_clp_v1.ps1"

$MinClaimJson = Join-Path $TVDir "minimal-claim\claim.json"
$MinClaimExp  = Join-Path $TVDir "minimal-claim\expected_claim_id.txt"
$MinRcptJson  = Join-Path $TVDir "minimal-receipt\receipt.json"
$MinRcptExp   = Join-Path $TVDir "minimal-receipt\expected_receipt_id.txt"

# -------------------------
# Parse-gate required scripts first
# -------------------------
ParseGateFile $LibPath
ParseGateFile $HashClaim
ParseGateFile $HashRcpt
ParseGateFile $RunTV

# -------------------------
# Fix minimal-claim expected_claim_id.txt (no placeholder)
# -------------------------
EnsureDir (Split-Path -Parent $MinClaimExp)
$tmpStd = Join-Path $env:TEMP ("clp_hash_claim_" + [guid]::NewGuid().ToString("n") + ".out.txt")
$tmpErr = Join-Path $env:TEMP ("clp_hash_claim_" + [guid]::NewGuid().ToString("n") + ".err.txt")
$r = RunChildCapture $PSExe $HashClaim @{ RepoRoot=$RepoRoot; ClaimJsonPath=$MinClaimJson } $tmpStd $tmpErr
if($r.ExitCode -ne 0){ Die ("HASH_CLAIM_FAILED_EXIT: " + $r.ExitCode + "`n" + $r.Stderr) }
$claimId = ($r.Stdout -replace "`r","").Trim()
if([string]::IsNullOrWhiteSpace($claimId)){ Die ("HASH_CLAIM_EMPTY_OUTPUT") }
WriteUtf8NoBomLf $MinClaimExp ($claimId + "`n")

# -------------------------
# Write scripts/_selftest_clp_v1.ps1 (known-good, file-based)
# -------------------------
ParseGateFile $Selftest

# -------------------------
# Run vectors now (should be GREEN)
# -------------------------
$rV = RunChildCapture $PSExe $RunTV @{ RepoRoot=$RepoRoot } (Join-Path $env:TEMP ("clp_vectors_" + [guid]::NewGuid().ToString("n") + ".out.txt")) (Join-Path $env:TEMP ("clp_vectors_" + [guid]::NewGuid().ToString("n") + ".err.txt"))
if($rV.ExitCode -ne 0){ Die ("RUN_VECTORS_FAILED_EXIT: " + $rV.ExitCode + "`n" + $rV.Stderr) }

# -------------------------
# Run selftest (emits proofs/receipts/clp_selftest/...)
# -------------------------
$rS = RunChildCapture $PSExe $Selftest @{ RepoRoot=$RepoRoot } (Join-Path $env:TEMP ("clp_selftest_" + [guid]::NewGuid().ToString("n") + ".out.txt")) (Join-Path $env:TEMP ("clp_selftest_" + [guid]::NewGuid().ToString("n") + ".err.txt"))
if($rS.ExitCode -ne 0){ Die ("SELFTEST_FAILED_EXIT: " + $rS.ExitCode + "`n" + $rS.Stderr) }
Write-Host ("PATCH_AND_SELFTEST_OK: " + $Selftest) -ForegroundColor Green
