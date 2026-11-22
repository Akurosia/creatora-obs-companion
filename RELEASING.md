# Release process (OBS Studio 33 / Windows x64)

The `.github/workflows/release.yml` workflow builds on a **trusted, dedicated Windows self-hosted GitHub Actions runner** with the `obs33` label. This is intentional: the supplied project depends on a prebuilt OBS 33.0.1 development tree and a matching Qt installation. It will not build on a stock GitHub-hosted runner without first bootstrapping those dependencies. Do not attach this runner to public fork pull-request workflows.

Set repository **Settings → Secrets and variables → Actions → Variables**:

- `OBS_SOURCE_ROOT` (e.g. `C:\OBS-Development\obs-studio`): OBS source tree with `build_x64` and expected 33.0.1 deps.
- `QT_ROOT` (e.g. `C:\Qt\6.11.1\msvc2022_64`): matching MSVC Qt SDK with WebSockets and Schannel.
- `OBS_QT_CORE_DLL`: full path to `Qt6Core.dll` shipped with the OBS runtime you support, for a Qt major.minor compatibility guard.

Install GitHub CLI (`gh`) on the runner and ensure it is in PATH. Ensure runner has CMake, MSVC, Windows SDK and compiled OBS frontend libraries. The existing `build-obs33.ps1` currently assumes the specific 2026-10-23 OBS dependency directory names documented in `BUILDING_OBS33.md`.

1. Commit source changes to `main`. Main branch builds produce downloadable workflow artifacts, but not releases.
2. Increment `project(... VERSION X.Y.Z ...)` in `CMakeLists.txt` and merge.
3. Create/push matching tag: `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. GitHub Actions checks version matching, builds, packages, generates SHA256, and publishes a GitHub Release with the ZIP and checksum.
5. **Test the ZIP on a clean installation of the intended OBS 33 runtime before promoting or widely distributing it.** Automated runtime smoke tests are not included.

The plugin can query `https://api.github.com/repos/OWNER/REPO/releases/latest` when compiled with the `-GitHubRepository OWNER/REPO` build parameter. The workflow populates this from `github.repository`. The endpoint is anonymous and therefore requires releases to be publicly accessible. It checks at startup and via the dock button; it only shows a download link, **never downloads or replaces running DLLs**. GitHub's `latest` endpoint ignores pre-releases.

Automatic updating is intentionally not included. A safe future updater should be a separate signed installer/updater executing **after OBS exits**, with validated version and artifact integrity, plus user consent.

The older `build-obs33.ps1` still produces its historical manual ZIP; `package-release.ps1` is the authoritative release artifact and uses the supported `bin/64bit` directory layout.
