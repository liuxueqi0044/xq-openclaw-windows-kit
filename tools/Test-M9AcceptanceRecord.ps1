#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$RecordPath,[Parameter(Mandatory)][string]$PackagePath,[string]$EvidenceRoot=(Split-Path -Parent $RecordPath),[string]$SchemaPath=(Join-Path $PSScriptRoot '..\manifest\schemas\acceptance-record.schema.json'))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Fail([string]$m){ throw ('M9 acceptance gate failed closed: '+$m) }
try {
  if(-not(Test-Path -LiteralPath $SchemaPath -PathType Leaf)){Fail 'acceptance schema is missing'}; $schema=Get-Content -LiteralPath $SchemaPath -Raw|ConvertFrom-Json; if($schema.type -ne 'object' -or $schema.properties.status.enum -notcontains 'accepted'){Fail 'acceptance schema is invalid'}
  $recordJson=Get-Content -LiteralPath $RecordPath -Raw
  $redactionModule=Join-Path $PSScriptRoot 'XQ.Redaction.psm1'; if(-not(Test-Path -LiteralPath $redactionModule -PathType Leaf)){Fail 'shared M5 redaction module is missing'}; Import-Module $redactionModule -Force -DisableNameChecking
  if($null -eq (Get-Command Test-Json -ErrorAction SilentlyContinue)){Fail 'PowerShell 7 Test-Json is required'}; if(-not(Test-Json -Json $recordJson -SchemaFile $SchemaPath)){Fail 'acceptance record does not satisfy its JSON schema'}
  $r=$recordJson | ConvertFrom-Json
  if($r.schemaVersion -ne 1){Fail 'unsupported schema'}
  if($r.status -ne 'accepted'){Fail 'record status must be accepted, not pending/rejected'}
  if(-not(Test-Path -LiteralPath $PackagePath -PathType Leaf)){Fail 'approved package file is missing'}
  if($r.vm.os -ne 'Windows 11' -or $r.vm.architecture -ne 'x64' -or $r.vm.cleanSnapshot -ne $true){Fail 'clean Windows 11 x64 VM evidence is required'}
  if([string]$r.vm.tester -eq '' -or [string]$r.vm.completedAtUtc -eq ''){Fail 'tester and completion time are required'}; try{[datetime]::Parse([string]$r.vm.completedAtUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)|Out-Null}catch{Fail 'completion time is not a valid date-time'}
  if([string]$r.package.fileName -match '(?i)^latest\.zip$' -or [string]$r.package.fileName -notmatch '(?i)\.zip$'){Fail 'delivery filename must be versioned and end in .zip'}
  if([string]$r.package.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [string]$r.package.upstreamVersion -eq ''){Fail 'package hash and upstream version are required'}
  if([IO.Path]::GetFileName($PackagePath) -cne [string]$r.package.fileName){Fail 'package filename differs from record'}
  $actualHash=(Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash
  if($actualHash -cne [string]$r.package.sha256.ToUpperInvariant()){Fail 'package hash differs from record'}
  $steps=@($r.steps); if($steps.Count -ne 12){Fail 'exactly twelve acceptance steps are required'}
  # The schema intentionally contains the control fields secretScan and
  # testKeyRevoked.  Normalize only those schema-constrained values before the
  # generic M5 assignment scan so their names do not create false positives;
  # every unconstrained record value is still scanned verbatim.
  $scanRecord=$recordJson|ConvertFrom-Json
  $scanRecord.evidence.secretScan='[REDACTED]'
  $scanRecord.credentials.testKeyRevoked='[REDACTED]'
  Assert-XqTextIsSafe -Text ($scanRecord|ConvertTo-Json -Depth 20)
  $root=[IO.Path]::GetFullPath($EvidenceRoot).TrimEnd('\')+'\';$rootItem=Get-Item -LiteralPath $EvidenceRoot;if(($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){Fail 'evidence root is a reparse point'}
  function Assert-NoAlternateDataStream([string]$path){
    if($null -eq (Get-Command Get-Item -ErrorAction SilentlyContinue)){return}
    try { $streams=@(Get-Item -LiteralPath $path -Stream * -ErrorAction Stop); foreach($stream in $streams){ if([string]$stream.Stream -notin @(':$DATA','::$DATA','$DATA','')){Fail ('alternate data stream is not allowed: '+$path)} } } catch [System.Management.Automation.ParameterBindingException] { Write-Verbose 'Alternate data stream inspection is unavailable on this platform.' }
  }
  Assert-NoAlternateDataStream $EvidenceRoot
  foreach($gateInput in @($RecordPath,$PackagePath)){
    $gateItem=Get-Item -LiteralPath $gateInput
    if(($gateItem.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){Fail ('gate input is a reparse point: '+[IO.Path]::GetFileName($gateInput))}
    if($gateItem.Length -le 0){Fail ('gate input is empty: '+[IO.Path]::GetFileName($gateInput))}
    Assert-NoAlternateDataStream $gateInput
  }
  function Assert-EvidenceRef([string]$ref){ if([string]::IsNullOrWhiteSpace($ref) -or [IO.Path]::IsPathRooted($ref) -or $ref -match '(^|[\\/])\.\.([\\/]|$)'){Fail 'evidence reference is absolute or traverses parent'}; $full=[IO.Path]::GetFullPath((Join-Path $root $ref)); if(-not $full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){Fail 'evidence reference escapes evidence root'}; if(-not(Test-Path -LiteralPath $full -PathType Leaf)){Fail ('missing evidence: '+$ref)}; $item=Get-Item -LiteralPath $full; if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Fail 'reparse evidence is not allowed'}; if($item.Length -le 0){Fail ('empty evidence is not allowed: '+$ref)}; Assert-NoAlternateDataStream $full }
  for($i=1;$i -le 12;$i++){ $s=@($steps|Where-Object id -eq $i); if($s.Count -ne 1 -or $s[0].result -ne 'passed' -or [string]::IsNullOrWhiteSpace($s[0].evidenceRef)){Fail ('step '+$i+' lacks passed evidence')}; Assert-EvidenceRef $s[0].evidenceRef }
  if(@($r.evidence.screenshots).Count -lt 5 -or @($r.evidence.screenshots|Select-Object -Unique).Count -ne @($r.evidence.screenshots).Count -or [string]::IsNullOrWhiteSpace($r.evidence.recording) -or [string]::IsNullOrWhiteSpace($r.evidence.diagnosticReport) -or [string]::IsNullOrWhiteSpace($r.evidence.defenderScan) -or [string]::IsNullOrWhiteSpace($r.evidence.uninstallCheck)){Fail 'required evidence references are missing or duplicate'}
  $textRefs=@($r.evidence.diagnosticReport,$r.evidence.defenderScan,$r.evidence.uninstallCheck)
  foreach($ref in @($r.evidence.screenshots)+@($r.evidence.recording)+$textRefs){Assert-EvidenceRef $ref}
  foreach($ref in $r.evidence.screenshots){if([IO.Path]::GetExtension([string]$ref) -notmatch '(?i)^\.(png|jpe?g|gif|bmp|webp)$'){Fail ('screenshot must be a common image file: '+$ref)}}
  if([IO.Path]::GetExtension([string]$r.evidence.recording) -notmatch '(?i)^\.(mp4|mov|mkv|webm|avi)$'){Fail 'recording evidence must be a common video file'}
  foreach($ref in $textRefs){if([IO.Path]::GetExtension([string]$ref) -notmatch '(?i)^\.(txt|json|md|log|xml|csv)$'){Fail ('diagnostic, Defender and uninstall evidence must be text-scannable: '+$ref)}}
  $allTextRefs=@($textRefs)+@($steps|ForEach-Object{$_.evidenceRef}); foreach($ref in $allTextRefs){ $full=[IO.Path]::GetFullPath((Join-Path $root $ref)); if([IO.Path]::GetExtension($full) -match '(?i)\.(txt|json|md|log|yaml|yml|xml|csv|ini|html?)$'){ $body=Get-Content -LiteralPath $full -Raw; try{Assert-XqTextIsSafe -Text $body}catch{Fail ('secret scan failed for '+$ref)}} }
  if($r.evidence.secretScan -ne 'passed' -or $r.privacy.reviewed -ne $true -or $r.credentials.testKeyRevoked -ne $true -or [string]::IsNullOrWhiteSpace($r.credentials.revokedAtUtc)){Fail 'privacy review, secret scan and key revocation are required'}; try{[datetime]::Parse([string]$r.credentials.revokedAtUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)|Out-Null}catch{Fail 'revocation time is not a valid date-time'}
  if([string]::IsNullOrWhiteSpace($r.approval.approvedBy) -or [string]::IsNullOrWhiteSpace($r.approval.approvedAtUtc)){Fail 'human M9 approver and approval time are required'}; try{[datetime]::Parse([string]$r.approval.approvedAtUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)|Out-Null}catch{Fail 'approval time is not a valid date-time'}
  Write-Output ('M9 accepted: '+$r.package.fileName+' '+$r.package.sha256.ToUpperInvariant())
} catch { if($_.Exception.Message -like 'M9 acceptance gate failed closed:*'){throw}; throw ('M9 acceptance gate failed closed: '+$_.Exception.Message) }
