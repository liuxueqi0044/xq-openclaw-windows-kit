#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }

Describe 'M4 report integration safety' {
    BeforeAll {
        $repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        . (Join-Path $repo 'tools\OpenClaw-XQ-Diagnose.ps1') -NoRun
        Initialize-XqDiagnosticPolicy (Join-Path $repo 'policy\diagnostic-command-policy.json') | Out-Null
        $out = Join-Path ([IO.Path]::GetTempPath()) ('xq-report-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $out | Out-Null
    }

    It 'writes a new readable report and never overwrites an existing report' {
        $report = [pscustomobject]@{ Metadata=[pscustomobject]@{ReportVersion='1';ProductVersion='0.1.0';GeneratedAtUtc='now'}; WindowsHost=[pscustomobject]@{Status='Unknown'}; HubInstallation=[pscustomobject]@{Status='NotDetected'}; WslGateway=[pscustomobject]@{Status='Stopped'}; NativeCli=[pscustomobject]@{Status='NotDetected'}; HealthFindings=@(); CommandResults=@(); RedactionSummary=[pscustomobject]@{ReplacementToken='[REDACTED]'}; Limitations=@('test') }
        $first = Write-XqDiagnosticReport $report $out
        $second = Write-XqDiagnosticReport $report $out
        $first | Should -Not -Be $second
        (Get-Content $first -Raw) | Should -Match 'XQ 只读诊断报告|\[Windows 主机\]'
        (Get-ChildItem $out -Filter 'OpenClaw-Diagnostic-*.txt').Count | Should -Be 2
    }

    It 'redacts fixture command output before it is placed in a report' {
        $raw = Get-Content (Join-Path $repo 'tests\Fixtures\m3m4\redaction-sample.txt') -Raw
        $safe = Redact-XqText $raw
        $safe | Should -Not -Match 'fixture-(bearer|password|token|payload|signature)'
        $safe | Should -Match '0\.6\.12|E_FAIL'
    }
}
