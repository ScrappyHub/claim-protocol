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

function ReadJsonObjectNoDepth([string]$Path){
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

function Validate-ClaimObject($Obj){
  if(-not (HasProp $Obj "schema")){ return "MISSING_REQUIRED_FIELD:schema" }
  $schema = [string](GetProp $Obj "schema")
  if($schema -ne "clp.claim.v1"){ return ("INVALID_SCHEMA:" + $schema) }

  if(-not (HasProp $Obj "claim_type")){ return "MISSING_REQUIRED_FIELD:claim_type" }
  if(-not (HasProp $Obj "producer")){ return "MISSING_REQUIRED_FIELD:producer" }
  if(-not (HasProp $Obj "timestamp")){ return "MISSING_REQUIRED_FIELD:timestamp" }
  if(-not (HasProp $Obj "payload")){ return "MISSING_REQUIRED_FIELD:payload" }

  if((GetProp $Obj "claim_type") -isnot [string]){ return "INVALID_FIELD_TYPE:claim_type" }
  if((GetProp $Obj "producer") -isnot [string]){ return "INVALID_FIELD_TYPE:producer" }
  if((GetProp $Obj "timestamp") -isnot [string]){ return "INVALID_FIELD_TYPE:timestamp" }

  $payload = GetProp $Obj "payload"
  if(-not (IsJsonObjectValue $payload)){ return "INVALID_FIELD_TYPE:payload" }

  return "OK"
}

function Validate-ReceiptObject($Obj){
  if(-not (HasProp $Obj "schema")){ return "MISSING_REQUIRED_FIELD:schema" }
  $schema = [string](GetProp $Obj "schema")
  if($schema -ne "clp.receipt.v1"){ return ("INVALID_SCHEMA:" + $schema) }

  if(-not (HasProp $Obj "receipt_type")){ return "MISSING_REQUIRED_FIELD:receipt_type" }
  if(-not (HasProp $Obj "for_claim")){ return "MISSING_REQUIRED_FIELD:for_claim" }
  if(-not (HasProp $Obj "result")){ return "MISSING_REQUIRED_FIELD:result" }
  if(-not (HasProp $Obj "timestamp")){ return "MISSING_REQUIRED_FIELD:timestamp" }

  if((GetProp $Obj "receipt_type") -isnot [string]){ return "INVALID_FIELD_TYPE:receipt_type" }
  if((GetProp $Obj "for_claim") -isnot [string]){ return "INVALID_FIELD_TYPE:for_claim" }
  if((GetProp $Obj "timestamp") -isnot [string]){ return "INVALID_FIELD_TYPE:timestamp" }

  $result = GetProp $Obj "result"
  if(-not (IsJsonObjectValue $result)){ return "INVALID_FIELD_TYPE:result" }

  return "OK"
}

function Validate-DecisionObject($Obj){
  if(-not (HasProp $Obj "schema")){ return "MISSING_REQUIRED_FIELD:schema" }
  $schema = [string](GetProp $Obj "schema")
  if($schema -ne "clp.decision.v1"){ return ("INVALID_SCHEMA:" + $schema) }

  if(-not (HasProp $Obj "decision_type")){ return "MISSING_REQUIRED_FIELD:decision_type" }
  if(-not (HasProp $Obj "inputs")){ return "MISSING_REQUIRED_FIELD:inputs" }
  if(-not (HasProp $Obj "result")){ return "MISSING_REQUIRED_FIELD:result" }
  if(-not (HasProp $Obj "producer")){ return "MISSING_REQUIRED_FIELD:producer" }
  if(-not (HasProp $Obj "timestamp")){ return "MISSING_REQUIRED_FIELD:timestamp" }
  if(-not (HasProp $Obj "payload")){ return "MISSING_REQUIRED_FIELD:payload" }

  if((GetProp $Obj "decision_type") -isnot [string]){ return "INVALID_FIELD_TYPE:decision_type" }
  if((GetProp $Obj "producer") -isnot [string]){ return "INVALID_FIELD_TYPE:producer" }
  if((GetProp $Obj "timestamp") -isnot [string]){ return "INVALID_FIELD_TYPE:timestamp" }

  $inputs = GetProp $Obj "inputs"
  if(-not (IsJsonArrayValue $inputs)){ return "INVALID_FIELD_TYPE:inputs" }

  $result = GetProp $Obj "result"
  if(-not (IsJsonObjectValue $result)){ return "INVALID_FIELD_TYPE:result" }

  $payload = GetProp $Obj "payload"
  if(-not (IsJsonObjectValue $payload)){ return "INVALID_FIELD_TYPE:payload" }

  return "OK"
}

function Validate-ObjectLawVector([string]$VectorDir,[string]$ExpectedMode,[string]$ExpectedTokenPrefix){
  $objPath = Join-Path $VectorDir "object.json"
  EnsureLeaf $objPath

  $raw = ReadTextUtf8NoBom $objPath
  $parsed = $raw | ConvertFrom-Json

  if($null -eq $parsed){
    if($ExpectedMode -eq "negative" -and $ExpectedTokenPrefix -eq "INVALID_JSON"){
      return "PASS"
    }
    return "FAIL:INVALID_JSON"
  }

  if(-not (IsJsonObjectValue $parsed)){
    $token = "INVALID_TOP_LEVEL_TYPE"
    if($ExpectedMode -eq "negative" -and $ExpectedTokenPrefix -eq $token){
      return "PASS"
    }
    return ("FAIL:" + $token)
  }

  if(-not (HasProp $parsed "schema")){
    $token = "MISSING_REQUIRED_FIELD:schema"
    if($ExpectedMode -eq "negative" -and $ExpectedTokenPrefix -eq $token){
      return "PASS"
    }
    return ("FAIL:" + $token)
  }

  $schema = [string](GetProp $parsed "schema")
  $token = ""
  if($schema -eq "clp.claim.v1"){
    $token = Validate-ClaimObject $parsed
  }
  elseif($schema -eq "clp.receipt.v1"){
    $token = Validate-ReceiptObject $parsed
  }
  elseif($schema -eq "clp.decision.v1"){
    $token = Validate-DecisionObject $parsed
  }
  else {
    $token = ("INVALID_SCHEMA:" + $schema)
  }

  if($ExpectedMode -eq "positive"){
    if($token -eq "OK"){
      return "PASS"
    }
    return ("FAIL:" + $token)
  }

  if($ExpectedMode -eq "negative"){
    if($token.StartsWith($ExpectedTokenPrefix,[System.StringComparison]::Ordinal)){
      return "PASS"
    }
    return ("FAIL:" + $token)
  }

  return "FAIL:BAD_EXPECTED_MODE"
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  Die ("MISSING_REPOROOT: " + $RepoRoot)
}

$SelfPath = $PSCommandPath
ParseGateFile $SelfPath

$Base = Join-Path $RepoRoot "test_vectors\object_law"

$Vectors = @(
  @{ Name="positive_claim_minimal"; ExpectedMode="positive"; ExpectedTokenPrefix="OK" },
  @{ Name="positive_receipt_minimal"; ExpectedMode="positive"; ExpectedTokenPrefix="OK" },
  @{ Name="positive_decision_minimal"; ExpectedMode="positive"; ExpectedTokenPrefix="OK" },
  @{ Name="negative_missing_schema"; ExpectedMode="negative"; ExpectedTokenPrefix="MISSING_REQUIRED_FIELD:schema" },
  @{ Name="negative_claim_payload_not_object"; ExpectedMode="negative"; ExpectedTokenPrefix="INVALID_FIELD_TYPE:payload" },
  @{ Name="negative_decision_inputs_not_array"; ExpectedMode="negative"; ExpectedTokenPrefix="INVALID_FIELD_TYPE:inputs" }
)

$Pass = 0
$Fail = 0
$Results = New-Object System.Collections.Generic.List[string]

foreach($v in @($Vectors)){
  $name = [string]$v.Name
  $mode = [string]$v.ExpectedMode
  $prefix = [string]$v.ExpectedTokenPrefix
  $dir = Join-Path $Base $name

  $r = Validate-ObjectLawVector -VectorDir $dir -ExpectedMode $mode -ExpectedTokenPrefix $prefix
  if($r -eq "PASS"){
    $Pass++
    $line = ("PASS: " + $name)
    [void]$Results.Add($line)
    Write-Host $line -ForegroundColor Green
  }
  else {
    $Fail++
    $line = ($name + " => " + $r)
    [void]$Results.Add($line)
    Write-Host ("FAIL: " + $line) -ForegroundColor Red
  }
}

if($Fail -ne 0){
  Die ("OBJECT_LAW_VECTORS_FAIL: pass=" + $Pass + " fail=" + $Fail)
}

Write-Host ("OBJECT_LAW_VECTORS_OK: pass=" + $Pass + " fail=" + $Fail) -ForegroundColor Green