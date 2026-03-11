param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ EnsureDir $dir }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function ParseGate([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("PARSE_GATE_MISSING: " + $Path) }
  $tokens=$null; $errs=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errs)
  if($errs -and $errs.Count -gt 0){
    $msg = ($errs | ForEach-Object { $_.ToString() }) -join "`n"
    Die ("PARSE_GATE_FAIL: " + $Path + "`n" + $msg)
  }
}

$ScriptsDir = Join-Path $RepoRoot "scripts"
$LibPath    = Join-Path $ScriptsDir "_lib_clp_v1.ps1"
$RunTVPath  = Join-Path $ScriptsDir "clp_run_test_vectors_v1.ps1"
EnsureDir $ScriptsDir
if(-not (Test-Path -LiteralPath $LibPath -PathType Leaf)){ Die ("MISSING_LIB: " + $LibPath) }

# Write scripts/clp_run_test_vectors_v1.ps1 (known-good) WITHOUT using interactive-scope vars
$tv = New-Object System.Collections.Generic.List[string]
[void]$tv.Add('param([Parameter(Mandatory=$true)][string]$RepoRoot)')
[void]$tv.Add('$ErrorActionPreference="Stop"')
[void]$tv.Add('Set-StrictMode -Version Latest')
[void]$tv.Add('')
[void]$tv.Add('function Die([string]$m){ throw $m }')
[void]$tv.Add('function EnsureLeaf([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_FILE: " + $p) } }')
[void]$tv.Add('')
[void]$tv.Add('. (Join-Path $RepoRoot "scripts\_lib_clp_v1.ps1")')
[void]$tv.Add('$tvd = Join-Path $RepoRoot "test_vectors"')
[void]$tv.Add('')
[void]$tv.Add('# Minimal claim')
[void]$tv.Add('$claimPath = Join-Path $tvd "minimal-claim\claim.json"')
[void]$tv.Add('$expClaim  = Join-Path $tvd "minimal-claim\expected_claim_id.txt"')
[void]$tv.Add('EnsureLeaf $claimPath')
[void]$tv.Add('EnsureLeaf $expClaim')
[void]$tv.Add('$claimObj = ReadJson $claimPath')
[void]$tv.Add('$gotClaim = ClaimIdFromClaimObject $claimObj')
[void]$tv.Add('$want = ([System.IO.File]::ReadAllText($expClaim,(New-Object System.Text.UTF8Encoding($false)))).Trim()')
[void]$tv.Add('if($want -ne $gotClaim){ Die ("TEST_VECTOR_FAIL: minimal-claim claim_id want=" + $want + " got=" + $gotClaim) }')
[void]$tv.Add('')
[void]$tv.Add('# Minimal receipt')
[void]$tv.Add('$rcptPath = Join-Path $tvd "minimal-receipt\receipt.json"')
[void]$tv.Add('$expRcpt  = Join-Path $tvd "minimal-receipt\expected_receipt_id.txt"')
[void]$tv.Add('EnsureLeaf $rcptPath')
[void]$tv.Add('EnsureLeaf $expRcpt')
[void]$tv.Add('$rcptObj = ReadJson $rcptPath')
[void]$tv.Add('$gotRcpt = ReceiptIdFromReceiptObject $rcptObj')
[void]$tv.Add('$wantR = ([System.IO.File]::ReadAllText($expRcpt,(New-Object System.Text.UTF8Encoding($false)))).Trim()')
[void]$tv.Add('if($wantR -ne $gotRcpt){ Die ("TEST_VECTOR_FAIL: minimal-receipt receipt_id want=" + $wantR + " got=" + $gotRcpt) }')
[void]$tv.Add('')
[void]$tv.Add('Write-Host ("TEST_VECTORS_OK: claim_id=" + $gotClaim + " receipt_id=" + $gotRcpt) -ForegroundColor Green')

WriteUtf8NoBomLf $RunTVPath ((@($tv.ToArray()) -join "`n") + "`n")
ParseGate $RunTVPath
& $RunTVPath -RepoRoot $RepoRoot
