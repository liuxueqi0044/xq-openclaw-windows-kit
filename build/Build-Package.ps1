#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Formal','Test')][string]$Mode = 'Formal',
    [Parameter(Mandatory)][string]$VerifiedDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$LockPath,
    [string]$TestSummaryPath,
    [string]$TestInputRoot,
    [string]$GitCommit,
    [datetime]$BuildTimestampUtc = ([datetime]'2000-01-01T00:00:00Z')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'SupplyChain.Common.psm1') -Force
Import-Module (Join-Path $repo 'tools/XQ.Redaction.psm1') -Force -DisableNameChecking

function Get-RelativePathSafe([string]$Root, [string]$Path) {
    $relative = [IO.Path]::GetRelativePath($Root, $Path).Replace('\','/')
    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|/)\.\.(/|$)' -or $relative -eq '.') { throw 'Unsafe relative path.' }
    return $relative
}
function Test-AllowedPath([string]$Path, $Policy) { return @($Policy.allowedPaths | Where-Object { $Path -like $_ }).Count -eq 1 }
function Assert-SafeFile([string]$Path, [string]$Root, $Forbidden) {
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse points are not permitted.' }
    if ($item.Length -gt [Int64]$Forbidden.maxFileSizeBytes) { throw 'Package file exceeds policy size limit.' }
    $relative = Get-RelativePathSafe $Root $Path
    $lower = $relative.ToLowerInvariant()
    foreach ($fragment in $Forbidden.forbiddenPathFragments) { if ($lower.Contains(([string]$fragment).ToLowerInvariant())) { throw 'Forbidden package path fragment.' } }
    foreach ($extension in $Forbidden.forbiddenExtensions) { if ($lower.EndsWith(([string]$extension).ToLowerInvariant())) { throw 'Forbidden package extension.' } }
    if ($PSVersionTable.PSEdition -eq 'Core') {
        try { if (@(Get-Item -LiteralPath $Path -Stream * -ErrorAction Stop | Where-Object { $_.Stream -ne ':$DATA' }).Count -gt 0) { throw 'Alternate data streams are not permitted.' } } catch [System.Management.Automation.ParameterBindingException] { Write-Verbose 'Alternate data stream enumeration is unavailable on this runtime.' }
    }
}
function Copy-CheckedFile([string]$Source, [string]$DestinationRelative, [string]$SourceRoot, [string]$StageRoot, $Allow, $Forbidden) {
    if (-not (Test-AllowedPath $DestinationRelative $Allow)) { throw 'Package destination is not on the explicit allowlist.' }
    Assert-SafeFile $Source $SourceRoot $Forbidden
    $destination = Join-Path $StageRoot $DestinationRelative
    $parent = Split-Path -Parent $destination; New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $destination -Force
    Assert-SafeFile $destination $StageRoot $Forbidden
}
function Write-HashManifest([string]$StageRoot) {
    $lines = foreach ($file in @(Get-ChildItem -LiteralPath $StageRoot -File -Recurse -Force | Sort-Object FullName)) {
        $relative = Get-RelativePathSafe $StageRoot $file.FullName
        if ($relative -ne 'SHA256SUMS.txt') { "$(Get-XqSha256 -Path $file.FullName)  $relative" }
    }
    [IO.File]::WriteAllText((Join-Path $StageRoot 'SHA256SUMS.txt'), (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
}
function Assert-HashManifest([string]$Root) {
    $manifestPath = Join-Path $Root 'SHA256SUMS.txt'
    $seen = @{}
    foreach ($line in @(Get-Content -LiteralPath $manifestPath)) {
        if ($line -notmatch '^([A-Fa-f0-9]{64})  ([^\\].+)$') { throw 'Hash manifest has invalid syntax.' }
        $relative = [string]$Matches[2]
        if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)' -or $relative -eq 'SHA256SUMS.txt' -or $seen.ContainsKey($relative)) { throw 'Hash manifest contains an unsafe, duplicate, or self-referential entry.' }
        $target = Join-Path $Root $relative
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw 'Hash manifest references a missing file.' }
        Assert-XqSha256 -Actual (Get-XqSha256 -Path $target) -Expected $Matches[1] -Label 'Extracted hash manifest'
        $seen[$relative] = $true
    }
    $expected = @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force | ForEach-Object { Get-RelativePathSafe $Root $_.FullName } | Where-Object { $_ -ne 'SHA256SUMS.txt' })
    if ($seen.Count -ne $expected.Count -or @($expected | Where-Object { -not $seen.ContainsKey($_) }).Count -ne 0) { throw 'Hash manifest does not cover every extracted delivery file exactly once.' }
}
function Assert-StagedTree([string]$StageRoot, $Allow, $Forbidden) {
    foreach ($file in @(Get-ChildItem -LiteralPath $StageRoot -File -Recurse -Force)) {
        $relative = Get-RelativePathSafe $StageRoot $file.FullName
        if (-not (Test-AllowedPath $relative $Allow)) { throw 'Staged tree contains a non-whitelisted file.' }
        Assert-SafeFile $file.FullName $StageRoot $Forbidden
    }
}
function Assert-SafeDirectory([string]$Path) {
    foreach ($item in @((Get-Item -LiteralPath $Path -Force)) + @(Get-ChildItem -LiteralPath $Path -Force -Recurse)) { if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Directory tree contains a reparse point.' } }
}
function Assert-TextAndOffline([string]$Root) {
    $textExtensions = @('.html','.txt','.md','.json','.css','.ps1','.psm1','.cmd')
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force | Where-Object { $textExtensions -contains $_.Extension.ToLowerInvariant() })) {
        $text = Get-Content -LiteralPath $file.FullName -Raw
        if (@(Get-XqSensitiveFindings -Text $text).Count -gt 0) { throw 'Package text secret scan failed.' }
        if ($file.Extension -eq '.html' -and $text -match '(?i)(?:src|href)\s*=\s*["'']\s*(?:https?:|//)') { throw 'Offline HTML contains a remote reference.' }
    }
}
function Assert-FormalGit([string]$Commit,[string]$LockFile) {
    $head = (& git -C $repo rev-parse HEAD).Trim(); if ($Commit -cne $head) { throw 'Formal build GitCommit must equal current HEAD.' }
    if (@(& git -C $repo status --porcelain).Count -ne 0) { throw 'Formal build requires a clean worktree.' }
    $expected = [IO.Path]::GetFullPath((Join-Path $repo 'manifest/upstream-lock.json')); if ([IO.Path]::GetFullPath($LockFile) -cne $expected) { throw 'Formal build accepts only manifest/upstream-lock.json.' }
    & git -C $repo ls-files --error-unmatch 'manifest/upstream-lock.json' 2>$null | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'Formal upstream lock must be tracked by current commit.' }
}
function Assert-VerifiedM2([string]$Root, $Verification, $Lock) {
    Assert-SafeDirectory $Root
    if ($Verification.status -ne 'verified') { throw 'Formal mode requires M2 verified output.' }
    if ($Verification.repository.owner -cne $Lock.repository.owner -or $Verification.repository.name -cne $Lock.repository.name -or [int64]$Verification.repository.repositoryId -ne [int64]$Lock.repository.repositoryId) { throw 'M2 repository provenance does not match lock.' }
    if ($Verification.release.tag -cne $Lock.release.tag -or [int64]$Verification.release.releaseId -ne [int64]$Lock.release.releaseId) { throw 'M2 release provenance does not match lock.' }
    $installer = Join-Path $Root 'OpenClawCompanion-Setup-x64.exe'
    if ((Get-Item -LiteralPath $installer).Length -ne [int64]$Lock.installer.size) { throw 'Verified installer size does not match lock.' }
    $installerHash = Get-XqSha256 -Path $installer
    Assert-XqSha256 -Actual $installerHash -Expected $Lock.installer.sha256 -Label 'Verified installer'; Assert-XqSha256 -Actual $installerHash -Expected $Lock.installer.officialDigestSha256 -Label 'Verified official digest'
    Assert-XqSha256 -Actual $Verification.installer.installerSha256 -Expected $Lock.installer.sha256 -Label 'M2 installer result'; Assert-XqSha256 -Actual $Verification.installer.officialDigestSha256 -Expected $Lock.installer.officialDigestSha256 -Label 'M2 digest result'
    if ($Verification.installer.authenticode.status -cne 'Valid' -or $Verification.installer.authenticode.signerSubject -cne $Lock.installer.signerSubject -or $Verification.installer.authenticode.signerThumbprint -cne $Lock.installer.signerThumbprint -or -not [bool]$Verification.installer.authenticode.timestampPresent) { throw 'M2 Authenticode result does not match lock.' }
    foreach ($pair in @(@('LICENSE','licenseSha256'),@('THIRD_PARTY_NOTICES.md','thirdPartyNoticesSha256'))) { Assert-XqSha256 -Actual (Get-XqSha256 -Path (Join-Path $Root $pair[0])) -Expected $Lock.sourceFiles.($pair[1]) -Label $pair[0]; Assert-XqSha256 -Actual $Verification.sourceFiles.($pair[1]) -Expected $Lock.sourceFiles.($pair[1]) -Label "M2 $($pair[0]) result" }
    if ($Verification.sourceFiles.commitSha -cne $Lock.sourceFiles.commitSha) { throw 'M2 source commit does not match lock.' }
}

$stageParent = $null
$outputCreated = $false
try {
    $allowPath = Join-Path $repo 'policy/allowed-package-files.json'; $forbiddenPath = Join-Path $repo 'policy/forbidden-patterns.json'
    if (-not (Test-Json -LiteralPath $allowPath -SchemaFile (Join-Path $repo 'manifest/schemas/allowed-package-files.schema.json'))) { throw 'Allowed package file policy does not pass schema validation.' }
    if (-not (Test-Json -LiteralPath $forbiddenPath -SchemaFile (Join-Path $repo 'manifest/schemas/forbidden-patterns.schema.json'))) { throw 'Forbidden pattern policy does not pass schema validation.' }
    $productConfigPath = Join-Path $repo 'manifest/product-config.json'
    if (-not (Test-Json -LiteralPath $productConfigPath -SchemaFile (Join-Path $repo 'manifest/schemas/product-config.schema.json'))) { throw 'Product config does not pass schema validation.' }
    $allow = Get-Content -LiteralPath $allowPath -Raw | ConvertFrom-Json
    $forbidden = Get-Content -LiteralPath $forbiddenPath -Raw | ConvertFrom-Json
    $productConfig = Get-Content -LiteralPath $productConfigPath -Raw | ConvertFrom-Json
    if ($allow.packageRootName -match '[\\/]|\.\.' -or @($allow.allowedPaths | Where-Object { $_ -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted($_) -or $_ -eq '*' }).Count -ne 0) { throw 'Allowed package policy contains an unsafe wildcard or path.' }
    if (@($allow.allowedExecutablePaths | Where-Object { -not (Test-AllowedPath $_ $allow) }).Count -ne 0) { throw 'Allowed executable policy must be a subset of the delivery allowlist.' }
    if (@($forbidden.forbiddenPathFragments | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -ne 0) { throw 'Forbidden pattern policy contains an empty fragment.' }
    $out = [IO.Path]::GetFullPath($OutputDirectory)
    if (Test-Path -LiteralPath $out) { throw 'Output directory already exists; refusing to mix prior artifacts.' }
    if ([string]::IsNullOrWhiteSpace($GitCommit)) { $GitCommit = (& git -C $repo rev-parse HEAD).Trim() }
    if ($GitCommit -notmatch '^[A-Fa-f0-9]{40}$') { throw 'A fixed 40-character Git commit is required.' }

    if ($Mode -eq 'Formal') {
        if ([string]::IsNullOrWhiteSpace($LockPath)) { throw 'Formal mode requires an approved upstream lock.' }
        Assert-FormalGit $GitCommit $LockPath
        $lock = Get-Content -LiteralPath $LockPath -Raw | ConvertFrom-Json
        Assert-XqApprovedLock -Lock $lock
        $verifiedRoot = [IO.Path]::GetFullPath($VerifiedDirectory)
        $verificationPath = Join-Path $verifiedRoot 'verification-result.json'
        $verification = Get-Content -LiteralPath $verificationPath -Raw | ConvertFrom-Json
        Assert-VerifiedM2 $verifiedRoot $verification $lock
        if ([string]::IsNullOrWhiteSpace($TestSummaryPath) -or -not (Test-Path -LiteralPath $TestSummaryPath)) { throw 'Formal mode requires a M7 test summary.' }
        if (-not (Test-Json -LiteralPath $TestSummaryPath -SchemaFile (Join-Path $repo 'manifest/schemas/test-summary.schema.json'))) { throw 'M7 test summary is invalid.' }
        $testSummary = Get-Content -LiteralPath $TestSummaryPath -Raw | ConvertFrom-Json
        $reportPath = "$TestSummaryPath.report.json"
        $coveragePath = "$TestSummaryPath.coverage.xml"
        if ([bool]$testSummary.fixture -or -not [bool]$testSummary.analyzerPassed -or [int]$testSummary.skippedCount -ne 0 -or [double]$testSummary.coveragePercent -lt [double]$testSummary.coverageTarget -or [double]$testSummary.coverageTarget -ne 85 -or $testSummary.commitSha -cne $GitCommit -or -not (Test-Path -LiteralPath $reportPath) -or -not (Test-Path -LiteralPath $coveragePath) -or (Get-XqSha256 -Path $reportPath) -cne $testSummary.reportSha256.ToUpperInvariant() -or (Get-XqSha256 -Path $coveragePath) -cne $testSummary.coverageReportSha256.ToUpperInvariant()) { throw 'Formal mode rejects incomplete, skipped, fixture, analyzer-failed, under-covered, unverifiable, or wrong-commit M7 summaries.' }
        $contentRoot = Join-Path $repo 'content'; $toolsRoot = Join-Path $repo 'tools'
    } else {
        $fixtureRoot = if ($TestInputRoot) { [IO.Path]::GetFullPath($TestInputRoot) } else { Join-Path $repo 'tests/Fixtures/m6/package-input' }
        if (-not $fixtureRoot.StartsWith((Join-Path $repo 'tests/Fixtures'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Test mode accepts only isolated test fixtures.' }
        $verifiedRoot = Join-Path $fixtureRoot 'verified'; $contentRoot = Join-Path $fixtureRoot 'content'; $toolsRoot = Join-Path $fixtureRoot 'tools'
        $verificationPath = Join-Path $verifiedRoot 'verification-result.json'; $verification = Get-Content -LiteralPath $verificationPath -Raw | ConvertFrom-Json
        if ($verification.status -ne 'verified') { throw 'Test fixture must represent verified M2 output.' }
        $lock = Get-Content -LiteralPath (Join-Path $fixtureRoot 'approved-upstream-lock.json') -Raw | ConvertFrom-Json
        Assert-XqApprovedLock -Lock $lock
        $testSummary = Get-Content -LiteralPath (Join-Path $fixtureRoot 'test-summary.json') -Raw | ConvertFrom-Json
        if (-not [bool]$testSummary.fixture) { throw 'Test mode requires a fixture-marked test summary.' }
    }
    Assert-SafeDirectory $verifiedRoot; Assert-SafeDirectory $contentRoot; Assert-SafeDirectory $toolsRoot
    $stageParent = Join-Path ([IO.Path]::GetTempPath()) ('xq-package-' + [guid]::NewGuid().ToString('N'))
    $stage = Join-Path $stageParent $allow.packageRootName; New-Item -ItemType Directory -Path $stage -Force | Out-Null
    foreach ($name in @('OpenClawCompanion-Setup-x64.exe','LICENSE','THIRD_PARTY_NOTICES.md')) { Copy-CheckedFile (Join-Path $verifiedRoot $name) $name $verifiedRoot $stage $allow $forbidden }
    foreach ($file in @(Get-ChildItem -LiteralPath $contentRoot -File -Recurse -Force)) { Copy-CheckedFile $file.FullName (Get-RelativePathSafe $contentRoot $file.FullName) $contentRoot $stage $allow $forbidden }
    foreach ($name in @('OpenClaw-XQ-Diagnose.ps1','XQ.Redaction.psm1','运行诊断工具.cmd')) { Copy-CheckedFile (Join-Path $toolsRoot $name) "tools/$name" $toolsRoot $stage $allow $forbidden }
    $installerHash = Get-XqSha256 -Path (Join-Path $verifiedRoot 'OpenClawCompanion-Setup-x64.exe')
    Assert-XqSha256 -Actual (Get-XqSha256 -Path (Join-Path $stage 'OpenClawCompanion-Setup-x64.exe')) -Expected $installerHash -Label 'Staged installer'
    $source = [ordered]@{ schemaVersion=1; buildMode=if($Mode -eq 'Formal'){'formal'}else{'test-fixture-non-release'}; productVersion=$productConfig.productVersion; gitCommit=$GitCommit; builtAtUtc=$BuildTimestampUtc.ToUniversalTime().ToString('o'); builderVersion='Build-Package.ps1/1'; upstream=[ordered]@{repository='openclaw/openclaw-windows-node';tag=$lock.release.tag;releaseId=[int64]$lock.release.releaseId};installer=[ordered]@{assetId=[int64]$lock.installer.assetId;size=[int64]$lock.installer.size;sha256=$installerHash;officialDigestMatched=$true;authenticode=[ordered]@{status='Valid';subject=$lock.installer.signerSubject;thumbprint=$lock.installer.signerThumbprint;timestampValid=$true}};sourceFiles=$lock.sourceFiles;automatedTests=[ordered]@{passed=[bool]$testSummary.passed;summary="Pester $($testSummary.pesterVersion): $($testSummary.totalCount) passed; coverage $($testSummary.coveragePercent)%; report $($testSummary.reportSha256)";totalCount=[int]$testSummary.totalCount;skippedCount=[int]$testSummary.skippedCount;pesterVersion=$testSummary.pesterVersion;reportSha256=$testSummary.reportSha256;coveragePercent=[double]$testSummary.coveragePercent;coverageTarget=[double]$testSummary.coverageTarget;coverageReportSha256=$testSummary.coverageReportSha256;analyzerPassed=[bool]$testSummary.analyzerPassed}}
    [IO.File]::WriteAllText((Join-Path $stage 'SOURCE-AND-VERSION.json'), ($source | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
    if (-not (Test-Json -LiteralPath (Join-Path $stage 'SOURCE-AND-VERSION.json') -SchemaFile (Join-Path $repo 'manifest/schemas/provenance.schema.json'))) { throw 'Staged provenance does not pass schema validation.' }
    Write-HashManifest $stage; Assert-StagedTree $stage $allow $forbidden; Assert-TextAndOffline $stage
    $zipName = if($Mode -eq 'Formal'){"XQ-OpenClaw-Windows-x64-v$($productConfig.productVersion).zip"}else{"XQ-OpenClaw-Windows-x64-v$($productConfig.productVersion)-TEST-NON-RELEASE.zip"}; $zipTemp = Join-Path $stageParent $zipName
    & (Join-Path $PSScriptRoot 'New-DeterministicZip.ps1') -SourceDirectory $stage -ZipPath $zipTemp -ArchiveRoot $allow.packageRootName -TimestampUtc $BuildTimestampUtc
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipRead = [IO.Compression.ZipFile]::OpenRead($zipTemp); try { $names=@($zipRead.Entries | ForEach-Object FullName); if (($names -join "`n") -cne (($names | Sort-Object) -join "`n")) { throw 'ZIP entries are not sorted.' }; foreach($entry in $zipRead.Entries){ if($entry.FullName -notlike "$($allow.packageRootName)/*" -or $entry.FullName -match '(^|/)\.\.(/|$)' -or [IO.Path]::IsPathRooted($entry.FullName)){throw 'ZIP contains an unsafe entry path.'} } } finally { $zipRead.Dispose() }
    $extract = Join-Path $stageParent 'extract'; [IO.Compression.ZipFile]::ExtractToDirectory($zipTemp, $extract)
    $extractedRoot = Join-Path $extract $allow.packageRootName; Assert-StagedTree $extractedRoot $allow $forbidden; Assert-TextAndOffline $extractedRoot
    if (-not (Test-Json -LiteralPath (Join-Path $extractedRoot 'SOURCE-AND-VERSION.json') -SchemaFile (Join-Path $repo 'manifest/schemas/provenance.schema.json'))) { throw 'Extracted provenance does not pass schema validation.' }
    Assert-XqSha256 -Actual (Get-XqSha256 -Path (Join-Path $extractedRoot 'OpenClawCompanion-Setup-x64.exe')) -Expected $installerHash -Label 'Extracted installer'
    Assert-HashManifest $extractedRoot
    if ($Mode -eq 'Formal') { $signature=Get-XqSignatureSummary -Path (Join-Path $extractedRoot 'OpenClawCompanion-Setup-x64.exe'); Assert-XqSignature -Signature $signature -InstallerLock $lock.installer }
    New-Item -ItemType Directory -Path $out | Out-Null; $outputCreated = $true
    Move-Item -LiteralPath $zipTemp -Destination (Join-Path $out $zipName)
    $zipHash = Get-XqSha256 -Path (Join-Path $out $zipName)
    [IO.File]::WriteAllText((Join-Path $out "$zipName.sha256"), "$zipHash  $zipName`n", (New-Object Text.UTF8Encoding($false)))
    [pscustomobject]@{ status='package-built'; zipPath=(Join-Path $out $zipName); zipSha256=$zipHash; mode=$Mode }
}
catch { if ($null -ne $stageParent -and (Test-Path -LiteralPath $stageParent)) { Remove-Item -LiteralPath $stageParent -Recurse -Force -ErrorAction SilentlyContinue }; if ($outputCreated -and (Test-Path -LiteralPath $out)) { Remove-Item -LiteralPath $out -Recurse -Force -ErrorAction SilentlyContinue }; throw 'Package build failed. No formal package output was produced.' }
finally { if ($null -ne $stageParent -and (Test-Path -LiteralPath $stageParent)) { Remove-Item -LiteralPath $stageParent -Recurse -Force -ErrorAction SilentlyContinue } }
