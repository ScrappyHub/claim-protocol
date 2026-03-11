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
  Die ("MISSING_RESULT_FIELD: " + $Name)
}

function QuoteArg([string]$s){
  if($null -eq $s){ return '""' }
  if($s -match '[\s"`]'){
    return '"' + ($s -replace '"','\"') + '"'
  }
  return $s
}

function RunChildCapture([string]$PSExe,[string]$ScriptPath,[string[]]$ArgList){
  EnsureLeaf $PSExe
  EnsureLeaf $ScriptPath

  $full = New-Object System.Collections.Generic.List[string]
  [void]$full.Add('-NoProfile')
  [void]$full.Add('-NonInteractive')
  [void]$full.Add('-ExecutionPolicy')
  [void]$full.Add('Bypass')
  [void]$full.Add('-File')
  [void]$full.Add($ScriptPath)

  foreach($a in @($ArgList)){
    [void]$full.Add([string]$a)
  }

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $PSExe
  $psi.Arguments = (@($full.ToArray()) | ForEach-Object { QuoteArg $_ }) -join ' '
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true

  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  if(-not $p.Start()){ Die ("CHILD_START_FAIL: " + $ScriptPath) }

  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  $code = [int]$p.ExitCode
  $p.Dispose()

  return @{ ExitCode=$code; Stdout=$stdout; Stderr=$stderr }
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  Die ("MISSING_REPOROOT: " + $RepoRoot)
}

$PSExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$Runner = Join-Path $RepoRoot "scripts\clp_verify_object_v1.ps1"
ParseGateFile $Runner

$Base = Join-Path $RepoRoot "test_vectors\verifier"

$Vectors = @(
  @{ Name="positive_claim_valid"; ExpectedOk=$true; ExpectedReason="OK" },
  @{ Name="positive_receipt_valid"; ExpectedOk=$true; ExpectedReason="OK" },
  @{ Name="positive_decision_valid"; ExpectedOk=$true; ExpectedReason="OK" },
  @{ Name="positive_blob_ref_metadata_valid"; ExpectedOk=$true; ExpectedReason="OK" },
  @{ Name="negative_missing_schema"; ExpectedOk=$false; ExpectedReason="MISSING_REQUIRED_FIELD:schema" },
  @{ Name="negative_bad_payload_mode"; ExpectedOk=$false; ExpectedReason="INVALID_PAYLOAD_MODE" },
  @{ Name="negative_blob_ref_missing_digest"; ExpectedOk=$false; ExpectedReason="MISSING_REQUIRED_FIELD:digest" },
  @{ Name="negative_decision_inputs_not_array"; ExpectedOk=$false; ExpectedReason="INVALID_FIELD_TYPE:inputs" },
  @{ Name="negative_unsupported_schema"; ExpectedOk=$false; ExpectedReason="UNSUPPORTED_SCHEMA:clp.unknown.v1" },
  @{ Name="negative_top_level_not_object"; ExpectedOk=$false; ExpectedReason="INVALID_TOP_LEVEL_TYPE" }
)

$Pass = 0
$Fail = 0

foreach($v in @($Vectors)){
  $name = [string]$v.Name
  $expectedOk = [bool]$v.ExpectedOk
  $expectedReason = [string]$v.ExpectedReason
  $objPath = Join-Path (Join-Path $Base $name) "object.json"

  $r = RunChildCapture $PSExe $Runner @('-RepoRoot',$RepoRoot,'-ObjectJsonPath',$objPath)
  if($r.ExitCode -ne 0){
    $Fail++
    Write-Host ("FAIL: " + $name + " => VERIFY_EXIT_" + $r.ExitCode) -ForegroundColor Red
    continue
  }

  $out = ($r.Stdout -replace "`r","").Trim()
  if([string]::IsNullOrWhiteSpace($out)){
    $Fail++
    Write-Host ("FAIL: " + $name + " => EMPTY_OUTPUT") -ForegroundColor Red
    continue
  }

  $obj = $out | ConvertFrom-Json
  if($null -eq $obj){
    $Fail++
    Write-Host ("FAIL: " + $name + " => INVALID_RESULT_JSON") -ForegroundColor Red
    continue
  }

  if(-not (HasProp $obj "ok")){
    $Fail++
    Write-Host ("FAIL: " + $name + " => MISSING_RESULT_OK") -ForegroundColor Red
    continue
  }

  if(-not (HasProp $obj "reason_token")){
    $Fail++
    Write-Host ("FAIL: " + $name + " => MISSING_RESULT_REASON") -ForegroundColor Red
    continue
  }

  $ok = [bool](GetProp $obj "ok")
  $reason = [string](GetProp $obj "reason_token")

  if($ok -ne $expectedOk){
    $Fail++
    Write-Host ("FAIL: " + $name + " => OK_MISMATCH got=" + $ok + " expected=" + $expectedOk) -ForegroundColor Red
    continue
  }

  if($reason -ne $expectedReason){
    $Fail++
    Write-Host ("FAIL: " + $name + " => REASON_MISMATCH got=" + $reason + " expected=" + $expectedReason) -ForegroundColor Red
    continue
  }

  $Pass++
  Write-Host ("PASS: " + $name) -ForegroundColor Green
}

if($Fail -ne 0){
  Die ("VERIFIER_VECTORS_FAIL: pass=" + $Pass + " fail=" + $Fail)
}

Write-Host ("VERIFIER_VECTORS_OK: pass=" + $Pass + " fail=" + $Fail) -ForegroundColor Green
