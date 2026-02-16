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

$ScriptsDir  = Join-Path $RepoRoot "scripts"
$TVDir       = Join-Path $RepoRoot "test_vectors"
$MinClaimDir = Join-Path $TVDir "minimal-claim"
$MinRcptDir  = Join-Path $TVDir "minimal-receipt"
EnsureDir $ScriptsDir; EnsureDir $TVDir; EnsureDir $MinClaimDir; EnsureDir $MinRcptDir

# ---------------------------------------------------------
# scripts/_lib_clp_v1.ps1
# ---------------------------------------------------------
$LibPath = Join-Path $ScriptsDir "_lib_clp_v1.ps1"
$T = New-Object System.Collections.Generic.List[string]
[void]$T.Add('$ErrorActionPreference="Stop"')
[void]$T.Add('Set-StrictMode -Version Latest')
[void]$T.Add('')
[void]$T.Add('function Die([string]$m){ throw $m }')
[void]$T.Add('')
[void]$T.Add('function _JsonEscape([string]$s){')
[void]$T.Add('  if($null -eq $s){ return "" }')
[void]$T.Add('  $sb = New-Object System.Text.StringBuilder')
[void]$T.Add('  $i=0')
[void]$T.Add('  while($i -lt $s.Length){')
[void]$T.Add('    $c = [int][char]$s[$i]')
[void]$T.Add('    if($c -eq 34){ [void]$sb.Append("\\\"") }')
[void]$T.Add('    elseif($c -eq 92){ [void]$sb.Append("\\\\") }')
[void]$T.Add('    elseif($c -eq 8){  [void]$sb.Append("\\b") }')
[void]$T.Add('    elseif($c -eq 12){ [void]$sb.Append("\\f") }')
[void]$T.Add('    elseif($c -eq 10){ [void]$sb.Append("\\n") }')
[void]$T.Add('    elseif($c -eq 13){ [void]$sb.Append("\\r") }')
[void]$T.Add('    elseif($c -eq 9){  [void]$sb.Append("\\t") }')
[void]$T.Add('    elseif($c -lt 32){ [void]$sb.Append(("\\u{0:x4}" -f $c)) }')
[void]$T.Add('    else{ [void]$sb.Append([char]$c) }')
[void]$T.Add('    $i++')
[void]$T.Add('  }')
[void]$T.Add('  return $sb.ToString()')
[void]$T.Add('}')
[void]$T.Add('')
[void]$T.Add('function _IsNumberLike($v){')
[void]$T.Add('  return ($v -is [byte] -or $v -is [sbyte] -or $v -is [int16] -or $v -is [uint16] -or')
[void]$T.Add('          $v -is [int32] -or $v -is [uint32] -or $v -is [int64] -or $v -is [uint64] -or')
[void]$T.Add('          $v -is [single] -or $v -is [double] -or $v -is [decimal])')
[void]$T.Add('}')
[void]$T.Add('')
[void]$T.Add('function _CanonNumber($v){')
[void]$T.Add('  $ci = [System.Globalization.CultureInfo]::InvariantCulture')
[void]$T.Add('  if($v -is [double] -or $v -is [single]){')
[void]$T.Add('    if([double]::IsNaN([double]$v) -or [double]::IsInfinity([double]$v)){ Die "CANON_JSON_INVALID_NUMBER: NaN/Infinity" }')
[void]$T.Add('    return ([double]$v).ToString("R",$ci)')
[void]$T.Add('  }')
[void]$T.Add('  if($v -is [decimal]){ return ([decimal]$v).ToString($ci) }')
[void]$T.Add('  return ([string]::Format($ci,"{0}",$v))')
[void]$T.Add('}')
[void]$T.Add('')
[void]$T.Add('function _CanonJsonValue($v){')
[void]$T.Add('  if($null -eq $v){ return "null" }')
[void]$T.Add('  if($v -is [bool]){ return ($(if($v){"true"}else{"false"})) }')
[void]$T.Add('  if(_IsNumberLike $v){ return (_CanonNumber $v) }')
[void]$T.Add('  if($v -is [string]){ return ("""" + (_JsonEscape $v) + """") }')
[void]$T.Add('')
[void]$T.Add('  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [System.Collections.IDictionary]) -and -not ($v -is [string])){')
[void]$T.Add('    $parts = New-Object System.Collections.Generic.List[string]')
[void]$T.Add('    foreach($it in $v){ [void]$parts.Add((_CanonJsonValue $it)) }')
[void]$T.Add('    return ("[" + (@($parts.ToArray()) -join ",") + "]")')
[void]$T.Add('  }')
[void]$T.Add('')
[void]$T.Add('  if($v -is [System.Collections.IDictionary]){')
[void]$T.Add('    $keys = New-Object System.Collections.Generic.List[string]')
[void]$T.Add('    foreach($k in $v.Keys){ [void]$keys.Add([string]$k) }')
[void]$T.Add('    $keys.Sort([StringComparer]::Ordinal)')
[void]$T.Add('    $pairs = New-Object System.Collections.Generic.List[string]')
[void]$T.Add('    foreach($k in $keys){ $val=$v[$k]; [void]$pairs.Add( (""""+(_JsonEscape $k)+""":"")+(_CanonJsonValue $val) ) }')
[void]$T.Add('    return ("{" + (@($pairs.ToArray()) -join ",") + "}")')
[void]$T.Add('  }')
[void]$T.Add('')
[void]$T.Add('  $ht=@{}')
[void]$T.Add('  $props=@($v.PSObject.Properties | ForEach-Object { $_.Name })')
[void]$T.Add('  $props=@($props | Sort-Object)')
[void]$T.Add('  foreach($pn in $props){ $ht[$pn] = $v.$pn }')
[void]$T.Add('  return (_CanonJsonValue $ht)')
[void]$T.Add('}')
[void]$T.Add('')
[void]$T.Add('function To-CanonJson([Parameter(Mandatory=$true)]$Obj){ return (_CanonJsonValue $Obj) }')
[void]$T.Add('function To-CanonJsonBytes([Parameter(Mandatory=$true)]$Obj){ $s=To-CanonJson $Obj; $enc=New-Object System.Text.UTF8Encoding($false); return $enc.GetBytes($s) }')
[void]$T.Add('')
[void]$T.Add('function Sha256HexBytes([byte[]]$Bytes){ if($null -eq $Bytes){ $Bytes=@() }; $sha=[System.Security.Cryptography.SHA256]::Create(); try{ $hash=$sha.ComputeHash([byte[]]$Bytes); $sb=New-Object System.Text.StringBuilder; $i=0; while($i -lt $hash.Length){ [void]$sb.Append($hash[$i].ToString("x2")); $i++ }; return $sb.ToString() } finally { $sha.Dispose() } }')
[void]$T.Add('')
[void]$T.Add('function ReadJson([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_JSON: " + $Path) }; $raw=[System.IO.File]::ReadAllText($Path,(New-Object System.Text.UTF8Encoding($false))); return ($raw | ConvertFrom-Json -Depth 50) }')
[void]$T.Add('function WriteCanonJson([string]$Path,$Obj){ $dir=Split-Path -Parent $Path; if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $json=To-CanonJson $Obj; $enc=New-Object System.Text.UTF8Encoding($false); $txt=($json+"`n").Replace("`r`n","`n").Replace("`r","`n"); [System.IO.File]::WriteAllText($Path,$txt,$enc) }')
[void]$T.Add('function _RemoveKey([hashtable]$ht,[string]$key){ if($ht.ContainsKey($key)){ [void]$ht.Remove($key) } }')
[void]$T.Add('function ClaimIdFromClaimObject($claimObj){ $ht=@{}; foreach($p in $claimObj.PSObject.Properties){ $ht[$p.Name]=$p.Value }; _RemoveKey $ht "signature"; return (Sha256HexBytes (To-CanonJsonBytes $ht)) }')
[void]$T.Add('function ReceiptIdFromReceiptObject($receiptObj){ $ht=@{}; foreach($p in $receiptObj.PSObject.Properties){ $ht[$p.Name]=$p.Value }; _RemoveKey $ht "signature"; return (Sha256HexBytes (To-CanonJsonBytes $ht)) }')
$libOut = (@($T.ToArray()) -join "`n") + "`n"
WriteUtf8NoBomLf $LibPath $libOut

# scripts/clp_hash_claim_v1.ps1
$HashClaimPath = Join-Path $ScriptsDir "clp_hash_claim_v1.ps1"
$hc = @()
$hc += 'param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$ClaimJsonPath)'
$hc += '$ErrorActionPreference="Stop"'
$hc += 'Set-StrictMode -Version Latest'
$hc += '. (Join-Path $RepoRoot "scripts\_lib_clp_v1.ps1")'
$hc += '$claim = ReadJson $ClaimJsonPath'
$hc += '$id = ClaimIdFromClaimObject $claim'
$hc += 'Write-Output $id'
WriteUtf8NoBomLf $HashClaimPath ((@($hc) -join "`n") + "`n")

# scripts/clp_hash_receipt_v1.ps1
$HashRcptPath = Join-Path $ScriptsDir "clp_hash_receipt_v1.ps1"
$hr = @()
$hr += 'param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$ReceiptJsonPath)'
$hr += '$ErrorActionPreference="Stop"'
$hr += 'Set-StrictMode -Version Latest'
$hr += '. (Join-Path $RepoRoot "scripts\_lib_clp_v1.ps1")'
$hr += '$rcpt = ReadJson $ReceiptJsonPath'
$hr += '$id = ReceiptIdFromReceiptObject $rcpt'
$hr += 'Write-Output $id'
WriteUtf8NoBomLf $HashRcptPath ((@($hr) -join "`n") + "`n")

# derive minimal-receipt from minimal-claim
$MinClaimJson = Join-Path $MinClaimDir "claim.json"
if(-not (Test-Path -LiteralPath $MinClaimJson -PathType Leaf)){ Die ("MISSING_MINIMAL_CLAIM_JSON: " + $MinClaimJson) }
. $LibPath
$claimObj = ReadJson $MinClaimJson
$claimId = ClaimIdFromClaimObject $claimObj
$ReceiptJson = Join-Path $MinRcptDir "receipt.json"
$ReceiptExp  = Join-Path $MinRcptDir "expected_receipt_id.txt"
$rcptHt = @{ for_claim=$claimId; receipt_type="test.witness.receipt.v1"; result=@{ ok=$true; reason="unit" }; timestamp="0" }
WriteCanonJson $ReceiptJson $rcptHt
$rcptObj = ReadJson $ReceiptJson
$rcptId  = ReceiptIdFromReceiptObject $rcptObj
WriteUtf8NoBomLf $ReceiptExp ($rcptId + "`n")

# scripts/clp_run_test_vectors_v1.ps1
$RunTVPath = Join-Path $ScriptsDir "clp_run_test_vectors_v1.ps1"
$tv = @()
$tv += 'param([Parameter(Mandatory=$true)][string]$RepoRoot)'
$tv += '$ErrorActionPreference="Stop"'
$tv += 'Set-StrictMode -Version Latest'
$tv += 'function Die([string]$m){ throw $m }'
$tv += 'function EnsureLeaf([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_FILE: " + $p) } }'
$tv += '. (Join-Path $RepoRoot "scripts\_lib_clp_v1.ps1")'
$tv += '$tvd = Join-Path $RepoRoot "test_vectors"'
$tv += '$claimPath = Join-Path $tvd "minimal-claim\claim.json"'
$tv += '$expClaim  = Join-Path $tvd "minimal-claim\expected_claim_id.txt"'
$tv += 'EnsureLeaf $claimPath; EnsureLeaf $expClaim'
$tv += '$claimObj = ReadJson $claimPath'
$tv += '$gotClaim = ClaimIdFromClaimObject $claimObj'
$tv += '$want = ([System.IO.File]::ReadAllText($expClaim,(New-Object System.Text.UTF8Encoding($false)))).Trim()'
$tv += 'if($want -ne $gotClaim){ Die ("TEST_VECTOR_FAIL: minimal-claim claim_id want=" + $want + " got=" + $gotClaim) }'
$tv += '$rcptPath = Join-Path $tvd "minimal-receipt\receipt.json"'
$tv += '$expRcpt  = Join-Path $tvd "minimal-receipt\expected_receipt_id.txt"'
$tv += 'EnsureLeaf $rcptPath; EnsureLeaf $expRcpt'
$tv += '$rcptObj = ReadJson $rcptPath'
$tv += '$gotRcpt = ReceiptIdFromReceiptObject $rcptObj'
$tv += '$wantR = ([System.IO.File]::ReadAllText($expRcpt,(New-Object System.Text.UTF8Encoding($false)))).Trim()'
$tv += 'if($wantR -ne $gotRcpt){ Die ("TEST_VECTOR_FAIL: minimal-receipt receipt_id want=" + $wantR + " got=" + $gotRcpt) }'
$tv += 'Write-Host ("TEST_VECTORS_OK: claim_id=" + $gotClaim + " receipt_id=" + $gotRcpt) -ForegroundColor Green'
WriteUtf8NoBomLf $RunTVPath ((@($tv) -join "`n") + "`n")

# parse-gate + run
ParseGate $LibPath; ParseGate $HashClaimPath; ParseGate $HashRcptPath; ParseGate $RunTVPath
& $RunTVPath -RepoRoot $RepoRoot
Write-Host ("CLP_REPAIR_OK: claim_id=" + $claimId + " receipt_id=" + $rcptId) -ForegroundColor Green
