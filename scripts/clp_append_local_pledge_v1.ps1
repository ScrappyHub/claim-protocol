param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$RepoRoot,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ClaimJsonPath,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Actor,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Timestamp
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

function EnsureLeaf([string]$p){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    Die ("MISSING_FILE: " + $p)
  }
}

function ReadTextUtf8NoBom([string]$p){
  EnsureLeaf $p
  return [System.IO.File]::ReadAllText($p,(New-Object System.Text.UTF8Encoding($false)))
}

function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ EnsureDir $dir }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [System.IO.File]::WriteAllText($Path,$t,(New-Object System.Text.UTF8Encoding($false)))
}

function Sha256HexBytes([byte[]]$Bytes){
  if($null -eq $Bytes){ $Bytes = @() }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try{
    $h = $sha.ComputeHash([byte[]]$Bytes)
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    while($i -lt $h.Length){
      [void]$sb.Append($h[$i].ToString("x2"))
      $i++
    }
    return $sb.ToString()
  } finally {
    $sha.Dispose()
  }
}

function Sha256HexFile([string]$Path){
  EnsureLeaf $Path
  return (Sha256HexBytes ([System.IO.File]::ReadAllBytes($Path)))
}

function _JsonEscape([string]$s){
  if($null -eq $s){ return "" }
  $sb = New-Object System.Text.StringBuilder
  $i = 0
  while($i -lt $s.Length){
    $c = [int][char]$s[$i]
    if($c -eq 34){ [void]$sb.Append('\"') }
    elseif($c -eq 92){ [void]$sb.Append('\\') }
    elseif($c -eq 8){ [void]$sb.Append('\b') }
    elseif($c -eq 12){ [void]$sb.Append('\f') }
    elseif($c -eq 10){ [void]$sb.Append('\n') }
    elseif($c -eq 13){ [void]$sb.Append('\r') }
    elseif($c -eq 9){ [void]$sb.Append('\t') }
    elseif($c -lt 32){ [void]$sb.Append(('\u{0:x4}' -f $c)) }
    else { [void]$sb.Append([char]$c) }
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
  $ci = [System.Globalization.CultureInfo]::InvariantCulture
  if($v -is [double] -or $v -is [single]){
    if([double]::IsNaN([double]$v) -or [double]::IsInfinity([double]$v)){ Die "CANON_JSON_INVALID_NUMBER" }
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
    foreach($k in $keys){
      [void]$pairs.Add(('"' + (_JsonEscape $k) + '":' + (_CanonJsonValue $v[$k])))
    }
    return ("{" + (@($pairs.ToArray()) -join ",") + "}")
  }

  $ht = @{}
  $props = @(@($v.PSObject.Properties) | ForEach-Object { $_.Name } | Sort-Object)
  foreach($pn in $props){ $ht[$pn] = $v.$pn }
  return (_CanonJsonValue $ht)
}

function ToCanonJson($Obj){
  return (_CanonJsonValue $Obj)
}

function ToCanonJsonBytes($Obj){
  $enc = New-Object System.Text.UTF8Encoding($false)
  return $enc.GetBytes((ToCanonJson $Obj))
}

function ReadJson([string]$Path){
  EnsureLeaf $Path
  $raw = ReadTextUtf8NoBom $Path
  return ($raw | ConvertFrom-Json)
}

function RemoveKey([hashtable]$ht,[string]$key){
  if($ht.ContainsKey($key)){ [void]$ht.Remove($key) }
}

function ClaimIdFromClaimObject($claimObj){
  $ht = @{}
  foreach($p in @(@($claimObj.PSObject.Properties))){ $ht[$p.Name] = $p.Value }
  RemoveKey $ht "signature"
  return (Sha256HexBytes (ToCanonJsonBytes $ht))
}

$ScriptsDir = Join-Path $RepoRoot "scripts"
$LibPath = Join-Path $ScriptsDir "_lib_clp_v1.ps1"
if(Test-Path -LiteralPath $LibPath -PathType Leaf){
  . $LibPath
}

$ClaimObj = ReadJson $ClaimJsonPath
$ClaimId = ClaimIdFromClaimObject $ClaimObj
$ObjectSha = Sha256HexFile $ClaimJsonPath

$LedgerDir = Join-Path $RepoRoot "proofs\local_pledge"
$LedgerPath = Join-Path $LedgerDir "claims.ndjson"
EnsureDir $LedgerDir

$PrevHash = ""
if(Test-Path -LiteralPath $LedgerPath -PathType Leaf){
  $rawLedger = ReadTextUtf8NoBom $LedgerPath
  $lines = @($rawLedger -split "`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -ne "" })
  if(@(@($lines)).Count -gt 0){
    $last = $lines[@(@($lines)).Count - 1] | ConvertFrom-Json
    $PrevHash = [string]$last.entry_hash
  }
}

$entryNoHash = [ordered]@{
  actor = $Actor
  claim_id = $ClaimId
  event_type = "clp.local_pledge.append.v1"
  object_sha256 = $ObjectSha
  previous_entry_hash = $PrevHash
  schema = "clp.pledge.entry.v1"
  timestamp = $Timestamp
}

$EntryHash = Sha256HexBytes (ToCanonJsonBytes $entryNoHash)

$entry = [ordered]@{
  actor = $Actor
  claim_id = $ClaimId
  entry_hash = $EntryHash
  event_type = "clp.local_pledge.append.v1"
  object_sha256 = $ObjectSha
  previous_entry_hash = $PrevHash
  schema = "clp.pledge.entry.v1"
  timestamp = $Timestamp
}

$line = (ToCanonJson $entry)
if(Test-Path -LiteralPath $LedgerPath -PathType Leaf){
  $existing = ReadTextUtf8NoBom $LedgerPath
  $combined = $existing
  if(-not $combined.EndsWith("`n")){ $combined += "`n" }
  $combined += ($line + "`n")
  WriteUtf8NoBomLf $LedgerPath $combined
} else {
  WriteUtf8NoBomLf $LedgerPath ($line + "`n")
}

Write-Host ("LOCAL_PLEDGE_APPEND_OK: claim_id=" + $ClaimId + " entry_hash=" + $EntryHash) -ForegroundColor Green
