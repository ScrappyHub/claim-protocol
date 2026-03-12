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

function ReadTextUtf8NoBom([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  return [System.IO.File]::ReadAllText($Path,(New-Object System.Text.UTF8Encoding($false)))
}

function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ EnsureDir $dir }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [System.IO.File]::WriteAllText($Path,$t,(New-Object System.Text.UTF8Encoding($false)))
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

function RelPath([string]$Base,[string]$Full){
  $b = [System.IO.Path]::GetFullPath($Base).TrimEnd("\","/")
  $f = [System.IO.Path]::GetFullPath($Full)
  if($f.Length -lt $b.Length){ Die ("REL_PATH_FAIL: base longer than full: " + $Base + " :: " + $Full) }
  if($f.Substring(0,$b.Length).ToLowerInvariant() -ne $b.ToLowerInvariant()){ Die ("REL_PATH_FAIL: file not under base: " + $Full) }
  $rel = $f.Substring($b.Length).TrimStart("\","/")
  $rel = ($rel -replace "\\","/")
  return $rel
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
  $root = Sha256HexBytes ((New-Object System.Text.UTF8Encoding($false)).GetBytes($txt))
  return @{ Root = $root; ManifestText = $txt }
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
$ScriptsDir = Join-Path $RepoRoot "scripts"
$TVDir = Join-Path $RepoRoot "test_vectors"
$LibPath = Join-Path $ScriptsDir "_lib_clp_v1.ps1"
$HashClaim = Join-Path $ScriptsDir "clp_hash_claim_v1.ps1"
$HashRcpt = Join-Path $ScriptsDir "clp_hash_receipt_v1.ps1"
$RunTV = Join-Path $ScriptsDir "clp_run_test_vectors_v1.ps1"
$RunObjectLaw = Join-Path $ScriptsDir "clp_run_object_law_vectors_v1.ps1"
$RunMediaStorage = Join-Path $ScriptsDir "clp_run_media_storage_vectors_v1.ps1"
$RunVerifier = Join-Path $ScriptsDir "clp_run_verifier_vectors_v1.ps1"
$AppendPledge = Join-Path $ScriptsDir "clp_append_local_pledge_v1.ps1"
$VerifyPledge = Join-Path $ScriptsDir "clp_verify_local_pledge_v1.ps1"
$RunPledgeVectors = Join-Path $ScriptsDir "clp_run_local_pledge_vectors_v1.ps1"
$SelfPath = $PSCommandPath
$MinClaimJson = Join-Path $TVDir "minimal-claim\claim.json"
$MinClaimExp = Join-Path $TVDir "minimal-claim\expected_claim_id.txt"
$MinRcptJson = Join-Path $TVDir "minimal-receipt\receipt.json"
$MinRcptExp = Join-Path $TVDir "minimal-receipt\expected_receipt_id.txt"
$Claim2 = Join-Path $TVDir "local_pledge\claim2.json"

ParseGateFile $LibPath
ParseGateFile $HashClaim
ParseGateFile $HashRcpt
ParseGateFile $RunTV
ParseGateFile $RunObjectLaw
ParseGateFile $RunMediaStorage
ParseGateFile $RunVerifier
ParseGateFile $AppendPledge
ParseGateFile $VerifyPledge
ParseGateFile $RunPledgeVectors
ParseGateFile $SelfPath

$inputs = @(
  $LibPath,
  $HashClaim,
  $HashRcpt,
  $RunTV,
  $RunObjectLaw,
  $RunMediaStorage,
  $RunVerifier,
  $AppendPledge,
  $VerifyPledge,
  $RunPledgeVectors,
  $SelfPath,
  $MinClaimJson,
  $MinClaimExp,
  $MinRcptJson,
  $MinRcptExp,
  $Claim2,
  (Join-Path $TVDir "object_law\positive_claim_minimal\object.json"),
  (Join-Path $TVDir "object_law\positive_receipt_minimal\object.json"),
  (Join-Path $TVDir "object_law\positive_decision_minimal\object.json"),
  (Join-Path $TVDir "object_law\negative_missing_schema\object.json"),
  (Join-Path $TVDir "object_law\negative_claim_payload_not_object\object.json"),
  (Join-Path $TVDir "object_law\negative_decision_inputs_not_array\object.json"),
  (Join-Path $TVDir "media_storage\positive_inline_json\payload.json"),
  (Join-Path $TVDir "media_storage\positive_inline_text\payload.json"),
  (Join-Path $TVDir "media_storage\positive_blob_ref\payload.json"),
  (Join-Path $TVDir "media_storage\positive_packet_ref\payload.json"),
  (Join-Path $TVDir "media_storage\negative_bad_mode\payload.json"),
  (Join-Path $TVDir "media_storage\negative_blob_ref_missing_digest\payload.json"),
  (Join-Path $TVDir "media_storage\negative_packet_ref_missing_packet_id\payload.json"),
  (Join-Path $TVDir "verifier\positive_claim_valid\object.json"),
  (Join-Path $TVDir "verifier\positive_receipt_valid\object.json"),
  (Join-Path $TVDir "verifier\positive_decision_valid\object.json"),
  (Join-Path $TVDir "verifier\positive_blob_ref_metadata_valid\object.json"),
  (Join-Path $TVDir "verifier\negative_missing_schema\object.json"),
  (Join-Path $TVDir "verifier\negative_bad_payload_mode\object.json"),
  (Join-Path $TVDir "verifier\negative_blob_ref_missing_digest\object.json"),
  (Join-Path $TVDir "verifier\negative_decision_inputs_not_array\object.json"),
  (Join-Path $TVDir "verifier\negative_unsupported_schema\object.json"),
  (Join-Path $TVDir "verifier\negative_top_level_not_object\object.json")
)
$rootObj = ComputeInputsRootHash $RepoRoot $inputs
$root = [string]$rootObj.Root
$manifestText = [string]$rootObj.ManifestText
$RcptBase = Join-Path $RepoRoot "proofs\receipts\clp_selftest"
$RcptDir = Join-Path $RcptBase $root
EnsureDir $RcptDir
WriteUtf8NoBomLf (Join-Path $RcptDir "inputs_manifest.txt") $manifestText
WriteUtf8NoBomLf (Join-Path $RcptDir "inputs_root_hash.txt") $root

$std1 = Join-Path $RcptDir "01_hash_claim_stdout.log"
$err1 = Join-Path $RcptDir "01_hash_claim_stderr.log"
$r1 = RunChildCapture $PSExe $HashClaim @{ RepoRoot = $RepoRoot; ClaimJsonPath = $MinClaimJson } $std1 $err1
if($r1.ExitCode -ne 0){ Die ("SELFTEST_FAIL_HASH_CLAIM_EXIT: " + $r1.ExitCode + "`n" + $r1.Stderr) }
$gotClaim = ($r1.Stdout -replace "`r","").Trim()
$wantClaim = (ReadTextUtf8NoBom $MinClaimExp).Trim()
if($wantClaim -ne $gotClaim){ Die ("SELFTEST_FAIL_HASH_CLAIM_MISMATCH: want=" + $wantClaim + " got=" + $gotClaim) }

$std2 = Join-Path $RcptDir "02_hash_receipt_stdout.log"
$err2 = Join-Path $RcptDir "02_hash_receipt_stderr.log"
$r2 = RunChildCapture $PSExe $HashRcpt @{ RepoRoot = $RepoRoot; ReceiptJsonPath = $MinRcptJson } $std2 $err2
if($r2.ExitCode -ne 0){ Die ("SELFTEST_FAIL_HASH_RECEIPT_EXIT: " + $r2.ExitCode + "`n" + $r2.Stderr) }
$gotRcpt = ($r2.Stdout -replace "`r","").Trim()
$wantRcpt = (ReadTextUtf8NoBom $MinRcptExp).Trim()
if($wantRcpt -ne $gotRcpt){ Die ("SELFTEST_FAIL_HASH_RECEIPT_MISMATCH: want=" + $wantRcpt + " got=" + $gotRcpt) }

$std3 = Join-Path $RcptDir "03_run_vectors_stdout.log"
$err3 = Join-Path $RcptDir "03_run_vectors_stderr.log"
$r3 = RunChildCapture $PSExe $RunTV @{ RepoRoot = $RepoRoot } $std3 $err3
if($r3.ExitCode -ne 0){ Die ("SELFTEST_FAIL_RUN_VECTORS_EXIT: " + $r3.ExitCode + "`n" + $r3.Stderr) }
$runTvOut = ($r3.Stdout -replace "`r","").Trim()
if($runTvOut -notmatch "TEST_VECTORS_OK:"){ Die ("SELFTEST_FAIL_RUN_VECTORS_TOKEN_MISSING") }

$std4 = Join-Path $RcptDir "04_run_object_law_vectors_stdout.log"
$err4 = Join-Path $RcptDir "04_run_object_law_vectors_stderr.log"
$r4 = RunChildCapture $PSExe $RunObjectLaw @{ RepoRoot = $RepoRoot } $std4 $err4
if($r4.ExitCode -ne 0){ Die ("SELFTEST_FAIL_RUN_OBJECT_LAW_EXIT: " + $r4.ExitCode + "`n" + $r4.Stderr) }
$runObjectOut = ($r4.Stdout -replace "`r","").Trim()
if($runObjectOut -notmatch "OBJECT_LAW_VECTORS_OK: pass=6 fail=0"){ Die ("SELFTEST_FAIL_RUN_OBJECT_LAW_TOKEN_MISSING") }

$std5 = Join-Path $RcptDir "05_run_media_storage_vectors_stdout.log"
$err5 = Join-Path $RcptDir "05_run_media_storage_vectors_stderr.log"
$r5 = RunChildCapture $PSExe $RunMediaStorage @{ RepoRoot = $RepoRoot } $std5 $err5
if($r5.ExitCode -ne 0){ Die ("SELFTEST_FAIL_RUN_MEDIA_STORAGE_EXIT: " + $r5.ExitCode + "`n" + $r5.Stderr) }
$runMediaOut = ($r5.Stdout -replace "`r","").Trim()
if($runMediaOut -notmatch "MEDIA_STORAGE_VECTORS_OK: pass=7 fail=0"){ Die ("SELFTEST_FAIL_RUN_MEDIA_STORAGE_TOKEN_MISSING") }

$std6 = Join-Path $RcptDir "06_run_verifier_vectors_stdout.log"
$err6 = Join-Path $RcptDir "06_run_verifier_vectors_stderr.log"
$r6 = RunChildCapture $PSExe $RunVerifier @{ RepoRoot = $RepoRoot } $std6 $err6
if($r6.ExitCode -ne 0){ Die ("SELFTEST_FAIL_RUN_VERIFIER_EXIT: " + $r6.ExitCode + "`n" + $r6.Stderr) }
$runVerifierOut = ($r6.Stdout -replace "`r","").Trim()
if($runVerifierOut -notmatch "VERIFIER_VECTORS_OK: pass=10 fail=0"){ Die ("SELFTEST_FAIL_RUN_VERIFIER_TOKEN_MISSING") }

$std7 = Join-Path $RcptDir "07_run_local_pledge_vectors_stdout.log"
$err7 = Join-Path $RcptDir "07_run_local_pledge_vectors_stderr.log"
$r7 = RunChildCapture $PSExe $RunPledgeVectors @{ RepoRoot = $RepoRoot } $std7 $err7
if($r7.ExitCode -ne 0){ Die ("SELFTEST_FAIL_RUN_LOCAL_PLEDGE_VECTORS_EXIT: " + $r7.ExitCode + "`n" + $r7.Stderr) }
$runPledgeOut = ($r7.Stdout -replace "`r","").Trim()
if($runPledgeOut -notmatch "LOCAL_PLEDGE_VECTOR_OK: pass=5 fail=0"){ Die ("SELFTEST_FAIL_RUN_LOCAL_PLEDGE_TOKEN_MISSING") }

$json = '{"schema":"clp.selftest.result.v1","ok":true,"root_hash":"' + $root + '","claim_id":"' + $gotClaim + '","receipt_id":"' + $gotRcpt + '","object_law_vectors_ok":true,"media_storage_vectors_ok":true,"verifier_vectors_ok":true,"local_pledge_vectors_ok":true}'
WriteUtf8NoBomLf (Join-Path $RcptDir "result.json") $json

$files = @(
  "inputs_manifest.txt",
  "inputs_root_hash.txt",
  "01_hash_claim_stdout.log",
  "01_hash_claim_stderr.log",
  "02_hash_receipt_stdout.log",
  "02_hash_receipt_stderr.log",
  "03_run_vectors_stdout.log",
  "03_run_vectors_stderr.log",
  "04_run_object_law_vectors_stdout.log",
  "04_run_object_law_vectors_stderr.log",
  "05_run_media_storage_vectors_stdout.log",
  "05_run_media_storage_vectors_stderr.log",
  "06_run_verifier_vectors_stdout.log",
  "06_run_verifier_vectors_stderr.log",
  "07_run_local_pledge_vectors_stdout.log",
  "07_run_local_pledge_vectors_stderr.log",
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
