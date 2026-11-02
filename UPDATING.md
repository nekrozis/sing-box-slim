# Updating sing-box and Go

All managed versions live in `versions.env`:

```text
SING_BOX_REF=v1.14.4
GO_VERSION=1.27.3
PKGREL=1
```

- `SING_BOX_REF`: upstream sing-box tag, branch, or commit.
- `GO_VERSION`: exact Go toolchain version.
- `PKGREL`: Arch-style package release counter (`pkgver-pkgrel`). It starts at `1` for a new sing-box version and increments for a rebuild that does not change the upstream source.

The binary keeps reporting the upstream sing-box version (`sing-box version 1.14.4`). The `-PKGREL` suffix appears in the release tag, artifact file names, build metadata, and release notes.

## Version model

| Change | Example release | PKGREL |
| --- | --- | --- |
| First build of a sing-box version | `1.14.4-1` | `1` |
| Go/toolchain-only rebuild | `1.14.4-2` | `2` |
| Next Go-only rebuild | `1.14.4-3` | `3` |
| New sing-box version | `1.15.0-1` | reset to `1` |

## Update sing-box

1. Edit `versions.env`:

   ```text
   SING_BOX_REF=v1.15.0
   PKGREL=1
   ```

   Keep `GO_VERSION` unchanged unless Go is also being updated.

2. Fetch and verify:

   ```bash
   make fetch
   make build
   make repro
   ```

3. Check the local outputs:

   ```bash
   dist/linux-amd64v3/sing-box version
   cat dist/linux-amd64v3/build-info.txt
   ```

   The binary reports `1.15.0`; `Release version` is `1.15.0-1`.

4. Commit and push:

   ```bash
   git add versions.env
   git commit -m "Update sing-box to v1.15.0"
   git push
   ```

5. Publish the release:

   ```bash
   gh workflow run build-sing-box --ref main -f publish_release=true
   ```

   Or use **Actions → build-sing-box → Run workflow** and enable `publish_release`.

## Update Go only

1. Edit `versions.env`:

   ```text
   GO_VERSION=1.27.4
   PKGREL=2
   ```

   Keep `SING_BOX_REF` unchanged. Increment `PKGREL` from the previous value.

2. Fetch and verify:

   ```bash
   make fetch
   make build
   make repro
   ```

3. Commit and push:

   ```bash
   git add versions.env
   git commit -m "Rebuild with Go 1.27.4"
   git push
   ```

4. Publish the release:

   ```bash
   gh workflow run build-sing-box --ref main -f publish_release=true
   ```

   The release is `1.14.4-2`; the binary still reports `1.14.4`.

## Automated checks

The `version-check` workflow runs daily at `03:17 UTC`:

- It checks the latest stable sing-box release and Go toolchain.
- It updates `versions.env` and opens or updates the `automation/version-update` pull request.
- It assigns the PR to `nekrozis` and creates or updates a `version-update` issue as a notification.
- It never merges automatically.

The automation applies the same `PKGREL` rules described above. Review the PR, let CI run, merge it, and then publish the release.

PR checks triggered by `GITHUB_TOKEN` may be suppressed by GitHub. Add a fine-grained personal access token with Contents, Pull requests, and Issues write access as the `VERSION_UPDATE_TOKEN` repository secret to let PR checks run automatically.

## Files to change

For a normal version update, change only `versions.env`.

- `versions.env`: `SING_BOX_REF`, `GO_VERSION`, `PKGREL`.
- `README.md`: only when usage or output descriptions change. It contains no build version pins.
- `UPDATING.md`: only when this process changes.
- No workflow or script edits are needed for a version bump; they read `versions.env`.

## Release behavior

`publish_release=true` runs after the build matrix, reproducibility verification, and Windows smoke test. The release job:

- uses tag `v<release_version>` (for example `v1.14.4-2`);
- attaches the final Linux/Windows binaries, `SHA256SUMS`, build metadata, and `README.txt`;
- writes release notes that identify the upstream sing-box version, Go version, source commit, and `PKGREL`;
- updates the release if the tag already exists.

## Verify a release

```bash
sha256sum -c SHA256SUMS
```

Check `build-info-linux.txt` and `build-info-windows.txt` for:

- `sing-box version` (upstream version);
- `Release version` (with `PKGREL`);
- `Go version`;
- build tags.
