param(
  [Parameter(Mandatory=$true)][string]$ObsSdkRoot,
  [string]$QtRoot = "",
  [string]$Generator = "Visual Studio 18 2026",
  [switch]$ConfigureOnly
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not (Test-Path -LiteralPath $ObsSdkRoot)) { throw "OBS SDK directory not found: $ObsSdkRoot" }
$libobs = Get-ChildItem -LiteralPath $ObsSdkRoot -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -in @('libobsConfig.cmake','libobs-config.cmake') } | Select-Object -First 1
$frontend = Get-ChildItem -LiteralPath $ObsSdkRoot -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -in @('obs-frontend-apiConfig.cmake','obs-frontend-api-config.cmake') } | Select-Object -First 1
if (-not $libobs -or -not $frontend) {
  throw @"
No usable OBS *development SDK* found in '$ObsSdkRoot'.
OBS Studio's installed DLLs are not enough: you need the SDK CMake package files
libobsConfig.cmake and obs-frontend-apiConfig.cmake, plus their headers/libs.
Follow README.md for OBS 33 SDK setup.
"@
}
$paths = @($ObsSdkRoot)
if ($QtRoot) {
  if (-not (Test-Path -LiteralPath $QtRoot)) { throw "Qt root not found: $QtRoot" }
  $paths += $QtRoot
}
$prefixPath = $paths -join ';'
Write-Host "OBS SDK: $($libobs.DirectoryName)"
Write-Host "Frontend API: $($frontend.DirectoryName)"
$build = Join-Path $root 'build-obs33'
$args = @('-S', $root, '-B', $build, '-G', $Generator, '-A', 'x64',
  "-DOBS_SDK_ROOT=$ObsSdkRoot", "-Dlibobs_DIR=$($libobs.DirectoryName)",
  "-Dobs-frontend-api_DIR=$($frontend.DirectoryName)", "-DCMAKE_PREFIX_PATH=$prefixPath")
& cmake @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if (-not $ConfigureOnly) {
  & cmake --build $build --config Release
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  Write-Host 'Built. Verify in OBS Studio 33 before installing for regular use.'
}
