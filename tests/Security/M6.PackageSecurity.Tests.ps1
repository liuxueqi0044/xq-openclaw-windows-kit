#requires -Version 7.0
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }

BeforeAll { $script:kit = Split-Path -Parent (Split-Path -Parent $PSScriptRoot); $script:build = Join-Path $script:kit 'build/Build-Package.ps1'; $script:fixture = Join-Path $script:kit 'tests/Fixtures/m6/package-input'; $script:commit='ce34e00b8ed56109b09faab27fba39046e886d2d' }
Describe 'M6 package security gates' {
    It 'keeps every production package source allowlisted, offline and privacy-safe' {
        Import-Module (Join-Path $script:kit 'tools/XQ.Redaction.psm1') -Force -DisableNameChecking
        $policy=Get-Content (Join-Path $script:kit 'policy/allowed-package-files.json') -Raw|ConvertFrom-Json
        $contentRoot=Join-Path $script:kit 'content'
        foreach($file in @(Get-ChildItem -LiteralPath $contentRoot -File -Recurse)){
            $relative=[IO.Path]::GetRelativePath($contentRoot,$file.FullName).Replace('\','/')
            @($policy.allowedPaths|Where-Object{$relative -like $_}).Count|Should -Be 1
            $text=Get-Content -LiteralPath $file.FullName -Raw;@(Get-XqSensitiveFindings -Text $text)|Should -HaveCount 0
            if($file.Extension -eq '.html'){$text|Should -Not -Match '(?i)(?:src|href)\s*=\s*["'']\s*(?:https?:|//)'}
        }
        foreach($name in @('OpenClaw-XQ-Diagnose.ps1','XQ.Redaction.psm1','运行诊断工具.cmd')){
            $path=Join-Path $script:kit ('tools/'+$name);@(Get-XqSensitiveFindings -Text (Get-Content -LiteralPath $path -Raw))|Should -HaveCount 0
        }
    }
    It 'rejects an injected dotenv file and produces no package output' {
        $input = Join-Path $script:kit ('tests/Fixtures/m6/runtime-input-' + [guid]::NewGuid().ToString('N')); $out = Join-Path ([IO.Path]::GetTempPath()) ('m6-out-' + [guid]::NewGuid().ToString('N'))
        try {
            Copy-Item -LiteralPath $script:fixture -Destination $input -Recurse
            [IO.File]::WriteAllText((Join-Path $input 'content/.env'), 'not-a-real-secret')
            { & $script:build -Mode Test -TestInputRoot $input -VerifiedDirectory (Join-Path $input 'verified') -OutputDirectory $out -GitCommit $script:commit } | Should -Throw
            (Test-Path -LiteralPath $out) | Should -BeFalse
        } finally { Remove-Item -LiteralPath $input,$out -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'rejects formal mode when only a forged verified status is supplied' {
        $out = Join-Path ([IO.Path]::GetTempPath()) ('m6-formal-' + [guid]::NewGuid().ToString('N'))
        try { { & $script:build -Mode Formal -VerifiedDirectory (Join-Path $script:fixture 'verified') -LockPath (Join-Path $script:fixture 'approved-upstream-lock.json') -OutputDirectory $out -GitCommit $script:commit } | Should -Throw; (Test-Path -LiteralPath $out) | Should -BeFalse } finally { Remove-Item -LiteralPath $out -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'rejects a Formal GitCommit that is not the current clean HEAD' {
        $out = Join-Path ([IO.Path]::GetTempPath()) ('m6-wrong-commit-' + [guid]::NewGuid().ToString('N'))
        try { { & $script:build -Mode Formal -VerifiedDirectory (Join-Path $script:fixture 'verified') -LockPath (Join-Path $script:fixture 'approved-upstream-lock.json') -OutputDirectory $out -GitCommit ('0' * 40) } | Should -Throw; (Test-Path -LiteralPath $out) | Should -BeFalse } finally { Remove-Item -LiteralPath $out -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'rejects path traversal before ZIP creation' {
        $out = Join-Path ([IO.Path]::GetTempPath()) ('m6-escape-' + [guid]::NewGuid().ToString('N') + '.zip')
        try { { & (Join-Path $script:kit 'build/New-DeterministicZip.ps1') -SourceDirectory (Join-Path $script:fixture 'content') -ZipPath $out -ArchiveRoot '../escape' } | Should -Throw; (Test-Path -LiteralPath $out) | Should -BeFalse } finally { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }
    }
    It 'rejects a sensitive token in a staged text input without echoing it' {
        $input = Join-Path $script:kit ('tests/Fixtures/m6/runtime-secret-' + [guid]::NewGuid().ToString('N')); $out = Join-Path ([IO.Path]::GetTempPath()) ('m6-secret-' + [guid]::NewGuid().ToString('N'))
        try { Copy-Item -LiteralPath $script:fixture -Destination $input -Recurse; Add-Content -LiteralPath (Join-Path $input 'content/README.txt') -Value 'apiKey=sk-proj-abcdefghijklmnop'; { & $script:build -Mode Test -TestInputRoot $input -VerifiedDirectory (Join-Path $input 'verified') -OutputDirectory $out -GitCommit $script:commit } | Should -Throw; (Test-Path -LiteralPath $out) | Should -BeFalse } finally { Remove-Item -LiteralPath $input,$out -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'rejects a remote HTML reference during the staged offline check' {
        $input = Join-Path $script:kit ('tests/Fixtures/m6/runtime-link-' + [guid]::NewGuid().ToString('N')); $out = Join-Path ([IO.Path]::GetTempPath()) ('m6-link-' + [guid]::NewGuid().ToString('N'))
        try { Copy-Item -LiteralPath $script:fixture -Destination $input -Recurse; Add-Content -LiteralPath (Join-Path $input 'content/guide/00-开始这里.html') -Value '<img src="https://example.invalid/a.png">'; { & $script:build -Mode Test -TestInputRoot $input -VerifiedDirectory (Join-Path $input 'verified') -OutputDirectory $out -GitCommit $script:commit } | Should -Throw; (Test-Path -LiteralPath $out) | Should -BeFalse } finally { Remove-Item -LiteralPath $input,$out -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
