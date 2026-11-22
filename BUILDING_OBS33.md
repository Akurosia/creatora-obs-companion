# Building and packaging Creatora OBS Companion for OBS Studio 33 (Windows x64)

This guide records the **working Windows development workflow** confirmed while building the Creatora OBS Companion against **OBS Studio 33.0.1**. The plugin ultimately loaded in the user's OBS installation after using **Qt 6.11.1**, matching OBS's runtime.

> Scope: Windows x64, OBS Studio **33.0.1**, Visual Studio 2026, CMake, portable OBS. Other OBS/Qt versions must be tested separately.
>
> The repository's `scripts/build-obs33.ps1` is the intended build-and-package entry point. Keep it aligned with the paths and versions below. The *latest locally adjusted script* was reported working, but that version of the script was not supplied for independent review.

## 1. Required tools

- **Visual Studio 2026** with **Desktop development with C++**, x64 MSVC toolchain and Windows SDK. The successful build used **Visual Studio 18 2026**, MSVC 19.51 and Windows SDK 10.0.28000.
- **CMake** with support for the Visual Studio generator; the successful build used CMake 4.4.
- **Git** (for cloning OBS and checking out the target tag).
- **OBS Studio 33.0.1 source** and its matching Windows dependency packages.
- **Qt 6.11.1 MSVC 2022 64-bit**, including **Qt WebSockets**. Do **not** use the `mingw_64` Qt installation with MSVC. Do **not** use Qt 6.12.0 for a plugin that must load in this OBS 33.0.1 runtime (Qt 6.11.1).

Verify tools in PowerShell:

```powershell
cmake --version
git --version
```

## 2. Confirmed local directory layout

```text
C:\OBS-Development\
├── obs-studio\                         # OBS 33.0.1 source and build
│   ├── build_x64\
│   └── .deps\
│       ├── obs-deps-2026-10-23-x64\
│       └── obs-deps-qt6-2026-10-23-x64\
└── creatora_obs_companion\            # This repository
    ├── CMakeLists.txt
    ├── src\
    └── scripts\build-obs33.ps1

C:\Qt\6.11.1\msvc2022_64\            # Matching Qt SDK + WebSockets
```

The dated OBS dependency directories are specific to the verified OBS source build. **Do not assume those names for other OBS versions or fresh checkouts**: inspect `obs-studio/build_x64/CMakeCache.txt` first.

## 3. Prepare OBS 33.0.1 source and dependencies

If OBS is not yet checked out:

```powershell
cd C:\OBS-Development
git clone --recursive https://github.com/obsproject/obs-studio.git
cd obs-studio
git fetch --tags
git checkout 33.0.1
git submodule update --init --recursive
```

Configure OBS using the checkout's CMake preset (the verified build had `windows-x64`):

```powershell
cmake --list-presets
cmake --preset windows-x64
```

This creates `build_x64` and prepares dependencies. **A CMake package configuration file alone does not mean the corresponding `.lib` was compiled.** In particular, build the OBS frontend API:

```powershell
cmake --build build_x64 --target obs-frontend-api --config Release --parallel 4
Test-Path "C:\OBS-Development\obs-studio\build_x64\frontend\api\Release\obs-frontend-api.lib"
```

The last command must return `True`. If the target/build fails, resolve that failure before compiling Creatora.

## 4. Install and verify matching Qt

Install **Qt 6.11.1 → MSVC 2022 64-bit** and the **Qt WebSockets** module using the Qt installer / Maintenance Tool. The MinGW variant is not interchangeable with MSVC.

```powershell
Test-Path "C:\Qt\6.11.1\msvc2022_64\lib\cmake\Qt6\Qt6Config.cmake"
Test-Path "C:\Qt\6.11.1\msvc2022_64\lib\cmake\Qt6WebSockets\Qt6WebSocketsConfig.cmake"
```

Both must return `True`.

Your OBS 33.0.1 portable runtime reported **Qt 6.11.1** in **Help → Log Files → View Current Log**. Match that runtime rather than using another Qt installation merely because it builds successfully. OBS's separate `obs-deps-qt6-2026-10-23-x64` package was missing `Qt6WebSocketsConfig.cmake`; this is why the matching external Qt installation is required for this project.

## 5. One-command build and ZIP packaging

From the repository root:

```powershell
cd C:\OBS-Development\creatora_obs_companion
.\scripts\build-obs33.ps1 -Clean
```

For subsequent incremental builds:

```powershell
.\scripts\build-obs33.ps1
```

The **working, locally adjusted build helper** must:

1. Configure with the OBS 33.0.1 `libobs` and `obs-frontend-api` packages.
2. Add OBS's `w32-pthreads` package, official CMake finders and SIMDe include path.
3. Select **Qt 6.11.1 MSVC** *explicitly* (and its WebSockets module), not OBS's incomplete Qt package or the previously installed Qt 6.12.0.
4. Build `Release` for Windows `x64`.
5. **Only after a successful build**, create/overwrite `creatora-obs-companion-obs33-win64.zip` **in the repository root**.
6. **Never automatically install** the plugin into an OBS directory.

### Manual CMake configuration (diagnostics/fallback)

If you need to reproduce the successful compile setup without the helper, use the following *confirmed development paths*:

```powershell
cd C:\OBS-Development\creatora_obs_companion

# Required when switching between Qt installations or after stale CMake cache errors:
if (Test-Path .\build) { Remove-Item .\build -Recurse -Force }

cmake -S . -B build -A x64 `
  -Dlibobs_DIR="C:/OBS-Development/obs-studio/build_x64/libobs" `
  -Dobs-frontend-api_DIR="C:/OBS-Development/obs-studio/build_x64/frontend/api" `
  -Dw32-pthreads_DIR="C:/OBS-Development/obs-studio/build_x64/deps/w32-pthreads" `
  -DCMAKE_MODULE_PATH="C:/OBS-Development/obs-studio/cmake/finders" `
  -DSIMDe_INCLUDE_DIR="C:/OBS-Development/obs-studio/.deps/obs-deps-2026-10-23-x64/include" `
  -DCMAKE_PREFIX_PATH="C:/OBS-Development/obs-studio/.deps/obs-deps-2026-10-23-x64;C:/Qt/6.11.1/msvc2022_64" `
  -DQt6_DIR="C:/Qt/6.11.1/msvc2022_64/lib/cmake/Qt6"

cmake --build build --config Release --parallel 4
```

The compiled DLL should be:

```text
build\Release\creatora-obs-companion.dll
```

> This manual sequence builds the DLL, **not** the final ZIP. The repository helper must perform the packaging step automatically after the build.

## 6. Required release ZIP layout (portable OBS 33)

The distribution file **in the project root** must be:

```text
creatora-obs-companion-obs33-win64.zip
└── creatora-obs-companion/
    ├── creatora-obs-companion.dll
    ├── Qt6WebSockets.dll
    └── INSTALL.txt
```

**No `bin/64bit/`, `bin/64-bit/`, or `obs-plugins/64bit/` directory inside this particular archive.** The folder structure above is the one requested and used for this portable OBS installation. The `Qt6WebSockets.dll` must be **the Qt 6.11.1 MSVC x64 build** matching OBS. Do not bundle `Qt6Core.dll`, `Qt6Network.dll`, `Qt6Widgets.dll`, `obs.dll`, or `obs-frontend-api.dll` from another SDK; OBS supplies its own copies.

Verify the ZIP with PowerShell:

```powershell
Add-Type -AssemblyName System.IO.Compression
$zip = [IO.Compression.ZipFile]::OpenRead(".\creatora-obs-companion-obs33-win64.zip")
try { $zip.Entries.FullName } finally { $zip.Dispose() }
```

Expected: three entries under `creatora-obs-companion/` and no nested `bin` path. The ZIP is only shippable after confirming it loads on OBS 33.0.1.

## 7. Manual installation into portable OBS

For the confirmed portable OBS setup, extract the ZIP's `creatora-obs-companion` folder to:

```text
<OBS-portable-root>\plugins\creatora-obs-companion\
```

The plugin DLL should end up at:

```text
<OBS-portable-root>\plugins\creatora-obs-companion\creatora-obs-companion.dll
```

Close OBS before copying the files, then launch OBS and check **Help → Log Files → View Current Log**. In the observed setup the portable OBS root was `C:\Users\kamot\Desktop\OBS`; it is not under `C:\Program Files\obs-studio`.

The OBS log initially showed:

```text
Module '../../plugins/creatora-obs-companion/creatora-obs-companion.dll' not loaded
```

The plugin was later reported to **load successfully** after switching the build to matching Qt **6.11.1**. A successfully produced `.dll` or `.zip` alone is not proof the plugin loads.

## 8. Troubleshooting history

| Symptom | Cause | Resolution |
|---|---|---|
| `find_package(libobs)` fails | SDK path was still a placeholder | Use `build_x64/libobs` and `build_x64/frontend/api` from the configured OBS source tree |
| `w32-pthreads` missing | `libobs` needs its CMake dependency | `-Dw32-pthreads_DIR=".../build_x64/deps/w32-pthreads"` |
| `SIMDe` package missing | OBS supplies a `FindSIMDe.cmake` finder, not necessarily `SIMDeConfig.cmake` | Set `CMAKE_MODULE_PATH` to `obs-studio/cmake/finders` and SIMDe include path to `.deps/obs-deps-2026-10-23-x64/include` |
| CMake error references `YOUR_ACTUAL_SIMDE_INCLUDE_DIRECTORY` | Literal placeholder cached | Replace with the real path; clean stale build cache if necessary |
| MSVC error `C2589` around `std::min` | Windows `min` macro conflict | Define `NOMINMAX` before `windows.h` or use `(std::min)(...)` as appropriate |
| Linker `LNK1181` for `obs-frontend-api.lib` | OBS frontend library configured but not built | Build `obs-frontend-api` Release target in the OBS tree |
| `Qt6WebSockets_DIR` missing | OBS's Qt dependency bundle does not include WebSockets | Use the matching Qt 6.11.1 MSVC SDK with Qt WebSockets installed |
| CMake builds successfully but OBS doesn't load DLL | Dependency/Qt runtime mismatch (observed Qt 6.12 vs 6.11.1) | Rebuild and package with matching Qt 6.11.1; inspect missing imports with Dependencies if necessary |
| DLL copy to `C:\Program Files\obs-studio` fails | OBS is portable elsewhere | Package only; manually extract to the portable OBS `plugins` folder |
| ZIP contains unwanted `bin/64bit` tree | Packaging helper assembled the wrong layout | Use the flat three-file `creatora-obs-companion/` ZIP layout above |

### Further checks if OBS fails to load the plugin

- Confirm OBS's log reports **OBS 33.0.1 x64** and **Qt 6.11.1**.
- Inspect the compiled plugin with [Dependencies](https://github.com/lucasg/Dependencies), configured to search `<OBS-portable-root>\bin\64bit`, to diagnose missing DLL imports.
- Make sure `Qt6WebSockets.dll` is located beside the plugin DLL and matches Qt 6.11.1 MSVC x64.
- Do not resolve loader issues by copying arbitrary Qt/OBS runtime DLLs into the plugin folder.

## 9. Connection and security requirements

The build/package workflow does **not** automatically connect to the Creatora server. The plugin's desired security policy is:

- **Manual connection by default.** Connecting requires an intentional user action.
- Optional **connect automatically on OBS startup** only after explicit opt-in with a clear warning that enabling it allows remotely authorized OBS actions while OBS is running and **may increase security risk**.
- Outbound TLS-protected connection to Creatora; do not expose a local OBS WebSocket port or password to the internet.
- Device-specific credentials, secure local storage, revocation, server-side permission checks and allowlisted OBS commands.

The initial protocol scope includes scene switching, scene-item visibility, and input muting. Implementing the server protocol and reviewing its security are separate from validating the OBS binary distribution; do not describe a successful DLL load as end-to-end security verification.

## 10. Release checklist

- [ ] Source is on OBS `33.0.1` and frontend API Release library has been built.
- [ ] Qt **6.11.1 MSVC x64** and `Qt6WebSockets` are present.
- [ ] Run `./scripts/build-obs33.ps1 -Clean` from the plugin repository.
- [ ] Build exits with success and creates a ZIP **at the project root**.
- [ ] ZIP contains exactly the flat `creatora-obs-companion/` folder with three distribution files.
- [ ] No Qt version mismatch warning.
- [ ] OBS 33.0.1 loads the plugin when manually installed in the portable `plugins` directory.
- [ ] Manual connection is the default; auto-connect remains an explicit, warned opt-in.
- [ ] Device pairing, revocation, command permissions and reconnect behavior have been tested against the actual Creatora server before public distribution.
