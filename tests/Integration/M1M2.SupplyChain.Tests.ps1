#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }

BeforeAll {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { throw 'PSScriptRoot is required.' }
    $script:kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:buildRoot = Join-Path $script:kitRoot 'build'
    $script:fixtureRoot = Join-Path $script:kitRoot 'tests/Fixtures/m1m2'
    $script:installer = Join-Path $script:fixtureRoot 'OpenClawCompanion-Setup-x64.exe'
    $script:license = Join-Path $script:fixtureRoot 'LICENSE'
    $script:notices = Join-Path $script:fixtureRoot 'THIRD_PARTY_NOTICES.md'
    $script:commit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $script:repoResponse = [pscustomobject]@{ id = 1144728715; name = 'openclaw-windows-node'; owner = [pscustomobject]@{ login = 'openclaw' } }
    $script:release = [pscustomobject]@{
        id = 777; tag_name = 'v0.fixture'; draft = $false; prerelease = $false; published_at = '2026-01-01T00:00:00Z'; html_url = 'https://github.com/openclaw/openclaw-windows-node/releases/tag/v0.fixture'
        assets = @(
            [pscustomobject]@{ id = 1001; name = 'OpenClawCompanion-Setup-x64.exe'; size = 15; state = 'uploaded'; digest = 'sha256:6a58945c7aabaa87cad1e75bd3acdf93389028e165aaafbb03413d62b7671668' }
        )
    }
    $release = $script:release
    $commit = $script:commit
    $license = $script:license
    $notices = $script:notices
    $repoResponse = $script:repoResponse
    $installer = $script:installer
    $script:request = {
        param($Uri, $Headers)
        [void]$Headers
        if ($Uri -match '/releases\?') { return @($release) }
        if ($Uri -match '/releases/777$') { return $release }
        if ($Uri -match '/commits/') { return [pscustomobject]@{ sha = $commit } }
        if ($Uri -match '/contents/LICENSE') { return [pscustomobject]@{ encoding = 'base64'; content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($license)) } }
        if ($Uri -match '/contents/src/OpenClaw\.Tray\.WinUI/THIRD_PARTY_NOTICES\.md') { return [pscustomobject]@{ encoding = 'base64'; content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($notices)) } }
        return $repoResponse
    }.GetNewClosure()
    $script:download = {
        param($Uri, $Destination, $Headers)
        [void]$Headers
        if ($Uri -match '/1001$') { Copy-Item -LiteralPath $installer -Destination $Destination }
        else { throw 'Unexpected fixture asset request.' }
        return [pscustomobject]@{ FinalUri = 'https://objects.githubusercontent.com/fixture' }
    }.GetNewClosure()
    $script:signature = { param($Path) [void]$Path; [pscustomobject]@{ Status = 'Valid'; SignerSubject = 'CN=XQ Fixture Signer'; SignerThumbprint = '00112233445566778899AABBCCDDEEFF00112233'; TimestampPresent = $true } }
}

Describe 'M1 to M2 fixed-input flow' {
    It 'resolves a pending candidate without creating an approved lock' {
        $candidate = Join-Path ([IO.Path]::GetTempPath()) ("candidate-" + [guid]::NewGuid().ToString('N') + '.json')
        try {
            & (Join-Path $script:buildRoot 'Resolve-UpstreamCandidate.ps1') -CandidateOutputPath $candidate -RequestInvoker $script:request -DownloadInvoker $script:download -SignatureInvoker $script:signature
            $candidateLock = Get-Content -Raw $candidate | ConvertFrom-Json
            $candidateLock.approval.status | Should -Be 'pending-human-review'
            $candidateLock.repository.repositoryId | Should -Be 1144728715
            ([DateTime]$candidateLock.release.publishedAtUtc).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss') | Should -Be '2026-01-01T00:00:00'
        }
        finally { Remove-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue }
    }

    It 'only emits verified files after all locked checks pass' {
        $output = Join-Path ([IO.Path]::GetTempPath()) ("verified-" + [guid]::NewGuid().ToString('N'))
        try {
            & (Join-Path $script:buildRoot 'Fetch-LockedArtifacts.ps1') -LockPath (Join-Path $script:fixtureRoot 'approved-upstream-lock.json') -VerifiedOutputDirectory $output -RequestInvoker $script:request -DownloadInvoker $script:download -SignatureInvoker $script:signature
            (Test-Path -LiteralPath (Join-Path $output 'verification-result.json')) | Should -BeTrue
            (Get-Content -Raw (Join-Path $output 'verification-result.json') | ConvertFrom-Json).status | Should -Be 'verified'
        }
        finally { Remove-Item -LiteralPath $output -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects a draft release and leaves no candidate output' {
        $candidate = Join-Path ([IO.Path]::GetTempPath()) ("candidate-draft-" + [guid]::NewGuid().ToString('N') + '.json')
        $draftRequest = {
            param($Uri, $Headers)
            [void]$Headers
            if ($Uri -match '/releases\?') { return @([pscustomobject]@{ id = 778; tag_name = 'v0.draft'; draft = $true; prerelease = $false; assets = @() }) }
            return $repoResponse
        }.GetNewClosure()
        try {
            { & (Join-Path $script:buildRoot 'Resolve-UpstreamCandidate.ps1') -CandidateOutputPath $candidate -RequestInvoker $draftRequest } | Should -Throw
            (Test-Path -LiteralPath $candidate) | Should -BeFalse
        }
        finally { Remove-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects a tampered installer and leaves no verified output' {
        $output = Join-Path ([IO.Path]::GetTempPath()) ("verified-tampered-" + [guid]::NewGuid().ToString('N'))
        $tamperedDownload = {
            param($Uri, $Destination, $Headers)
            [void]$Headers
            if ($Uri -match '/1001$') { [IO.File]::WriteAllBytes($Destination, ([IO.File]::ReadAllBytes($installer) + [byte[]](0))) }
            else { throw 'Unexpected fixture asset request.' }
            return [pscustomobject]@{ FinalUri = 'https://objects.githubusercontent.com/fixture' }
        }.GetNewClosure()
        try {
            { & (Join-Path $script:buildRoot 'Fetch-LockedArtifacts.ps1') -LockPath (Join-Path $script:fixtureRoot 'approved-upstream-lock.json') -VerifiedOutputDirectory $output -RequestInvoker $script:request -DownloadInvoker $tamperedDownload -SignatureInvoker $script:signature } | Should -Throw
            (Test-Path -LiteralPath $output) | Should -BeFalse
        }
        finally { Remove-Item -LiteralPath $output -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects a release tag that no longer resolves to the approved commit' {
        $output = Join-Path ([IO.Path]::GetTempPath()) ("verified-retagged-" + [guid]::NewGuid().ToString('N'))
        $baseRequest = $script:request
        $retaggedRequest = {
            param($Uri, $Headers)
            if ($Uri -match '/commits/') { return [pscustomobject]@{ sha = ('b' * 40) } }
            return & $baseRequest $Uri $Headers
        }.GetNewClosure()
        try {
            { & (Join-Path $script:buildRoot 'Fetch-LockedArtifacts.ps1') -LockPath (Join-Path $script:fixtureRoot 'approved-upstream-lock.json') -VerifiedOutputDirectory $output -RequestInvoker $retaggedRequest -DownloadInvoker $script:download -SignatureInvoker $script:signature } | Should -Throw
            (Test-Path -LiteralPath $output) | Should -BeFalse
        }
        finally { Remove-Item -LiteralPath $output -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
