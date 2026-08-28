Set-StrictMode -Version Latest

$script:TrustedRepository = [ordered]@{
    Owner = 'openclaw'
    Name = 'openclaw'
    RepositoryId = [Int64]1103012935
}
$script:InstallerAssetName = 'OpenClawCompanion-Setup-x64.exe'
$script:ChecksumAssetName = 'OpenClawCompanion-SHA256SUMS.txt'
$script:AllowedDownloadHosts = @(
    'api.github.com', 'github.com', 'objects.githubusercontent.com',
    'github-releases.githubusercontent.com', 'release-assets.githubusercontent.com',
    'objects-origin.githubusercontent.com'
)

function Get-XqTrustedRepository {
    [CmdletBinding()]
    param()
    return [pscustomobject]$script:TrustedRepository
}

function Get-XqProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        [switch]$Required
    )

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
    }
    elseif ($null -ne $Object.PSObject.Properties[$Name]) {
        return $Object.PSObject.Properties[$Name].Value
    }
    if ($Required) { throw "Required property '$Name' is missing." }
    return $null
}

function Assert-XqTrustedRepository {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Repository)

    $owner = [string](Get-XqProperty -Object $Repository -Name 'owner' -Required)
    $name = [string](Get-XqProperty -Object $Repository -Name 'name' -Required)
    $id = [Int64](Get-XqProperty -Object $Repository -Name 'id' -Required)
    if ($owner -cne $script:TrustedRepository.Owner -or $name -cne $script:TrustedRepository.Name -or $id -ne $script:TrustedRepository.RepositoryId) {
        throw 'Repository identity does not match the fixed trusted repository.'
    }
}

function New-XqGitHubHeaders {
    [CmdletBinding()]
    param([string]$Accept = 'application/vnd.github+json')

    $headers = @{ Accept = $Accept; 'User-Agent' = 'xq-openclaw-windows-kit' }
    # The token is deliberately never written to host, verbose output, errors, or URLs.
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        $headers.Authorization = "Bearer $($env:GITHUB_TOKEN)"
    }
    return $headers
}

function Assert-XqOfficialApiUri {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Uri)
    try { $parsed = [uri]$Uri } catch { throw 'GitHub API URI is invalid.' }
    if ($parsed.Scheme -cne 'https' -or $parsed.Host -cne 'api.github.com' -or -not $parsed.IsDefaultPort -or -not [string]::IsNullOrEmpty($parsed.UserInfo)) {
        throw 'Real GitHub API requests must use HTTPS api.github.com with no userinfo and the default port.'
    }
}

function Invoke-XqGitHubJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [scriptblock]$RequestInvoker
    )

    if ($null -ne $RequestInvoker) {
        return & $RequestInvoker $Uri (New-XqGitHubHeaders)
    }
    Assert-XqOfficialApiUri -Uri $Uri
    return Invoke-RestMethod -Uri $Uri -Headers (New-XqGitHubHeaders) -Method Get -ErrorAction Stop
}

function Get-XqReleaseAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Release,
        [Parameter(Mandatory)][string]$ExactName
    )

    $assets = @(Get-XqProperty -Object $Release -Name 'assets' -Required)
    $matches = @($assets | Where-Object { [string](Get-XqProperty -Object $_ -Name 'name' -Required) -ceq $ExactName })
    if ($matches.Count -ne 1) {
        throw "Release must contain exactly one asset named '$ExactName'."
    }
    $asset = $matches[0]
    $size = [Int64](Get-XqProperty -Object $asset -Name 'size' -Required)
    $assetId = [Int64](Get-XqProperty -Object $asset -Name 'id' -Required)
    if ($size -le 0 -or $assetId -le 0) { throw "Release asset '$ExactName' has an invalid id or size." }
    return $asset
}

function Get-XqSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'File to hash was not found.' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
}

function Assert-XqSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Actual,
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][string]$Label
    )
    if ($Expected -notmatch '^[A-Fa-f0-9]{64}$') { throw "$Label expected SHA-256 is invalid." }
    if ($Actual -cne $Expected.ToUpperInvariant()) { throw "$Label SHA-256 mismatch." }
}

function Get-XqChecksumEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ChecksumPath,
        [Parameter(Mandatory)][string]$AssetName
    )

    $checksumMatches = @()
    foreach ($line in (Get-Content -LiteralPath $ChecksumPath -ErrorAction Stop)) {
        if ($line -match '^\s*([A-Fa-f0-9]{64})\s+\*?(.+?)\s*$') {
            if ($Matches[2] -ceq $AssetName) { $checksumMatches += $Matches[1].ToUpperInvariant() }
        }
    }
    if ($checksumMatches.Count -ne 1) { throw "Checksum file must contain exactly one checksum for '$AssetName'." }
    return $checksumMatches[0]
}

function Assert-XqDownloadUri {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Uri)
    $parsed = [uri]$Uri
    if ($parsed.Scheme -ne 'https' -or $script:AllowedDownloadHosts -notcontains $parsed.Host.ToLowerInvariant()) {
        throw 'Asset download redirected outside GitHub official download infrastructure.'
    }
}

function Invoke-XqOfficialAssetDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Int64]$AssetId,
        [Parameter(Mandatory)][string]$DestinationPath,
        [string]$ApiBaseUri = 'https://api.github.com',
        [scriptblock]$DownloadInvoker
    )

    $api = $ApiBaseUri.TrimEnd('/')
    $uri = "$api/repos/$($script:TrustedRepository.Owner)/$($script:TrustedRepository.Name)/releases/assets/$AssetId"
    if ($null -ne $DownloadInvoker) {
        $result = & $DownloadInvoker $uri $DestinationPath (New-XqGitHubHeaders -Accept 'application/octet-stream')
        if ($null -eq $result -or $null -eq $result.PSObject.Properties['FinalUri']) { throw 'Download provider did not supply a final download URI.' }
        Assert-XqDownloadUri -Uri ([string]$result.FinalUri)
        if (-not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) { throw 'Mock download did not create its requested destination file.' }
        return
    }

    if ($api -cne 'https://api.github.com') { throw 'Real asset downloads must use the fixed https://api.github.com endpoint.' }
    $response = Invoke-WebRequest -Uri $uri -Headers (New-XqGitHubHeaders -Accept 'application/octet-stream') -OutFile $DestinationPath -MaximumRedirection 5 -PassThru -ErrorAction Stop
    $finalUri = $null
    if ($null -ne $response.BaseResponse -and $null -ne $response.BaseResponse.RequestMessage -and $null -ne $response.BaseResponse.RequestMessage.RequestUri) {
        $finalUri = $response.BaseResponse.RequestMessage.RequestUri.AbsoluteUri
    }
    elseif ($null -ne $response.BaseResponse -and $null -ne $response.BaseResponse.ResponseUri) {
        $finalUri = $response.BaseResponse.ResponseUri.AbsoluteUri
    }
    if ([string]::IsNullOrWhiteSpace($finalUri)) { throw 'Could not determine the final official asset download URI.' }
    Assert-XqDownloadUri -Uri $finalUri
    if (-not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) { throw 'Official asset download did not create a file.' }
}

function Get-XqSignatureSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [scriptblock]$SignatureInvoker
    )
    if ($null -ne $SignatureInvoker) { return & $SignatureInvoker $Path }
    $signature = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
    $timestampPresent = $null -ne $signature.TimeStamperCertificate
    return [pscustomobject]@{
        Status = [string]$signature.Status
        SignerSubject = if ($null -ne $signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
        SignerThumbprint = if ($null -ne $signature.SignerCertificate) { [string]$signature.SignerCertificate.Thumbprint } else { '' }
        TimestampPresent = $timestampPresent
        TimestampSubject = if ($timestampPresent) { [string]$signature.TimeStamperCertificate.Subject } else { '' }
    }
}

function Assert-XqSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Signature,
        [Parameter(Mandatory)]$InstallerLock
    )
    $status = [string](Get-XqProperty -Object $Signature -Name 'Status' -Required)
    $subject = [string](Get-XqProperty -Object $Signature -Name 'SignerSubject' -Required)
    $thumbprint = ([string](Get-XqProperty -Object $Signature -Name 'SignerThumbprint' -Required)).Replace(' ', '').ToUpperInvariant()
    $expectedSubject = [string](Get-XqProperty -Object $InstallerLock -Name 'signerSubject' -Required)
    $expectedThumbprint = ([string](Get-XqProperty -Object $InstallerLock -Name 'signerThumbprint' -Required)).Replace(' ', '').ToUpperInvariant()
    if ($status -cne 'Valid') { throw 'Authenticode status is not Valid.' }
    if ($subject -cne $expectedSubject) { throw 'Authenticode signer subject does not match the approved lock.' }
    if ($thumbprint -cne $expectedThumbprint) { throw 'Authenticode signer thumbprint does not match the approved lock.' }
    if ([bool](Get-XqProperty -Object $InstallerLock -Name 'timestampRequired' -Required) -and -not [bool](Get-XqProperty -Object $Signature -Name 'TimestampPresent' -Required)) {
        throw 'Authenticode timestamp is required but missing.'
    }
}

function Assert-XqCandidateSignature {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Signature)
    $status = [string](Get-XqProperty -Object $Signature -Name 'Status' -Required)
    $subject = [string](Get-XqProperty -Object $Signature -Name 'SignerSubject' -Required)
    $thumbprint = ([string](Get-XqProperty -Object $Signature -Name 'SignerThumbprint' -Required)).Replace(' ', '')
    if ($status -cne 'Valid') { throw 'Candidate Authenticode status is not Valid.' }
    if ([string]::IsNullOrWhiteSpace($subject) -or $subject.Length -gt 1024) { throw 'Candidate Authenticode signer subject is empty or invalid.' }
    if ($thumbprint -notmatch '^[A-Fa-f0-9]{40}$') { throw 'Candidate Authenticode signer thumbprint is invalid.' }
    if (-not [bool](Get-XqProperty -Object $Signature -Name 'TimestampPresent' -Required)) { throw 'Candidate Authenticode timestamp is required.' }
}

function Assert-XqApprovedLock {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Lock)
    if ([Int32](Get-XqProperty -Object $Lock -Name 'schemaVersion' -Required) -ne 1) { throw 'Approved lock schemaVersion is unsupported.' }
    $repository = Get-XqProperty -Object $Lock -Name 'repository' -Required
    Assert-XqTrustedRepository -Repository ([pscustomobject]@{
        owner = Get-XqProperty -Object $repository -Name 'owner' -Required
        name = Get-XqProperty -Object $repository -Name 'name' -Required
        id = Get-XqProperty -Object $repository -Name 'repositoryId' -Required
    })
    $approval = Get-XqProperty -Object $Lock -Name 'approval' -Required
    if ([string](Get-XqProperty -Object $approval -Name 'status' -Required) -cne 'approved') { throw 'Formal build requires approval.status = approved.' }
    if ([string]::IsNullOrWhiteSpace([string](Get-XqProperty -Object $approval -Name 'approvedBy' -Required))) { throw 'Approved lock must identify its approver.' }
    $approvedAt = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string](Get-XqProperty -Object $approval -Name 'approvedAtUtc' -Required), [ref]$approvedAt)) { throw 'Approved lock approval time is invalid.' }
    $release = Get-XqProperty -Object $Lock -Name 'release' -Required
    if ([bool](Get-XqProperty -Object $release -Name 'draft' -Required) -or [bool](Get-XqProperty -Object $release -Name 'prerelease' -Required)) { throw 'Approved lock cannot name a draft or prerelease.' }
    if ([Int64](Get-XqProperty -Object $release -Name 'releaseId' -Required) -le 0 -or [string]::IsNullOrWhiteSpace([string](Get-XqProperty -Object $release -Name 'tag' -Required))) { throw 'Approved lock release id or tag is invalid.' }
    $installer = Get-XqProperty -Object $Lock -Name 'installer' -Required
    if ([Int64](Get-XqProperty -Object $installer -Name 'assetId' -Required) -le 0 -or [string](Get-XqProperty -Object $installer -Name 'name' -Required) -cne $script:InstallerAssetName -or [Int64](Get-XqProperty -Object $installer -Name 'size' -Required) -le 0) { throw 'Approved lock installer identity is invalid.' }
    if ([string]::IsNullOrWhiteSpace([string](Get-XqProperty -Object $installer -Name 'signerSubject' -Required)) -or ([string](Get-XqProperty -Object $installer -Name 'signerThumbprint' -Required)).Replace(' ', '') -notmatch '^[A-Fa-f0-9]{40}$' -or -not [bool](Get-XqProperty -Object $installer -Name 'timestampRequired' -Required)) { throw 'Approved lock signer policy is invalid.' }
    $checksumAsset = Get-XqProperty -Object $Lock -Name 'checksumAsset' -Required
    if ([Int64](Get-XqProperty -Object $checksumAsset -Name 'assetId' -Required) -le 0 -or [string](Get-XqProperty -Object $checksumAsset -Name 'name' -Required) -cne $script:ChecksumAssetName) { throw 'Approved lock checksum asset identity is invalid.' }
    $sources = Get-XqProperty -Object $Lock -Name 'sourceFiles' -Required
    if ([string](Get-XqProperty -Object $sources -Name 'commitSha' -Required) -notmatch '^[A-Fa-f0-9]{40}$') { throw 'Approved lock source commit is invalid.' }
    foreach ($hashPath in @(
        @($installer, 'sha256'), @($checksumAsset, 'sha256'),
        @($sources, 'licenseSha256'), @($sources, 'thirdPartyNoticesSha256')
    )) {
        $hash = [string](Get-XqProperty -Object $hashPath[0] -Name $hashPath[1] -Required)
        if ($hash -notmatch '^[A-Fa-f0-9]{64}$') { throw 'Approved lock contains an invalid SHA-256 value.' }
    }
}

function Get-XqSourceContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CommitSha,
        [Parameter(Mandatory)][string]$Path,
        [string]$ApiBaseUri = 'https://api.github.com',
        [scriptblock]$RequestInvoker
    )
    if ($Path -notin @('LICENSE', 'THIRD_PARTY_NOTICES.md')) { throw 'Only the approved license source files may be fetched.' }
    if ($CommitSha -notmatch '^[A-Fa-f0-9]{40}$') { throw 'Source commit must be a full 40-character SHA.' }
    $uri = "$($ApiBaseUri.TrimEnd('/'))/repos/$($script:TrustedRepository.Owner)/$($script:TrustedRepository.Name)/contents/$Path`?ref=$CommitSha"
    $response = Invoke-XqGitHubJson -Uri $uri -RequestInvoker $RequestInvoker
    $content = Get-XqProperty -Object $response -Name 'content' -Required
    $encoding = [string](Get-XqProperty -Object $response -Name 'encoding' -Required)
    if ($encoding -cne 'base64') { throw 'GitHub source file response used an unexpected encoding.' }
    try { return [Convert]::FromBase64String(([string]$content -replace '\s', '')) }
    catch { throw 'GitHub source file response did not contain valid base64 content.' }
}

Export-ModuleMember -Function @(
    'Get-XqTrustedRepository', 'Get-XqProperty', 'Assert-XqTrustedRepository', 'Invoke-XqGitHubJson',
    'Get-XqReleaseAsset', 'Get-XqSha256', 'Assert-XqSha256', 'Get-XqChecksumEntry',
    'Invoke-XqOfficialAssetDownload', 'Get-XqSignatureSummary', 'Assert-XqSignature', 'Assert-XqCandidateSignature',
    'Assert-XqApprovedLock', 'Get-XqSourceContent'
)
