param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$ReceiptJsonPath)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $RepoRoot "scripts\_lib_clp_v1.ps1")
$rcpt = ReadJson $ReceiptJsonPath
$id = ReceiptIdFromReceiptObject $rcpt
Write-Output $id
