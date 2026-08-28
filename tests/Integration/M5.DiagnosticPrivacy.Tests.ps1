#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }

Describe 'M5 diagnostic privacy integration' {
    BeforeAll {
        $script:repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        Import-Module (Join-Path $script:repo 'tools\XQ.Redaction.psm1') -Force -DisableNameChecking -ErrorAction Stop
        . (Join-Path $script:repo 'tools\OpenClaw-XQ-Diagnose.ps1') -NoRun
    }

    It 'routes command output through the single redaction module before it enters a report object' {
        $script:XqRedactionContext = New-XqRedactionContext
        Mock Invoke-XqExternalCommand {
            [pscustomobject]@{
                ExitCode = 0; TimedOut = $false
                StdOut = '{"access_token":"fixture-value-abcdefghijkl","path":"C:\\Users\\FixtureUser\\OpenClaw"}'
                StdErr = 'Authorization: Bearer fixtureBearerabcdefghijkl'
                Error = $null
            }
        }

        $result = Invoke-XqSafeCommand -Component 'Fixture' -DisplayCommand 'openclaw doctor --json' -FileName 'openclaw' -Arguments @('doctor','--json') -TimeoutSeconds 1
        @(Get-XqSensitiveFindings -Text ($result.StdOut + "`n" + $result.StdErr)).Count | Should -Be 0
        $result.StdOut | Should -Match '\[REDACTED\]'
        $result.StdOut | Should -Match '\[USER\]'
        (Get-XqRedactionSummary -Context $script:XqRedactionContext).TotalReplacements | Should -BeGreaterThan 0
    }

    It 'writes only a redacted report after the final privacy scan succeeds' {
        $output = Join-Path ([IO.Path]::GetTempPath()) ('xq-m5-report-' + [guid]::NewGuid().ToString('N'))
        try {
            $script:XqRedactionContext = New-XqRedactionContext
            $report = [pscustomobject]@{
                Metadata = [pscustomobject]@{ ReportVersion = 1; ProductVersion = '0.1.0'; GeneratedAtUtc = '2026-08-28T00:00:00Z' }
                WindowsHost = [pscustomobject]@{ Status = 'Detected'; Path = 'C:\Users\FixtureUser\OpenClaw' }
                HubInstallation = [pscustomobject]@{ Status = 'NotDetected' }
                WslGateway = [pscustomobject]@{ Status = 'NotDetected' }
                NativeCli = [pscustomobject]@{ Status = 'NotDetected' }
                HealthFindings = @([pscustomobject]@{ Severity = 'Warning'; Component = 'Fixture'; Code = 'Fixture'; Message = 'Authorization: Bearer fixtureBearerabcdefghijkl' })
                CommandResults = @([pscustomobject]@{ Component = 'Fixture'; Command = 'openclaw doctor --json'; ExitCode = 0; TimedOut = $false; StdOut = '{"clientSecret":"fixture-value-abcdefghijkl"}'; StdErr = ''; Error = $null })
                RedactionSummary = $null
                Limitations = @('fixture')
            }
            $path = Write-XqDiagnosticReport -Report $report -OutputDirectory $output
            $text = Get-Content -LiteralPath $path -Raw
            @(Get-XqSensitiveFindings -Text $text).Count | Should -Be 0
            $text | Should -Match '\[REDACTED\]'
            $text | Should -Match '\[USER\]'
        } finally {
            if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Recurse -Force }
        }
    }
}
