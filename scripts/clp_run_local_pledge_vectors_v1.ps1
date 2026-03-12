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

function RunChild([string]$Script,[string[]]$Args){
  $PSExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
  $all = New-Object System.Collections.Generic.List[string]
  [void]$all.Add("-NoProfile")
  [void]$all.Add("-NonInteractive")
  [void]$all.Add("-ExecutionPolicy")
  [void]$all.Add("Bypass")
  [void]$all.Add("-File")
  [void]$all.Add($Script)
  foreach($a in @($Args)){ [void]$all.Add($a) }
  & $PSExe @(@($all.ToArray()))
  return $LASTEXITCODE
}

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

# positive_append_first_entry
$Case1 = Join-Path $WorkRoot "positive_append_first_entry"
EnsureDir $Case1
WriteUtf8NoBomLf (Join-Path $Case1 "claim.json") (Get-Content -LiteralPath $Claim1 -Raw)
$c = RunChild $AppendScript @("-RepoRoot",$Case1,"-ClaimJsonPath",(Join-Path $Case1 "claim.json"),"-Actor","unit","-Timestamp","2026-03-10T00:00:10Z")
if($c -ne 0){ Die "FAIL: positive_append_first_entry" }
Write-Host "PASS: positive_append_first_entry" -ForegroundColor Green

# positive_append_second_entry
$Case2 = Join-Path $WorkRoot "positive_append_second_entry"
EnsureDir $Case2
WriteUtf8NoBomLf (Join-Path $Case2 "claim1.json") (Get-Content -LiteralPath $Claim1 -Raw)
WriteUtf8NoBomLf (Join-Path $Case2 "claim2.json") (Get-Content -LiteralPath $Claim2 -Raw)
$c = RunChild $AppendScript @("-RepoRoot",$Case2,"-ClaimJsonPath",(Join-Path $Case2 "claim1.json"),"-Actor","unit","-Timestamp","2026-03-10T00:00:10Z")
if($c -ne 0){ Die "FAIL: positive_append_second_entry.step1" }
$c = RunChild $AppendScript @("-RepoRoot",$Case2,"-ClaimJsonPath",(Join-Path $Case2 "claim2.json"),"-Actor","unit","-Timestamp","2026-03-10T00:00:11Z")
if($c -ne 0){ Die "FAIL: positive_append_second_entry.step2" }
Write-Host "PASS: positive_append_second_entry" -ForegroundColor Green

# positive_verify_two_entry_chain
$Case3 = Join-Path $WorkRoot "positive_verify_two_entry_chain"
EnsureDir $Case3
WriteUtf8NoBomLf (Join-Path $Case3 "claim1.json") (Get-Content -LiteralPath $Claim1 -Raw)
WriteUtf8NoBomLf (Join-Path $Case3 "claim2.json") (Get-Content -LiteralPath $Claim2 -Raw)
$c = RunChild $AppendScript @("-RepoRoot",$Case3,"-ClaimJsonPath",(Join-Path $Case3 "claim1.json"),"-Actor","unit","-Timestamp","2026-03-10T00:00:10Z")
if($c -ne 0){ Die "FAIL: positive_verify_two_entry_chain.step1" }
$c = RunChild $AppendScript @("-RepoRoot",$Case3,"-ClaimJsonPath",(Join-Path $Case3 "claim2.json"),"-Actor","unit","-Timestamp","2026-03-10T00:00:11Z")
if($c -ne 0){ Die "FAIL: positive_verify_two_entry_chain.step2" }
$c = RunChild $VerifyScript @("-RepoRoot",$Case3)
if($c -ne 0){ Die "FAIL: positive_verify_two_entry_chain.verify" }
Write-Host "PASS: positive_verify_two_entry_chain" -ForegroundColor Green

# negative_previous_entry_hash_mismatch
$Case4 = Join-Path $WorkRoot "negative_previous_entry_hash_mismatch"
EnsureDir $Case4
WriteUtf8NoBomLf (Join-Path $Case4 "claim1.json") (Get-Content -LiteralPath $Claim1 -Raw)
WriteUtf8NoBomLf (Join-Path $Case4 "claim2.json") (Get-Content -LiteralPath $Claim2 -Raw)
$c = RunChild $AppendScript @("-RepoRoot",$Case4,"-ClaimJsonPath",(Join-Path $Case4 "claim1.json"),"-Actor","unit","-Timestamp","2026-03-10T00:00:10Z")
if($c -ne 0){ Die "FAIL: negative_previous_entry_hash_mismatch.step1" }
$c = RunChild $AppendScript @("-RepoRoot",$Case4,"-ClaimJsonPath",(Join-Path $Case4 "claim2.json"),"-Actor","unit","-Timestamp","2026-03-10T00:00:11Z")
if($c -ne 0){ Die "FAIL: negative_previous_entry_hash_mismatch.step2" }
$ledger4 = Join-Path $Case4 "proofs\local_pledge\claims.ndjson"
$lines4 = @((Get-Content -LiteralPath $ledger4) | Where-Object { $_ -ne "" })
$obj4 = $lines4[1] | ConvertFrom-Json
$obj4.previous_entry_hash = "BADHASH"
$lines4[1] = ($obj4 | ConvertTo-Json -Compress)
WriteUtf8NoBomLf $ledger4 ((@($lines4) -join "`n") + "`n")
$c = RunChild $VerifyScript @("-RepoRoot",$Case4)
if($c -eq 0){ Die "FAIL: negative_previous_entry_hash_mismatch.verify_expected_fail" }
Write-Host "PASS: negative_previous_entry_hash_mismatch" -ForegroundColor Green

# negative_entry_hash_mismatch
$Case5 = Join-Path $WorkRoot "negative_entry_hash_mismatch"
EnsureDir $Case5
WriteUtf8NoBomLf (Join-Path $Case5 "claim1.json") (Get-Content -LiteralPath $Claim1 -Raw)
$c = RunChild $AppendScript @("-RepoRoot",$Case5,"-ClaimJsonPath",(Join-Path $Case5 "claim1.json"),"-Actor","unit","-Timestamp","2026-03-10T00:00:10Z")
if($c -ne 0){ Die "FAIL: negative_entry_hash_mismatch.step1" }
$ledger5 = Join-Path $Case5 "proofs\local_pledge\claims.ndjson"
$lines5 = @((Get-Content -LiteralPath $ledger5) | Where-Object { $_ -ne "" })
$obj5 = $lines5[0] | ConvertFrom-Json
$obj5.entry_hash = "BADHASH"
$lines5[0] = ($obj5 | ConvertTo-Json -Compress)
WriteUtf8NoBomLf $ledger5 ((@($lines5) -join "`n") + "`n")
$c = RunChild $VerifyScript @("-RepoRoot",$Case5)
if($c -eq 0){ Die "FAIL: negative_entry_hash_mismatch.verify_expected_fail" }
Write-Host "PASS: negative_entry_hash_mismatch" -ForegroundColor Green

# negative_claim_id_mismatch
$Case6 = Join-Path $WorkRoot "negative_claim_id_mismatch"
EnsureDir $Case6
WriteUtf8NoBomLf (Join-Path $Case6 "claim1.json") (Get-Content -LiteralPath $Claim1 -Raw)
$c = RunChild $AppendScript @("-RepoRoot",$Case6,"-ClaimJsonPath",(Join-Path $Case6 "claim1.json"),"-Actor","unit","-Timestamp","2026-03-10T00:00:10Z")
if($c -ne 0){ Die "FAIL: negative_claim_id_mismatch.step1" }
$ledger6 = Join-Path $Case6 "proofs\local_pledge\claims.ndjson"
$lines6 = @((Get-Content -LiteralPath $ledger6) | Where-Object { $_ -ne "" })
$obj6 = $lines6[0] | ConvertFrom-Json
$obj6.claim_id = "BADCLAIMID"
$lines6[0] = ($obj6 | ConvertTo-Json -Compress)
WriteUtf8NoBomLf $ledger6 ((@($lines6) -join "`n") + "`n")
$c = RunChild $VerifyScript @("-RepoRoot",$Case6)
if($c -eq 0){ Die "FAIL: negative_claim_id_mismatch.verify_expected_fail" }
Write-Host "PASS: negative_claim_id_mismatch" -ForegroundColor Green

Write-Host "LOCAL_PLEDGE_VECTOR_OK: pass=6 fail=0" -ForegroundColor Green