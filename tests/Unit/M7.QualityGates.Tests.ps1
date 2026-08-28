#requires -Version 7.0
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }
Describe 'M7 quality gate contract' {
    It 'pins Pester 5.7.1 and blocks missing ScriptAnalyzer in formal mode' {
        $kit = Split-Path -Parent (Split-Path -Parent $PSScriptRoot); $gate = Get-Content -LiteralPath (Join-Path $kit 'build/Invoke-QualityGates.ps1') -Raw
        $gate | Should -Match 'Pester 5\.7\.1'; $gate | Should -Match 'PSScriptAnalyzer 1\.25\.0 is required'
        $gate | Should -Match 'CoveragePercentTarget'; $gate | Should -Match 'coverageTarget = 85\.0'
    }
}
