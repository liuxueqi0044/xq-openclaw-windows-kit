#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }

BeforeAll {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { throw 'PSScriptRoot is required.' }
    $script:kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:buildRoot = Join-Path $script:kitRoot 'build'
    Import-Module (Join-Path $script:buildRoot 'SupplyChain.Common.psm1') -Force
}

Describe 'M1 upstream candidate safeguards' {
    It 'rejects a repository with the right name but a different repository ID' {
        { Assert-XqTrustedRepository -Repository ([pscustomobject]@{ owner = 'openclaw'; name = 'openclaw-windows-node'; id = 1 }) } | Should -Throw
    }

    It 'requires exactly one x64 installer asset with a REST digest' {
        $release = [pscustomobject]@{ assets = @(
            [pscustomobject]@{ id = 1; name = 'OpenClawCompanion-Setup-x64.exe'; size = 1; state = 'uploaded'; digest = 'sha256:' + ('a' * 64) },
            [pscustomobject]@{ id = 2; name = 'OpenClawCompanion-Setup-x64.exe'; size = 1; state = 'uploaded'; digest = 'sha256:' + ('b' * 64) }
        ) }
        { Get-XqReleaseAsset -Release $release -ExactName 'OpenClawCompanion-Setup-x64.exe' } | Should -Throw
        Get-XqAssetDigestSha256 -Asset ([pscustomobject]@{ id = 1; name = 'OpenClawCompanion-Setup-x64.exe'; size = 1; state = 'uploaded'; digest = 'sha256:' + ('a' * 64) }) | Should -Be ('A' * 64)
        { Get-XqAssetDigestSha256 -Asset ([pscustomobject]@{ id = 1; name = 'OpenClawCompanion-Setup-x64.exe'; size = 1; state = 'uploaded'; digest = 'sha512:' + ('a' * 64) }) } | Should -Throw
    }

    It 'rejects an asset that is not fully uploaded' {
        $release = [pscustomobject]@{ assets = @([pscustomobject]@{ id = 1; name = 'OpenClawCompanion-Setup-x64.exe'; size = 1; state = 'open'; digest = 'sha256:' + ('a' * 64) }) }
        { Get-XqReleaseAsset -Release $release -ExactName 'OpenClawCompanion-Setup-x64.exe' } | Should -Throw
    }

    It 'never permits candidate output to overwrite the approved lock name, regardless of case' {
        $path = Join-Path ([IO.Path]::GetTempPath()) 'UPSTREAM-LOCK.JSON'
        { & (Join-Path $script:buildRoot 'Resolve-UpstreamCandidate.ps1') -CandidateOutputPath $path } | Should -Throw
    }

    It 'exposes a repository ID input but refuses values other than the trusted ID' {
        $path = Join-Path ([IO.Path]::GetTempPath()) ("candidate-" + [guid]::NewGuid().ToString('N') + '.json')
        try {
            { & (Join-Path $script:buildRoot 'Resolve-UpstreamCandidate.ps1') -CandidateOutputPath $path -ExpectedRepositoryId 1 } | Should -Throw
            (Test-Path -LiteralPath $path) | Should -BeFalse
        }
        finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects a malicious API base before any real HTTP request can receive a token' {
        InModuleScope SupplyChain.Common {
            Mock -CommandName Invoke-RestMethod -MockWith { throw 'HTTP should not have been reached.' }
            { Invoke-XqGitHubJson -Uri 'https://api.github.com.evil.invalid/repos/openclaw/openclaw-windows-node' } | Should -Throw
            Should -Invoke -CommandName Invoke-RestMethod -Times 0 -Exactly
        }
        $path = Join-Path ([IO.Path]::GetTempPath()) ("candidate-bad-api-" + [guid]::NewGuid().ToString('N') + '.json')
        try {
            { & (Join-Path $script:buildRoot 'Resolve-UpstreamCandidate.ps1') -CandidateOutputPath $path -ApiBaseUri 'https://api.github.com.evil.invalid' } | Should -Throw
            (Test-Path -LiteralPath $path) | Should -BeFalse
        }
        finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects unsigned, malformed, or untimestamped candidate signing summaries' {
        foreach ($summary in @(
            [pscustomobject]@{ Status = 'NotSigned'; SignerSubject = 'CN=Fixture'; SignerThumbprint = '00112233445566778899AABBCCDDEEFF00112233'; TimestampPresent = $true },
            [pscustomobject]@{ Status = 'Valid'; SignerSubject = ''; SignerThumbprint = '00112233445566778899AABBCCDDEEFF00112233'; TimestampPresent = $true },
            [pscustomobject]@{ Status = 'Valid'; SignerSubject = 'CN=Fixture'; SignerThumbprint = 'bad'; TimestampPresent = $true },
            [pscustomobject]@{ Status = 'Valid'; SignerSubject = 'CN=Fixture'; SignerThumbprint = '00112233445566778899AABBCCDDEEFF00112233'; TimestampPresent = $false }
        )) {
            { Assert-XqCandidateSignature -Signature $summary } | Should -Throw
        }
    }
}
