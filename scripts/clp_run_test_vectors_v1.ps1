param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function EnsureLeaf([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_FILE: " + $p) } }

. (Join-Path $RepoRoot "scripts\_lib_clp_v1.ps1")
$tvd = Join-Path $RepoRoot "test_vectors"

# Minimal claim
$claimPath = Join-Path $tvd "minimal-claim\claim.json"
$expClaim  = Join-Path $tvd "minimal-claim\expected_claim_id.txt"
EnsureLeaf $claimPath
EnsureLeaf $expClaim
$claimObj = ReadJson $claimPath
$gotClaim = ClaimIdFromClaimObject $claimObj
$want = ([System.IO.File]::ReadAllText($expClaim,(New-Object System.Text.UTF8Encoding($false)))).Trim()
if($want -ne $gotClaim){ Die ("TEST_VECTOR_FAIL: minimal-claim claim_id want=" + $want + " got=" + $gotClaim) }

# Minimal receipt
$rcptPath = Join-Path $tvd "minimal-receipt\receipt.json"
$expRcpt  = Join-Path $tvd "minimal-receipt\expected_receipt_id.txt"
EnsureLeaf $rcptPath
EnsureLeaf $expRcpt
$rcptObj = ReadJson $rcptPath
$gotRcpt = ReceiptIdFromReceiptObject $rcptObj
$wantR = ([System.IO.File]::ReadAllText($expRcpt,(New-Object System.Text.UTF8Encoding($false)))).Trim()
if($wantR -ne $gotRcpt){ Die ("TEST_VECTOR_FAIL: minimal-receipt receipt_id want=" + $wantR + " got=" + $gotRcpt) }

Write-Host ("TEST_VECTORS_OK: claim_id=" + $gotClaim + " receipt_id=" + $gotRcpt) -ForegroundColor Green
