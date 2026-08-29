[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$LockPath,
    [Parameter(Mandatory)][string]$VerifiedOutputDirectory,
    [Int64]$ExpectedRepositoryId = 1144728715,
    [string]$ApiBaseUri = 'https://api.github.com',
    [scriptblock]$RequestInvoker,
    [scriptblock]$DownloadInvoker,
    [scriptblock]$SignatureInvoker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SupplyChain.Common.psm1') -Force

function Assert-LockedReleaseMetadata {
    param([object]$Release, [object]$Lock)
    $lockRelease = Get-XqProperty -Object $Lock -Name 'release' -Required
    if ([Int64](Get-XqProperty -Object $Release -Name 'id' -Required) -ne [Int64](Get-XqProperty -Object $lockRelease -Name 'releaseId' -Required)) { throw 'Release ID differs from the approved lock.' }
    if ([string](Get-XqProperty -Object $Release -Name 'tag_name' -Required) -cne [string](Get-XqProperty -Object $lockRelease -Name 'tag' -Required)) { throw 'Release tag differs from the approved lock.' }
    $releasePublished = ConvertTo-XqUtcTimestamp -Value (Get-XqProperty -Object $Release -Name 'published_at' -Required)
    $lockedPublished = ConvertTo-XqUtcTimestamp -Value (Get-XqProperty -Object $lockRelease -Name 'publishedAtUtc' -Required)
    if ($releasePublished -cne $lockedPublished) { throw 'Release publication time differs from the approved lock.' }
    if ([bool](Get-XqProperty -Object $Release -Name 'draft' -Required) -or [bool](Get-XqProperty -Object $Release -Name 'prerelease' -Required)) { throw 'Locked release is no longer a stable release.' }
    $installerAsset = Get-XqReleaseAsset -Release $Release -ExactName 'OpenClawCompanion-Setup-x64.exe'
    $installerLock = Get-XqProperty -Object $Lock -Name 'installer' -Required
    if ([Int64](Get-XqProperty -Object $installerAsset -Name 'id' -Required) -ne [Int64](Get-XqProperty -Object $installerLock -Name 'assetId' -Required)) { throw 'Installer asset ID differs from the approved lock.' }
    if ([Int64](Get-XqProperty -Object $installerAsset -Name 'size' -Required) -ne [Int64](Get-XqProperty -Object $installerLock -Name 'size' -Required)) { throw 'Installer asset size differs from the approved lock.' }
    Assert-XqSha256 -Actual (Get-XqAssetDigestSha256 -Asset $installerAsset) -Expected ([string](Get-XqProperty -Object $installerLock -Name 'officialDigestSha256' -Required)) -Label 'Release asset digest'
    return [pscustomobject]@{ Installer = $installerAsset }
}

try {
    $outputFullPath = [IO.Path]::GetFullPath($VerifiedOutputDirectory)
    if (Test-Path -LiteralPath $outputFullPath) { throw 'Verified output directory already exists; refusing to reuse any cache or prior output.' }
    $lock = Get-Content -LiteralPath $LockPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    Assert-XqApprovedLock -Lock $lock
    $trusted = Get-XqTrustedRepository
    if ($ExpectedRepositoryId -ne [Int64]$trusted.RepositoryId) { throw 'Configured repository ID does not match the fixed trusted repository ID.' }
    $api = $ApiBaseUri.TrimEnd('/')
    $repo = Invoke-XqGitHubJson -Uri "$api/repos/$($trusted.Owner)/$($trusted.Name)" -RequestInvoker $RequestInvoker
    Assert-XqTrustedRepository -Repository ([pscustomobject]@{
        owner = Get-XqProperty -Object (Get-XqProperty -Object $repo -Name 'owner' -Required) -Name 'login' -Required
        name = Get-XqProperty -Object $repo -Name 'name' -Required
        id = Get-XqProperty -Object $repo -Name 'id' -Required
    })
    $releaseId = [Int64](Get-XqProperty -Object (Get-XqProperty -Object $lock -Name 'release' -Required) -Name 'releaseId' -Required)
    $release = Invoke-XqGitHubJson -Uri "$api/repos/$($trusted.Owner)/$($trusted.Name)/releases/$releaseId" -RequestInvoker $RequestInvoker
    $assets = Assert-LockedReleaseMetadata -Release $release -Lock $lock
    $sourceFiles = Get-XqProperty -Object $lock -Name 'sourceFiles' -Required
    $commitSha = [string](Get-XqProperty -Object $sourceFiles -Name 'commitSha' -Required)
    $lockedTag = [string](Get-XqProperty -Object (Get-XqProperty -Object $lock -Name 'release' -Required) -Name 'tag' -Required)
    $tagCommit = Invoke-XqGitHubJson -Uri "$api/repos/$($trusted.Owner)/$($trusted.Name)/commits/$([uri]::EscapeDataString($lockedTag))" -RequestInvoker $RequestInvoker
    if ([string](Get-XqProperty -Object $tagCommit -Name 'sha' -Required) -cne $commitSha) { throw 'Release tag no longer resolves to the approved source commit.' }

    $stage = Join-Path ([IO.Path]::GetTempPath()) ("xq-openclaw-verified-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    try {
        $installerPart = Join-Path $stage 'OpenClawCompanion-Setup-x64.exe.part'
        Invoke-XqOfficialAssetDownload -AssetId ([Int64](Get-XqProperty -Object $assets.Installer -Name 'id' -Required)) -DestinationPath $installerPart -ApiBaseUri $api -DownloadInvoker $DownloadInvoker
        $artifactVerification = & (Join-Path $PSScriptRoot 'Verify-OfficialArtifact.ps1') -LockPath $LockPath -InstallerPath $installerPart -SignatureInvoker $SignatureInvoker
        if ($null -eq $artifactVerification) { throw 'Artifact verifier did not report success.' }

        $licensePart = Join-Path $stage 'LICENSE.part'
        $noticesPart = Join-Path $stage 'THIRD_PARTY_NOTICES.md.part'
        [IO.File]::WriteAllBytes($licensePart, (Get-XqSourceContent -CommitSha $commitSha -Path 'LICENSE' -ApiBaseUri $api -RequestInvoker $RequestInvoker))
        [IO.File]::WriteAllBytes($noticesPart, (Get-XqSourceContent -CommitSha $commitSha -Path 'src/OpenClaw.Tray.WinUI/THIRD_PARTY_NOTICES.md' -ApiBaseUri $api -RequestInvoker $RequestInvoker))
        Assert-XqSha256 -Actual (Get-XqSha256 -Path $licensePart) -Expected ([string](Get-XqProperty -Object $sourceFiles -Name 'licenseSha256' -Required)) -Label 'LICENSE'
        Assert-XqSha256 -Actual (Get-XqSha256 -Path $noticesPart) -Expected ([string](Get-XqProperty -Object $sourceFiles -Name 'thirdPartyNoticesSha256' -Required)) -Label 'THIRD_PARTY_NOTICES'

        Move-Item -LiteralPath $installerPart -Destination (Join-Path $stage 'OpenClawCompanion-Setup-x64.exe')
        Move-Item -LiteralPath $licensePart -Destination (Join-Path $stage 'LICENSE')
        Move-Item -LiteralPath $noticesPart -Destination (Join-Path $stage 'THIRD_PARTY_NOTICES.md')
        $result = [ordered]@{
            schemaVersion = 1
            status = 'verified'
            verifiedAtUtc = [DateTime]::UtcNow.ToString('o')
            repository = [ordered]@{ owner = $trusted.Owner; name = $trusted.Name; repositoryId = $trusted.RepositoryId }
            release = Get-XqProperty -Object $lock -Name 'release' -Required
            installer = $artifactVerification
            sourceFiles = [ordered]@{ commitSha = $commitSha; licenseSha256 = Get-XqSha256 -Path (Join-Path $stage 'LICENSE'); thirdPartyNoticesSha256 = Get-XqSha256 -Path (Join-Path $stage 'THIRD_PARTY_NOTICES.md') }
        }
        [IO.File]::WriteAllText((Join-Path $stage 'verification-result.json'), ($result | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
        $outputParent = Split-Path -Parent $outputFullPath
        if (-not [string]::IsNullOrWhiteSpace($outputParent)) { New-Item -ItemType Directory -Path $outputParent -Force | Out-Null }
        Move-Item -LiteralPath $stage -Destination $outputFullPath -ErrorAction Stop
        $stage = $null
        Write-Information -Tags 'XqSupplyChain' -MessageData ([pscustomobject]@{ stage = 'M2'; status = 'verified-output-created'; outputDirectory = $outputFullPath })
    }
    finally {
        if ($null -ne $stage -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
catch {
    Write-Information -Tags 'XqSupplyChain' -MessageData ([pscustomobject]@{ stage = 'M2'; status = 'rejected'; errorCode = 'locked-fetch-or-verification-failed' })
    throw 'Locked artifact fetch and verification failed. No verified output was produced.'
}
