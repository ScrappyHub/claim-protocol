param(
  [Parameter(Mandatory=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$RepoRoot
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){
  throw $m
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

function ParseGateFile([string]$Path){
  EnsureLeaf $Path
  $tokens = $null
  $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errs)
  $e = @(@($errs))
  if($e.Count -gt 0){
    $msg = ($e | ForEach-Object { $_.ToString() }) -join "`n"
    Die ("PARSE_GATE_FAIL: " + $Path + "`n" + $msg)
  }
}

function ReadJsonNoDepth([string]$Path){
  $raw = ReadTextUtf8NoBom $Path
  $obj = $raw | ConvertFrom-Json
  if($null -eq $obj){
    Die ("INVALID_JSON_NULL: " + $Path)
  }
  return $obj
}

function HasProp($Obj,[string]$Name){
  $props = @(@($Obj.PSObject.Properties))
  foreach($p in $props){
    if([string]$p.Name -eq $Name){
      return $true
    }
  }
  return $false
}

function GetProp($Obj,[string]$Name){
  $props = @(@($Obj.PSObject.Properties))
  foreach($p in $props){
    if([string]$p.Name -eq $Name){
      return $p.Value
    }
  }
  Die ("MISSING_REQUIRED_FIELD: " + $Name)
}

function IsJsonObjectValue($v){
  if($null -eq $v){ return $false }
  if($v -is [System.Collections.IDictionary]){ return $true }
  if($v -is [pscustomobject]){ return $true }
  return $false
}

function IsJsonArrayValue($v){
  if($null -eq $v){ return $false }
  if($v -is [string]){ return $false }
  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [System.Collections.IDictionary])){
    return $true
  }
  return $false
}

function Validate-InlineJson($Obj){
  if(-not (HasProp $Obj "value")){ return "MISSING_REQUIRED_FIELD:value" }
  $value = GetProp $Obj "value"
  if(-not ((IsJsonObjectValue $value) -or (IsJsonArrayValue $value))){ return "INVALID_FIELD_TYPE:value" }
  if(HasProp $Obj "media_type"){
    if((GetProp $Obj "media_type") -isnot [string]){ return "INVALID_FIELD_TYPE:media_type" }
  }
  return "OK"
}

function Validate-InlineText($Obj){
  if(-not (HasProp $Obj "media_type")){ return "MISSING_REQUIRED_FIELD:media_type" }
  if(-not (HasProp $Obj "text")){ return "MISSING_REQUIRED_FIELD:text" }
  if((GetProp $Obj "media_type") -isnot [string]){ return "INVALID_FIELD_TYPE:media_type" }
  if((GetProp $Obj "text") -isnot [string]){ return "INVALID_FIELD_TYPE:text" }
  return "OK"
}

function Validate-BlobRef($Obj){
  if(-not (HasProp $Obj "media_type")){ return "MISSING_REQUIRED_FIELD:media_type" }
  if(-not (HasProp $Obj "digest")){ return "MISSING_REQUIRED_FIELD:digest" }
  if(-not (HasProp $Obj "length")){ return "MISSING_REQUIRED_FIELD:length" }

  if((GetProp $Obj "media_type") -isnot [string]){ return "INVALID_FIELD_TYPE:media_type" }
  if((GetProp $Obj "digest") -isnot [string]){ return "INVALID_FIELD_TYPE:digest" }

  $digest = [string](GetProp $Obj "digest")
  if(-not $digest.StartsWith("sha256:",[System.StringComparison]::Ordinal)){ return "INVALID_DIGEST_FORMAT" }

  $length = GetProp $Obj "length"
  if(-not ($length -is [byte] -or $length -is [sbyte] -or $length -is [int16] -or $length -is [uint16] -or $length -is [int32] -or $length -is [uint32] -or $length -is [int64] -or $length -is [uint64] -or $length -is [single] -or $length -is [double] -or $length -is [decimal])){ return "INVALID_FIELD_TYPE:length" }

  if(HasProp $Obj "filename"){
    if((GetProp $Obj "filename") -isnot [string]){ return "INVALID_FIELD_TYPE:filename" }
  }

  return "OK"
}

function Validate-PacketRef($Obj){
  if(-not (HasProp $Obj "packet_id")){ return "MISSING_REQUIRED_FIELD:packet_id" }
  if((GetProp $Obj "packet_id") -isnot [string]){ return "INVALID_FIELD_TYPE:packet_id" }

  if(HasProp $Obj "manifest_digest"){
    if((GetProp $Obj "manifest_digest") -isnot [string]){ return "INVALID_FIELD_TYPE:manifest_digest" }
  }

  if(HasProp $Obj "path"){
    if((GetProp $Obj "path") -isnot [string]){ return "INVALID_FIELD_TYPE:path" }
  }

  return "OK"
}

function Validate-PayloadVector([string]$VectorDir,[string]$ExpectedMode,[string]$ExpectedTokenPrefix){
  $payloadPath = Join-Path $VectorDir "payload.json"
  EnsureLeaf $payloadPath

  $parsed = ReadJsonNoDepth $payloadPath
  if(-not (IsJsonObjectValue $parsed)){
    $token = "INVALID_TOP_LEVEL_TYPE"
    if($ExpectedMode -eq "negative" -and $ExpectedTokenPrefix -eq $token){
      return "PASS"
    }
    return ("FAIL:" + $token)
  }

  if(-not (HasProp $parsed "mode")){
    $token = "MISSING_REQUIRED_FIELD:mode"
    if($ExpectedMode -eq "negative" -and $ExpectedTokenPrefix -eq $token){
      return "PASS"
    }
    return ("FAIL:" + $token)
  }

  $mode = GetProp $parsed "mode"
  if($mode -isnot [string]){
    $token = "INVALID_FIELD_TYPE:mode"
    if($ExpectedMode -eq "negative" -and $ExpectedTokenPrefix -eq $token){
      return "PASS"
    }
    return ("FAIL:" + $token)
  }

  $token = ""
  switch([string]$mode){
    "inline_json" { $token = Validate-InlineJson $parsed; break }
    "inline_text" { $token = Validate-InlineText $parsed; break }
    "blob_ref" { $token = Validate-BlobRef $parsed; break }
    "packet_ref" { $token = Validate-PacketRef $parsed; break }
    default { $token = "INVALID_PAYLOAD_MODE" }
  }

  if($ExpectedMode -eq "positive"){
    if($token -eq "OK"){ return "PASS" }
    return ("FAIL:" + $token)
  }

  if($ExpectedMode -eq "negative"){
    if($token.StartsWith($ExpectedTokenPrefix,[System.StringComparison]::Ordinal)){ return "PASS" }
    return ("FAIL:" + $token)
  }

  return "FAIL:BAD_EXPECTED_MODE"
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  Die ("MISSING_REPOROOT: " + $RepoRoot)
}

$SelfPath = $PSCommandPath
ParseGateFile $SelfPath

$Base = Join-Path $RepoRoot "test_vectors\media_storage"

$Vectors = @(
  @{ Name="positive_inline_json"; ExpectedMode="positive"; ExpectedTokenPrefix="OK" },
  @{ Name="positive_inline_text"; ExpectedMode="positive"; ExpectedTokenPrefix="OK" },
  @{ Name="positive_blob_ref"; ExpectedMode="positive"; ExpectedTokenPrefix="OK" },
  @{ Name="positive_packet_ref"; ExpectedMode="positive"; ExpectedTokenPrefix="OK" },
  @{ Name="negative_bad_mode"; ExpectedMode="negative"; ExpectedTokenPrefix="INVALID_PAYLOAD_MODE" },
  @{ Name="negative_blob_ref_missing_digest"; ExpectedMode="negative"; ExpectedTokenPrefix="MISSING_REQUIRED_FIELD:digest" },
  @{ Name="negative_packet_ref_missing_packet_id"; ExpectedMode="negative"; ExpectedTokenPrefix="MISSING_REQUIRED_FIELD:packet_id" }
)

$Pass = 0
$Fail = 0

foreach($v in @($Vectors)){
  $name = [string]$v.Name
  $mode = [string]$v.ExpectedMode
  $prefix = [string]$v.ExpectedTokenPrefix
  $dir = Join-Path $Base $name

  $r = Validate-PayloadVector -VectorDir $dir -ExpectedMode $mode -ExpectedTokenPrefix $prefix
  if($r -eq "PASS"){
    $Pass++
    Write-Host ("PASS: " + $name) -ForegroundColor Green
  }
  else {
    $Fail++
    Write-Host ("FAIL: " + $name + " => " + $r) -ForegroundColor Red
  }
}

if($Fail -ne 0){
  Die ("MEDIA_STORAGE_VECTORS_FAIL: pass=" + $Pass + " fail=" + $Fail)
}

Write-Host ("MEDIA_STORAGE_VECTORS_OK: pass=" + $Pass + " fail=" + $Fail) -ForegroundColor Green