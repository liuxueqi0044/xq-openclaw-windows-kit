#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$LedgerPath,[Parameter(Mandatory)][ValidateSet('publish','pause','withdraw','replace')][string]$EventType,[Parameter(Mandatory)][string]$XqVersion,[Parameter(Mandatory)][string]$FileName,[Parameter(Mandatory)][string]$ZipSha256,[Parameter(Mandatory)][string]$M9RecordSha256,[Parameter(Mandatory)][string]$Actor,[string]$Reason='')
Set-StrictMode -Version Latest; $ErrorActionPreference='Stop'
function Get-CanonicalEvent($e){$created=if($e.createdAtUtc -is [datetime]){([datetime]$e.createdAtUtc).ToUniversalTime().ToString('o')}else{[string]$e.createdAtUtc};[ordered]@{eventId=[string]$e.eventId;eventType=[string]$e.eventType;xqVersion=[string]$e.xqVersion;fileName=[string]$e.fileName;zipSha256=[string]$e.zipSha256;m9RecordSha256=[string]$e.m9RecordSha256;createdAtUtc=$created;actor=[string]$e.actor;previousEventHash=[string]$e.previousEventHash;reason=[string]$e.reason}}
function Get-EventHash($e){$sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes((Get-CanonicalEvent $e|ConvertTo-Json -Compress -Depth 5)))).Replace('-','')).ToLowerInvariant()}finally{$sha.Dispose()}}
function Assert-LedgerChain($ledger){
  $seen=@{};$previous='GENESIS';$previousCreated=[DateTimeOffset]::MinValue;$states=@{}
  foreach($e in @($ledger.entries)){
    $eventId=[string]$e.eventId
    if($seen.ContainsKey($eventId)){throw 'Ledger contains duplicate eventId.'};$seen[$eventId]=$true
    if([string]$e.previousEventHash -cne $previous){throw 'Ledger previousEventHash chain is broken.'}
    if([string]$e.eventHash -cne (Get-EventHash $e)){throw 'Ledger eventHash does not match canonical event.'}
    $created=if($e.createdAtUtc -is [datetime]){[DateTimeOffset]([datetime]$e.createdAtUtc)}else{[DateTimeOffset]::Parse([string]$e.createdAtUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)}
    if($created -lt $previousCreated){throw 'Ledger timestamps are not monotonic.'};$previousCreated=$created
    if([string]::IsNullOrWhiteSpace([string]$e.xqVersion) -or [string]::IsNullOrWhiteSpace([string]$e.actor)){throw 'Ledger contains an empty release identity or actor.'}
    if([string]$e.fileName -match '(?i)^latest\.zip$' -or [string]$e.fileName -notmatch '(?i)\.zip$'){throw 'Ledger contains an invalid delivery filename.'}
    $key=([string]$e.xqVersion)+'|'+([string]$e.fileName)
    if(-not $states.ContainsKey($key)){$states[$key]=[ordered]@{Status='none';ZipSha256='';M9RecordSha256='';LastEventType=''}}
    $state=$states[$key];$zip=([string]$e.zipSha256).ToUpperInvariant();$m9=([string]$e.m9RecordSha256).ToUpperInvariant()
    switch([string]$e.eventType){
      'publish' {
        if($state.Status -ne 'none'){throw 'Publish cannot reuse an existing release identity.'}
        $state.Status='active';$state.ZipSha256=$zip;$state.M9RecordSha256=$m9
      }
      'replace' {
        if($state.Status -ne 'active'){throw 'Replace requires an active publish.'}
        if($zip -cne $state.ZipSha256 -or $m9 -cne $state.M9RecordSha256){throw 'Replace cannot change immutable ZIP or M9 approval bytes; publish a new versioned identity instead.'}
      }
      'pause' {
        if($state.Status -ne 'active'){throw 'Pause requires an active publish.'}
        if($zip -cne $state.ZipSha256 -or $m9 -cne $state.M9RecordSha256){throw 'Pause event differs from the active release evidence.'}
        $state.Status='paused'
      }
      'withdraw' {
        if($state.Status -notin @('active','paused')){throw 'Withdraw requires an active or paused release.'}
        if($zip -cne $state.ZipSha256 -or $m9 -cne $state.M9RecordSha256){throw 'Withdraw event differs from the active release evidence.'}
        $state.Status='withdrawn'
      }
      default {throw 'Unknown ledger event type.'}
    }
    $state.LastEventType=[string]$e.eventType;$previous=[string]$e.eventHash
  }
  return $states
}
$temp=$null
try {
  if([string]::IsNullOrWhiteSpace($XqVersion) -or [string]::IsNullOrWhiteSpace($Actor) -or $FileName -match '(?i)^latest\.zip$' -or $FileName -notmatch '(?i)\.zip$' -or $ZipSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or $M9RecordSha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Ledger event requires a version, actor, versioned ZIP filename and valid hashes.'}
  if($null -eq (Get-Command Test-Json -ErrorAction SilentlyContinue)){throw 'PowerShell 7 Test-Json is required.'};$ledgerJson=Get-Content -LiteralPath $LedgerPath -Raw;$ledgerSchemaPath=Join-Path $PSScriptRoot '..\manifest\schemas\release-ledger.schema.json';if(-not(Test-Json -Json $ledgerJson -SchemaFile $ledgerSchemaPath)){throw 'Ledger does not satisfy its schema.'};$ledger=$ledgerJson|ConvertFrom-Json;if($ledger.schemaVersion -ne 1){throw 'Unsupported ledger schema.'};$active=Assert-LedgerChain $ledger
  $key=$XqVersion+'|'+$FileName;$state=if($active.ContainsKey($key)){$active[$key].Status}else{'none'}
  if(($EventType -eq 'publish' -and $state -ne 'none') -or ($EventType -eq 'pause' -and $state -ne 'active') -or ($EventType -eq 'withdraw' -and $state -notin @('active','paused')) -or ($EventType -eq 'replace' -and $state -ne 'active')){throw ('Illegal state transition: '+$EventType)}
  $previous='GENESIS';$entries=@($ledger.entries);if($entries.Count -gt 0){$previous=[string]$entries[$entries.Count-1].eventHash}
  $entry=[ordered]@{eventId=[guid]::NewGuid().ToString('N');eventType=$EventType;xqVersion=$XqVersion;fileName=$FileName;zipSha256=$ZipSha256.ToUpperInvariant();m9RecordSha256=$M9RecordSha256.ToUpperInvariant();createdAtUtc=[DateTime]::UtcNow.ToString('o');actor=$Actor;previousEventHash=$previous;reason=$Reason};$entry.eventHash=Get-EventHash $entry
  $entries+=[pscustomobject]$entry;$output=[pscustomobject][ordered]@{schemaVersion=1;entries=$entries}
  Assert-LedgerChain $output|Out-Null
  $temp=$LedgerPath+'.'+[guid]::NewGuid().ToString('N')+'.partial';[IO.File]::WriteAllText($temp,($output|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)));Move-Item -LiteralPath $temp -Destination $LedgerPath -Force;Write-Output ('Ledger appended: '+$entry.eventType+' '+$entry.xqVersion+' '+$entry.eventId)
} catch { throw ('Release ledger update failed closed: '+$_.Exception.Message) }
finally { if($temp -and (Test-Path -LiteralPath $temp)){Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue} }
