#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }

BeforeAll {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { throw 'PSScriptRoot is required.' }
    $script:kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:buildRoot = Join-Path $script:kitRoot 'build'
    $script:fixtureRoot = Join-Path $script:kitRoot 'tests/Fixtures/m1m2'
    $script:installer = Join-Path $script:fixtureRoot 'OpenClawCompanion-Setup-x64.exe'
    $script:checksums = Join-Path $script:fixtureRoot 'OpenClawCompanion-SHA256SUMS.txt'
    $script:license = Join-Path $script:fixtureRoot 'LICENSE'
    $script:notices = Join-Path $script:fixtureRoot 'THIRD_PARTY_NOTICES.md'
    $script:commit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $script:repoResponse = [pscustomobject]@{ id = 1103012935; name = 'openclaw'; owner = [pscustomobject]@{ login = 'openclaw' } }
    $script:release = [pscustomobject]@{
        id = 777; tag_name = 'v0.fixture'; draft = $false; prerelease = $false; published_at = '2026-01-01T00:00:00Z'; html_url = 'https://github.com/openclaw/openclaw/releases/tag/v0.fixture'
        assets = @(
            [pscustomobject]@{ id = 1001; name = 'OpenClawCompanion-Setup-x64.exe'; size = 15 },
            [pscustomobject]@{ id = 1002; name = 'OpenClawCompanion-SHA256SUMS.txt'; size = 98 }
        )
    }
    $release = $script:release
    $commit = $script:commit
    $license = $script:license
    $notices = $script:notices
    $repoResponse = $script:repoResponse
    $installer = $script:installer
    $checksums = $script:checksums
    $script:request = {
        param($Uri, $Headers)
        if ($Uri -match '/releases\?') { return @($release) }
        if ($Uri -match '/releases/777$') { return $release }
        if ($Uri -match '/commits/') { return [pscustomobject]@{ sha = $commit } }
        if ($Uri -match '/contents/LICENSE') { return [pscustomobject]@{ encoding = 'base64'; content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($license)) } }
        if ($Uri -match '/contents/THIRD_PARTY_NOTICES.md') { return [pscustomobject]@{ encoding = 'base64'; content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($notices)) } }
        return $repoResponse
    }.GetNewClosure()
    $script:download = {
        param($Uri, $Destination, $Headers)
        if ($Uri -match '/1001$') { Copy-Item -LiteralPath $installer -Destination $Destination }
        elseif ($Uri -match '/1002$') { Copy-Item -LiteralPath $checksums -Destination $Destination }
        else { throw 'Unexpected fixture asset request.' }
        return [pscustomobject]@{ FinalUri = 'https://objects.githubusercontent.com/fixture' }
    }.GetNewClosure()
    $script:signature = { param($Path) [pscustomobject]@{ Status = 'Valid'; SignerSubject = 'CN=XQ Fixture Signer'; SignerThumbprint = '00112233445566778899AABBCCDDEEFF00112233'; TimestampPresent = $true } }
}

Describe 'M1 to M2 fixed-input flow' {
    It 'resolves a pending candidate without creating an approved lock' {
        $candidate = Join-Path ([IO.Path]::GetTempPath()) ("candidate-" + [guid]::NewGuid().ToString('N') + '.json')
        try {
            & (Join-Path $script:buildRoot 'Resolve-UpstreamCandidate.ps1') -CandidateOutputPath $candidate -RequestInvoker $script:request -DownloadInvoker $script:download -SignatureInvoker $script:signature
            $candidateLock = Get-Content -Raw $candidate | ConvertFrom-Json
            $candidateLock.approval.status | Should -Be 'pending-human-review'
            $candidateLock.repository.repositoryId | Should -Be 1103012935
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
            if ($Uri -match '/1001$') { [IO.File]::WriteAllBytes($Destination, ([IO.File]::ReadAllBytes($installer) + [byte[]](0))) }
            elseif ($Uri -match '/1002$') { Copy-Item -LiteralPath $checksums -Destination $Destination }
            else { throw 'Unexpected fixture asset request.' }
            return [pscustomobject]@{ FinalUri = 'https://objects.githubusercontent.com/fixture' }
        }.GetNewClosure()
        try {
            { & (Join-Path $script:buildRoot 'Fetch-LockedArtifacts.ps1') -LockPath (Join-Path $script:fixtureRoot 'approved-upstream-lock.json') -VerifiedOutputDirectory $output -RequestInvoker $script:request -DownloadInvoker $tamperedDownload -SignatureInvoker $script:signature } | Should -Throw
            (Test-Path -LiteralPath $output) | Should -BeFalse
        }
        finally { Remove-Item -LiteralPath $output -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
