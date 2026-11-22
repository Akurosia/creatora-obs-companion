# Build Creatora OBS Companion against the existing OBS Studio 33.0.1 build.
# Run from any directory: .\scripts\build-obs33.ps1
[CmdletBinding()]
param(
    [string]$ObsRoot = 'C:\OBS-Development\obs-studio',
    [string]$QtRoot = 'C:\Qt\6.11.1\msvc2022_64',
    [string]$BuildDir = '',
    [ValidateSet('Release', 'RelWithDebInfo', 'Debug')]
    [string]$Configuration = 'Release',
    [int]$Parallel = 4,
    [string]$GitHubRepository = '',
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    $BuildDir = Join-Path $projectRoot 'build'
}

$obsBuild = Join-Path $ObsRoot 'build_x64'
$obsDeps = Join-Path $ObsRoot '.deps\obs-deps-2026-10-23-x64'
$libobsDir = Join-Path $obsBuild 'libobs'
$frontendDir = Join-Path $obsBuild 'frontend\api'
$pthreadsDir = Join-Path $obsBuild 'deps\w32-pthreads'
$finderDir = Join-Path $ObsRoot 'cmake\finders'
$simdeInclude = Join-Path $obsDeps 'include'
$qtConfigDir = Join-Path $QtRoot 'lib\cmake\Qt6'

$required = @(
    (Join-Path $libobsDir 'libobsConfig.cmake'),
    (Join-Path $frontendDir 'obs-frontend-apiConfig.cmake'),
    (Join-Path $pthreadsDir 'w32-pthreadsConfig.cmake'),
    (Join-Path $finderDir 'FindSIMDe.cmake'),
    (Join-Path $simdeInclude 'simde\simde-common.h'),
    (Join-Path $qtConfigDir 'Qt6Config.cmake'),
    (Join-Path $QtRoot 'lib\cmake\Qt6WebSockets\Qt6WebSocketsConfig.cmake'),
    (Join-Path $frontendDir 'Release\obs-frontend-api.lib'),
    (Join-Path $libobsDir 'Release\obs.lib')
)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing OBS dependency: $path`nCheck the OBS source/build and dependency paths."
    }
}
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw 'cmake not found on PATH.'
}
if ($Clean -and (Test-Path -LiteralPath $BuildDir)) {
    Write-Host "Removing build directory: $BuildDir"
    Remove-Item -LiteralPath $BuildDir -Recurse -Force
}

$prefix = @($obsDeps.Replace('\','/'), $QtRoot.Replace('\','/')) -join ';'
$argsConfigure = @(
    '-S', $projectRoot,
    '-B', $BuildDir,
    '-A', 'x64',
    "-Dlibobs_DIR=$($libobsDir.Replace('\','/'))",
    "-Dobs-frontend-api_DIR=$($frontendDir.Replace('\','/'))",
    "-Dw32-pthreads_DIR=$($pthreadsDir.Replace('\','/'))",
    "-DCMAKE_MODULE_PATH=$($finderDir.Replace('\','/'))",
    "-DSIMDe_INCLUDE_DIR=$($simdeInclude.Replace('\','/'))",
    "-DCMAKE_PREFIX_PATH=$prefix",
    "-DQt6_DIR=$($qtConfigDir.Replace('\','/'))",
    "-DCREATORA_GITHUB_REPOSITORY=$GitHubRepository"
)
Write-Host 'Configuring Creatora OBS Companion for OBS Studio 33.0.1...'
& cmake @argsConfigure
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed (exit $LASTEXITCODE)." }

Write-Host "Building Creatora OBS Companion ($Configuration)..."
& cmake --build $BuildDir --config $Configuration --parallel $Parallel
if ($LASTEXITCODE -ne 0) { throw "CMake build failed (exit $LASTEXITCODE)." }

Write-Host 'Build completed. Plugin DLL(s):'
Get-ChildItem -LiteralPath $BuildDir -Recurse -Filter '*creatora*.dll' -File -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName

# Automatically create the shipping ZIP in the project root after a successful build.
# The archive is not extracted or installed anywhere by this script.
$pluginDll = Join-Path (Join-Path $BuildDir $Configuration) 'creatora-obs-companion.dll'
$webSocketsDll = Join-Path $QtRoot 'bin\Qt6WebSockets.dll'
foreach ($file in @($pluginDll, $webSocketsDll)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Cannot create distribution ZIP; missing required file: $file"
    }
}

# This check is advisory: the installed OBS runtime might differ from the OBS build dependency.
$obsQtCore = Join-Path $ObsRoot '.deps\obs-deps-qt6-2026-10-23-x64\bin\Qt6Core.dll'
if (Test-Path -LiteralPath $obsQtCore -PathType Leaf) {
    $coreVersion = (Get-Item -LiteralPath $obsQtCore).VersionInfo.ProductVersion
    $wsVersion = (Get-Item -LiteralPath $webSocketsDll).VersionInfo.ProductVersion
    $coreMM = [regex]::Match($coreVersion, '^\d+\.\d+')
    $wsMM = [regex]::Match($wsVersion, '^\d+\.\d+')
    if ($coreMM.Success -and $wsMM.Success -and $coreMM.Value -ne $wsMM.Value) {
        Write-Warning "Qt mismatch: OBS build Qt $coreVersion vs plugin WebSockets Qt $wsVersion. This ZIP may not load in OBS; use matching Qt libraries before distribution."
    }
}

$outputZip = Join-Path $projectRoot 'creatora-obs-companion-obs33-win64.zip'
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ('creatora-obs-package-' + [guid]::NewGuid().ToString('N'))
try {
    $packageDir = Join-Path $staging 'creatora-obs-companion'
    New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
    Copy-Item -LiteralPath $pluginDll -Destination (Join-Path $packageDir 'creatora-obs-companion.dll')
    Copy-Item -LiteralPath $webSocketsDll -Destination (Join-Path $packageDir 'Qt6WebSockets.dll')
    @'
Creatora OBS Companion - OBS Studio 33 / Windows x64

Close OBS Studio and extract the creatora-obs-companion folder into:
%APPDATA%\obs-studio\plugins\

Expected file locations:
%APPDATA%\obs-studio\plugins\creatora-obs-companion\creatora-obs-companion.dll
%APPDATA%\obs-studio\plugins\creatora-obs-companion\Qt6WebSockets.dll

No installation script is required. Do not copy Qt6Core.dll into OBS.
Verify the plugin loads in Help > Log Files > View Current Log.
The plugin requires the matching Creatora server endpoints.
'@ | Set-Content -LiteralPath (Join-Path $packageDir 'INSTALL.txt') -Encoding UTF8

    $fileCount = @(Get-ChildItem -LiteralPath $packageDir -File -Recurse).Count
    if ($fileCount -ne 3) { throw "Unexpected package contents: expected 3 files, got $fileCount" }
    if (Test-Path -LiteralPath $outputZip) { Remove-Item -LiteralPath $outputZip -Force }
    Compress-Archive -LiteralPath $packageDir -DestinationPath $outputZip -CompressionLevel Optimal -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $outputZip -PathType Leaf)) { throw 'Distribution ZIP not created.' }
    Write-Host "Distribution ZIP created: $outputZip"
    Write-Host 'ZIP contains creatora-obs-companion/ with the 3 distribution files; nothing installed.'
} finally {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
}
