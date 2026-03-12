param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$RepoRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ EnsureDir $dir }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [System.IO.File]::WriteAllText($Path,$t,(New-Object System.Text.UTF8Encoding($false)))
}

function QuoteArg([string]$s){
  if($null -eq $s){ return '""' }
  if($s -match '[\s"`]'){
    return '"' + ($s -replace '"','\"') + '"'
  }
  return $s
}

function RunChildCapture(
  [string]$PSExe,
  [string]$ScriptPath,
  [string[]]$Args,
  [string]$StdOutPath,
  [string]$StdErrPath
){
  if(-not (Test-Path -LiteralPath $PSExe -PathType Leaf)){ Die ("MISSING_POWERSHELL_EXE: " + $PSExe) }
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){ Die ("MISSING_SCRIPT: " + $ScriptPath) }
  $all = New-Object System.Collections.Generic.List[string]
  [void]$all.Add("-NoProfile")
  [void]$all.Add("-NonInteractive")
  [void]$all.Add("-ExecutionPolicy")
  [void]$all.Add("Bypass")
  [void]$all.Add("-File")
  [void]$all.Add($ScriptPath)
  foreach($a in @($Args)){ [void]$all.Add([string]$a) }
  $argString = (@($all.ToArray()) | ForEach-Object { QuoteArg $_ }) -join " "
  $proc = Start-Process -FilePath $PSExe -ArgumentList $argString -RedirectStandardOutput $StdOutPath -RedirectStandardError $StdErrPath -NoNewWindow -Wait -PassThru
  $stdout = ""
  $stderr = ""
  if(Test-Path -LiteralPath $StdOutPath -PathType Leaf){
    $stdout = [System.IO.File]::ReadAllText($StdOutPath,(New-Object System.Text.UTF8Encoding($false)))
  }
  if(Test-Path -LiteralPath $StdErrPath -PathType Leaf){
    $stderr = [System.IO.File]::ReadAllText($StdErrPath,(New-Object System.Text.UTF8Encoding($false)))
  }
  return @{ ExitCode = [int]$proc.ExitCode; Stdout = $stdout; Stderr = $stderr }
}

$PSExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$AppendScript = Join-Path $RepoRoot "scripts\clp_append_local_pledge_v1.ps1"
$VerifyScript = Join-Path $RepoRoot "scripts\clp_verify_local_pledge_v1.ps1"

$TvBase = Join-Path $RepoRoot "test_vectors\local_pledge"
EnsureDir $TvBase

$Claim1 = Join-Path $TvBase "claim1.json"
$Claim2 = Join-Path $TvBase "claim2.json"

WriteUtf8NoBomLf $Claim1 '{"claim_type":"core.commit.v1","payload":{"mode":"inline_json","value":{"x":"1"}},"producer":"unit","schema":"clp.claim.v1","timestamp":"2026-03-10T00:00:00Z"}'
WriteUtf8NoBomLf $Claim2 '{"claim_type":"core.commit.v1","payload":{"mode":"inline_json","value":{"x":"2"}},"producer":"unit","schema":"clp.claim.v1","timestamp":"2026-03-10T00:00:01Z"}'

$WorkRoot = Join-Path $RepoRoot "proofs\local_pledge_vector_work"
if(Test-Path -LiteralPath $WorkRoot){
  Remove-Item -LiteralPath $WorkRoot -Recurse -Force -ErrorAction Stop -Confirm:$false
}
EnsureDir $WorkRoot

function RunAppendCase([string]$CaseRoot,[string]$ClaimFileName,[string]$Timestamp,[string]$Label){
  $stdout = Join-Path $CaseRoot ($Label + "_stdout.log")
  $stderr = Join-Path $CaseRoot ($Label + "_stderr.log")
  $claimPath = Join-Path $CaseRoot $ClaimFileName
  $r = RunChildCapture $PSExe $AppendScript @(
    "-RepoRoot", $CaseRoot,
    "-ClaimJsonPath", $claimPath,
    "-Actor", "unit",
    "-Timestamp", $Timestamp
  ) $stdout $stderr
  if($r.ExitCode -ne 0){
    Die ("FAIL: " + $Label + "`nSTDERR:`n" + $r.Stderr + "`nSTDOUT:`n" + $r.Stdout)
  }
}

function RunVerifyCase([string]$CaseRoot,[string]$Label,[bool]$ExpectSuccess){
  $stdout = Join-Path $CaseRoot ($Label + "_stdout.log")
  $stderr = Join-Path $CaseRoot ($Label + "_stderr.log")
  $r = RunChildCapture $PSExe $VerifyScript @(
    "-RepoRoot", $CaseRoot
  ) $stdout $stderr
  if($ExpectSuccess){
    if($r.ExitCode -ne 0){ Die ("FAIL: " + $Label + "`nSTDERR:`n" + $r.Stderr + "`nSTDOUT:`n" + $r.Stdout) }
  } else {
    if($r.ExitCode -eq 0){ Die ("FAIL: " + $Label + "_expected_fail_but_passed") }
  }
}

$Case1 = Join-Path $WorkRoot "positive_append_first_entry"
EnsureDir $Case1
WriteUtf8NoBomLf (Join-Path $Case1 "claim.json") ([System.IO.File]::ReadAllText($Claim1,(New-Object System.Text.UTF8Encoding($false))))
RunAppendCase $Case1 "claim.json" "2026-03-10T00:00:10Z" "positive_append_first_entry"
Write-Host "PASS: positive_append_first_entry" -ForegroundColor Green

$Case2 = Join-Path $WorkRoot "positive_append_second_entry"
EnsureDir $Case2
WriteUtf8NoBomLf (Join-Path $Case2 "claim1.json") ([System.IO.File]::ReadAllText($Claim1,(New-Object System.Text.UTF8Encoding($false))))
WriteUtf8NoBomLf (Join-Path $Case2 "claim2.json") ([System.IO.File]::ReadAllText($Claim2,(New-Object System.Text.UTF8Encoding($false))))
RunAppendCase $Case2 "claim1.json" "2026-03-10T00:00:10Z" "positive_append_second_entry_step1"
RunAppendCase $Case2 "claim2.json" "2026-03-10T00:00:11Z" "positive_append_second_entry_step2"
Write-Host "PASS: positive_append_second_entry" -ForegroundColor Green

$Case3 = Join-Path $WorkRoot "positive_verify_two_entry_chain"
EnsureDir $Case3
WriteUtf8NoBomLf (Join-Path $Case3 "claim1.json") ([System.IO.File]::ReadAllText($Claim1,(New-Object System.Text.UTF8Encoding($false))))
WriteUtf8NoBomLf (Join-Path $Case3 "claim2.json") ([System.IO.File]::ReadAllText($Claim2,(New-Object System.Text.UTF8Encoding($false))))
RunAppendCase $Case3 "claim1.json" "2026-03-10T00:00:10Z" "positive_verify_two_entry_chain_step1"
RunAppendCase $Case3 "claim2.json" "2026-03-10T00:00:11Z" "positive_verify_two_entry_chain_step2"
RunVerifyCase $Case3 "positive_verify_two_entry_chain_verify" $true
Write-Host "PASS: positive_verify_two_entry_chain" -ForegroundColor Green

$Case4 = Join-Path $WorkRoot "negative_previous_entry_hash_mismatch"
EnsureDir $Case4
WriteUtf8NoBomLf (Join-Path $Case4 "claim1.json") ([System.IO.File]::ReadAllText($Claim1,(New-Object System.Text.UTF8Encoding($false))))
WriteUtf8NoBomLf (Join-Path $Case4 "claim2.json") ([System.IO.File]::ReadAllText($Claim2,(New-Object System.Text.UTF8Encoding($false))))
RunAppendCase $Case4 "claim1.json" "2026-03-10T00:00:10Z" "negative_previous_entry_hash_mismatch_step1"
RunAppendCase $Case4 "claim2.json" "2026-03-10T00:00:11Z" "negative_previous_entry_hash_mismatch_step2"
$ledger4 = Join-Path $Case4 "proofs\local_pledge\claims.ndjson"
$lines4 = @((Get-Content -LiteralPath $ledger4) | Where-Object { $_ -ne "" })
$obj4 = $lines4[1] | ConvertFrom-Json
$obj4.previous_entry_hash = "BADHASH"
$lines4[1] = ($obj4 | ConvertTo-Json -Compress)
WriteUtf8NoBomLf $ledger4 ((@($lines4) -join "`n") + "`n")
RunVerifyCase $Case4 "negative_previous_entry_hash_mismatch_verify" $false
Write-Host "PASS: negative_previous_entry_hash_mismatch" -ForegroundColor Green

$Case5 = Join-Path $WorkRoot "negative_entry_hash_mismatch"
EnsureDir $Case5
WriteUtf8NoBomLf (Join-Path $Case5 "claim1.json") ([System.IO.File]::ReadAllText($Claim1,(New-Object System.Text.UTF8Encoding($false))))
RunAppendCase $Case5 "claim1.json" "2026-03-10T00:00:10Z" "negative_entry_hash_mismatch_step1"
$ledger5 = Join-Path $Case5 "proofs\local_pledge\claims.ndjson"
$lines5 = @((Get-Content -LiteralPath $ledger5) | Where-Object { $_ -ne "" })
$obj5 = $lines5[0] | ConvertFrom-Json
$obj5.entry_hash = "BADHASH"
$lines5[0] = ($obj5 | ConvertTo-Json -Compress)
WriteUtf8NoBomLf $ledger5 ((@($lines5) -join "`n") + "`n")
RunVerifyCase $Case5 "negative_entry_hash_mismatch_verify" $false
Write-Host "PASS: negative_entry_hash_mismatch" -ForegroundColor Green

Write-Host "LOCAL_PLEDGE_VECTOR_OK: pass=5 fail=0" -ForegroundColor Green
