#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$PesterModulePath,
    [string]$PSScriptAnalyzerModulePath,
    [ValidateSet('Formal','Developer')][string]$Mode = 'Formal',
    [switch]$SkipScriptAnalyzer,
    [string]$TestSummaryPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$coverageReportPath = $null
$temporaryCoverageReport = $false
try {
    if ($PesterModulePath) { if (-not (Test-Path -LiteralPath $PesterModulePath)) { throw 'Pinned Pester module path is unavailable.' }; Import-Module $PesterModulePath -Force }
    else { $pesterModule = Get-Module -ListAvailable Pester | Where-Object { $_.Version -eq [version]'5.7.1' } | Select-Object -First 1; if ($null -eq $pesterModule) { throw 'Pinned Pester 5.7.1 module is unavailable.' }; Import-Module $pesterModule.Path -Force }
    if ((Get-Module Pester).Version -ne [version]'5.7.1') { throw 'Pester 5.7.1 is required.' }
    $coverageTarget = 85.0
    if ($TestSummaryPath) { $coverageReportPath = "$TestSummaryPath.coverage.xml" }
    else { $coverageReportPath = Join-Path ([IO.Path]::GetTempPath()) ('xq-coverage-' + [guid]::NewGuid().ToString('N') + '.xml'); $temporaryCoverageReport = $true }
    $pesterConfig = New-PesterConfiguration
    $pesterConfig.Run.Path = @((Join-Path $repo 'tests')); $pesterConfig.Run.PassThru = $true
    $pesterConfig.Output.Verbosity = 'Normal'
    $pesterConfig.CodeCoverage.Enabled = $true
    $pesterConfig.CodeCoverage.Path = @((Join-Path $repo 'tools/XQ.Redaction.psm1'),(Join-Path $repo 'tools/Update-ReleaseLedger.ps1'))
    $pesterConfig.CodeCoverage.OutputFormat = 'JaCoCo'; $pesterConfig.CodeCoverage.OutputPath = $coverageReportPath; $pesterConfig.CodeCoverage.CoveragePercentTarget = $coverageTarget
    $pester = Invoke-Pester -Configuration $pesterConfig
    if ($pester.FailedCount -ne 0 -or $pester.SkippedCount -ne 0) { throw 'Pester gate failed or skipped a test.' }
    $coveragePercent = [math]::Round([double]$pester.CodeCoverage.CoveragePercent, 2)
    if ($coveragePercent -lt $coverageTarget -or -not (Test-Path -LiteralPath $coverageReportPath -PathType Leaf)) { throw 'Critical-module code coverage is below the 85 percent release threshold.' }
    $coverageReportHash = (Get-FileHash -LiteralPath $coverageReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($SkipScriptAnalyzer -and $Mode -ne 'Developer') { throw 'Formal quality gates cannot skip PSScriptAnalyzer.' }
    $analyzerPassed = $false
    if (-not $SkipScriptAnalyzer) {
        if ($PSScriptAnalyzerModulePath) {
            if (-not (Test-Path -LiteralPath $PSScriptAnalyzerModulePath)) { throw 'Pinned PSScriptAnalyzer module path is unavailable.' }
            $analyzer = Test-ModuleManifest -Path $PSScriptAnalyzerModulePath -ErrorAction Stop
        } else {
            $analyzer = Get-Module -ListAvailable PSScriptAnalyzer | Where-Object { $_.Version -eq [version]'1.25.0' } | Select-Object -First 1
        }
        if ($null -eq $analyzer -or $analyzer.Version -ne [version]'1.25.0') { throw 'PSScriptAnalyzer 1.25.0 is required for the formal quality gate.' }
        Import-Module $analyzer.Path -Force
        $analyzerCommand = Get-Command Invoke-ScriptAnalyzer -ErrorAction Stop
        if ($analyzerCommand.ModuleName -ne 'PSScriptAnalyzer' -or $analyzerCommand.Module.Version -ne [version]'1.25.0') { throw 'PSScriptAnalyzer 1.25.0 is required for the formal quality gate.' }
        $findings = @()
        $findings += @(Invoke-ScriptAnalyzer -Path (Join-Path $repo 'build') -Recurse -Settings (Join-Path $repo 'PSScriptAnalyzerSettings.psd1') -ErrorAction Stop)
        $findings += @(Invoke-ScriptAnalyzer -Path (Join-Path $repo 'tools') -Recurse -Settings (Join-Path $repo 'PSScriptAnalyzerSettings.psd1') -ErrorAction Stop)
        if ($findings.Count -ne 0) { throw 'PSScriptAnalyzer reported blocking findings.' }
        $analyzerPassed = $true
    }
    $commit = (& git -C $repo rev-parse HEAD).Trim(); if ($commit -notmatch '^[A-Fa-f0-9]{40}$') { throw 'A fixed Git commit is required for test evidence.' }
    $report = [ordered]@{schemaVersion=1;totalCount=[int]$pester.TotalCount;passedCount=[int]$pester.PassedCount;failedCount=[int]$pester.FailedCount;skippedCount=[int]$pester.SkippedCount;pesterVersion='5.7.1';coveragePercent=$coveragePercent;coverageTarget=$coverageTarget;coverageReportSha256=$coverageReportHash;commitSha=$commit}
    $reportJson = $report | ConvertTo-Json -Compress
    $reportHash = -join ([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($reportJson)) | ForEach-Object { $_.ToString('x2') })
    $summary = [ordered]@{schemaVersion=1;passed=$true;totalCount=[int]$pester.TotalCount;failedCount=0;skippedCount=[int]$pester.SkippedCount;pesterVersion='5.7.1';reportSha256=$reportHash;coveragePercent=$coveragePercent;coverageTarget=$coverageTarget;coverageReportSha256=$coverageReportHash;fixture=($Mode -eq 'Developer');analyzerPassed=$analyzerPassed;commitSha=$commit}
    if ($TestSummaryPath) { [IO.File]::WriteAllText($TestSummaryPath, ($summary | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false))); [IO.File]::WriteAllText("$TestSummaryPath.report.json", $reportJson, (New-Object Text.UTF8Encoding($false))) }
    [pscustomobject]@{ status='passed'; pesterVersion='5.7.1'; tests=$pester.TotalCount; scriptAnalyzerSkipped=[bool]$SkipScriptAnalyzer; summary=$summary }
}
catch { throw ('Quality gate failed: ' + $_.Exception.Message) }
finally { if ($temporaryCoverageReport -and $coverageReportPath -and (Test-Path -LiteralPath $coverageReportPath)) { Remove-Item -LiteralPath $coverageReportPath -Force -ErrorAction SilentlyContinue } }
