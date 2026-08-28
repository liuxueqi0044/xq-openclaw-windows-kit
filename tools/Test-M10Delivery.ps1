#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$AcceptanceRecordPath,[Parameter(Mandatory)][string]$DeliveryZipPath,[Parameter(Mandatory)][string]$LedgerPath,[Parameter(Mandatory)][string]$ListingManifestPath,[Parameter(Mandatory)][string]$ProductConfigPath,[Parameter(Mandatory)][string]$LockPath,[string]$EvidenceRoot=(Split-Path -Parent $AcceptanceRecordPath))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Get-CanonicalLedgerEvent($e){$created=if($e.createdAtUtc -is [datetime]){([datetime]$e.createdAtUtc).ToUniversalTime().ToString('o')}else{[string]$e.createdAtUtc};[ordered]@{eventId=[string]$e.eventId;eventType=[string]$e.eventType;xqVersion=[string]$e.xqVersion;fileName=[string]$e.fileName;zipSha256=[string]$e.zipSha256;m9RecordSha256=[string]$e.m9RecordSha256;createdAtUtc=$created;actor=[string]$e.actor;previousEventHash=[string]$e.previousEventHash;reason=[string]$e.reason}}
function Get-LedgerEventHash($e){$s=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($s.ComputeHash([Text.Encoding]::UTF8.GetBytes((Get-CanonicalLedgerEvent $e|ConvertTo-Json -Compress -Depth 5)))).Replace('-','')).ToLowerInvariant()}finally{$s.Dispose()}}
function Assert-Ledger($ledger){
  $prev='GENESIS';$previousCreated=[DateTimeOffset]::MinValue;$ids=@{};$states=@{}
  foreach($e in @($ledger.entries)){
    $eventId=[string]$e.eventId
    if($ids.ContainsKey($eventId)){throw 'Ledger duplicate eventId.'};$ids[$eventId]=$true
    if([string]$e.previousEventHash -cne $prev -or [string]$e.eventHash -cne (Get-LedgerEventHash $e)){throw 'Ledger event hash chain is invalid.'}
    $created=if($e.createdAtUtc -is [datetime]){[DateTimeOffset]([datetime]$e.createdAtUtc)}else{[DateTimeOffset]::Parse([string]$e.createdAtUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)}
    if($created -lt $previousCreated){throw 'Ledger timestamps are not monotonic.'};$previousCreated=$created
    $key=([string]$e.xqVersion)+'|'+([string]$e.fileName)
    if(-not $states.ContainsKey($key)){$states[$key]=[ordered]@{Status='none';ZipSha256='';M9RecordSha256='';LastEventType=''}}
    $state=$states[$key];$zip=([string]$e.zipSha256).ToUpperInvariant();$m9=([string]$e.m9RecordSha256).ToUpperInvariant()
    switch([string]$e.eventType){
      'publish' {
        if($state.Status -ne 'none'){throw 'Publish cannot reuse an existing release identity.'}
        $state.Status='active';$state.ZipSha256=$zip;$state.M9RecordSha256=$m9
      }
      'replace' {
        if($state.Status -ne 'active'){throw 'Replace without active publish.'}
        if($zip -cne $state.ZipSha256 -or $m9 -cne $state.M9RecordSha256){throw 'Replace cannot change immutable release bytes or M9 evidence.'}
      }
      'pause' {
        if($state.Status -ne 'active'){throw 'Pause without active publish.'}
        if($zip -cne $state.ZipSha256 -or $m9 -cne $state.M9RecordSha256){throw 'Pause event differs from the active release evidence.'}
        $state.Status='paused'
      }
      'withdraw' {
        if($state.Status -notin @('active','paused')){throw 'Withdraw without active release.'}
        if($zip -cne $state.ZipSha256 -or $m9 -cne $state.M9RecordSha256){throw 'Withdraw event differs from the active release evidence.'}
        $state.Status='withdrawn'
      }
      default {throw 'Invalid ledger event type.'}
    }
    $state.LastEventType=[string]$e.eventType;$prev=[string]$e.eventHash
  }
  return $states
}
function Assert-JsonSchema([string]$Json,[string]$SchemaPath,[string]$Label){
  if(-not(Test-Path -LiteralPath $SchemaPath -PathType Leaf)){throw ($Label+' schema is missing.')}
  if(-not(Test-Json -Json $Json -SchemaFile $SchemaPath)){throw ($Label+' does not satisfy its schema.')}
}
try {
  $r=Get-Content -LiteralPath $AcceptanceRecordPath -Raw|ConvertFrom-Json
  if($r.status -ne 'accepted'){throw 'M9 record is not accepted.'}
  & (Join-Path $PSScriptRoot 'Test-M9AcceptanceRecord.ps1') -RecordPath $AcceptanceRecordPath -PackagePath $DeliveryZipPath -EvidenceRoot $EvidenceRoot | Out-Null
  $name=[IO.Path]::GetFileName($DeliveryZipPath); if($name -match '(?i)^latest\.zip$' -or $name -notmatch '(?i)\.zip$'){throw 'Delivery ZIP must have a versioned filename, never latest.zip.'}
  if(-not(Test-Path -LiteralPath $DeliveryZipPath -PathType Leaf)){throw 'Delivery ZIP does not exist.'}
  $actual=(Get-FileHash -LiteralPath $DeliveryZipPath -Algorithm SHA256).Hash
  if($actual -cne [string]$r.package.sha256.ToUpperInvariant()){throw 'Delivery ZIP SHA-256 differs from M9-approved package hash.'}
  if($null -eq (Get-Command Test-Json -ErrorAction SilentlyContinue)){throw 'PowerShell 7 Test-Json is required.'}
  $listingJson=Get-Content -LiteralPath $ListingManifestPath -Raw;$configJson=Get-Content -LiteralPath $ProductConfigPath -Raw;$lockJson=Get-Content -LiteralPath $LockPath -Raw
  Assert-JsonSchema $listingJson (Join-Path $PSScriptRoot '..\manifest\schemas\product-listing.schema.json') 'Listing manifest'
  Assert-JsonSchema $configJson (Join-Path $PSScriptRoot '..\manifest\schemas\product-config.schema.json') 'Product config'
  Assert-JsonSchema $lockJson (Join-Path $PSScriptRoot '..\manifest\schemas\upstream-lock.schema.json') 'Approved upstream lock'
  $redactionModule=Join-Path $PSScriptRoot 'XQ.Redaction.psm1';if(-not(Test-Path -LiteralPath $redactionModule -PathType Leaf)){throw 'Shared M5 redaction module is missing.'};Import-Module $redactionModule -Force -DisableNameChecking;Assert-XqTextIsSafe -Text $listingJson
  $listing=$listingJson|ConvertFrom-Json;$config=$configJson|ConvertFrom-Json;$lock=$lockJson|ConvertFrom-Json
  if($listing.status -ne 'ready'){throw 'Listing manifest is not ready.'}
  if([string]$listing.xqVersion -cne [string]$r.package.xqVersion -or [string]$listing.zipFileName -cne $name -or [string]$listing.zipSha256.ToUpperInvariant() -cne $actual.ToUpperInvariant()){throw 'Listing does not match M9 package.'}
  if([string]$listing.xqVersion -cne [string]$config.productVersion -or [string]$listing.primaryMode -cne [string]$config.primaryInstallMode -or ((@($listing.supportedOs)-join '|') -cne (@($config.supportedOs)-join '|'))){throw 'Listing scope differs from product config.'}
  if([string]$listing.upstreamTag -cne [string]$lock.release.tag -or [string]$r.package.upstreamVersion -cne [string]$lock.release.tag){throw 'Listing or M9 upstream version differs from approved lock.'}
  $claims=(@($listing.claims)-join ' ');if($claims -match '(?i)official authorization|perpetual|unlimited token|guaranteed compatibility|官方授权|永久更新|无限\s*Token|无条件兼容'){throw 'Listing contains prohibited claims.'}
  $recordHash=(Get-FileHash -LiteralPath $AcceptanceRecordPath -Algorithm SHA256).Hash.ToUpperInvariant();$ledgerJson=Get-Content -LiteralPath $LedgerPath -Raw;Assert-JsonSchema $ledgerJson (Join-Path $PSScriptRoot '..\manifest\schemas\release-ledger.schema.json') 'Ledger';$ledger=$ledgerJson|ConvertFrom-Json;$states=Assert-Ledger $ledger
  $key=([string]$r.package.xqVersion+'|'+$name);if(-not $states.ContainsKey($key)){throw 'Ledger has no event for this release identity.'};$releaseState=$states[$key]
  if($releaseState.Status -ne 'active' -or $releaseState.LastEventType -notin @('publish','replace') -or $releaseState.ZipSha256 -cne $actual.ToUpperInvariant() -or $releaseState.M9RecordSha256 -cne $recordHash){throw 'Ledger has no matching active publish event for this exact M9 record and ZIP.'}
  Write-Output ('Delivery gate passed: '+$name+' '+$actual.ToUpperInvariant())
} catch { throw ('M10 delivery gate failed closed: '+$_.Exception.Message) }
