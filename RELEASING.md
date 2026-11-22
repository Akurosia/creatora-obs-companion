# Releasing Creatora OBS Companion (OBS Studio 33 / Windows x64)

The GitHub Actions workflow runs on **GitHub-hosted `windows-2022` runners**.
There is **no self-hosted runner**, and no `OBS_SOURCE_ROOT`, `QT_ROOT`, or
`OBS_QT_CORE_DLL` repository variable is required.

## Pipeline

1. Check out the plugin and the official OBS Studio **33.0.1** source.
2. Install **Qt 6.11.1 MSVC x64** with the WebSockets module on the runner.
3. Run OBS's own Windows preset to download its pinned development dependencies.
4. Compile the `obs-frontend-api` target (and dependent `libobs` library).
5. Build the standalone Creatora module using those OBS development libraries.
6. Download the **official OBS 33.0.1 Windows x64 ZIP** and verify that the
   plugin's Qt WebSockets DLL matches its `Qt6Core.dll` major/minor version.
7. Package `creatora-obs-companion-vX.Y.Z-obs33-win64.zip` and its `.sha256`.
8. Upload the files as GitHub Actions artifacts on branch, pull-request and manual builds.
9. On a matching `vX.Y.Z` tag pushed to GitHub, publish both files in GitHub Releases.

Build validation runs on `main` and pull requests. Release publishing only runs
for pushed tags. The workflow uses only the built-in `GITHUB_TOKEN` with write
permission in its tag-publishing job.

## How to publish

Update the CMake project version first:

```cmake
project(creatora-obs-companion VERSION 0.2.0 LANGUAGES CXX)
```

Then merge/push to `main`, check the Actions build status, and create a matching tag:

```bash
git tag v0.2.0
git push origin v0.2.0
```

GitHub Actions will create a release named `Creatora OBS Companion v0.2.0`.
You can also run a manual test build using **Actions → Build and release OBS
Companion → Run workflow** without publishing a release.

## Important compatibility and deployment notes

- OBS 33.0.1 uses Qt 6.11.1 in the previously verified Windows runtime. This
  workflow deliberately pins that Qt version and refuses mismatched packages.
- Build and packaging remain **Windows x64 only**. The example workflow's
  OBS 28, Qt 6.3.1, Windows x86 and macOS/Linux settings must not be copied.
- A successful Actions build is **not a live OBS plugin loading test**. Verify
  one release on the actual OBS 33 installation before distributing it broadly.
- The first GitHub-hosted run may fail due to upstream OBS dependencies,
  the Qt archive mirror, or changes in the OBS preset. The workflow is prepared
  but has **not been executed on GitHub Actions yet**.
- On OBS 33 the plugin has a `source.screenshot` capability for the optional
  Polaroid capture flow. Publishing the DLL does not configure Discord delivery;
  that is a separate server/bot concern.

## Update notifications

When built with `CREATORA_GITHUB_REPOSITORY`, the OBS dock can check the latest
public GitHub Release for a newer version. This pipeline passes the repository
name automatically. Pre-releases are not returned by GitHub's `/releases/latest`
endpoint. The plugin shows an update link but does not overwrite a DLL while OBS
is running.
