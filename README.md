> **CI / releases / update notices:** See [RELEASING.md](RELEASING.md). GitHub tags publish versioned Windows x64 ZIPs via a preconfigured OBS 33 Windows runner; the OBS dock checks public GitHub Releases for newer versions (manual install only).

# Creatora OBS Companion — OBS Studio 32 and 33 (Windows x64)

Native source plugin. The server API is specified separately in `docs/CODEX_SERVER_IMPLEMENTATION.md`; it must be implemented before pairing works.

## Why the original CMake command failed

`C:/path/to/obs-and-qt-sdk` was an example placeholder. `find_package(libobs)` requires OBS **development** headers, import libraries, and a `libobsConfig.cmake` package file. Installing OBS Studio alone is insufficient. OBS 33 additionally requires compatible `obs-frontend-api` and Qt 6 modules including **Qt6 WebSockets**. Do not copy random `libobs.dll` or Qt DLLs into your project.

## Obtaining the OBS 33 development SDK

**Recommended:** use [OBS's official plugin template](https://github.com/obsproject/obs-plugintemplate) and its Windows dependency/bootstrap process, or build the [OBS Studio 33 source](https://github.com/obsproject/obs-studio/releases) following the [official Windows build instructions](https://github.com/obsproject/obs-studio/wiki/Build-Instructions-for-Windows). Pin the OBS **33.x** release you intend to support; the plugin template's current default version may NOT be OBS 33. Supply the resulting *installed CMake development packages* as an SDK directory.

The SDK directory must actually contain both of these files (under any nested folder):

- `libobsConfig.cmake` (or `libobs-config.cmake`)
- `obs-frontend-apiConfig.cmake` (or `obs-frontend-api-config.cmake`)

It must also contain the corresponding header and binary/import libraries. Use matching Qt 6 development packages (Core, Widgets, Network and WebSockets). **Qt6WebSockets is not guaranteed to be included in the OBS plugin template's downloaded Qt package**; if missing, obtain a compatible Qt6 WebSockets development package. Do not mix incompatible Qt runtimes in the OBS installation.

## Build command (PowerShell)

Once the OBS 33 SDK has been built and installed at an actual path, run:

```powershell
.\scripts\build-windows.ps1 -ObsSdkRoot 'C:\actual\obs33-sdk' -QtRoot 'C:\actual\compatible-qt6'
```

You can omit `-QtRoot` if Qt is already found by CMake via your environment. If your installed Visual Studio uses another generator, pass `-Generator 'Visual Studio 17 2022'` (or another installed generator). A clean build is generated under `build-obs33`.

Alternatively configure directly:

```powershell
cmake -S . -B build-obs33 -A x64 -DOBS_SDK_ROOT='C:/actual/obs33-sdk' -DCMAKE_PREFIX_PATH='C:/actual/compatible-qt6'
cmake --build build-obs33 --config Release
```

The project will report missing development packages explicitly, and checks OBS major version when the SDK exports it. Successful CMake configuration is **not** proof of ABI compatibility: validate loading and functionality in a matching OBS Studio 33 build.

## Installation and operation

Once built, install `creatora-obs-companion.dll` in OBS's Windows x64 plugin directory using an OBS-compatible plugin layout. Launch OBS Studio 33, open **Docks → Creatora Companion**, set the HTTPS server, pair it through the Creatora account dashboard, then click **Connect**.

By default the plugin connects **manually**. Enabling *Connect automatically when OBS starts* requires accepting a security warning. It uses outbound HTTPS/WSS only, Windows DPAPI for local credentials, short-lived tokens and a strict action allowlist. Disconnect immediately disables remote control; revoke the device in Creatora to invalidate server-side credentials.

## Status

This is **source code, not a verified OBS 33 binary**. It was not compiled against OBS 33 here because the Windows OBS/Qt development toolchain is unavailable in this environment. Runtime compatibility, secure pairing, and command execution require integration testing with your actual Creatora server and OBS 33.


## Local builds for OBS 32 and OBS 33

Build against a separately prepared OBS source/development tree for the target release.
Each target uses a separate CMake build directory and ZIP name.

```powershell
.\scripts\build-obs32.ps1 -ObsRoot 'C:\OBS-Development\obs-studio-32' -Clean
.\scripts\build-obs33.ps1 -ObsRoot 'C:\OBS-Development\obs-studio-33' -Clean
```

The scripts use `Akurosia/creatora-obs-companion` as the release repository and
derive the plugin version from the most recent reachable `vMAJOR.MINOR.PATCH`
Git tag. Run `git fetch --tags` after cloning if needed, or pass
`-Version '1.2.3'` and `-GitHubRepository 'owner/repo'` explicitly.
If no tag is available, the version falls back to `0.0.0` with a warning.

To build using the existing OBS 33 script for OBS 32 directly, pass
`-ObsMajor 32`. The OBS development tree must match the selected major.
CI publishes separate OBS 32 and OBS 33 Windows archives.

## OBS 32.1.x compatibility

The Windows CI builds **separate OBS 32.1.2 (Qt 6.8.3)** and
**OBS 32.2.2 (Qt 6.11.1)** binaries, each compiled against the matching
OBS source and Qt runtime. Use the ZIP matching your installed OBS version;
these builds are not interchangeable. OBS logs now print compiled/runtime Qt versions and an
explicit reason when the plugin's dock initialization fails.

If OBS prints only `Module '../../obs-plugins/64bit/creatora-obs-companion.dll' not loaded`,
check dependencies using `dumpbin /dependents creatora-obs-companion.dll`
from a Visual Studio developer command prompt. Windows may be unable to find
Qt6WebSockets or a required Qt entry point, and an OBS module-load failure alone
does not identify the exact error.

## Windows ZIP layouts

The local build scripts, standalone OBS 33 packager, and CI release packager
produce the same two-DLL layouts. ZIPs have no extra root folder, install
file, nested bin directory, or TLS folder.

OBS 33:
```text
plugins/
└── creatora-obs-companion/
    ├── creatora-obs-companion.dll
    └── Qt6WebSockets.dll
```

OBS 32:
```text
obs-plugins/
└── 64bit/
    ├── creatora-obs-companion.dll
    └── Qt6WebSockets.dll
```

### OBS-specific release archives

GitHub Actions now produces three distinct Windows archives for each version tag:

- `creatora-obs-companion-vVERSION-obs32.1.2-win64.zip` (OBS 32.1.2, Qt 6.8.3)
- `creatora-obs-companion-vVERSION-obs32.2.2-win64.zip` (OBS 32.2.2, Qt 6.11.1)
- `creatora-obs-companion-vVERSION-obs33.0.1-win64.zip` (OBS 33.0.1)

The archive's **internal folder layout** remains `obs-plugins/64bit` for both
OBS 32 versions and `plugins/creatora-obs-companion` for OBS 33. Each contains
only the two DLLs. The build verifies the Qt WebSockets DLL version against the
matching official OBS runtime, and release filenames include the exact OBS
version so that mismatched binaries are not installed accidentally.

## OBS-managed companion settings and portable installations

Creatora stores its local configuration through OBS's module configuration path
(`obs_module_config_path("settings.ini")`), rather than writing to the global
Windows registry using Qt's organization/application settings.

- Normal OBS: inside OBS's per-user `obs-studio/plugin_config/creatora-obs-companion/` folder.
- Portable OBS: inside that portable OBS installation's own `config/obs-studio/plugin_config/creatora-obs-companion/` folder.
- Configuration includes server URL, auto-connect preference, allowed-file list,
  and Windows DPAPI-encrypted credentials. Independent portable OBS installations
  no longer share a global configuration.

**Upgrading from older Creatora builds:** Existing global settings are **not**
imported automatically. Re-enter the server URL and pair once in each OBS
installation. This avoids accidentally sharing device credentials between
portable installations. Existing Windows registry data is not automatically
deleted. The DPAPI encryption still binds credentials to the Windows user;
copying a portable OBS folder to another Windows account or machine requires
pairing again.

## OBS major-version compatibility

OBS 32.1.2 uses Qt 6.8.3, whereas OBS 32.2.2 uses Qt 6.11.1. Qt aims for
binary forward compatibility from older to newer Qt 6 runtimes; this does not
guarantee OBS module ABI compatibility or that a bundled Qt6WebSockets DLL
will load in a newer OBS runtime. The known v0.1.8 binary failed to load
under OBS 32.2.2, so the CI retains **separate OBS 32.1.2 and 32.2.2
artifacts** until a single OBS 32 DLL pair is tested successfully on both.
OBS 33 uses its own artifact. Do not rename an unverified OBS 32.1 binary
as a universal OBS 32 release.
