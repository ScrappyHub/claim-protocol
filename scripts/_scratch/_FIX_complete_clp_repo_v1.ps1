param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ EnsureDir $dir }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Parse-GateFile([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("PARSE_GATE_MISSING: " + $Path) }
  $tokens=$null; $errs=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errs)
  if($errs -and $errs.Count -gt 0){
    $msg = ($errs | ForEach-Object { $_.ToString() }) -join "`n"
    Die ("PARSE_GATE_FAIL: " + $Path + "`n" + $msg)
  }
}

# ---- CLP canonical JSON + hashing (ref lib) ----
function _JsonEscape([string]$s){
  if($null -eq $s){ return "" }
  $sb = New-Object System.Text.StringBuilder
  $i=0
  while($i -lt $s.Length){
    $c=[int][char]$s[$i]
    if($c -eq 34){ [void]$sb.Append('\\"') }
    elseif($c -eq 92){ [void]$sb.Append('\\\\') }
    elseif($c -eq 8){ [void]$sb.Append('\\b') }
    elseif($c -eq 12){ [void]$sb.Append('\\f') }
    elseif($c -eq 10){ [void]$sb.Append('\\n') }
    elseif($c -eq 13){ [void]$sb.Append('\\r') }
    elseif($c -eq 9){ [void]$sb.Append('\\t') }
    elseif($c -lt 32){ [void]$sb.Append(("\\u{0:x4}" -f $c)) }
    else{ [void]$sb.Append([char]$c) }
    $i++
  }
  return $sb.ToString()
}
function _IsNumberLike($v){
  return ($v -is [byte] -or $v -is [sbyte] -or $v -is [int16] -or $v -is [uint16] -or
          $v -is [int32] -or $v -is [uint32] -or $v -is [int64] -or $v -is [uint64] -or
          $v -is [single] -or $v -is [double] -or $v -is [decimal])
}
function _CanonNumber($v){
  $ci=[System.Globalization.CultureInfo]::InvariantCulture
  if($v -is [double] -or $v -is [single]){
    if([double]::IsNaN([double]$v) -or [double]::IsInfinity([double]$v)){ Die "CANON_JSON_INVALID_NUMBER: NaN/Infinity not allowed" }
    return ([double]$v).ToString("R",$ci)
  }
  if($v -is [decimal]){ return ([decimal]$v).ToString($ci) }
  return ([string]::Format($ci,"{0}",$v))
}
function _CanonJsonValue($v){
  if($null -eq $v){ return "null" }
  if($v -is [bool]){ return ($(if($v){"true"}else{"false"})) }
  if(_IsNumberLike $v){ return (_CanonNumber $v) }
  if($v -is [string]){ return ('"' + (_JsonEscape $v) + '"') }
  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [System.Collections.IDictionary]) -and -not ($v -is [string])){
    $parts = New-Object System.Collections.Generic.List[string]
    foreach($it in $v){ [void]$parts.Add((_CanonJsonValue $it)) }
    return ("[" + (@($parts.ToArray()) -join ",") + "]")
  }
  if($v -is [System.Collections.IDictionary]){
    $keys = New-Object System.Collections.Generic.List[string]
    foreach($k in $v.Keys){ [void]$keys.Add([string]$k) }
    $keys.Sort([StringComparer]::Ordinal)
    $pairs = New-Object System.Collections.Generic.List[string]
    foreach($k in $keys){ [void]$pairs.Add(('"'+(_JsonEscape $k)+'":'+(_CanonJsonValue $v[$k]))) }
    return ("{" + (@($pairs.ToArray()) -join ",") + "}")
  }
  $ht=@{}
  $props=@($v.PSObject.Properties | ForEach-Object { $_.Name })
  $props=@($props | Sort-Object)
  foreach($pn in $props){ $ht[$pn]=$v.$pn }
  return (_CanonJsonValue $ht)
}
function To-CanonJson($Obj){ return (_CanonJsonValue $Obj) }
function To-CanonJsonBytes($Obj){ $enc=New-Object System.Text.UTF8Encoding($false); return $enc.GetBytes((To-CanonJson $Obj)) }
function Sha256HexBytes([byte[]]$Bytes){
  if($null -eq $Bytes){ $Bytes=@() }
  $sha=[System.Security.Cryptography.SHA256]::Create()
  try{
    $h=$sha.ComputeHash([byte[]]$Bytes)
    $sb=New-Object System.Text.StringBuilder
    $i=0
    while($i -lt $h.Length){ [void]$sb.Append($h[$i].ToString("x2")); $i++ }
    return $sb.ToString()
  } finally { $sha.Dispose() }
}
function ReadJson([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_JSON: " + $Path) }
  $raw=[System.IO.File]::ReadAllText($Path,(New-Object System.Text.UTF8Encoding($false)))
  return ($raw | ConvertFrom-Json -Depth 50)
}
function WriteCanonJson([string]$Path,$Obj){ Write-Utf8NoBomLf $Path ((To-CanonJson $Obj) + "`n") }
function _RemoveKey([hashtable]$ht,[string]$key){ if($ht.ContainsKey($key)){ [void]$ht.Remove($key) } }
function ClaimIdFromClaimObject($claimObj){ $ht=@{}; foreach($p in $claimObj.PSObject.Properties){ $ht[$p.Name]=$p.Value }; _RemoveKey $ht "signature"; return (Sha256HexBytes (To-CanonJsonBytes $ht)) }
function ReceiptIdFromReceiptObject($receiptObj){ $ht=@{}; foreach($p in $receiptObj.PSObject.Properties){ $ht[$p.Name]=$p.Value }; _RemoveKey $ht "signature"; return (Sha256HexBytes (To-CanonJsonBytes $ht)) }

# ---- Paths ----
$LawsDir    = Join-Path $RepoRoot "laws"
$SchemasDir = Join-Path $RepoRoot "schemas"
$TVDir      = Join-Path $RepoRoot "test_vectors"
$ScriptsDir = Join-Path $RepoRoot "scripts"
EnsureDir $LawsDir; EnsureDir $SchemasDir; EnsureDir $TVDir; EnsureDir $ScriptsDir
EnsureDir (Join-Path $TVDir "minimal-receipt")

# ---- Add missing law files ----
$p = Join-Path $LawsDir "receipt-identity.md"
if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
  Write-Utf8NoBomLf $p (("Receipt identity excludes signatures (mirrors claims).`n`nReceiptId = SHA-256(canonical_bytes(receipt_without_signature))`n") )
}

# ---- Add missing schema docs ----
$p2 = Join-Path $SchemasDir "canonical_json_rules.md"
if(-not (Test-Path -LiteralPath $p2 -PathType Leaf)){
  Write-Utf8NoBomLf $p2 (("# Canonical JSON Rules (CLP)`n`n- object keys sorted by ordinal ordering`n- no whitespace`n- stable escaping`n- invariant numeric formatting (no NaN/Infinity)`n- UTF-8 no BOM`n- LF`n") )
}

# ---- Write scripts/_lib_clp_v1.ps1 ----
$lib = Join-Path $ScriptsDir "_lib_clp_v1.ps1"
if(-not (Test-Path -LiteralPath $lib -PathType Leaf)){
  $txt = @()
  $txt += '$ErrorActionPreference="Stop"'
  $txt += 'Set-StrictMode -Version Latest'
  $txt += ''
  $txt += (${function:Die}.ToString())
  $txt += ''
  # Embed minimal required functions by re-emitting from this fixer
  $txt += 'function _JsonEscape([string]$s){'
  $txt += '  if($null -eq $s){ return "" }'
  $txt += '  $sb = New-Object System.Text.StringBuilder'
  $txt += '  $i=0'
  $txt += '  while($i -lt $s.Length){'
  $txt += '    $c=[int][char]$s[$i]'
  $txt += '    if($c -eq 34){ [void]$sb.Append('\\"') }'
  $txt += '    elseif($c -eq 92){ [void]$sb.Append('\\\\') }'
  $txt += '    elseif($c -eq 8){ [void]$sb.Append('\\b') }'
  $txt += '    elseif($c -eq 12){ [void]$sb.Append('\\f') }'
  $txt += '    elseif($c -eq 10){ [void]$sb.Append('\\n') }'
  $txt += '    elseif($c -eq 13){ [void]$sb.Append('\\r') }'
  $txt += '    elseif($c -eq 9){ [void]$sb.Append('\\t') }'
  $txt += '    elseif($c -lt 32){ [void]$sb.Append(("\\u{0:x4}" -f $c)) }'
  $txt += '    else{ [void]$sb.Append([char]$c) }'
  $txt += '    $i++'
  $txt += '  }'
  $txt += '  return $sb.ToString()'
  $txt += '}'
  $txt += 'function _IsNumberLike($v){ return ($v -is [byte] -or $v -is [sbyte] -or $v -is [int16] -or $v -is [uint16] -or $v -is [int32] -or $v -is [uint32] -or $v -is [int64] -or $v -is [uint64] -or $v -is [single] -or $v -is [double] -or $v -is [decimal]) }'
  $txt += 'function _CanonNumber($v){ $ci=[System.Globalization.CultureInfo]::InvariantCulture; if($v -is [double] -or $v -is [single]){ if([double]::IsNaN([double]$v) -or [double]::IsInfinity([double]$v)){ Die "CANON_JSON_INVALID_NUMBER: NaN/Infinity not allowed" }; return ([double]$v).ToString("R",$ci) }; if($v -is [decimal]){ return ([decimal]$v).ToString($ci) }; return ([string]::Format($ci,"{0}",$v)) }'
  $txt += 'function _CanonJsonValue($v){ if($null -eq $v){ return "null" }; if($v -is [bool]){ return ($(if($v){"true"}else{"false"})) }; if(_IsNumberLike $v){ return (_CanonNumber $v) }; if($v -is [string]){ return ('"'+(_JsonEscape $v)+'"') }; if($v -is [System.Collections.IEnumerable] -and -not ($v -is [System.Collections.IDictionary]) -and -not ($v -is [string])){ $parts=New-Object System.Collections.Generic.List[string]; foreach($it in $v){ [void]$parts.Add((_CanonJsonValue $it)) }; return ("["+(@($parts.ToArray()) -join ",")+"]") }; if($v -is [System.Collections.IDictionary]){ $keys=New-Object System.Collections.Generic.List[string]; foreach($k in $v.Keys){ [void]$keys.Add([string]$k) }; $keys.Sort([StringComparer]::Ordinal); $pairs=New-Object System.Collections.Generic.List[string]; foreach($k in $keys){ [void]$pairs.Add(('"'+(_JsonEscape $k)+'":'+(_CanonJsonValue $v[$k]))) }; return ("{"+(@($pairs.ToArray()) -join ",")+"}") }; $ht=@{}; $props=@($v.PSObject.Properties | ForEach-Object { $_.Name }); $props=@($props | Sort-Object); foreach($pn in $props){ $ht[$pn]=$v.$pn }; return (_CanonJsonValue $ht) }'
  $txt += 'function To-CanonJson($Obj){ return (_CanonJsonValue $Obj) }'
  $txt += 'function To-CanonJsonBytes($Obj){ $enc=New-Object System.Text.UTF8Encoding($false); return $enc.GetBytes((To-CanonJson $Obj)) }'
  $txt += 'function Sha256HexBytes([byte[]]$Bytes){ if($null -eq $Bytes){ $Bytes=@() }; $sha=[System.Security.Cryptography.SHA256]::Create(); try{ $h=$sha.ComputeHash([byte[]]$Bytes); $sb=New-Object System.Text.StringBuilder; $i=0; while($i -lt $h.Length){ [void]$sb.Append($h[$i].ToString("x2")); $i++ }; return $sb.ToString() } finally { $sha.Dispose() } }'
  $txt += 'function ReadJson([string]$Path){ if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_JSON: " + $Path) }; $raw=[System.IO.File]::ReadAllText($Path,(New-Object System.Text.UTF8Encoding($false))); return ($raw | ConvertFrom-Json -Depth 50) }'
  $txt += 'function _RemoveKey([hashtable]$ht,[string]$key){ if($ht.ContainsKey($key)){ [void]$ht.Remove($key) } }'
  $txt += 'function ClaimIdFromClaimObject($claimObj){ $ht=@{}; foreach($p in $claimObj.PSObject.Properties){ $ht[$p.Name]=$p.Value }; _RemoveKey $ht "signature"; return (Sha256HexBytes (To-CanonJsonBytes $ht)) }'
  $txt += 'function ReceiptIdFromReceiptObject($receiptObj){ $ht=@{}; foreach($p in $receiptObj.PSObject.Properties){ $ht[$p.Name]=$p.Value }; _RemoveKey $ht "signature"; return (Sha256HexBytes (To-CanonJsonBytes $ht)) }'
  Write-Utf8NoBomLf $lib ((@($txt) -join "`n") + "`n")
}

# ---- Write test vector scripts ----
$tvRunner = Join-Path $ScriptsDir "clp_run_test_vectors_v1.ps1"
if(-not (Test-Path -LiteralPath $tvRunner -PathType Leaf)){
  $t = @()
  $t += 'param([Parameter(Mandatory=$true)][string]$RepoRoot)'
  $t += '$ErrorActionPreference="Stop"'
  $t += 'Set-StrictMode -Version Latest'
  $t += ''
  $t += '. (Join-Path $RepoRoot "scripts\_lib_clp_v1.ps1")'
  $t += 'function Die([string]$m){ throw $m }'
  $t += 'function EnsureLeaf([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_FILE: " + $p) } }'
  $t += ''
  $t += '$tv = Join-Path $RepoRoot "test_vectors"'
  $t += '$claimPath = Join-Path $tv "minimal-claim\claim.json"'
  $t += '$expClaim  = Join-Path $tv "minimal-claim\expected_claim_id.txt"'
  $t += 'EnsureLeaf $claimPath'
  $t += '$claimObj = ReadJson $claimPath'
  $t += '$gotClaim = ClaimIdFromClaimObject $claimObj'
  $t += 'if(Test-Path -LiteralPath $expClaim -PathType Leaf){ $want=([System.IO.File]::ReadAllText($expClaim)).Trim(); if($want -and $want -ne $gotClaim){ Die ("TEST_VECTOR_FAIL: claim_id want=" + $want + " got=" + $gotClaim) } }'
  $t += ''
  $t += '$rcptPath = Join-Path $tv "minimal-receipt\receipt.json"'
  $t += '$expRcpt  = Join-Path $tv "minimal-receipt\expected_receipt_id.txt"'
  $t += 'EnsureLeaf $rcptPath'
  $t += '$rcptObj = ReadJson $rcptPath'
  $t += '$gotRcpt = ReceiptIdFromReceiptObject $rcptObj'
  $t += 'if(Test-Path -LiteralPath $expRcpt -PathType Leaf){ $wantR=([System.IO.File]::ReadAllText($expRcpt)).Trim(); if($wantR -and $wantR -ne $gotRcpt){ Die ("TEST_VECTOR_FAIL: receipt_id want=" + $wantR + " got=" + $gotRcpt) } }'
  $t += ''
  $t += 'Write-Host ("TEST_VECTORS_OK: claim_id=" + $gotClaim + " receipt_id=" + $gotRcpt) -ForegroundColor Green'
  Write-Utf8NoBomLf $tvRunner ((@($t) -join "`n") + "`n")
}

# ---- Create minimal receipt vector deterministically (derive from claim id) ----
$claimJson = Join-Path $TVDir "minimal-claim\claim.json"
if(-not (Test-Path -LiteralPath $claimJson -PathType Leaf)){ Die ("MISSING_MINIMAL_CLAIM_JSON: " + $claimJson) }
$claimObj = ReadJson $claimJson
$claimId = ClaimIdFromClaimObject $claimObj
$rcptDir = Join-Path $TVDir "minimal-receipt"
EnsureDir $rcptDir
$rcptJson = Join-Path $rcptDir "receipt.json"
$rcptExp  = Join-Path $rcptDir "expected_receipt_id.txt"
Write-Utf8NoBomLf $rcptJson ('{"for_claim":"'+$claimId+'","receipt_type":"test.witness.receipt.v1","result":{"ok":true,"reason":"unit"},"timestamp":"0"}' + "`n")
$rcptObj = ReadJson $rcptJson
$rcptId = ReceiptIdFromReceiptObject $rcptObj
Write-Utf8NoBomLf $rcptExp ($rcptId + "`n")

# ---- Parse-gate scripts ----
Parse-GateFile (Join-Path $ScriptsDir "_lib_clp_v1.ps1")
Parse-GateFile (Join-Path $ScriptsDir "clp_run_test_vectors_v1.ps1")

Write-Host ("CLP_FIX_OK: claim_id=" + $claimId + " receipt_id=" + $rcptId) -ForegroundColor Green
