#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }

Describe 'M4 read-only diagnostic contracts' {
    BeforeAll {
        $repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        . (Join-Path $repo 'tools\OpenClaw-XQ-Diagnose.ps1') -NoRun
        Initialize-XqDiagnosticPolicy (Join-Path $repo 'policy\diagnostic-command-policy.json') | Out-Null
        $policy = Get-Content (Join-Path $repo 'policy\diagnostic-command-policy.json') -Raw | ConvertFrom-Json
    }

    It 'redacts structured sensitive fields and command text' {
        $obj = [pscustomobject]@{ api_key='fixture-key'; Nested=[pscustomobject]@{ Authorization='Bearer fixture'; gatewayToken='short-secret' }; Version='0.6.12'; Path='C:\Users\Alice\OpenClaw' }
        $safe = ConvertTo-XqRedactedObject $obj
        $safe.api_key | Should -Be '[REDACTED]'
        $safe.Nested.Authorization | Should -Be '[REDACTED]'
        $safe.Nested.gatewayToken | Should -Be '[REDACTED]'
        $safe.Version | Should -Be '0.6.12'
        (Redact-XqText 'Authorization: Bearer fixture-token-123456789') | Should -Not -Match 'fixture-token'
        (Redact-XqText 'C:\Users\Alice\OpenClaw') | Should -Match '\[USER\]'
        $safeJson = Redact-XqCommandOutput '{"gatewayToken":"short-secret","Status":"ok"}' 'openclaw doctor --json'
        $safeJson | Should -Not -Match 'short-secret'
        $safeJson | ConvertFrom-Json | Select-Object -ExpandProperty gatewayToken | Should -Be '[REDACTED]'
        (Redact-XqText 'gatewayToken=short-secret apiKeyValue:short-key client_secret=short-secret') | Should -Not -Match 'short-(secret|key)'
        (Redact-XqCommandOutput 'not valid json gatewayToken=short-secret' 'openclaw doctor --json') | Should -Not -Match 'short-secret'
        Redact-XqText '{"gatewayToken":"[REDACTED]","Status":"ok"}' | Should -Be '{"gatewayToken":"[REDACTED]","Status":"ok"}'
    }

    It 'consumes the exact policy command allowlist' {
        (Get-XqPolicyCommand 'managed-wsl-openclaw-doctor').arguments -join ' ' | Should -Be '--distribution OpenClawGateway --user openclaw -- openclaw doctor --json'
        { Get-XqPolicyCommand 'not-approved' } | Should -Throw
        $policy.commands.id | Should -Contain 'wsl-running-list'
        $policy.commands.Count | Should -Be 10
    }

    It 'uses a UTF-8 BOM so Windows PowerShell 5.1 parses Chinese safely' {
        $diagnosticScript = Join-Path $repo 'tools\OpenClaw-XQ-Diagnose.ps1'
        $scriptBytes = [IO.File]::ReadAllBytes($diagnosticScript)
        @($scriptBytes[0..2]) | Should -Be @(0xEF,0xBB,0xBF)
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $diagnosticScript -NoRun
        $LASTEXITCODE | Should -Be 0
    }

    It 'keeps the CMD launcher ASCII-only with Windows line endings' {
        $launcherBytes = [IO.File]::ReadAllBytes((Join-Path $repo 'tools\运行诊断工具.cmd'))
        @($launcherBytes | Where-Object { $_ -gt 0x7F }) | Should -HaveCount 0
        $launcherText = [Text.Encoding]::ASCII.GetString($launcherBytes)
        $launcherText | Should -Match "`r`n"
        ($launcherText -replace "`r`n", '') | Should -Not -Match "`n"
    }

    It 'rejects a rewritten executable or an extra command' {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('xq-policy-' + [guid]::NewGuid().ToString('N') + '.json')
        try {
            $copy = $policy | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $copy.commands[0].executable = 'curl.exe'
            $copy | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmp
            { Initialize-XqDiagnosticPolicy $tmp } | Should -Throw
            $copy = $policy | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $copy.commands[2].arguments[5] = 'unsafe-command'
            $copy | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmp
            { Initialize-XqDiagnosticPolicy $tmp } | Should -Throw
            $copy = $policy | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $copy.commands[0].executionContext = 'native-cli-if-present'
            $copy | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmp
            { Initialize-XqDiagnosticPolicy $tmp } | Should -Throw
            $copy = $policy | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $extra = [pscustomobject]@{ id='unapproved'; executable='wsl.exe'; arguments=@('--version'); executionContext='windows-host' }
            $copy.commands += $extra
            $copy | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmp
            { Initialize-XqDiagnosticPolicy $tmp } | Should -Throw
        } finally { if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Force } }
    }

    It 'does not run managed commands for a stopped WSL distribution' {
        Mock Invoke-XqExternalCommand -ParameterFilter { $Arguments -contains '--running' } { [pscustomobject]@{ ExitCode=0;TimedOut=$false;StdOut='';StdErr='';Error=$null } }
        Mock Invoke-XqExternalCommand { [pscustomobject]@{ ExitCode=0;TimedOut=$false;StdOut=(Get-Content (Join-Path $repo 'tests\Fixtures\m3m4\wsl-list-stopped.txt') -Raw);StdErr='';Error=$null } }
        $result = Invoke-XqManagedGatewayProbe 1
        ($result.Commands | Where-Object Command -match 'openclaw') | Should -HaveCount 0
    }

    It 'drains large stdout without a pipe deadlock' {
        $hostExecutable = (Get-Command powershell.exe -CommandType Application -ErrorAction Stop).Source
        $result = Invoke-XqExternalCommand -FileName $hostExecutable -Arguments @('-NoProfile','-Command',"[Console]::Out.Write(('x' * 200000))") -TimeoutSeconds 10
        $result.TimedOut | Should -BeFalse
        $result.ExitCode | Should -Be 0
        $result.StdOut.Length | Should -Be 200000
    }

    It 'returns after the configured timeout' {
        $hostExecutable = (Get-Command powershell.exe -CommandType Application -ErrorAction Stop).Source
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-XqExternalCommand -FileName $hostExecutable -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 5') -TimeoutSeconds 1
        $watch.Stop()
        $result.TimedOut | Should -BeTrue
        $watch.Elapsed.TotalSeconds | Should -BeLessThan 4
    }
}
