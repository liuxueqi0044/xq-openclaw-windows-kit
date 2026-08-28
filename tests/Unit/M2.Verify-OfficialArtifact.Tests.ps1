#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }

BeforeAll {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { throw 'PSScriptRoot is required.' }
    $script:kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:buildRoot = Join-Path $script:kitRoot 'build'
    $script:fixtureRoot = Join-Path $script:kitRoot 'tests/Fixtures/m1m2'
    $script:lockPath = Join-Path $script:fixtureRoot 'approved-upstream-lock.json'
    $script:installerPath = Join-Path $script:fixtureRoot 'OpenClawCompanion-Setup-x64.exe'
    $script:checksumPath = Join-Path $script:fixtureRoot 'OpenClawCompanion-SHA256SUMS.txt'
    $script:validSignature = { param($Path) [pscustomobject]@{ Status = 'Valid'; SignerSubject = 'CN=XQ Fixture Signer'; SignerThumbprint = '00112233445566778899AABBCCDDEEFF00112233'; TimestampPresent = $true } }
    Import-Module (Join-Path $script:buildRoot 'SupplyChain.Common.psm1') -Force
}

Describe 'M2 official artifact verification' {
    It 'accepts three matching hashes and the approved signer' {
        $result = & (Join-Path $script:buildRoot 'Verify-OfficialArtifact.ps1') -LockPath $script:lockPath -InstallerPath $script:installerPath -ChecksumPath $script:checksumPath -SignatureInvoker $script:validSignature
        $result.installerSha256 | Should -Be '6A58945C7AABAA87CAD1E75BD3ACDF93389028E165AAAFBB03413D62B7671668'
    }

    It 'rejects an otherwise valid signature with the wrong publisher thumbprint' {
        $wrongSigner = [pscustomobject]@{ Status = 'Valid'; SignerSubject = 'CN=XQ Fixture Signer'; SignerThumbprint = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'; TimestampPresent = $true }
        $lock = Get-Content -Raw $script:lockPath | ConvertFrom-Json
        { Assert-XqSignature -Signature $wrongSigner -InstallerLock $lock.installer } | Should -Throw
    }

    It 'requires the timestamp required by the lock' {
        $noTimestamp = [pscustomobject]@{ Status = 'Valid'; SignerSubject = 'CN=XQ Fixture Signer'; SignerThumbprint = '00112233445566778899AABBCCDDEEFF00112233'; TimestampPresent = $false }
        $lock = Get-Content -Raw $script:lockPath | ConvertFrom-Json
        { Assert-XqSignature -Signature $noTimestamp -InstallerLock $lock.installer } | Should -Throw
    }

    It 'rejects an approved lock with a wrong exact installer name' {
        $lock = Get-Content -Raw $script:lockPath | ConvertFrom-Json
        $lock.installer.name = 'some-other.exe'
        { Assert-XqApprovedLock -Lock $lock } | Should -Throw
    }
}
