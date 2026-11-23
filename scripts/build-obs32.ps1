# OBS 32 convenience entry point. Forwards all parameters to the shared build script.
[CmdletBinding()]
param(
    [string]$ObsRoot = 'C:\OBS-Development\obs-studio',
    [string]$QtRoot = 'C:\Qt\6.11.1\msvc2022_64',
    [string]$BuildDir = '',
    [ValidateSet('Release', 'RelWithDebInfo', 'Debug')]
    [string]$Configuration = 'Release',
    [int]$Parallel = 4,
    [string]$GitHubRepository = '',
    [string]$Version = '',
    [switch]$SkipLegacyPackage,
    [switch]$Clean
)
& (Join-Path $PSScriptRoot 'build-obs33.ps1') -ObsMajor 32 -ObsRoot $ObsRoot -QtRoot $QtRoot -BuildDir $BuildDir -Configuration $Configuration -Parallel $Parallel -GitHubRepository $GitHubRepository -Version $Version -SkipLegacyPackage:$SkipLegacyPackage -Clean:$Clean
if (-not $?) { throw 'OBS 32 build failed' }
