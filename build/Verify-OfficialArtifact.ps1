[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$LockPath,
    [Parameter(Mandatory)][string]$InstallerPath,
    [scriptblock]$SignatureInvoker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SupplyChain.Common.psm1') -Force

try {
    $lock = Get-Content -LiteralPath $LockPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    Assert-XqApprovedLock -Lock $lock
    $installerLock = Get-XqProperty -Object $lock -Name 'installer' -Required
    if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) { throw 'Installer input is missing.' }
    if ((Get-Item -LiteralPath $InstallerPath).Length -ne [Int64](Get-XqProperty -Object $installerLock -Name 'size' -Required)) {
        throw 'Installer size does not match the approved lock.'
    }
    $localInstallerHash = Get-XqSha256 -Path $InstallerPath
    Assert-XqSha256 -Actual $localInstallerHash -Expected ([string](Get-XqProperty -Object $installerLock -Name 'sha256' -Required)) -Label 'Installer lock'
    Assert-XqSha256 -Actual $localInstallerHash -Expected ([string](Get-XqProperty -Object $installerLock -Name 'officialDigestSha256' -Required)) -Label 'Official GitHub asset digest'
    $signature = Get-XqSignatureSummary -Path $InstallerPath -SignatureInvoker $SignatureInvoker
    Assert-XqSignature -Signature $signature -InstallerLock $installerLock
    $verification = [pscustomobject]@{
        installerSha256 = $localInstallerHash
        officialDigestSha256 = [string](Get-XqProperty -Object $installerLock -Name 'officialDigestSha256' -Required)
        authenticode = [ordered]@{
            status = [string](Get-XqProperty -Object $signature -Name 'Status' -Required)
            signerSubject = [string](Get-XqProperty -Object $signature -Name 'SignerSubject' -Required)
            signerThumbprint = [string](Get-XqProperty -Object $signature -Name 'SignerThumbprint' -Required)
            timestampPresent = [bool](Get-XqProperty -Object $signature -Name 'TimestampPresent' -Required)
        }
    }
    Write-Information -Tags 'XqSupplyChain' -MessageData ([pscustomobject]@{ stage = 'M2'; status = 'artifact-verified'; installerSha256 = $localInstallerHash })
    $verification
}
catch {
    Write-Information -Tags 'XqSupplyChain' -MessageData ([pscustomobject]@{ stage = 'M2'; status = 'rejected'; errorCode = 'official-artifact-verification-failed' })
    throw 'Official artifact verification failed.'
}
