#requires -Version 7.0
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }

BeforeAll {
    $script:kit = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:build = Join-Path $script:kit 'build/Build-Package.ps1'
    $script:fixture = Join-Path $script:kit 'tests/Fixtures/m6/package-input'
    $script:commit = 'ce34e00b8ed56109b09faab27fba39046e886d2d'
}
Describe 'M6 isolated deterministic package build' {
    It 'builds two byte-identical fixture packages with provenance, hashes, and licenses' {
        $one = Join-Path ([IO.Path]::GetTempPath()) ('m6-one-' + [guid]::NewGuid().ToString('N'))
        $two = Join-Path ([IO.Path]::GetTempPath()) ('m6-two-' + [guid]::NewGuid().ToString('N'))
        try {
            & $script:build -Mode Test -VerifiedDirectory (Join-Path $script:fixture 'verified') -OutputDirectory $one -GitCommit $script:commit | Out-Null
            & $script:build -Mode Test -VerifiedDirectory (Join-Path $script:fixture 'verified') -OutputDirectory $two -GitCommit $script:commit | Out-Null
            $zipOne = Join-Path $one 'XQ-OpenClaw-Windows-x64-v0.1.0-TEST-NON-RELEASE.zip'; $zipTwo = Join-Path $two 'XQ-OpenClaw-Windows-x64-v0.1.0-TEST-NON-RELEASE.zip'
            (Get-FileHash -LiteralPath $zipOne -Algorithm SHA256).Hash | Should -Be (Get-FileHash -LiteralPath $zipTwo -Algorithm SHA256).Hash
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $archive = [IO.Compression.ZipFile]::OpenRead($zipOne); try { $names=@($archive.Entries.FullName); $names | Should -Contain 'XQ-OpenClaw-Windows/LICENSE'; $names | Should -Contain 'XQ-OpenClaw-Windows/THIRD_PARTY_NOTICES.md'; $names | Should -Contain 'XQ-OpenClaw-Windows/SHA256SUMS.txt'; ($names -join "`n") | Should -Be (($names | Sort-Object) -join "`n") } finally { $archive.Dispose() }
        } finally { Remove-Item -LiteralPath $one,$two -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
