[CmdletBinding()]
param(
    [string]$BuildDir = 'build',
    [string]$Configuration = 'Release',
    [string]$QtRoot = 'C:\Qt\6.11.1\msvc2022_64',
    [Parameter(Mandatory=$true)][string]$Version,
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
$schannelDll = Join-Path $QtRoot 'plugins\tls\qschannelbackend.dll'
foreach ($file in @($pluginDll, $wsDll, $schannelDll)) {
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
    $dir = Join-Path $stage 'creatora-obs-companion\bin\64bit'
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'tls') | Out-Null
    Copy-Item -LiteralPath $pluginDll -Destination $dir
    Copy-Item -LiteralPath $wsDll -Destination $dir
    Copy-Item -LiteralPath $schannelDll -Destination (Join-Path $dir 'tls')
    @"
Creatora OBS Companion v$Version — Windows x64 / OBS 33

Close OBS completely before updating.
Extract creatora-obs-companion into:
%APPDATA%\obs-studio\plugins\

Do not overwrite OBS Qt6Core.dll. Start OBS again after installation.
"@ | Set-Content -LiteralPath (Join-Path $stage 'creatora-obs-companion\INSTALL.txt') -Encoding utf8
    $zip = Join-Path $OutputDir "creatora-obs-companion-v$Version-obs33-win64.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $stage 'creatora-obs-companion') -DestinationPath $zip -CompressionLevel Optimal
    $sha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    "$sha  $([IO.Path]::GetFileName($zip))" | Set-Content -LiteralPath "$zip.sha256" -Encoding ascii
    Write-Host "Release package: $zip"
} finally { if (Test-Path $stage) { Remove-Item $stage -Recurse -Force } }
