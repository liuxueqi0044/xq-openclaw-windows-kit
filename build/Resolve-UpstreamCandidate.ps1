[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CandidateOutputPath,
    [Int64]$ExpectedRepositoryId = 1103012935,
    [string]$ApiBaseUri = 'https://api.github.com',
    [scriptblock]$RequestInvoker,
    [scriptblock]$DownloadInvoker,
    [scriptblock]$SignatureInvoker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SupplyChain.Common.psm1') -Force
$partialOutput = $null

function Get-FirstStableRelease {
    param([object[]]$Releases)
    $stable = @($Releases | Where-Object {
        -not [bool](Get-XqProperty -Object $_ -Name 'draft' -Required) -and
        -not [bool](Get-XqProperty -Object $_ -Name 'prerelease' -Required)
    })
    if ($stable.Count -eq 0) { throw 'No stable GitHub release was returned.' }
    return $stable[0]
}

try {
    $trusted = Get-XqTrustedRepository
    if ($ExpectedRepositoryId -ne [Int64]$trusted.RepositoryId) { throw 'Configured repository ID does not match the fixed trusted repository ID.' }
    $outputFullPath = [IO.Path]::GetFullPath($CandidateOutputPath)
    if ([string]::Equals([IO.Path]::GetFileName($outputFullPath), 'upstream-lock.json', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Candidate resolution is not allowed to write upstream-lock.json.'
    }
    $api = $ApiBaseUri.TrimEnd('/')
    $repo = Invoke-XqGitHubJson -Uri "$api/repos/$($trusted.Owner)/$($trusted.Name)" -RequestInvoker $RequestInvoker
    Assert-XqTrustedRepository -Repository ([pscustomobject]@{
        owner = Get-XqProperty -Object $repo -Name 'owner' -Required | ForEach-Object { Get-XqProperty -Object $_ -Name 'login' -Required }
        name = Get-XqProperty -Object $repo -Name 'name' -Required
        id = Get-XqProperty -Object $repo -Name 'id' -Required
    })

    $releasesResponse = Invoke-XqGitHubJson -Uri "$api/repos/$($trusted.Owner)/$($trusted.Name)/releases?per_page=100" -RequestInvoker $RequestInvoker
    $release = Get-FirstStableRelease -Releases @($releasesResponse)
    $releaseId = [Int64](Get-XqProperty -Object $release -Name 'id' -Required)
    $tag = [string](Get-XqProperty -Object $release -Name 'tag_name' -Required)
    if ($releaseId -le 0 -or [string]::IsNullOrWhiteSpace($tag)) { throw 'Stable release id or tag is invalid.' }
    $installerAsset = Get-XqReleaseAsset -Release $release -ExactName 'OpenClawCompanion-Setup-x64.exe'
    $checksumAsset = Get-XqReleaseAsset -Release $release -ExactName 'OpenClawCompanion-SHA256SUMS.txt'

    $commitResponse = Invoke-XqGitHubJson -Uri "$api/repos/$($trusted.Owner)/$($trusted.Name)/commits/$([uri]::EscapeDataString($tag))" -RequestInvoker $RequestInvoker
    $commitSha = [string](Get-XqProperty -Object $commitResponse -Name 'sha' -Required)
    if ($commitSha -notmatch '^[A-Fa-f0-9]{40}$') { throw 'Release tag did not resolve to a full commit SHA.' }

    $work = Join-Path ([IO.Path]::GetTempPath()) ("xq-openclaw-candidate-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $installerPart = Join-Path $work 'installer.part'
        $checksumPart = Join-Path $work 'checksums.part'
        Invoke-XqOfficialAssetDownload -AssetId ([Int64](Get-XqProperty -Object $installerAsset -Name 'id' -Required)) -DestinationPath $installerPart -ApiBaseUri $api -DownloadInvoker $DownloadInvoker
        Invoke-XqOfficialAssetDownload -AssetId ([Int64](Get-XqProperty -Object $checksumAsset -Name 'id' -Required)) -DestinationPath $checksumPart -ApiBaseUri $api -DownloadInvoker $DownloadInvoker
        if ((Get-Item -LiteralPath $installerPart).Length -ne [Int64](Get-XqProperty -Object $installerAsset -Name 'size' -Required)) { throw 'Downloaded installer size differs from the release metadata.' }
        if ((Get-Item -LiteralPath $checksumPart).Length -ne [Int64](Get-XqProperty -Object $checksumAsset -Name 'size' -Required)) { throw 'Downloaded checksum size differs from the release metadata.' }
        $officialInstallerHash = Get-XqChecksumEntry -ChecksumPath $checksumPart -AssetName 'OpenClawCompanion-Setup-x64.exe'
        $observedInstallerHash = Get-XqSha256 -Path $installerPart
        if ($officialInstallerHash -cne $observedInstallerHash) { throw 'Candidate installer does not match the official checksum asset.' }
        $signature = Get-XqSignatureSummary -Path $installerPart -SignatureInvoker $SignatureInvoker
        Assert-XqCandidateSignature -Signature $signature
        $licenseBytes = Get-XqSourceContent -CommitSha $commitSha -Path 'LICENSE' -ApiBaseUri $api -RequestInvoker $RequestInvoker
        $noticeBytes = Get-XqSourceContent -CommitSha $commitSha -Path 'THIRD_PARTY_NOTICES.md' -ApiBaseUri $api -RequestInvoker $RequestInvoker
        $licensePath = Join-Path $work 'LICENSE'
        $noticePath = Join-Path $work 'THIRD_PARTY_NOTICES.md'
        [IO.File]::WriteAllBytes($licensePath, $licenseBytes)
        [IO.File]::WriteAllBytes($noticePath, $noticeBytes)

        $candidate = [ordered]@{
            schemaVersion = 1
            repository = [ordered]@{ owner = $trusted.Owner; name = $trusted.Name; repositoryId = $trusted.RepositoryId }
            release = [ordered]@{
                tag = $tag
                releaseId = $releaseId
                draft = $false
                prerelease = $false
                publishedAtUtc = [string](Get-XqProperty -Object $release -Name 'published_at' -Required)
                htmlUrl = [string](Get-XqProperty -Object $release -Name 'html_url' -Required)
            }
            installer = [ordered]@{
                assetId = [Int64](Get-XqProperty -Object $installerAsset -Name 'id' -Required)
                name = 'OpenClawCompanion-Setup-x64.exe'
                size = [Int64](Get-XqProperty -Object $installerAsset -Name 'size' -Required)
                sha256 = $officialInstallerHash
                observedSha256 = $observedInstallerHash
                signerSubject = [string](Get-XqProperty -Object $signature -Name 'SignerSubject' -Required)
                signerThumbprint = [string](Get-XqProperty -Object $signature -Name 'SignerThumbprint' -Required)
                authenticodeStatus = [string](Get-XqProperty -Object $signature -Name 'Status' -Required)
                timestampPresent = [bool](Get-XqProperty -Object $signature -Name 'TimestampPresent' -Required)
                timestampRequired = $true
            }
            checksumAsset = [ordered]@{
                assetId = [Int64](Get-XqProperty -Object $checksumAsset -Name 'id' -Required)
                name = 'OpenClawCompanion-SHA256SUMS.txt'
                sha256 = Get-XqSha256 -Path $checksumPart
            }
            sourceFiles = [ordered]@{
                commitSha = $commitSha.ToLowerInvariant()
                licenseSha256 = Get-XqSha256 -Path $licensePath
                thirdPartyNoticesSha256 = Get-XqSha256 -Path $noticePath
            }
            approval = [ordered]@{ status = 'pending-human-review'; approvedAtUtc = $null; approvedBy = $null }
        }
        $outputParent = Split-Path -Parent $outputFullPath
        if (-not [string]::IsNullOrWhiteSpace($outputParent)) { New-Item -ItemType Directory -Path $outputParent -Force | Out-Null }
        $partialOutput = "$outputFullPath.$([guid]::NewGuid().ToString('N')).partial"
        [IO.File]::WriteAllText($partialOutput, ($candidate | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $partialOutput -Destination $outputFullPath -Force
        Write-Information -Tags 'XqSupplyChain' -MessageData ([pscustomobject]@{ stage = 'M1'; status = 'candidate-resolved'; releaseId = $releaseId; candidatePath = $outputFullPath })
    }
    finally {
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
catch {
    if ($null -ne $partialOutput -and (Test-Path -LiteralPath $partialOutput)) {
        Remove-Item -LiteralPath $partialOutput -Force -ErrorAction SilentlyContinue
    }
    Write-Information -Tags 'XqSupplyChain' -MessageData ([pscustomobject]@{ stage = 'M1'; status = 'rejected'; errorCode = 'candidate-resolution-failed' })
    throw 'Candidate resolution failed. No approved upstream lock was modified.'
}
