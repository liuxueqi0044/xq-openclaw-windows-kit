#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }

Describe 'M5 unified redaction and privacy gate' {
    BeforeAll {
        $script:repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        Import-Module (Join-Path $script:repo 'tools\XQ.Redaction.psm1') -Force -DisableNameChecking -ErrorAction Stop
        . (Join-Path $script:repo 'tools\OpenClaw-XQ-Diagnose.ps1') -NoRun
        $script:corpus = Get-Content (Join-Path $script:repo 'tests\Fixtures\m5\redaction-corpus.json') -Raw | ConvertFrom-Json
    }

    It 'runs a synthetic mixed corpus of at least 100 cases without high-confidence residuals' {
        @($script:corpus.cases).Count | Should -BeGreaterOrEqual 100
        @($script:corpus.cases | Where-Object classification -eq 'secret').Count | Should -BeGreaterThan 0
        @($script:corpus.cases | Where-Object classification -eq 'nonsecret').Count | Should -BeGreaterThan 0

        foreach ($case in @($script:corpus.cases)) {
            $context = New-XqRedactionContext
            $safe = Redact-XqText -InputObject $case.input -Context $context
            @(Get-XqSensitiveFindings -Text $safe).Count | Should -Be 0
            if ($case.classification -eq 'secret') {
                ($safe -ceq $case.input) | Should -BeFalse
                $safe | Should -Match '\[(?:REDACTED|USER)\]'
            }
            if ($case.classification -eq 'nonsecret') { $safe | Should -Be $case.input }
        }
    }

    It 'redacts sensitive field-name segments recursively without redacting ordinary substrings' {
        $context = New-XqRedactionContext
        $source = [pscustomobject]@{
            apiKey = 'fixture-value'
            access_token = 'fixture-value'
            clientSecret = 'fixture-value'
            Nested = @([pscustomobject]@{ Authorization = 'Bearer fixture-value'; cookie_value = 'fixture-value' })
            monkey = 'keep'
            keyboard = 'keep'
            hockey = 'keep'
            layout = 'keep'
            Version = '0.6.12'
            ErrorCode = 'E_GATEWAY_STOPPED'
            Path = 'C:\Program Files\OpenClaw\openclaw.exe'
            When = [datetime]'2026-08-28T00:00:00Z'
            Bytes = [byte[]](1,2,3)
        }

        $safe = ConvertTo-XqRedactedObject -InputObject $source -Context $context
        $safe.apiKey | Should -Be '[REDACTED]'
        $safe.access_token | Should -Be '[REDACTED]'
        $safe.clientSecret | Should -Be '[REDACTED]'
        $safe.Nested[0].Authorization | Should -Be '[REDACTED]'
        $safe.Nested[0].cookie_value | Should -Be '[REDACTED]'
        $safe.monkey | Should -Be 'keep'
        $safe.keyboard | Should -Be 'keep'
        $safe.hockey | Should -Be 'keep'
        $safe.layout | Should -Be 'keep'
        $safe.Version | Should -Be '0.6.12'
        $safe.ErrorCode | Should -Be 'E_GATEWAY_STOPPED'
        $safe.Path | Should -Be 'C:\Program Files\OpenClaw\openclaw.exe'
        $safe.When | Should -BeOfType [datetime]
        ($safe.Bytes -is [byte[]]) | Should -BeTrue
        $safe.Bytes.Length | Should -Be 3
        $summary = Get-XqRedactionSummary -Context $context
        $summary.PSObject.Properties.Name | Should -Be @('Categories','TotalReplacements')
        $summary.Categories[0].PSObject.Properties.Name | Should -Be @('Category','Count')
    }

    It 'is idempotent without inflating replacement counts on already-safe text' {
        $context = New-XqRedactionContext
        $once = Redact-XqText -InputObject 'C:\Users\FixtureUser\report.txt https://user:fixture-password@example.test/' -Context $context
        $countAfterFirstPass = (Get-XqRedactionSummary -Context $context).TotalReplacements
        $twice = Redact-XqText -InputObject $once -Context $context
        $twice | Should -BeExactly $once
        (Get-XqRedactionSummary -Context $context).TotalReplacements | Should -Be $countAfterFirstPass
    }

    It 'does not treat unquoted numeric, boolean or null control values as secrets' {
        $safe = 'token=0 credential=$null authorization=$false secret=-1.5'
        (Get-XqSensitiveFindings -Text $safe) | Should -HaveCount 0
        Redact-XqText -InputObject $safe | Should -BeExactly $safe
    }

    It 'fails closed before writing a report when the final privacy gate rejects text' {
        $output = Join-Path ([IO.Path]::GetTempPath()) ('xq-m5-' + [guid]::NewGuid().ToString('N'))
        try {
            $script:XqRedactionContext = New-XqRedactionContext
            $report = [pscustomobject]@{
                Metadata = [pscustomobject]@{ ReportVersion = 1; ProductVersion = '0.1.0'; GeneratedAtUtc = '2026-08-28T00:00:00Z' }
                WindowsHost = [pscustomobject]@{ Status = 'Detected' }
                HubInstallation = [pscustomobject]@{ Status = 'NotDetected' }
                WslGateway = [pscustomobject]@{ Status = 'NotDetected' }
                NativeCli = [pscustomobject]@{ Status = 'NotDetected' }
                HealthFindings = @()
                CommandResults = @()
                RedactionSummary = $null
                Limitations = @('fixture')
            }
            Mock -CommandName Assert-XqTextIsSafe -MockWith { throw 'Sensitive-content scan failed; the report was not written.' }
            { Write-XqDiagnosticReport -Report $report -OutputDirectory $output } | Should -Throw 'Sensitive-content scan failed; only a safe privacy notice was written.'
            $notice = @(Get-ChildItem -LiteralPath $output -File)
            $notice.Count | Should -Be 1
            $notice[0].Name | Should -Match '^OpenClaw-Diagnostic-Privacy-Blocked-'
            (Get-Content -LiteralPath $notice[0].FullName -Raw) | Should -Match '请勿发送 API Key'
        } finally {
            if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Recurse -Force }
        }
    }

    It 'keeps source collection minimized and imports the single redaction module' {
        $diagnosticPath = Join-Path $script:repo 'tools\OpenClaw-XQ-Diagnose.ps1'
        $diagnostic = Get-Content -LiteralPath $diagnosticPath -Raw
        $diagnostic | Should -Match 'XQ\.Redaction\.psm1'
        $diagnostic | Should -Not -Match 'function\s+(Redact-XqText|Redact-XqCommandOutput|ConvertTo-XqRedactedObject)'
        $diagnostic | Should -Not -Match 'Get-ChildItem\s+(?:-Path\s+)?Env:'
        $diagnostic | Should -Not -Match 'openclaw\.json|Get-Clipboard|\\\.ssh'
    }
}
