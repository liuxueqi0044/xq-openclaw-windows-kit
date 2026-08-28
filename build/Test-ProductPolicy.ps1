[CmdletBinding()]
param(
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$manifestDirectory = Join-Path $repositoryRoot 'manifest'
$schemaDirectory = Join-Path $manifestDirectory 'schemas'
$policyDirectory = Join-Path $repositoryRoot 'policy'
$errors = [System.Collections.Generic.List[string]]::new()

function Add-PolicyError {
    param([Parameter(Mandatory)][string]$Message)
    $script:errors.Add($Message)
}

function Read-JsonObject {
    param([Parameter(Mandatory)][string]$Path)
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
}

function Test-AgainstSchema {
    param(
        [Parameter(Mandatory)][string]$JsonPath,
        [Parameter(Mandatory)][string]$SchemaPath
    )

    try {
        if (-not (Test-Json -LiteralPath $JsonPath -SchemaFile $SchemaPath)) {
            Add-PolicyError "Schema validation failed: $JsonPath"
        }
    }
    catch {
        Add-PolicyError "Schema validation errored for ${JsonPath}: $($_.Exception.Message)"
    }
}

$schemaPairs = @(
    @{ Json = (Join-Path $manifestDirectory 'product-config.json'); Schema = (Join-Path $schemaDirectory 'product-config.schema.json') },
    @{ Json = (Join-Path $policyDirectory 'diagnostic-command-policy.json'); Schema = (Join-Path $schemaDirectory 'diagnostic-command-policy.schema.json') },
    @{ Json = (Join-Path $policyDirectory 'release-gates.json'); Schema = (Join-Path $schemaDirectory 'release-gates.schema.json') },
    @{ Json = (Join-Path $policyDirectory 'signer-policy.json'); Schema = (Join-Path $schemaDirectory 'signer-policy.schema.json') },
    @{ Json = (Join-Path $policyDirectory 'support-policy.json'); Schema = (Join-Path $schemaDirectory 'support-policy.schema.json') }
)

foreach ($pair in $schemaPairs) {
    if (-not (Test-Path -LiteralPath $pair.Json) -or -not (Test-Path -LiteralPath $pair.Schema)) {
        Add-PolicyError "Missing JSON policy or schema: $($pair.Json)"
        continue
    }
    Test-AgainstSchema -JsonPath $pair.Json -SchemaPath $pair.Schema
}

$product = Read-JsonObject -Path (Join-Path $manifestDirectory 'product-config.json')
if (@($product.supportedOs).Count -ne 1 -or $product.supportedOs[0] -ne 'Windows 11 x64') {
    Add-PolicyError 'supportedOs must contain exactly Windows 11 x64.'
}
if ($product.primaryInstallMode -ne 'windows-hub-local-managed-wsl') {
    Add-PolicyError 'primaryInstallMode must be windows-hub-local-managed-wsl.'
}
if ($product.policyDefaults.failClosed -ne $true -or $product.policyDefaults.unknownState -ne 'unverified' -or $product.policyDefaults.unknownOfficialPrerequisiteAction -ne 'block-release') {
    Add-PolicyError 'Unknown or unverified official prerequisites must fail closed.'
}

$diagnostic = Read-JsonObject -Path (Join-Path $policyDirectory 'diagnostic-command-policy.json')
if ($diagnostic.mode -ne 'read-only') { Add-PolicyError 'Diagnostic policy must be read-only.' }
$forbidden = @('fix', 'repair', 'install', 'restart', 'set', 'remove')
foreach ($token in $forbidden) {
    if ($diagnostic.forbiddenTokens -notcontains $token) { Add-PolicyError "Forbidden diagnostic token missing from policy: $token" }
}
foreach ($command in $diagnostic.commands) {
    $serialized = @($command.executable) + @($command.arguments) -join ' '
    foreach ($token in $diagnostic.forbiddenTokens) {
        if ($serialized -match "(?i)(?<![a-z])$([regex]::Escape($token))(?![a-z])") {
            Add-PolicyError "Diagnostic allowlist contains forbidden token '$token' in command '$($command.id)'."
        }
    }
}
$requiredDiagnosticIds = @('wsl-list', 'wsl-running-list', 'managed-wsl-openclaw-version', 'managed-wsl-openclaw-doctor', 'managed-wsl-openclaw-gateway-status', 'native-openclaw-version', 'native-openclaw-doctor', 'native-openclaw-gateway-status')
foreach ($id in $requiredDiagnosticIds) {
    if (@($diagnostic.commands.id) -notcontains $id) { Add-PolicyError "Required diagnostic allowlist entry is missing: $id" }
}
foreach ($command in @($diagnostic.commands | Where-Object { $_.executionContext -eq 'managed-wsl-openclaw-user' })) {
    if ($command.arguments -notcontains 'OpenClawGateway') { Add-PolicyError "Managed WSL command must target the default OpenClawGateway distribution: $($command.id)" }
}
$runningListCommand = @($diagnostic.commands | Where-Object { $_.id -eq 'wsl-running-list' })
if ($runningListCommand.Count -ne 1 -or $runningListCommand[0].executable -ne 'wsl.exe' -or (@($runningListCommand[0].arguments) -join ' ') -ne '--list --running --quiet' -or $runningListCommand[0].executionContext -ne 'windows-host') {
    Add-PolicyError 'wsl-running-list must be the exact read-only wsl.exe --list --running --quiet host command.'
}

$signer = Read-JsonObject -Path (Join-Path $policyDirectory 'signer-policy.json')
if ($signer.approvedRepository.owner -ne 'openclaw' -or $signer.approvedRepository.name -ne 'openclaw' -or $signer.approvedRepository.repositoryId -ne 1103012935) {
    Add-PolicyError 'Signer policy must pin the approved OpenClaw repository identity.'
}
if ($signer.releaseInput.approvedLockRequired -ne $true -or $signer.releaseInput.allowLatestAlias -ne $false -or $signer.unknownStateAction -ne 'block-release') {
    Add-PolicyError 'Formal build input must require an approved lock and reject unknown state/latest aliases.'
}
if ($signer.licenseVerification.apiLicenseMetadataIsSufficient -ne $false) {
    Add-PolicyError 'GitHub API license metadata cannot replace file-level license verification.'
}

$gates = Read-JsonObject -Path (Join-Path $policyDirectory 'release-gates.json')
$expectedGateIds = @('G1', 'G2', 'G3', 'G4', 'G5', 'G6', 'G7', 'G8', 'G9')
if (@($gates.gates.id | Sort-Object) -join ',' -ne ($expectedGateIds -join ',')) {
    Add-PolicyError 'Release gate policy must define G1 through G9 exactly once.'
}
if ($gates.defaultFailureAction -ne 'block-release') { Add-PolicyError 'Release gate default must block release.' }

$support = Read-JsonObject -Path (Join-Path $policyDirectory 'support-policy.json')
if ($support.canonicalBoundary -ne 'manifest/product-config.json#/productBoundary') { Add-PolicyError 'Support policy must reference the canonical product boundary.' }
if ($support.remoteSupport.includedInSelfServiceSku -ne $false -or $support.remoteSupport.requiresSeparateSkuAndSop -ne $true) { Add-PolicyError 'Remote support must remain outside the self-service SKU.' }

$architecturePath = Join-Path $repositoryRoot 'docs/architecture.md'
if (-not (Test-Path -LiteralPath $architecturePath) -or (Get-Content -LiteralPath $architecturePath -Raw) -notmatch 'manifest/product-config\.json#/productBoundary') {
    Add-PolicyError 'Architecture documentation must point to the canonical product boundary.'
}

$result = [pscustomobject]@{
    Passed = ($errors.Count -eq 0)
    Errors = @($errors)
}

if ($PassThru) { return $result }
if (-not $result.Passed) {
    $result.Errors | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host 'M0 product-policy validation passed.'
