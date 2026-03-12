param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$RepoRoot)
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

function ReadUtf8NoBom([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  return [System.IO.File]::ReadAllText($Path,(New-Object System.Text.UTF8Encoding($false)))
}

function CopyTextFile([string]$Src,[string]$Dst){
  WriteUtf8NoBomLf $Dst (ReadUtf8NoBom $Src)
}

function RunAppendDirect([string]$CaseRoot,[string]$ClaimJsonPath,[string]$Actor,[string]$Timestamp,[string]$Label){
  $PSExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
  $Script = Join-Path $RepoRoot "scripts\clp_append_local_pledge_v1.ps1"
  $stdout = Join-Path $CaseRoot ($Label + "_stdout.log")
  $stderr = Join-Path $CaseRoot ($Label + "_stderr.log")
  if(Test-Path -LiteralPath $stdout -PathType Leaf){ Remove-Item -LiteralPath $stdout -Force -ErrorAction SilentlyContinue }
  if(Test-Path -LiteralPath $stderr -PathType Leaf){ Remove-Item -LiteralPath $stderr -Force -ErrorAction SilentlyContinue }
  & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Script -RepoRoot $CaseRoot -ClaimJsonPath $ClaimJsonPath -Actor $Actor -Timestamp $Timestamp 1> $stdout 2> $stderr
  $code = $LASTEXITCODE
  $out = ""
  $err = ""
  if(Test-Path -LiteralPath $stdout -PathType Leaf){ $out = ReadUtf8NoBom $stdout }
  if(Test-Path -LiteralPath $stderr -PathType Leaf){ $err = ReadUtf8NoBom $stderr }
  if($code -ne 0){ Die ("FAIL: " + $Label + "`nSTDERR:`n" + $err + "`nSTDOUT:`n" + $out) }
}

function RunVerifyDirectPass([string]$CaseRoot,[string]$Label){
  $PSExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
  $Script = Join-Path $RepoRoot "scripts\clp_verify_local_pledge_v1.ps1"
  $stdout = Join-Path $CaseRoot ($Label + "_stdout.log")
  $stderr = Join-Path $CaseRoot ($Label + "_stderr.log")
  if(Test-Path -LiteralPath $stdout -PathType Leaf){ Remove-Item -LiteralPath $stdout -Force -ErrorAction SilentlyContinue }
  if(Test-Path -LiteralPath $stderr -PathType Leaf){ Remove-Item -LiteralPath $stderr -Force -ErrorAction SilentlyContinue }
  & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Script -RepoRoot $CaseRoot 1> $stdout 2> $stderr
  $code = $LASTEXITCODE
  $out = ""
  $err = ""
  if(Test-Path -LiteralPath $stdout -PathType Leaf){ $out = ReadUtf8NoBom $stdout }
  if(Test-Path -LiteralPath $stderr -PathType Leaf){ $err = ReadUtf8NoBom $stderr }
  if($code -ne 0){ Die ("FAIL: " + $Label + "`nSTDERR:`n" + $err + "`nSTDOUT:`n" + $out) }
}

function RunVerifyDirectFail([string]$CaseRoot,[string]$Label){
  $PSExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
  $Script = Join-Path $RepoRoot "scripts\clp_verify_local_pledge_v1.ps1"
  $stdout = Join-Path $CaseRoot ($Label + "_stdout.log")
  $stderr = Join-Path $CaseRoot ($Label + "_stderr.log")
  if(Test-Path -LiteralPath $stdout -PathType Leaf){ Remove-Item -LiteralPath $stdout -Force -ErrorAction SilentlyContinue }
  if(Test-Path -LiteralPath $stderr -PathType Leaf){ Remove-Item -LiteralPath $stderr -Force -ErrorAction SilentlyContinue }
  & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Script -RepoRoot $CaseRoot 1> $stdout 2> $stderr
  $code = $LASTEXITCODE
  if($code -eq 0){ Die ("FAIL: " + $Label + "_expected_fail_but_passed") }
}

$AppendScript = Join-Path $RepoRoot "scripts\clp_append_local_pledge_v1.ps1"
$VerifyScript = Join-Path $RepoRoot "scripts\clp_verify_local_pledge_v1.ps1"
$Claim1 = Join-Path $RepoRoot "test_vectors\minimal-claim\claim.json"
$Claim2 = Join-Path $RepoRoot "test_vectors\local_pledge\claim2.json"
ParseGateFile $AppendScript
ParseGateFile $VerifyScript
EnsureDir (Join-Path $RepoRoot "test_vectors\local_pledge")
WriteUtf8NoBomLf $Claim2 '{"claim_type":"core.commit.v1","payload":{"mode":"inline_json","value":{"x":"2"}},"producer":"unit","schema":"clp.claim.v1","timestamp":"2026-03-10T00:00:01Z"}'

$WorkRoot = Join-Path $RepoRoot "proofs\local_pledge_vector_work"
if(Test-Path -LiteralPath $WorkRoot -PathType Container){ Remove-Item -LiteralPath $WorkRoot -Recurse -Force -ErrorAction Stop -Confirm:$false }
EnsureDir $WorkRoot

$Case1 = Join-Path $WorkRoot "positive_append_first_entry"
EnsureDir $Case1
$Case1Claim = Join-Path $Case1 "claim.json"
CopyTextFile $Claim1 $Case1Claim
RunAppendDirect $Case1 $Case1Claim "unit" "2026-03-10T00:00:10Z" "positive_append_first_entry"
Write-Host "PASS: positive_append_first_entry" -ForegroundColor Green

$Case2 = Join-Path $WorkRoot "positive_append_second_entry"
EnsureDir $Case2
$Case2Claim1 = Join-Path $Case2 "claim1.json"
$Case2Claim2 = Join-Path $Case2 "claim2.json"
CopyTextFile $Claim1 $Case2Claim1
CopyTextFile $Claim2 $Case2Claim2
RunAppendDirect $Case2 $Case2Claim1 "unit" "2026-03-10T00:00:10Z" "positive_append_second_entry_step1"
RunAppendDirect $Case2 $Case2Claim2 "unit" "2026-03-10T00:00:11Z" "positive_append_second_entry_step2"
Write-Host "PASS: positive_append_second_entry" -ForegroundColor Green

$Case3 = Join-Path $WorkRoot "positive_verify_two_entry_chain"
EnsureDir $Case3
$Case3Claim1 = Join-Path $Case3 "claim1.json"
$Case3Claim2 = Join-Path $Case3 "claim2.json"
CopyTextFile $Claim1 $Case3Claim1
CopyTextFile $Claim2 $Case3Claim2
RunAppendDirect $Case3 $Case3Claim1 "unit" "2026-03-10T00:00:10Z" "positive_verify_two_entry_chain_step1"
RunAppendDirect $Case3 $Case3Claim2 "unit" "2026-03-10T00:00:11Z" "positive_verify_two_entry_chain_step2"
RunVerifyDirectPass $Case3 "positive_verify_two_entry_chain"
Write-Host "PASS: positive_verify_two_entry_chain" -ForegroundColor Green

$Case4 = Join-Path $WorkRoot "negative_previous_entry_hash_mismatch"
EnsureDir $Case4
$Case4Claim1 = Join-Path $Case4 "claim1.json"
$Case4Claim2 = Join-Path $Case4 "claim2.json"
CopyTextFile $Claim1 $Case4Claim1
CopyTextFile $Claim2 $Case4Claim2
RunAppendDirect $Case4 $Case4Claim1 "unit" "2026-03-10T00:00:10Z" "negative_previous_entry_hash_mismatch_step1"
RunAppendDirect $Case4 $Case4Claim2 "unit" "2026-03-10T00:00:11Z" "negative_previous_entry_hash_mismatch_step2"
$Ledger4 = Join-Path $Case4 "proofs\local_pledge\claims.ndjson"
$Lines4 = @((Get-Content -LiteralPath $Ledger4) | Where-Object { $_ -ne "" })
$Obj4 = $Lines4[1] | ConvertFrom-Json
$Obj4.previous_entry_hash = "BADHASH"
$Lines4[1] = ($Obj4 | ConvertTo-Json -Compress)
WriteUtf8NoBomLf $Ledger4 ((@($Lines4) -join "`n") + "`n")
RunVerifyDirectFail $Case4 "negative_previous_entry_hash_mismatch"
Write-Host "PASS: negative_previous_entry_hash_mismatch" -ForegroundColor Green

$Case5 = Join-Path $WorkRoot "negative_entry_hash_mismatch"
EnsureDir $Case5
$Case5Claim = Join-Path $Case5 "claim.json"
CopyTextFile $Claim1 $Case5Claim
RunAppendDirect $Case5 $Case5Claim "unit" "2026-03-10T00:00:10Z" "negative_entry_hash_mismatch_step1"
$Ledger5 = Join-Path $Case5 "proofs\local_pledge\claims.ndjson"
$Lines5 = @((Get-Content -LiteralPath $Ledger5) | Where-Object { $_ -ne "" })
$Obj5 = $Lines5[0] | ConvertFrom-Json
$Obj5.entry_hash = "BADHASH"
$Lines5[0] = ($Obj5 | ConvertTo-Json -Compress)
WriteUtf8NoBomLf $Ledger5 ((@($Lines5) -join "`n") + "`n")
RunVerifyDirectFail $Case5 "negative_entry_hash_mismatch"
Write-Host "PASS: negative_entry_hash_mismatch" -ForegroundColor Green

Write-Host "LOCAL_PLEDGE_VECTOR_OK: pass=5 fail=0" -ForegroundColor Green
