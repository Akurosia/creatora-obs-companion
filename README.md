> **CI / releases / update notices:** See [RELEASING.md](RELEASING.md). GitHub tags publish versioned Windows x64 ZIPs via a preconfigured OBS 33 Windows runner; the OBS dock checks public GitHub Releases for newer versions (manual install only).

# Creatora OBS Companion — OBS Studio 33 (Windows x64)

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
