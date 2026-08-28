#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }

# Test baseline: Pester 5.7.1. The Pester 5 discovery/run lifecycle requires
# per-container initialization rather than top-level test-path variables.
BeforeAll {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        throw 'PSScriptRoot is required to locate the repository root.'
    }

    $script:repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:validator = Join-Path $script:repositoryRoot 'build/Test-ProductPolicy.ps1'

    if (-not (Test-Path -LiteralPath $script:validator -PathType Leaf)) {
        throw "M0 policy validator was not found: $script:validator"
    }
}

Describe 'M0 product strategy and safety baseline' {
    It 'validates every M0 JSON policy against its schema and semantic constraints' {
        $result = & $script:validator -PassThru
        $result.Passed | Should -BeTrue
        ($result.Errors -join "`n") | Should -Be ''
    }

    It 'has no repair or write posture in the diagnostic allowlist' {
        $policyPath = Join-Path $script:repositoryRoot 'policy/diagnostic-command-policy.json'
        $policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
        $forbidden = 'fix|repair|install|restart|set|remove'
        foreach ($command in $policy.commands) {
            (($command.executable + ' ' + ($command.arguments -join ' ')) -match "(?i)(?<![a-z])($forbidden)(?![a-z])") | Should -BeFalse
        }
    }

    It 'uses the exact running-list guard before any managed WSL probe' {
        $policyPath = Join-Path $script:repositoryRoot 'policy/diagnostic-command-policy.json'
        $policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
        $runningList = @($policy.commands | Where-Object { $_.id -eq 'wsl-running-list' })

        $runningList.Count | Should -Be 1
        $runningList[0].executable | Should -Be 'wsl.exe'
        ($runningList[0].arguments -join ' ') | Should -Be '--list --running --quiet'
        $runningList[0].executionContext | Should -Be 'windows-host'
    }
}
