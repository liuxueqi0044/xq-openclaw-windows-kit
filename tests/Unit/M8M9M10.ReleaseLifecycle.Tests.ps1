Describe 'M8-M10 release gates' {
  BeforeAll {
    $repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path; Write-Verbose ('Test repository: '+$repo)
    function New-M9AcceptedFixture {
      $root=Join-Path ([IO.Path]::GetTempPath()) ('xq-m9-'+[guid]::NewGuid().ToString('N')); $evidence=Join-Path $root 'evidence'; New-Item -ItemType Directory -Path $evidence -Force | Out-Null
      $zip=Join-Path $root 'XQ-v0.1.0.zip'; [IO.File]::WriteAllBytes($zip,[byte[]](1,2,3,4)); $zipHash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToUpperInvariant()
      $steps=[System.Collections.Generic.List[object]]::new(); for($i=1;$i -le 12;$i++){ $ref="step$i.txt"; [IO.File]::WriteAllText((Join-Path $evidence $ref),"step $i passed`n",(New-Object Text.UTF8Encoding($false))); $steps.Add([ordered]@{id=$i;result='passed';evidenceRef=$ref}) }
      foreach($name in @('s1.png','s2.png','s3.png','s4.png','s5.png')){[IO.File]::WriteAllBytes((Join-Path $evidence $name),[byte[]](137,80,78,71))}
      [IO.File]::WriteAllBytes((Join-Path $evidence 'recording.mp4'),[byte[]](0,0,0,24,102,116,121,112,109,112,52,50))
      foreach($name in @('diagnostic.txt','defender.txt','uninstall.txt')){[IO.File]::WriteAllText((Join-Path $evidence $name),'reviewed; no credentials or secrets present.',(New-Object Text.UTF8Encoding($false)))}
      $record=[ordered]@{
        schemaVersion=1;status='accepted';package=[ordered]@{fileName='XQ-v0.1.0.zip';sha256=$zipHash;xqVersion='0.1.0';upstreamVersion='v2026.08.1'}
        vm=[ordered]@{os='Windows 11';architecture='x64';cleanSnapshot=$true;tester='tester';completedAtUtc='2026-08-28T01:00:00Z'}
        steps=@($steps);evidence=[ordered]@{screenshots=@('s1.png','s2.png','s3.png','s4.png','s5.png');recording='recording.mp4';diagnosticReport='diagnostic.txt';defenderScan='defender.txt';uninstallCheck='uninstall.txt';secretScan='passed'}
        privacy=[ordered]@{reviewed=$true;notes='reviewed'};credentials=[ordered]@{testKeyRevoked=$true;revokedAtUtc='2026-08-28T01:10:00Z'};approval=[ordered]@{approvedBy='approver';approvedAtUtc='2026-08-28T01:20:00Z'}
      }
      $recordPath=Join-Path $root 'acceptance-record.json'; [IO.File]::WriteAllText($recordPath,($record|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
      [pscustomobject]@{Root=$root;Evidence=$evidence;Zip=$zip;Record=$recordPath;Hash=$zipHash}
    }
    function Get-TestLedgerEventHash($ledgerEvent) {
      $created=if($ledgerEvent.createdAtUtc -is [datetime]){([datetime]$ledgerEvent.createdAtUtc).ToUniversalTime().ToString('o')}else{[string]$ledgerEvent.createdAtUtc}
      $canonical=[ordered]@{eventId=[string]$ledgerEvent.eventId;eventType=[string]$ledgerEvent.eventType;xqVersion=[string]$ledgerEvent.xqVersion;fileName=[string]$ledgerEvent.fileName;zipSha256=[string]$ledgerEvent.zipSha256;m9RecordSha256=[string]$ledgerEvent.m9RecordSha256;createdAtUtc=$created;actor=[string]$ledgerEvent.actor;previousEventHash=[string]$ledgerEvent.previousEventHash;reason=[string]$ledgerEvent.reason}
      $sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($canonical|ConvertTo-Json -Compress -Depth 5)))).Replace('-','')).ToLowerInvariant()}finally{$sha.Dispose()}
    }
  }
  It 'workflows are read-only, pinned and separate candidate from release' {
    $a=Get-Content (Join-Path $repo '.github\workflows\resolve-candidate.yml') -Raw; $b=Get-Content (Join-Path $repo '.github\workflows\build-release.yml') -Raw
    ($a+$b) | Should -Not -Match 'uses:\s+actions/[^@\r\n]+@(v|main|master)(\s|$)'
    $a | Should -Not -Match '(?m)^\s*schedule:'
    @([regex]::Matches(($a+$b), '(?m)^\s*uses:\s+[^@\s]+@([A-Fa-f0-9]{40})\s')).Count | Should -BeGreaterThan 0
    @([regex]::Matches(($a+$b), '(?m)^\s*uses:\s+[^@\s]+@[^\s]+')).Value | ForEach-Object { $_ | Should -Match '@[A-Fa-f0-9]{40}(\s|$)' }
    ($a+$b) | Should -Match 'contents:\s*read'; $a | Should -Not -Match 'Build-Package|\.zip'; $a | Should -Match 'candidate-lock|candidate'
    @([regex]::Matches(($a+$b), 'persist-credentials:\s*false')).Count | Should -Be 2
    $b | Should -Match 'SOURCE_REF:\s*\$\{\{ inputs\.source_ref \}\}'; $b | Should -Not -Match "'\$\{\{ inputs\.source_ref \}\}'"
    $b | Should -Match 'approval\.status'; $b | Should -Match 'Upload candidate evidence|package-candidate'; $b | Should -Not -Match 'latest\.zip'
    $b | Should -Match 'Fetch-LockedArtifacts'; $b | Should -Match 'Invoke-QualityGates.*PesterModulePath'; $b | Should -Match 'Build-Package.*VerifiedDirectory.*OutputDirectory'; $b | Should -Match 'test-summary\.json\.report\.json'; $b | Should -Match 'test-summary\.json\.coverage\.xml'
  }
  It 'M9 gate rejects pending records and missing evidence' {
    $gate=Get-Content (Join-Path $repo 'tools\Test-M9AcceptanceRecord.ps1') -Raw
    $gate | Should -Match 'status.*accepted'; $gate | Should -Match 'cleanSnapshot'; $gate | Should -Match 'Get-XqSensitiveFindings|Assert-XqTextIsSafe'; $gate | Should -Match 'ReparsePoint|evidence root'
    $templatePath=Join-Path $repo 'evidence\templates\acceptance-record.template.json';$templateJson=Get-Content $templatePath -Raw;$template=$templateJson|ConvertFrom-Json; $template.status | Should -Be 'pending'
    Test-Json -Json $templateJson -SchemaFile (Join-Path $repo 'manifest\schemas\acceptance-record.schema.json') | Should -BeTrue
  }
  It 'M10 gate rejects latest, hash mismatch and non-published ledger state' {
    $gate=Get-Content (Join-Path $repo 'tools\Test-M10Delivery.ps1') -Raw
    $gate | Should -Match 'latest'; $gate | Should -Match 'SHA-256'; $gate | Should -Match 'eventType'; $gate | Should -Match 'Test-M9AcceptanceRecord'
    $schema=Get-Content (Join-Path $repo 'manifest\schemas\release-ledger.schema.json') -Raw|ConvertFrom-Json; $schema.properties.entries.items.required | Should -Contain 'previousEventHash'; $schema.properties.entries.items.required | Should -Contain 'eventHash'
    Test-Json -LiteralPath (Join-Path $repo 'evidence\templates\release-ledger.json') -SchemaFile (Join-Path $repo 'manifest\schemas\release-ledger.schema.json') | Should -BeTrue
    Test-Json -LiteralPath (Join-Path $repo 'evidence\templates\product-listing.template.json') -SchemaFile (Join-Path $repo 'manifest\schemas\product-listing.schema.json') | Should -BeTrue
  }
  It 'machine gates reject pending evidence and a non-accepted delivery' {
    $pending=Join-Path ([IO.Path]::GetTempPath()) ('xq-pending-'+[guid]::NewGuid().ToString('N')+'.json'); $zip=Join-Path ([IO.Path]::GetTempPath()) ('XQ-test-'+[guid]::NewGuid().ToString('N')+'.zip')
    try {
      Copy-Item (Join-Path $repo 'evidence\templates\acceptance-record.template.json') $pending; [IO.File]::WriteAllBytes($zip,[byte[]](1,2,3))
      { & (Join-Path $repo 'tools\Test-M9AcceptanceRecord.ps1') -RecordPath $pending -PackagePath $zip -EvidenceRoot ([IO.Path]::GetTempPath()) } | Should -Throw
      { & (Join-Path $repo 'tools\Test-M10Delivery.ps1') -AcceptanceRecordPath $pending -DeliveryZipPath $zip -LedgerPath (Join-Path $repo 'evidence\templates\release-ledger.json') -ListingManifestPath (Join-Path $repo 'evidence\templates\product-listing.template.json') -ProductConfigPath (Join-Path $repo 'manifest\product-config.json') -LockPath $pending } | Should -Throw
    } finally { if([IO.File]::Exists($pending)){[IO.File]::Delete($pending)}; if([IO.File]::Exists($zip)){[IO.File]::Delete($zip)} }
  }
  It 'ledger appends immutable events with a hash chain' {
    $ledger=Join-Path ([IO.Path]::GetTempPath()) ('xq-ledger-'+[guid]::NewGuid().ToString('N')+'.json'); Copy-Item (Join-Path $repo 'evidence\templates\release-ledger.json') $ledger
    try {
      $hash=('A'*64)
      & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType publish -XqVersion 0.1.0 -FileName XQ-v0.1.0.zip -ZipSha256 $hash -M9RecordSha256 $hash -Actor tester | Out-Null
      & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType pause -XqVersion 0.1.0 -FileName XQ-v0.1.0.zip -ZipSha256 $hash -M9RecordSha256 $hash -Actor tester -Reason test | Out-Null
      & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType withdraw -XqVersion 0.1.0 -FileName XQ-v0.1.0.zip -ZipSha256 $hash -M9RecordSha256 $hash -Actor tester -Reason test | Out-Null
      $l=Get-Content $ledger -Raw|ConvertFrom-Json; $l.entries.Count | Should -Be 3; $l.entries[1].previousEventHash | Should -Be $l.entries[0].eventHash; $l.entries[2].previousEventHash | Should -Be $l.entries[1].eventHash
    } finally { if([IO.File]::Exists($ledger)){[IO.File]::Delete($ledger)} }
  }
  It 'rejects tampered or reordered ledger history before append' {
    $ledger=Join-Path ([IO.Path]::GetTempPath()) ('xq-ledger-tamper-'+[guid]::NewGuid().ToString('N')+'.json'); Copy-Item (Join-Path $repo 'evidence\templates\release-ledger.json') $ledger
    try {
      $hash=('B'*64); & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType publish -XqVersion 0.1.0 -FileName XQ-v0.1.0.zip -ZipSha256 $hash -M9RecordSha256 $hash -Actor tester | Out-Null
      & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType pause -XqVersion 0.1.0 -FileName XQ-v0.1.0.zip -ZipSha256 $hash -M9RecordSha256 $hash -Actor tester | Out-Null
      $tampered=Get-Content $ledger -Raw|ConvertFrom-Json; $tampered.entries[0].actor='attacker'; $tampered|ConvertTo-Json -Depth 10|Set-Content $ledger
      { & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType pause -XqVersion 0.1.0 -FileName XQ-v0.1.0.zip -ZipSha256 $hash -M9RecordSha256 $hash -Actor tester } | Should -Throw
      Copy-Item (Join-Path $repo 'evidence\templates\release-ledger.json') $ledger
      & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType publish -XqVersion 0.1.0 -FileName XQ-v0.1.0.zip -ZipSha256 $hash -M9RecordSha256 $hash -Actor tester | Out-Null
      & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType pause -XqVersion 0.1.0 -FileName XQ-v0.1.0.zip -ZipSha256 $hash -M9RecordSha256 $hash -Actor tester | Out-Null
      $reordered=Get-Content $ledger -Raw|ConvertFrom-Json; [array]::Reverse($reordered.entries); $reordered|ConvertTo-Json -Depth 10|Set-Content $ledger
      { & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType withdraw -XqVersion 0.1.0 -FileName XQ-v0.1.0.zip -ZipSha256 $hash -M9RecordSha256 $hash -Actor tester } | Should -Throw
    } finally { if([IO.File]::Exists($ledger)){[IO.File]::Delete($ledger)} }
  }
  It 'rejects illegal republish and in-place replacement of immutable bytes' {
    $ledger=Join-Path ([IO.Path]::GetTempPath()) ('xq-ledger-state-'+[guid]::NewGuid().ToString('N')+'.json'); Copy-Item (Join-Path $repo 'evidence\templates\release-ledger.json') $ledger
    try {
      $hash=('C'*64);$m9=('D'*64)
      & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType publish -XqVersion 0.1.0 -FileName XQ-v0.1.0.zip -ZipSha256 $hash -M9RecordSha256 $m9 -Actor tester | Out-Null
      { & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType replace -XqVersion 0.1.0 -FileName XQ-v0.1.0.zip -ZipSha256 ('E'*64) -M9RecordSha256 $m9 -Actor tester } | Should -Throw
      & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType pause -XqVersion 0.1.0 -FileName XQ-v0.1.0.zip -ZipSha256 $hash -M9RecordSha256 $m9 -Actor tester | Out-Null
      { & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType publish -XqVersion 0.1.0 -FileName XQ-v0.1.0.zip -ZipSha256 $hash -M9RecordSha256 $m9 -Actor tester } | Should -Throw
    } finally { if([IO.File]::Exists($ledger)){[IO.File]::Delete($ledger)} }
  }
  It 'rejects a validly rehashed event whose timestamp moves backwards' {
    $ledger=Join-Path ([IO.Path]::GetTempPath()) ('xq-ledger-time-'+[guid]::NewGuid().ToString('N')+'.json'); Copy-Item (Join-Path $repo 'evidence\templates\release-ledger.json') $ledger
    try {
      $hash=('7'*64);& (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType publish -XqVersion 0.1.0 -FileName XQ-v0.1.0.zip -ZipSha256 $hash -M9RecordSha256 $hash -Actor tester | Out-Null
      & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType pause -XqVersion 0.1.0 -FileName XQ-v0.1.0.zip -ZipSha256 $hash -M9RecordSha256 $hash -Actor tester | Out-Null
      $changed=Get-Content $ledger -Raw|ConvertFrom-Json;$changed.entries[1].createdAtUtc=[datetime]'2000-01-01T00:00:00Z';$changed.entries[1].eventHash=Get-TestLedgerEventHash $changed.entries[1];[IO.File]::WriteAllText($ledger,($changed|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
      { & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType withdraw -XqVersion 0.1.0 -FileName XQ-v0.1.0.zip -ZipSha256 $hash -M9RecordSha256 $hash -Actor tester } | Should -Throw
    } finally { if([IO.File]::Exists($ledger)){[IO.File]::Delete($ledger)} }
  }
  It 'accepts a complete M9 fixture and rejects evidence or package hash tampering' {
    $fixture=New-M9AcceptedFixture
    try {
      { & (Join-Path $repo 'tools\Test-M9AcceptanceRecord.ps1') -RecordPath $fixture.Record -PackagePath $fixture.Zip -EvidenceRoot $fixture.Evidence } | Should -Not -Throw
      $badEvidence=Join-Path $fixture.Evidence 'diagnostic.txt'; [IO.File]::WriteAllText($badEvidence,'gatewayToken=short-secret',(New-Object Text.UTF8Encoding($false)));
      { & (Join-Path $repo 'tools\Test-M9AcceptanceRecord.ps1') -RecordPath $fixture.Record -PackagePath $fixture.Zip -EvidenceRoot $fixture.Evidence } | Should -Throw
      [IO.File]::WriteAllText($badEvidence,'',(New-Object Text.UTF8Encoding($false)))
      { & (Join-Path $repo 'tools\Test-M9AcceptanceRecord.ps1') -RecordPath $fixture.Record -PackagePath $fixture.Zip -EvidenceRoot $fixture.Evidence } | Should -Throw
      [IO.File]::WriteAllText($badEvidence,'reviewed; no credentials or secrets present.',(New-Object Text.UTF8Encoding($false))); $bad=Get-Content $fixture.Record -Raw|ConvertFrom-Json; $bad.package.sha256=('F'*64); [IO.File]::WriteAllText($fixture.Record,($bad|ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
      { & (Join-Path $repo 'tools\Test-M9AcceptanceRecord.ps1') -RecordPath $fixture.Record -PackagePath $fixture.Zip -EvidenceRoot $fixture.Evidence } | Should -Throw
    } finally { if(Test-Path $fixture.Root){Remove-Item -LiteralPath $fixture.Root -Recurse -Force} }
  }
  It 'accepts a matching M10 delivery, then blocks pause and listing mismatch' {
    $fixture=New-M9AcceptedFixture; $ledger=Join-Path $fixture.Root 'release-ledger.json'; $listing=Join-Path $fixture.Root 'listing.json'; $config=Join-Path $fixture.Root 'product-config.json'; $lock=Join-Path $fixture.Root 'upstream-lock.json'
    try {
      Copy-Item (Join-Path $repo 'evidence\templates\release-ledger.json') $ledger
      $recordHash=(Get-FileHash -LiteralPath $fixture.Record -Algorithm SHA256).Hash.ToUpperInvariant()
      & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType publish -XqVersion '0.1.0' -FileName 'XQ-v0.1.0.zip' -ZipSha256 $fixture.Hash -M9RecordSha256 $recordHash -Actor tester | Out-Null
      & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType replace -XqVersion '0.1.0' -FileName 'XQ-v0.1.0.zip' -ZipSha256 $fixture.Hash -M9RecordSha256 $recordHash -Actor tester -Reason 'rebind identical approved bytes' | Out-Null
      & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType publish -XqVersion '9.9.9' -FileName 'XQ-v9.9.9.zip' -ZipSha256 ('9'*64) -M9RecordSha256 ('9'*64) -Actor tester | Out-Null
      $listingObject=[ordered]@{schemaVersion=1;status='ready';xqVersion='0.1.0';upstreamTag='v2026.08.1';supportedOs=@('Windows 11 x64');primaryMode='windows-hub-local-managed-wsl';claims=@('独立中文引导与只读诊断资料');zipFileName='XQ-v0.1.0.zip';zipSha256=$fixture.Hash}; [IO.File]::WriteAllText($listing,($listingObject|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
      Copy-Item (Join-Path $repo 'manifest\product-config.json') $config
      Copy-Item (Join-Path $repo 'tests\Fixtures\m1m2\approved-upstream-lock.json') $lock
      $lockObject=Get-Content $lock -Raw|ConvertFrom-Json; $lockObject.release.tag='v2026.08.1'; [IO.File]::WriteAllText($lock,($lockObject|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
      { & (Join-Path $repo 'tools\Test-M10Delivery.ps1') -AcceptanceRecordPath $fixture.Record -DeliveryZipPath $fixture.Zip -LedgerPath $ledger -ListingManifestPath $listing -ProductConfigPath $config -LockPath $lock -EvidenceRoot $fixture.Evidence } | Should -Not -Throw
      $badLedger=Join-Path $fixture.Root 'bad-ledger.json'; Copy-Item (Join-Path $repo 'evidence\templates\release-ledger.json') $badLedger; & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $badLedger -EventType publish -XqVersion '0.1.0' -FileName 'XQ-v0.1.0.zip' -ZipSha256 $fixture.Hash -M9RecordSha256 ('0'*64) -Actor tester | Out-Null
      { & (Join-Path $repo 'tools\Test-M10Delivery.ps1') -AcceptanceRecordPath $fixture.Record -DeliveryZipPath $fixture.Zip -LedgerPath $badLedger -ListingManifestPath $listing -ProductConfigPath $config -LockPath $lock -EvidenceRoot $fixture.Evidence } | Should -Throw
      & (Join-Path $repo 'tools\Update-ReleaseLedger.ps1') -LedgerPath $ledger -EventType pause -XqVersion '0.1.0' -FileName 'XQ-v0.1.0.zip' -ZipSha256 $fixture.Hash -M9RecordSha256 $recordHash -Actor tester -Reason 'test' | Out-Null
      { & (Join-Path $repo 'tools\Test-M10Delivery.ps1') -AcceptanceRecordPath $fixture.Record -DeliveryZipPath $fixture.Zip -LedgerPath $ledger -ListingManifestPath $listing -ProductConfigPath $config -LockPath $lock -EvidenceRoot $fixture.Evidence } | Should -Throw
      $listingObject.xqVersion='0.1.1'; [IO.File]::WriteAllText($listing,($listingObject|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
      { & (Join-Path $repo 'tools\Test-M10Delivery.ps1') -AcceptanceRecordPath $fixture.Record -DeliveryZipPath $fixture.Zip -LedgerPath (Join-Path $repo 'evidence\templates\release-ledger.json') -ListingManifestPath $listing -ProductConfigPath $config -LockPath $lock -EvidenceRoot $fixture.Evidence } | Should -Throw
    } finally { if(Test-Path $fixture.Root){Remove-Item -LiteralPath $fixture.Root -Recurse -Force} }
  }
}
