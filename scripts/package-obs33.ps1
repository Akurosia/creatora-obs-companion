# Package the OBS 33 plugin with exactly two DLLs at plugins/creatora-obs-companion/.
[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$QtRoot = 'C:\Qt\6.12.0\msvc2022_64',
    [string]$BuildDir = '',
    [string]$ObsInstallRoot = '',
    [string]$OutputZip = '',
    [switch]$SkipQtVersionCheck
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
if ([string]::IsNullOrWhiteSpace($BuildDir)) { $BuildDir = Join-Path $ProjectRoot 'build-obs33' }
if (-not [IO.Path]::IsPathRooted($BuildDir)) { $BuildDir = Join-Path $ProjectRoot $BuildDir }
$pluginDll = Join-Path $BuildDir 'Release\creatora-obs-companion.dll'
$webSocketsDll = Join-Path $QtRoot 'bin\Qt6WebSockets.dll'
foreach ($path in @($pluginDll, $webSocketsDll)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required compiled DLL not found: $path"
    }
}

# Do not ship a Qt WebSockets build incompatible with OBS's Qt runtime.
if (-not $SkipQtVersionCheck) {
    if ([string]::IsNullOrWhiteSpace($ObsInstallRoot)) {
        throw 'Provide -ObsInstallRoot "C:\path\to\obs-studio" to check the installed OBS Qt runtime. This does NOT install anything.'
    }
    $obsQtDll = Join-Path $ObsInstallRoot 'bin\64bit\Qt6Core.dll'
    if (-not (Test-Path -LiteralPath $obsQtDll -PathType Leaf)) {
        throw "OBS Qt6Core.dll not found: $obsQtDll"
    }
    $obsQtVersion = (Get-Item -LiteralPath $obsQtDll).VersionInfo.ProductVersion
    $webSocketsVersion = (Get-Item -LiteralPath $webSocketsDll).VersionInfo.ProductVersion
    $obsMatch = [regex]::Match($obsQtVersion, '^\d+\.\d+')
    $webSocketsMatch = [regex]::Match($webSocketsVersion, '^\d+\.\d+')
    if (-not $obsMatch.Success -or -not $webSocketsMatch.Success -or $obsMatch.Value -ne $webSocketsMatch.Value) {
        throw "Qt version mismatch: OBS Qt6Core=$obsQtVersion vs Qt6WebSockets=$webSocketsVersion. Build WebSockets against OBS's Qt version; do not copy Qt6Core into OBS."
    }
    Write-Host "Compatible Qt major.minor versions: $($obsMatch.Value)"
} else {
    Write-Warning 'Qt runtime version check bypassed. The ZIP may fail to load or crash OBS if Qt versions differ.'
}

if ([string]::IsNullOrWhiteSpace($OutputZip)) {
    $OutputZip = Join-Path $ProjectRoot 'creatora-obs-companion-obs33-win64.zip'
}
$OutputZip = [System.IO.Path]::GetFullPath($OutputZip)
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ('creatora-obs33-' + [guid]::NewGuid().ToString('N'))
try {
    $pluginFolder = Join-Path $stage 'plugins\creatora-obs-companion'
    New-Item -ItemType Directory -Path $pluginFolder -Force | Out-Null
    Copy-Item -LiteralPath $pluginDll -Destination (Join-Path $pluginFolder 'creatora-obs-companion.dll')
    Copy-Item -LiteralPath $webSocketsDll -Destination (Join-Path $pluginFolder 'Qt6WebSockets.dll')
    $files = @(Get-ChildItem -LiteralPath $stage -Recurse -File)
    if ($files.Count -ne 2) { throw "Expected two DLLs; got $($files.Count)." }
    if (Test-Path -LiteralPath $OutputZip) { Remove-Item -LiteralPath $OutputZip -Force }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $OutputZip -CompressionLevel Optimal
    Write-Host "Created: $OutputZip"
    Write-Host 'Contains only plugins/creatora-obs-companion/creatora-obs-companion.dll and Qt6WebSockets.dll.'
    Write-Host 'Nothing was installed into OBS.'
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
