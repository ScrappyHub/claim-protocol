param(
  [Parameter(Mandatory=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$RepoRoot,
  [Parameter(Mandatory=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$ObjectJsonPath
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

function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [System.IO.File]::WriteAllText($Path,$t,(New-Object System.Text.UTF8Encoding($false)))
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

function IsJsonObjectValue($v){
  if($null -eq $v){ return $false }
  if($v -is [System.Collections.IDictionary]){ return $true }
  if($v -is [pscustomobject]){ return $true }
  return $false
}

function IsJsonArrayValue($v){
  if($null -eq $v){ return $false }
  if($v -is [string]){ return $false }
  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [System.Collections.IDictionary])){ return $true }
  return $false
}

function HasProp($Obj,[string]$Name){
  $props = @(@($Obj.PSObject.Properties))
  foreach($p in $props){
    if([string]$p.Name -eq $Name){ return $true }
  }
  return $false
}

function GetProp($Obj,[string]$Name){
  $props = @(@($Obj.PSObject.Properties))
  foreach($p in $props){
    if([string]$p.Name -eq $Name){ return $p.Value }
  }
  Die ("MISSING_REQUIRED_FIELD:" + $Name)
}

function Emit-VerifyResult([bool]$Ok,[string]$ObjectSchema,[string]$ReasonToken,[string]$PayloadMode){
  $parts = New-Object System.Collections.Generic.List[string]
  [void]$parts.Add('{"object_schema":"' + (_JsonEscape $ObjectSchema) + '"')
  [void]$parts.Add(',"ok":' + ($(if($Ok){'true'}else{'false'})))
  if(-not [string]::IsNullOrWhiteSpace($PayloadMode)){
    [void]$parts.Add(',"payload_mode":"' + (_JsonEscape $PayloadMode) + '"')
  }
  [void]$parts.Add(',"reason_token":"' + (_JsonEscape $ReasonToken) + '"')
  [void]$parts.Add(',"schema":"clp.verify.result.v1"}')
  $json = (@($parts.ToArray()) -join "")
  Write-Output $json
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

function Validate-Payload($PayloadObj){
  if(-not (IsJsonObjectValue $PayloadObj)){ return @{ Token="INVALID_FIELD_TYPE:payload"; Mode="" } }
  if(-not (HasProp $PayloadObj "mode")){ return @{ Token="MISSING_REQUIRED_FIELD:mode"; Mode="" } }
  $mode = GetProp $PayloadObj "mode"
  if($mode -isnot [string]){ return @{ Token="INVALID_FIELD_TYPE:mode"; Mode="" } }

  $m = [string]$mode
  $token = ""
  switch($m){
    "inline_json" { $token = Validate-InlineJson $PayloadObj; break }
    "inline_text" { $token = Validate-InlineText $PayloadObj; break }
    "blob_ref" { $token = Validate-BlobRef $PayloadObj; break }
    "packet_ref" { $token = Validate-PacketRef $PayloadObj; break }
    default { $token = "INVALID_PAYLOAD_MODE" }
  }
  return @{ Token=$token; Mode=$m }
}

function Verify-Claim($Obj){
  if(-not (HasProp $Obj "claim_type")){ return @{ Ok=$false; Reason="MISSING_REQUIRED_FIELD:claim_type"; Schema="clp.claim.v1"; PayloadMode="" } }
  if(-not (HasProp $Obj "producer")){ return @{ Ok=$false; Reason="MISSING_REQUIRED_FIELD:producer"; Schema="clp.claim.v1"; PayloadMode="" } }
  if(-not (HasProp $Obj "timestamp")){ return @{ Ok=$false; Reason="MISSING_REQUIRED_FIELD:timestamp"; Schema="clp.claim.v1"; PayloadMode="" } }
  if(-not (HasProp $Obj "payload")){ return @{ Ok=$false; Reason="MISSING_REQUIRED_FIELD:payload"; Schema="clp.claim.v1"; PayloadMode="" } }

  if((GetProp $Obj "claim_type") -isnot [string]){ return @{ Ok=$false; Reason="INVALID_FIELD_TYPE:claim_type"; Schema="clp.claim.v1"; PayloadMode="" } }
  if((GetProp $Obj "producer") -isnot [string]){ return @{ Ok=$false; Reason="INVALID_FIELD_TYPE:producer"; Schema="clp.claim.v1"; PayloadMode="" } }
  if((GetProp $Obj "timestamp") -isnot [string]){ return @{ Ok=$false; Reason="INVALID_FIELD_TYPE:timestamp"; Schema="clp.claim.v1"; PayloadMode="" } }

  $pv = Validate-Payload (GetProp $Obj "payload")
  if([string]$pv.Token -ne "OK"){ return @{ Ok=$false; Reason=[string]$pv.Token; Schema="clp.claim.v1"; PayloadMode=[string]$pv.Mode } }

  return @{ Ok=$true; Reason="OK"; Schema="clp.claim.v1"; PayloadMode=[string]$pv.Mode }
}

function Verify-Receipt($Obj){
  if(-not (HasProp $Obj "receipt_type")){ return @{ Ok=$false; Reason="MISSING_REQUIRED_FIELD:receipt_type"; Schema="clp.receipt.v1"; PayloadMode="" } }
  if(-not (HasProp $Obj "for_claim")){ return @{ Ok=$false; Reason="MISSING_REQUIRED_FIELD:for_claim"; Schema="clp.receipt.v1"; PayloadMode="" } }
  if(-not (HasProp $Obj "result")){ return @{ Ok=$false; Reason="MISSING_REQUIRED_FIELD:result"; Schema="clp.receipt.v1"; PayloadMode="" } }
  if(-not (HasProp $Obj "timestamp")){ return @{ Ok=$false; Reason="MISSING_REQUIRED_FIELD:timestamp"; Schema="clp.receipt.v1"; PayloadMode="" } }

  if((GetProp $Obj "receipt_type") -isnot [string]){ return @{ Ok=$false; Reason="INVALID_FIELD_TYPE:receipt_type"; Schema="clp.receipt.v1"; PayloadMode="" } }
  if((GetProp $Obj "for_claim") -isnot [string]){ return @{ Ok=$false; Reason="INVALID_FIELD_TYPE:for_claim"; Schema="clp.receipt.v1"; PayloadMode="" } }
  if((GetProp $Obj "timestamp") -isnot [string]){ return @{ Ok=$false; Reason="INVALID_FIELD_TYPE:timestamp"; Schema="clp.receipt.v1"; PayloadMode="" } }
  if(-not (IsJsonObjectValue (GetProp $Obj "result"))){ return @{ Ok=$false; Reason="INVALID_FIELD_TYPE:result"; Schema="clp.receipt.v1"; PayloadMode="" } }

  return @{ Ok=$true; Reason="OK"; Schema="clp.receipt.v1"; PayloadMode="" }
}

function Verify-Decision($Obj){
  if(-not (HasProp $Obj "decision_type")){ return @{ Ok=$false; Reason="MISSING_REQUIRED_FIELD:decision_type"; Schema="clp.decision.v1"; PayloadMode="" } }
  if(-not (HasProp $Obj "inputs")){ return @{ Ok=$false; Reason="MISSING_REQUIRED_FIELD:inputs"; Schema="clp.decision.v1"; PayloadMode="" } }
  if(-not (HasProp $Obj "result")){ return @{ Ok=$false; Reason="MISSING_REQUIRED_FIELD:result"; Schema="clp.decision.v1"; PayloadMode="" } }
  if(-not (HasProp $Obj "producer")){ return @{ Ok=$false; Reason="MISSING_REQUIRED_FIELD:producer"; Schema="clp.decision.v1"; PayloadMode="" } }
  if(-not (HasProp $Obj "timestamp")){ return @{ Ok=$false; Reason="MISSING_REQUIRED_FIELD:timestamp"; Schema="clp.decision.v1"; PayloadMode="" } }
  if(-not (HasProp $Obj "payload")){ return @{ Ok=$false; Reason="MISSING_REQUIRED_FIELD:payload"; Schema="clp.decision.v1"; PayloadMode="" } }

  if((GetProp $Obj "decision_type") -isnot [string]){ return @{ Ok=$false; Reason="INVALID_FIELD_TYPE:decision_type"; Schema="clp.decision.v1"; PayloadMode="" } }
  if((GetProp $Obj "producer") -isnot [string]){ return @{ Ok=$false; Reason="INVALID_FIELD_TYPE:producer"; Schema="clp.decision.v1"; PayloadMode="" } }
  if((GetProp $Obj "timestamp") -isnot [string]){ return @{ Ok=$false; Reason="INVALID_FIELD_TYPE:timestamp"; Schema="clp.decision.v1"; PayloadMode="" } }
  if(-not (IsJsonArrayValue (GetProp $Obj "inputs"))){ return @{ Ok=$false; Reason="INVALID_FIELD_TYPE:inputs"; Schema="clp.decision.v1"; PayloadMode="" } }
  if(-not (IsJsonObjectValue (GetProp $Obj "result"))){ return @{ Ok=$false; Reason="INVALID_FIELD_TYPE:result"; Schema="clp.decision.v1"; PayloadMode="" } }

  $pv = Validate-Payload (GetProp $Obj "payload")
  if([string]$pv.Token -ne "OK"){ return @{ Ok=$false; Reason=[string]$pv.Token; Schema="clp.decision.v1"; PayloadMode=[string]$pv.Mode } }

  return @{ Ok=$true; Reason="OK"; Schema="clp.decision.v1"; PayloadMode=[string]$pv.Mode }
}

EnsureLeaf $ObjectJsonPath
$raw = ReadTextUtf8NoBom $ObjectJsonPath

try {
  $parsed = $raw | ConvertFrom-Json
} catch {
  Emit-VerifyResult -Ok $false -ObjectSchema "" -ReasonToken "INVALID_JSON" -PayloadMode ""
  exit 0
}

if(-not (IsJsonObjectValue $parsed)){
  Emit-VerifyResult -Ok $false -ObjectSchema "" -ReasonToken "INVALID_TOP_LEVEL_TYPE" -PayloadMode ""
  exit 0
}

if(-not (HasProp $parsed "schema")){
  Emit-VerifyResult -Ok $false -ObjectSchema "" -ReasonToken "MISSING_REQUIRED_FIELD:schema" -PayloadMode ""
  exit 0
}

$schema = GetProp $parsed "schema"
if($schema -isnot [string]){
  Emit-VerifyResult -Ok $false -ObjectSchema "" -ReasonToken "INVALID_FIELD_TYPE:schema" -PayloadMode ""
  exit 0
}

$sv = [string]$schema
switch($sv){
  "clp.claim.v1" {
    $r = Verify-Claim $parsed
    Emit-VerifyResult -Ok ([bool]$r.Ok) -ObjectSchema ([string]$r.Schema) -ReasonToken ([string]$r.Reason) -PayloadMode ([string]$r.PayloadMode)
    exit 0
  }
  "clp.receipt.v1" {
    $r = Verify-Receipt $parsed
    Emit-VerifyResult -Ok ([bool]$r.Ok) -ObjectSchema ([string]$r.Schema) -ReasonToken ([string]$r.Reason) -PayloadMode ([string]$r.PayloadMode)
    exit 0
  }
  "clp.decision.v1" {
    $r = Verify-Decision $parsed
    Emit-VerifyResult -Ok ([bool]$r.Ok) -ObjectSchema ([string]$r.Schema) -ReasonToken ([string]$r.Reason) -PayloadMode ([string]$r.PayloadMode)
    exit 0
  }
  default {
    Emit-VerifyResult -Ok $false -ObjectSchema $sv -ReasonToken ("UNSUPPORTED_SCHEMA:" + $sv) -PayloadMode ""
    exit 0
  }
}