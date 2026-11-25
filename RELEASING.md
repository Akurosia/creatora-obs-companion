# Creatora OBS Companion — Releases and CI

## Test versus stable tags

- `tMAJOR.MINOR.PATCH` (e.g. `t0.1.9`): build the three Windows x64 targets **only** (OBS 32.1.2, OBS 32.2.2, and OBS 33.0.1). Publish their ZIPs and SHA-256 checksums as a GitHub **prerelease**. macOS/Linux jobs are skipped.
- `vMAJOR.MINOR.PATCH` (e.g. `v0.1.9`): build all Windows targets **and** run experimental macOS and Linux CI. Publish the Windows ZIPs and checksums as a normal GitHub Release. The experimental artifacts remain in Actions, not the release.
- Pushes to `main`: automatically run all existing CI jobs without publishing a release.
- Feature-branch pushes and pull requests: **no automatic builds**.
- Manual workflow dispatch (`Actions` → `Build and release OBS Companion` → `Run workflow`): select any branch, including feature branches, to build on demand without publishing a release.

Windows builds read the matching official OBS Qt version, compile against that OBS version, and package exactly two DLLs in the required OBS-version-specific layout. Stable/test tags both embed `MAJOR.MINOR.PATCH` (without `v` or `t`) into the plugin. Thus a test release `t0.1.9` and stable release `v0.1.9` both embed version `0.1.9`.

## Usage

```bash
git switch main
git pull --ff-only
git tag t0.1.9
git push origin t0.1.9
```

After validating the Windows test release, create the stable tag from the desired commit:

```bash
git switch main
git pull --ff-only
git tag v0.1.9
git push origin v0.1.9
```

GitHub Releases uses `--prerelease` for test tags so test builds do not replace the latest stable release shown to normal users. A tag name must be unique; move to a higher test version (e.g. `t0.1.10`) for another test instead of overwriting published tags.

**Important:** The plugin's update check uses GitHub's latest stable Release endpoint; test prereleases will not be advertised to ordinary users. Test releases still need manual installation and testing inside the target OBS runtime.

## Experimental platforms

The macOS and Linux jobs currently use `continue-on-error` and publish build artifacts for engineering validation only. They do not produce a verified installation package or appear in either GitHub Release type. They run for stable tags and ordinary CI, but skip on test tags.

**Manual builds:** `workflow_dispatch` remains available on any selectable branch; ensure the workflow file exists on the selected ref. Manual dispatch never publishes a release because the publishing job requires a tag `push` event.
