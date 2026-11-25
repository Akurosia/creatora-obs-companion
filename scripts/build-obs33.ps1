# Build Creatora OBS Companion against an existing OBS Studio 32 or 33 development build.
# Run from any directory: .\scripts\build-obs33.ps1
[CmdletBinding()]
param(
    [string]$ObsRoot = 'C:\OBS-Development\obs-studio',
    [ValidateSet(32, 33)]
    [int]$ObsMajor = 33,
    [string]$QtRoot = 'C:\Qt\6.11.1\msvc2022_64',
    [string]$BuildDir = '',
    [ValidateSet('Release', 'RelWithDebInfo', 'Debug')]
    [string]$Configuration = 'Release',
    [int]$Parallel = 4,
    [string]$GitHubRepository = '',
    [string]$Version = '',
    [ValidateSet('stable', 'test')]
    [string]$ReleaseChannel = 'stable',
    [switch]$SkipLegacyPackage,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    $BuildDir = Join-Path $projectRoot "build-obs$ObsMajor"
}

if ([string]::IsNullOrWhiteSpace($GitHubRepository)) {
    $GitHubRepository = 'Akurosia/creatora-obs-companion'
}
if ($GitHubRepository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
    throw "Invalid GitHub repository: $GitHubRepository (expected owner/repo)"
}
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = '0.0.0'
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $tag = (& git -C $projectRoot describe --tags --abbrev=0 --match 'v[0-9]*' 2>$null)
        if ($LASTEXITCODE -eq 0 -and $tag -match '^v(\d+\.\d+\.\d+)$') {
            $Version = $Matches[1]
        }
    }
    if ($Version -eq '0.0.0') {
        Write-Warning 'No reachable vMAJOR.MINOR.PATCH git tag found; using version 0.0.0. Pass -Version explicitly or fetch tags.'
    }
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Version must be MAJOR.MINOR.PATCH' }
Write-Host "Building for OBS $ObsMajor; plugin version $Version; releases: $GitHubRepository"

$obsBuild = Join-Path $ObsRoot 'build_x64'
# Resolve dependency version from the OBS checkout, not a hardcoded local date.
$obsDeps = Get-ChildItem -LiteralPath (Join-Path $ObsRoot '.deps') -Directory -Filter 'obs-deps-*-x64' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike 'obs-deps-qt6-*' -and (Test-Path (Join-Path $_.FullName 'include\simde\simde-common.h')) } |
    Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $obsDeps) { throw 'OBS prebuilt dependencies are missing; configure OBS via its CMake preset first.' }
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
    "-DCREATORA_GITHUB_REPOSITORY=$GitHubRepository",
    "-DCREATORA_BUILD_VERSION=$Version",
    "-DCREATORA_RELEASE_CHANNEL=$ReleaseChannel",
    "-DCREATORA_OBS_MAJOR=$ObsMajor"
)
Write-Host "Configuring Creatora OBS Companion for OBS Studio $ObsMajor..."
& cmake @argsConfigure
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed (exit $LASTEXITCODE)." }

Write-Host "Building Creatora OBS Companion ($Configuration)..."
& cmake --build $BuildDir --config $Configuration --parallel $Parallel
if ($LASTEXITCODE -ne 0) { throw "CMake build failed (exit $LASTEXITCODE)." }

Write-Host 'Build completed. Plugin DLL(s):'
Get-ChildItem -LiteralPath $BuildDir -Recurse -Filter '*creatora*.dll' -File -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName

# Automatically create the legacy ZIP for local builds unless CI disables it.
if ($SkipLegacyPackage) { return }

# Automatically create the shipping ZIP in the project root after a successful build.
# The archive is not extracted or installed anywhere by this script.
$pluginDll = Join-Path (Join-Path $BuildDir $Configuration) 'creatora-obs-companion.dll'
$webSocketsDll = Join-Path $QtRoot 'bin\Qt6WebSockets.dll'
$tlsDll = Join-Path $QtRoot 'plugins\tls\qschannelbackend.dll'
foreach ($file in @($pluginDll, $webSocketsDll, $tlsDll)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Cannot create distribution ZIP; missing required file: $file"
    }
}

# This check is advisory: the installed OBS runtime might differ from the OBS build dependency.
$obsQtCore = Get-ChildItem -LiteralPath (Join-Path $ObsRoot '.deps') -Directory -Filter 'obs-deps-qt6-*-x64' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'bin\Qt6Core.dll' } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if ($obsQtCore -and (Test-Path -LiteralPath $obsQtCore -PathType Leaf)) {
    $coreVersion = (Get-Item -LiteralPath $obsQtCore).VersionInfo.ProductVersion
    $wsVersion = (Get-Item -LiteralPath $webSocketsDll).VersionInfo.ProductVersion
    $coreMM = [regex]::Match($coreVersion, '^\d+\.\d+')
    $wsMM = [regex]::Match($wsVersion, '^\d+\.\d+')
    if ($coreMM.Success -and $wsMM.Success -and $coreMM.Value -ne $wsMM.Value) {
        Write-Warning "Qt mismatch: OBS build Qt $coreVersion vs plugin WebSockets Qt $wsVersion. This ZIP may not load in OBS; use matching Qt libraries before distribution."
    }
}

$outputZip = Join-Path $projectRoot "creatora-obs-companion-obs$ObsMajor-win64.zip"
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ('creatora-obs-package-' + [guid]::NewGuid().ToString('N'))
try {
    if ($ObsMajor -eq 33) {
        $packageDir = Join-Path $staging 'plugins\creatora-obs-companion'
    } else {
        $packageDir = Join-Path $staging 'obs-plugins\64bit'
    }
    New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
    Copy-Item -LiteralPath $pluginDll -Destination (Join-Path $packageDir 'creatora-obs-companion.dll')
    Copy-Item -LiteralPath $webSocketsDll -Destination (Join-Path $packageDir 'Qt6WebSockets.dll')
    $tlsDir = Join-Path $packageDir 'tls'
    New-Item -ItemType Directory -Force -Path $tlsDir | Out-Null
    Copy-Item -LiteralPath $tlsDll -Destination (Join-Path $tlsDir 'qschannelbackend.dll')

    $files = @(Get-ChildItem -LiteralPath $staging -File -Recurse)
    if ($files.Count -ne 3) { throw "Unexpected package contents: expected 3 DLLs, got $($files.Count)" }
    if (Test-Path -LiteralPath $outputZip) { Remove-Item -LiteralPath $outputZip -Force }
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $outputZip -CompressionLevel Optimal -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $outputZip -PathType Leaf)) { throw 'Distribution ZIP not created.' }
    Write-Host "Distribution ZIP created: $outputZip"
    Write-Host "OBS $ObsMajor package contains exactly three DLLs (including tls/qschannelbackend.dll) in $($packageDir.Substring($staging.Length + 1)); nothing installed."
} finally {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
}
