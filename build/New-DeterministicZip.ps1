#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceDirectory,
    [Parameter(Mandatory)][string]$ZipPath,
    [Parameter(Mandatory)][string]$ArchiveRoot,
    [datetime]$TimestampUtc = ([datetime]'2000-01-01T00:00:00Z')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-RelativeArchivePath([string]$Root, [string]$Path) {
    $relative = [IO.Path]::GetRelativePath($Root, $Path).Replace('\', '/')
    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|/)\.\.(/|$)') { throw 'Archive entry path escapes its source directory.' }
    return $relative
}

try {
    $sourceFull = [IO.Path]::GetFullPath($SourceDirectory)
    if (-not (Test-Path -LiteralPath $sourceFull -PathType Container)) { throw 'ZIP source directory does not exist.' }
    if ([string]::IsNullOrWhiteSpace($ArchiveRoot) -or $ArchiveRoot -match '[\\/]|\.\.') { throw 'Archive root name is unsafe.' }
    $zipFull = [IO.Path]::GetFullPath($ZipPath)
    $zipParent = Split-Path -Parent $zipFull
    if (-not (Test-Path -LiteralPath $zipParent)) { New-Item -ItemType Directory -Path $zipParent -Force | Out-Null }
    $partial = "$zipFull.$([guid]::NewGuid().ToString('N')).partial"
    try {
        $files = @(Get-ChildItem -LiteralPath $sourceFull -File -Recurse -Force | Sort-Object @{ Expression = { (Get-RelativeArchivePath $sourceFull $_.FullName) }; Ascending = $true })
        $stream = [IO.File]::Open($partial, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false, [Text.Encoding]::UTF8)
            try {
                foreach ($file in $files) {
                    $entryName = "$ArchiveRoot/$(Get-RelativeArchivePath $sourceFull $file.FullName)"
                    $entry = $archive.CreateEntry($entryName, [IO.Compression.CompressionLevel]::Optimal)
                    $entry.LastWriteTime = [DateTimeOffset]$TimestampUtc.ToUniversalTime()
                    $entryStream = $entry.Open(); $inputStream = [IO.File]::OpenRead($file.FullName)
                    try { $inputStream.CopyTo($entryStream) } finally { $inputStream.Dispose(); $entryStream.Dispose() }
                }
            }
            finally { $archive.Dispose() }
        }
        finally { $stream.Dispose() }
        Move-Item -LiteralPath $partial -Destination $zipFull -Force
    }
    finally { if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue } }
}
catch { throw 'Deterministic ZIP creation failed.' }
