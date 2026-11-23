[CmdletBinding()]
param(
    [string]$BuildDir = 'build',
    [string]$Configuration = 'Release',
    [string]$QtRoot = 'C:\Qt\6.11.1\msvc2022_64',
    [Parameter(Mandatory=$true)][string]$Version,
    [ValidateSet(32, 33)][int]$ObsMajor = 33,
    [string]$OutputDir = 'dist',
    [string]$ObsQtCoreDll = ''
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not [IO.Path]::IsPathRooted($BuildDir)) { $BuildDir = Join-Path $root $BuildDir }
if (-not [IO.Path]::IsPathRooted($OutputDir)) { $OutputDir = Join-Path $root $OutputDir }
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Version must be Major.Minor.Patch' }
$pluginDll = Join-Path $BuildDir "$Configuration\creatora-obs-companion.dll"
$wsDll = Join-Path $QtRoot 'bin\Qt6WebSockets.dll'
foreach ($file in @($pluginDll, $wsDll)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing: $file" }
}
if (-not $ObsQtCoreDll) { throw 'ObsQtCoreDll is required: provide the Qt6Core.dll from the targeted OBS runtime.' }
if (-not (Test-Path -LiteralPath $ObsQtCoreDll -PathType Leaf)) { throw "Missing OBS Qt runtime: $ObsQtCoreDll" }
$coreVersion = (Get-Item -LiteralPath $ObsQtCoreDll).VersionInfo.ProductVersion
$wsVersion = (Get-Item -LiteralPath $wsDll).VersionInfo.ProductVersion
$cm = [regex]::Match($coreVersion, '^\d+\.\d+')
$wm = [regex]::Match($wsVersion, '^\d+\.\d+')
if (-not $cm.Success -or -not $wm.Success -or $cm.Value -ne $wm.Value) {
    throw "Qt ABI mismatch: OBS QtCore=$coreVersion, WebSockets=$wsVersion"
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$stage = Join-Path ([IO.Path]::GetTempPath()) ('creatora-release-' + [guid]::NewGuid().ToString('N'))
try {
    if ($ObsMajor -eq 33) {
        $dir = Join-Path $stage 'plugins\creatora-obs-companion'
    } else {
        $dir = Join-Path $stage 'obs-plugins\64bit'
    }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Copy-Item -LiteralPath $pluginDll -Destination (Join-Path $dir 'creatora-obs-companion.dll')
    Copy-Item -LiteralPath $wsDll -Destination (Join-Path $dir 'Qt6WebSockets.dll')
    $files = @(Get-ChildItem -LiteralPath $stage -File -Recurse)
    if ($files.Count -ne 2) { throw "Expected exactly 2 DLLs in the package, got $($files.Count)" }
    $zip = Join-Path $OutputDir "creatora-obs-companion-v$Version-obs$ObsMajor-win64.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
    # Validate the ZIP entries, not just the staging directory. Prevent nested bin
    # folders, extra files, and accidental changes to the OBS-specific layout.
    Add-Type -AssemblyName System.IO.Compression
    if ($ObsMajor -eq 33) {
        $expectedPaths = @(
            'plugins/creatora-obs-companion/creatora-obs-companion.dll',
            'plugins/creatora-obs-companion/Qt6WebSockets.dll'
        )
    } else {
        $expectedPaths = @(
            'obs-plugins/64bit/creatora-obs-companion.dll',
            'obs-plugins/64bit/Qt6WebSockets.dll'
        )
    }
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $actualPaths = @($archive.Entries |
            Where-Object { $_.Name -ne '' } |
            ForEach-Object { $_.FullName.Replace('\', '/') } |
            Sort-Object)
        $wantedPaths = @($expectedPaths | Sort-Object)
        if (($actualPaths -join '|') -ne ($wantedPaths -join '|')) {
            throw "Invalid OBS $ObsMajor archive layout. Expected: $($wantedPaths -join ', '); got: $($actualPaths -join ', ')"
        }
        Write-Host "Validated OBS $ObsMajor ZIP: $($actualPaths -join ', ')"
    } finally {
        $archive.Dispose()
    }
    $sha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    "$sha  $([IO.Path]::GetFileName($zip))" | Set-Content -LiteralPath "$zip.sha256" -Encoding ascii
    Write-Host "Release package: $zip"
} finally { if (Test-Path $stage) { Remove-Item $stage -Recurse -Force } }
