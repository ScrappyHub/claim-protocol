param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$ClaimJsonPath)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $RepoRoot "scripts\_lib_clp_v1.ps1")
$claim = ReadJson $ClaimJsonPath
$id = ClaimIdFromClaimObject $claim
Write-Output $id
