param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function EnsureDir([string]$p){
  if (-not (Test-Path -LiteralPath $p -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { EnsureDir $dir }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Parse-GateFile([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("PARSE_GATE_MISSING: " + $Path) }
  $tokens=$null; $errs=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errs)
  if ($errs -and $errs.Count -gt 0) {
    $msg = ($errs | ForEach-Object { $_.ToString() }) -join "`n"
    Die ("PARSE_GATE_FAIL: " + $Path + "`n" + $msg)
  }
}

# Paths
$Scratch = Join-Path $RepoRoot "scripts\_scratch"
EnsureDir $Scratch
$Patch = Join-Path $Scratch "_PATCH_clp_hard_repair_v1.ps1"

# -------------------------
# Write PATCH script to disk
# -------------------------
$PatchText = @'
param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function EnsureDir([string]$p){
  if (-not (Test-Path -LiteralPath $p -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { EnsureDir $dir }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Parse-GateFile([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("PARSE_GATE_MISSING: " + $Path) }
  $tokens=$null; $errs=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errs)
  if ($errs -and $errs.Count -gt 0) {
    $msg = ($errs | ForEach-Object { $_.ToString() }) -join "`n"
    Die ("PARSE_GATE_FAIL: " + $Path + "`n" + $msg)
  }
}

# ---- Paths ----
$ScriptsDir  = Join-Path $RepoRoot "scripts"
$TVDir       = Join-Path $RepoRoot "test_vectors"
$MinClaimDir = Join-Path $TVDir "minimal-claim"
$MinRcptDir  = Join-Path $TVDir "minimal-receipt"

EnsureDir $ScriptsDir
EnsureDir $TVDir
EnsureDir $MinClaimDir
EnsureDir $MinRcptDir

# ---- Overwrite scripts/_lib_clp_v1.ps1 ----
$LibPath = Join-Path $ScriptsDir "_lib_clp_v1.ps1"

$LibText = @'
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function _JsonEscape([string]$s){
  if ($null -eq $s) { return "" }
  $sb = New-Object System.Text.StringBuilder
  $i = 0
  while ($i -lt $s.Length) {
    $c = [int][char]$s[$i]
    if ($c -eq 34)      { [void]$sb.Append('\\"') }          # "
    elseif ($c -eq 92)  { [void]$sb.Append('\\\\') }         # \
    elseif ($c -eq 8)   { [void]$sb.Append('\\b') }
    elseif ($c -eq 12)  { [void]$sb.Append('\\f') }
    elseif ($c -eq 10)  { [void]$sb.Append('\\n') }
    elseif ($c -eq 13)  { [void]$sb.Append('\\r') }
    elseif ($c -eq 9)   { [void]$sb.Append('\\t') }
    elseif ($c -lt 32)  { [void]$sb.Append(('\u{0:x4}' -f $c)) }
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
  if ($v -is [double] -or $v -is [single]) {
    if ([double]::IsNaN([double]$v) -or [double]::IsInfinity([double]$v)) {
      Die "CANON_JSON_INVALID_NUMBER: NaN/Infinity not allowed"
    }
    return ([double]$v).ToString("R",$ci)
  }
  if ($v -is [decimal]) { return ([decimal]$v).ToString($ci) }
  return ([string]::Format($ci, "{0}", $v))
}

function _CanonJsonValue($v){
  if ($null -eq $v) { return "null" }
  if ($v -is [bool]) { return ($(if ($v) { "true" } else { "false" })) }
  if (_IsNumberLike $v) { return (_CanonNumber $v) }
  if ($v -is [string]) { return ('"' + (_JsonEscape $v) + '"') }

  if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [System.Collections.IDictionary]) -and -not ($v -is [string])) {
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($it in $v) { [void]$parts.Add((_CanonJsonValue $it)) }
    return ("[" + (@($parts.ToArray()) -join ",") + "]")
  }

  if ($v -is [System.Collections.IDictionary]) {
    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($k in $v.Keys) { [void]$keys.Add([string]$k) }
    $keys.Sort([StringComparer]::Ordinal)

    $pairs = New-Object System.Collections.Generic.List[string]
    foreach ($k in $keys) {
      $val = $v[$k]
      [void]$pairs.Add(('"' + (_JsonEscape $k) + '":' + (_CanonJsonValue $val)))
    }
    return ("{" + (@($pairs.ToArray()) -join ",") + "}")
  }

  $ht = @{}
  $props = @($v.PSObject.Properties | ForEach-Object { $_.Name })
  $props = @($props | Sort-Object)
  foreach ($pn in $props) { $ht[$pn] = $v.$pn }
  return (_CanonJsonValue $ht)
}

function To-CanonJson([Parameter(Mandatory=$true)]$Obj){ return (_CanonJsonValue $Obj) }

function To-CanonJsonBytes([Parameter(Mandatory=$true)]$Obj){
  $s = To-CanonJson $Obj
  $enc = New-Object System.Text.UTF8Encoding($false)
  return $enc.GetBytes($s)
}

function Sha256HexBytes([byte[]]$Bytes){
  if ($null -eq $Bytes) { $Bytes = @() }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash([byte[]]$Bytes)
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    while ($i -lt $hash.Length) { [void]$sb.Append($hash[$i].ToString("x2")); $i++ }
    return $sb.ToString()
  } finally { $sha.Dispose() }
}

function ReadJson([string]$Path){
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Die ("MISSING_JSON: " + $Path) }
  $raw = [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
  return ($raw | ConvertFrom-Json -Depth 50)
}

function WriteCanonJson([string]$Path,$Obj){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $json = To-CanonJson $Obj
  $enc = New-Object System.Text.UTF8Encoding($false)
  $txt = ($json + "`n").Replace("`r`n","`n").Replace("`r","`n")
  [System.IO.File]::WriteAllText($Path,$txt,$enc)
}

function _RemoveKey([hashtable]$ht,[string]$key){
  if ($ht.ContainsKey($key)) { [void]$ht.Remove($key) }
}

function ClaimIdFromClaimObject($claimObj){
  $ht = @{}
  foreach ($p in $claimObj.PSObject.Properties) { $ht[$p.Name] = $p.Value }
  _RemoveKey $ht "signature"
  return (Sha256HexBytes (To-CanonJsonBytes $ht))
}

function ReceiptIdFromReceiptObject($receiptObj){
  $ht = @{}
  foreach ($p in $receiptObj.PSObject.Properties) { $ht[$p.Name] = $p.Value }
  _RemoveKey $ht "signature"
  return (Sha256HexBytes (To-CanonJsonBytes $ht))
}