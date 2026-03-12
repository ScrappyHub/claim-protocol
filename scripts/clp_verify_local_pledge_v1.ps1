param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$RepoRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function EnsureLeaf([string]$p){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    Die ("MISSING_FILE: " + $p)
  }
}

function ReadTextUtf8NoBom([string]$p){
  EnsureLeaf $p
  return [System.IO.File]::ReadAllText($p,(New-Object System.Text.UTF8Encoding($false)))
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

function ToCanonJsonBytes($Obj){
  $enc = New-Object System.Text.UTF8Encoding($false)
  return $enc.GetBytes((_CanonJsonValue $Obj))
}

function HasProp($Obj,[string]$Name){
  $props = @(@($Obj.PSObject.Properties))
  foreach($p in $props){
    if([string]$p.Name -eq $Name){ return $true }
  }
  return $false
}

function RemoveKey([hashtable]$ht,[string]$key){
  if($ht.ContainsKey($key)){ [void]$ht.Remove($key) }
}

$LedgerPath = Join-Path $RepoRoot "proofs\local_pledge\claims.ndjson"
EnsureLeaf $LedgerPath

$raw = ReadTextUtf8NoBom $LedgerPath
$lines = @($raw -split "`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -ne "" })
if(@(@($lines)).Count -eq 0){ Die "LEDGER_EMPTY" }

$prevHash = ""
$index = 0
foreach($line in @($lines)){
  $index++
  try {
    $obj = $line | ConvertFrom-Json
  } catch {
    Die ("INVALID_LEDGER_LINE: line=" + $index)
  }

  if(-not (HasProp $obj "schema")){ Die ("MISSING_REQUIRED_FIELD:schema line=" + $index) }
  if([string]$obj.schema -ne "clp.pledge.entry.v1"){ Die ("INVALID_ENTRY_SCHEMA: line=" + $index) }

  foreach($req in @("event_type","actor","claim_id","object_sha256","previous_entry_hash","timestamp","entry_hash")){
    if(-not (HasProp $obj $req)){ Die ("MISSING_REQUIRED_FIELD:" + $req + " line=" + $index) }
  }

  if($index -eq 1){
    if([string]$obj.previous_entry_hash -ne ""){ Die ("PREVIOUS_ENTRY_HASH_MISMATCH: line=" + $index) }
  } else {
    if([string]$obj.previous_entry_hash -ne $prevHash){ Die ("PREVIOUS_ENTRY_HASH_MISMATCH: line=" + $index) }
  }

  $ht = @{}
  foreach($p in @(@($obj.PSObject.Properties))){ $ht[$p.Name] = $p.Value }
  $claimedHash = [string]$ht["entry_hash"]
  RemoveKey $ht "entry_hash"
  $computedHash = Sha256HexBytes (ToCanonJsonBytes $ht)

  if($claimedHash -ne $computedHash){ Die ("ENTRY_HASH_MISMATCH: line=" + $index) }

  $prevHash = $claimedHash
}

Write-Host ("LOCAL_PLEDGE_VERIFY_OK: entries=" + @(@($lines)).Count + " final_entry_hash=" + $prevHash) -ForegroundColor Green