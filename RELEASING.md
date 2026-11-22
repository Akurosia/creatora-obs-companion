# Creatora OBS Companion — release process

## Versioning from Git tags

CI uses the pushed `vMAJOR.MINOR.PATCH` Git tag as the **only source of release versions**. It injects `CREATORA_BUILD_VERSION` into the CMake build on Windows, macOS, and Linux. The version embedded in the plugin and Windows ZIP filename therefore matches the tag.

For branch pushes, pull requests, and manual runs without a tag, the version is `0.0.0`. These builds publish Actions artifacts only, not GitHub Releases.

To release any version, first push changes to `main`, then push a new matching tag. **Do not edit `CMakeLists.txt` to change the version.**

```bash
git checkout main
git pull --ff-only
git tag v0.1.3
git push origin v0.1.3
```


## Build matrix

- **Windows x64:** stable GitHub-hosted `windows-2022` build; produces the Windows ZIP and SHA-256 checksum.
- **macOS x86_64:** experimental GitHub-hosted `macos-15-intel` compile job. Artifacts are for engineering validation only.
- **Linux x86_64:** experimental GitHub-hosted `ubuntu-24.04` compile job. Artifacts are for engineering validation only.

The experimental jobs use `continue-on-error`; their failures must be fixed before enabling release distribution. In particular, non-Windows credential encryption currently refuses pairing, macOS still needs a validated OBS `.plugin` bundle, and Linux needs a verified OBS-compatible installation layout. **Do not distribute the experimental binaries as working releases.**

## Why a successful build did not publish a release

Commits on `main` only upload workflow artifacts. The GitHub Release step executes only for a pushed `vX.Y.Z` tag matching the CMake project version. Currently CMake declares `0.1.2`. To publish the first Windows release after validating the build:

```bash
git checkout main
git pull --ff-only
git tag v0.1.2
git push origin v0.1.2
```

Check **Actions** for the tag build and **Releases** for the resulting ZIP. Never create the GitHub release manually before the workflow runs, because the current `gh release create` step expects to create it itself.

**Private repository note:** Public clients cannot check GitHub releases in a private repository without credentials. To support in-app update checks for external users, configure a separate public releases repository and publish the assets there; do not embed a GitHub token in the plugin.

---

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

Follow the tag-only process above. The `Publish GitHub Release` step runs only on tag pushes, after the Windows package is built.

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
