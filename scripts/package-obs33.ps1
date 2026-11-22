# Package a compiled Creatora OBS Companion for OBS 33 without installing it.
# Output: creatora-obs-companion-obs33-win64.zip
#          creatora-obs-companion/bin/64bit/creatora-obs-companion.dll
#          creatora-obs-companion/bin/64bit/Qt6WebSockets.dll
#          creatora-obs-companion/bin/64bit/tls/qschannelbackend.dll
#          creatora-obs-companion/INSTALL.txt
[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$QtRoot = 'C:\Qt\6.12.0\msvc2022_64',
    [string]$ObsInstallRoot = '',
    [string]$OutputZip = '',
    [switch]$SkipQtVersionCheck
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$pluginDll = Join-Path $ProjectRoot 'build\Release\creatora-obs-companion.dll'
$webSocketsDll = Join-Path $QtRoot 'bin\Qt6WebSockets.dll'
$schannelDll = Join-Path $QtRoot 'plugins\tls\qschannelbackend.dll'
foreach ($path in @($pluginDll, $webSocketsDll, $schannelDll)) {
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
    $pluginFolder = Join-Path $stage 'creatora-obs-companion'
    $binFolder = Join-Path $pluginFolder 'bin\64bit'
    $tlsFolder = Join-Path $binFolder 'tls'
    New-Item -ItemType Directory -Path $binFolder -Force | Out-Null
    New-Item -ItemType Directory -Path $tlsFolder -Force | Out-Null
    Copy-Item -LiteralPath $pluginDll -Destination (Join-Path $binFolder 'creatora-obs-companion.dll')
    Copy-Item -LiteralPath $webSocketsDll -Destination (Join-Path $binFolder 'Qt6WebSockets.dll')
    Copy-Item -LiteralPath $schannelDll -Destination (Join-Path $tlsFolder 'qschannelbackend.dll')
    @'
Creatora OBS Companion - Windows x64 / OBS Studio 33

This ZIP is a PER-USER OBS plugin package. It does not install automatically.

1. Close OBS Studio.
2. Extract the ZIP.
3. Copy the enclosed "creatora-obs-companion" folder into:
   %APPDATA%\obs-studio\plugins\
4. Start OBS and inspect Help > Log Files > View Current Log.

Expected installation layout:
%APPDATA%\obs-studio\plugins\creatora-obs-companion\bin\64bit\creatora-obs-companion.dll
%APPDATA%\obs-studio\plugins\creatora-obs-companion\bin\64bit\Qt6WebSockets.dll
%APPDATA%\obs-studio\plugins\creatora-obs-companion\bin\64bit\tls\qschannelbackend.dll

Do NOT copy Qt6Core.dll or other bundled Qt DLLs into OBS.
The Qt runtime version must be compatible with Qt6WebSockets.dll.
The companion requires corresponding Creatora server endpoints to pair and operate.
'@ | Set-Content -LiteralPath (Join-Path $pluginFolder 'INSTALL.txt') -Encoding UTF8

    $files = @(Get-ChildItem -LiteralPath $pluginFolder -Recurse -File)
    if ($files.Count -ne 4) { throw "Expected four distribution files; got $($files.Count)." }
    if (Test-Path -LiteralPath $OutputZip) { Remove-Item -LiteralPath $OutputZip -Force }
    Compress-Archive -LiteralPath $pluginFolder -DestinationPath $OutputZip -CompressionLevel Optimal
    Write-Host "Created: $OutputZip"
    Write-Host 'Contains top-level folder creatora-obs-companion with four files.'
    Write-Host 'Nothing was installed into OBS.'
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
