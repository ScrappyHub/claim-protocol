param(
  [Parameter(Mandatory=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$RepoRoot
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function ReadTextUtf8NoBom([string]$p){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_FILE: " + $p) }
  $enc = New-Object System.Text.UTF8Encoding($false)
  return [System.IO.File]::ReadAllText($p,$enc)
}

function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ EnsureDir $dir }
  $t = $Text
  $t = $t.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t = $t + "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function ParseGateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSE_GATE_MISSING: " + $Path) }
  $tokens=$null; $errs=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errs)
  $e = @(@($errs))
  if($e.Count -gt 0){
    $msg = ($e | ForEach-Object { $_.ToString() }) -join "`n"
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
  $b = [System.IO.Path]::GetFullPath($Base).TrimEnd("\","/")
  $f = [System.IO.Path]::GetFullPath($Full)
  if($f.Length -lt $b.Length){ Die ("REL_PATH_FAIL: base longer than full: " + $Base + " :: " + $Full) }
  if($f.Substring(0,$b.Length).ToLowerInvariant() -ne $b.ToLowerInvariant()){ Die ("REL_PATH_FAIL: file not under base: " + $Full) }
  $rel = $f.Substring($b.Length).TrimStart("\","/")
  return (($rel -replace "\\","/"))
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
  return @{ Root = $root; ManifestText = $txt }
}

function RunChildCapture([string]$PSExe,[string]$ScriptPath,[hashtable]$ArgMap,[string]$OutStd,[string]$OutErr){
  if(-not (Test-Path -LiteralPath $PSExe -PathType Leaf)){ Die ("MISSING_POWERSHELL_EXE: " + $PSExe) }
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){ Die ("MISSING_SCRIPT: " + $ScriptPath) }
  $args = New-Object System.Collections.Generic.List[string]
  [void]$args.Add("-NoProfile")
  [void]$args.Add("-NonInteractive")
  [void]$args.Add("-ExecutionPolicy")
  [void]$args.Add("Bypass")
  [void]$args.Add("-File")
  [void]$args.Add($ScriptPath)
  $keys = @(@($ArgMap.Keys) | Sort-Object)
  foreach($k in $keys){
    [void]$args.Add("-" + [string]$k)
    [void]$args.Add([string]$ArgMap[$k])
  }
  EnsureDir (Split-Path -Parent $OutStd)
  EnsureDir (Split-Path -Parent $OutErr)
  $p = Start-Process -FilePath $PSExe -ArgumentList @($args.ToArray()) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $OutStd -RedirectStandardError $OutErr
  $code = [int]$p.ExitCode
  $stdout = (ReadTextUtf8NoBom $OutStd)
  $stderr = (ReadTextUtf8NoBom $OutErr)
  return @{ ExitCode = $code; Stdout = $stdout; Stderr = $stderr }
}

# -------------------------
# Validate repo + paths
# -------------------------
if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){ Die ("MISSING_REPOROOT: " + $RepoRoot) }
$PSExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$ScriptsDir = Join-Path $RepoRoot "scripts"
$TVDir      = Join-Path $RepoRoot "test_vectors"
$LibPath    = Join-Path $ScriptsDir "_lib_clp_v1.ps1"
$HashClaim  = Join-Path $ScriptsDir "clp_hash_claim_v1.ps1"
$HashRcpt   = Join-Path $ScriptsDir "clp_hash_receipt_v1.ps1"
$RunTV      = Join-Path $ScriptsDir "clp_run_test_vectors_v1.ps1"
$SelfPath   = $PSCommandPath
$MinClaimJson = Join-Path $TVDir "minimal-claim\claim.json"
$MinClaimExp  = Join-Path $TVDir "minimal-claim\expected_claim_id.txt"
$MinRcptJson  = Join-Path $TVDir "minimal-receipt\receipt.json"
$MinRcptExp   = Join-Path $TVDir "minimal-receipt\expected_receipt_id.txt"

# -------------------------
# Parse-gate required scripts
# -------------------------
ParseGateFile $LibPath
ParseGateFile $HashClaim
ParseGateFile $HashRcpt
ParseGateFile $RunTV
ParseGateFile $SelfPath

# -------------------------
# Deterministic receipt dir root hash over inputs
# -------------------------
$inputs = @(
  $LibPath, $HashClaim, $HashRcpt, $RunTV, $SelfPath,
  $MinClaimJson, $MinClaimExp, $MinRcptJson, $MinRcptExp
)
$rootObj = ComputeInputsRootHash $RepoRoot $inputs
$root = [string]$rootObj.Root
$manifestText = [string]$rootObj.ManifestText
$RcptBase = Join-Path $RepoRoot "proofs\receipts\clp_selftest"
$RcptDir  = Join-Path $RcptBase $root
EnsureDir $RcptDir
WriteUtf8NoBomLf (Join-Path $RcptDir "inputs_manifest.txt") $manifestText
WriteUtf8NoBomLf (Join-Path $RcptDir "inputs_root_hash.txt") ($root + "`n")

# -------------------------
# 1) Hash minimal claim and compare to expected
# -------------------------
$std1 = Join-Path $RcptDir "01_hash_claim_stdout.log"
$err1 = Join-Path $RcptDir "01_hash_claim_stderr.log"
$r1 = RunChildCapture $PSExe $HashClaim @{ RepoRoot=$RepoRoot; ClaimJsonPath=$MinClaimJson } $std1 $err1
if($r1.ExitCode -ne 0){ Die ("SELFTEST_FAIL_HASH_CLAIM_EXIT: " + $r1.ExitCode + "`n" + $r1.Stderr) }
$gotClaim = (($r1.Stdout -replace "`r","").Trim())
$wantClaim = ((ReadTextUtf8NoBom $MinClaimExp).Trim())
if($wantClaim -ne $gotClaim){ Die ("SELFTEST_FAIL_HASH_CLAIM_MISMATCH: want=" + $wantClaim + " got=" + $gotClaim) }

# -------------------------
# 2) Hash minimal receipt and compare to expected
# -------------------------
$std2 = Join-Path $RcptDir "02_hash_receipt_stdout.log"
$err2 = Join-Path $RcptDir "02_hash_receipt_stderr.log"
$r2 = RunChildCapture $PSExe $HashRcpt @{ RepoRoot=$RepoRoot; ReceiptJsonPath=$MinRcptJson } $std2 $err2
if($r2.ExitCode -ne 0){ Die ("SELFTEST_FAIL_HASH_RECEIPT_EXIT: " + $r2.ExitCode + "`n" + $r2.Stderr) }
$gotRcpt = (($r2.Stdout -replace "`r","").Trim())
$wantRcpt = ((ReadTextUtf8NoBom $MinRcptExp).Trim())
if($wantRcpt -ne $gotRcpt){ Die ("SELFTEST_FAIL_HASH_RECEIPT_MISMATCH: want=" + $wantRcpt + " got=" + $gotRcpt) }

# -------------------------
# 3) Run the test-vector runner (must be GREEN)
# -------------------------
$std3 = Join-Path $RcptDir "03_run_vectors_stdout.log"
$err3 = Join-Path $RcptDir "03_run_vectors_stderr.log"
$r3 = RunChildCapture $PSExe $RunTV @{ RepoRoot=$RepoRoot } $std3 $err3
if($r3.ExitCode -ne 0){ Die ("SELFTEST_FAIL_RUN_VECTORS_EXIT: " + $r3.ExitCode + "`n" + $r3.Stderr) }

# -------------------------
# Emit result.json
# -------------------------
$resultObj = @{ schema="clp.selftest.result.v1"; ok=$true; root_hash=$root; claim_id=$gotClaim; receipt_id=$gotRcpt }
try {
  . $LibPath
  if(Get-Command -Name WriteCanonJson -ErrorAction SilentlyContinue){
    WriteCanonJson (Join-Path $RcptDir "result.json") $resultObj
  } else {
    $json = ('{"schema":"clp.selftest.result.v1","ok":true,"root_hash":"' + $root + '","claim_id":"' + $gotClaim + '","receipt_id":"' + $gotRcpt + '"}')
    WriteUtf8NoBomLf (Join-Path $RcptDir "result.json") ($json + "`n")
  }
} catch {
  $json = ('{"schema":"clp.selftest.result.v1","ok":true,"root_hash":"' + $root + '","claim_id":"' + $gotClaim + '","receipt_id":"' + $gotRcpt + '"}')
  WriteUtf8NoBomLf (Join-Path $RcptDir "result.json") ($json + "`n")
}

# -------------------------
# sha256sums.txt (written last)
# -------------------------
$files = @(
  "inputs_manifest.txt",
  "inputs_root_hash.txt",
  "01_hash_claim_stdout.log",
  "01_hash_claim_stderr.log",
  "02_hash_receipt_stdout.log",
  "02_hash_receipt_stderr.log",
  "03_run_vectors_stdout.log",
  "03_run_vectors_stderr.log",
  "result.json"
)
$lines = New-Object System.Collections.Generic.List[string]
foreach($f in @($files | Sort-Object)){
  $p = Join-Path $RcptDir $f
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_RECEIPT_FILE: " + $p) }
  $h = Sha256HexFile $p
  [void]$lines.Add(($h + "  " + ($f -replace "\\","/")))
}
WriteUtf8NoBomLf (Join-Path $RcptDir "sha256sums.txt") ((@($lines.ToArray()) -join "`n") + "`n")

Write-Host ("SELFTEST_CLP_OK: root_hash=" + $root + " claim_id=" + $gotClaim + " receipt_id=" + $gotRcpt) -ForegroundColor Green
