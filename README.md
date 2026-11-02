# sing-box slim reproducible builds

Builds a no-CGO sing-box for Linux and Windows `amd64` with `GOAMD64=v3`. Linux builds use PIE with full RELRO; Windows builds use the Go linker's ASLR/DEP defaults. With the same source commit, Go toolchain, build tags, and flags, the resulting binaries are byte-identical.

## Outputs

Each target produces:

- `sing-box` (Linux) or `sing-box.exe` (Windows)
- `<binary>.sha256`
- `build-info.txt`

The CI artifact is named `sing-box-v<release_version>-amd64v3` and contains:

```text
sing-box_<release_version>_linux_amd64v3
sing-box_<release_version>_windows_amd64v3.exe
SHA256SUMS
build-info-linux.txt
build-info-windows.txt
README.txt
```

`<release_version>` is `<sing-box-version>-<pkgrel>`, for example `1.14.4-1`.

Verify it with:

```bash
sha256sum -c SHA256SUMS
```

## Version management

`versions.env` is the managed version source:

```text
SING_BOX_REF=v1.14.4
GO_VERSION=1.27.3
PKGREL=1
```

Resolution order:

1. Workflow input or environment variable.
2. `versions.env`.
3. Hard failure.

No version defaults are built into CI. Edit `versions.env` to change the default versions. After changing `SING_BOX_REF`, run `make fetch` to update an existing `sing-box/` clone.

`PKGREL` is the Arch-style package release counter. The release version is `<sing-box-version>-<pkgrel>`; the binary itself keeps reporting the upstream sing-box version. See [UPDATING.md](UPDATING.md) for the version update procedure.

## Build configuration

- `CGO_ENABLED=0`
- `linux/amd64` and `windows/amd64`
- `GOAMD64=v3`
- Linux: `-buildmode=pie` and `-bindnow` (full RELRO, immediate binding)
- Windows: Go linker defaults for ASLR, DEP, and high-entropy VA
- Base tags:

  ```text
  with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,
  with_clash_api,with_tailscale,with_cloudflared,with_openvpn,
  with_openconnect,badlinkname,tfogo_checklinkname0
  ```

- Windows adds:

  ```text
  with_external_windivert,with_external_usbip_drivers
  ```

- Removed tags:

  ```text
  with_naive_outbound,with_purego,with_usbip,with_ccm,with_ocm
  ```

- Linker and build flags:

  ```text
  -trimpath
  -buildvcs=false
  -mod=readonly
  -s -w -buildid=
  -X github.com/sagernet/sing-box/constant.Version=<version>
  -X runtime.godebugDefault=multipathtcp=0,tlssha1=1
  -checklinkname=0
  ```

  Linux adds `-bindnow`. The build verifies `ET_DYN`, `GNU_RELRO`, non-executable `GNU_STACK`, `BIND_NOW`, and the PIE dynamic flag.

`with_external_windivert` keeps the WinDivert kernel driver out of the Windows executable. `bridge` and TLS spoof then require `WinDivert64.sys` (WinDivert 2.2.2) next to the executable; its SHA256 is checked and administrator privileges are required. Wintun remains embedded. `with_external_usbip_drivers` is included for the Windows tag set; USB/IP is disabled, so no USB/IP driver is built.

## Reproducibility

The build is reproducible when all of these inputs match:

1. sing-box source commit.
2. Exact Go toolchain version.
3. `GOOS`, `GOARCH=amd64`, `GOAMD64=v3`.
4. Build tags.
5. Compiler/linker flags and `CGO_ENABLED=0`.

CI builds every target twice on `ubuntu-24.04` and `ubuntu-22.04` and compares the outputs byte by byte. The `verify` job fails on any difference.

## Local usage

```bash
# Clone SING_BOX_REF from versions.env into ./sing-box
make source

# Build Linux and Windows
make build

# Build twice with separate caches and compare
make repro
```

Local outputs:

```text
dist/linux-amd64v3/sing-box
dist/linux-amd64v3/sing-box.sha256
dist/linux-amd64v3/build-info.txt

dist/windows-amd64v3/sing-box.exe
dist/windows-amd64v3/sing-box.exe.sha256
dist/windows-amd64v3/build-info.txt
```

Override the managed versions for a single build:

```bash
# Change the source ref and re-clone
make fetch SING_BOX_REF=v1.14.4

# Override the Go version, package release, and result label
make build GO_VERSION=1.27.3 PKGREL=1 SING_BOX_VERSION=v1.14.4
```

If `SING_BOX_REF`, `GO_VERSION`, or `PKGREL` is neither passed explicitly nor present in `versions.env`, the local scripts fail before building.

## GitHub Actions

Push the repository to GitHub, then run the `build-sing-box` workflow or push to `main`.

`workflow_dispatch` inputs:

| Input | Default | Description |
| --- | --- | --- |
| `sing_box_ref` | empty (falls back to `versions.env`) | sing-box tag, branch, or commit SHA |
| `sing_box_version` | empty | Optional upstream version label; defaults to the tag name or `0.0.0-<sha>` |
| `go_version` | empty (falls back to `versions.env`) | Exact Go toolchain version |
| `pkgrel` | empty (falls back to `versions.env`) | Arch-style rebuild counter, e.g. `1` |
| `publish_release` | `false` | Publish a GitHub Release after all checks pass |

Jobs:

1. `meta` resolves versions, computes the release version, fetches the source, and records the commit and timestamp. It fails before building if the versions cannot be resolved.
2. `build` runs the Linux and Windows builds on two runner images.
3. `verify` compares both builds byte by byte, runs the Linux binary, and assembles the final artifact.
4. `smoke-windows` checks the Windows checksum and runs `sing-box.exe version` on `windows-latest`.
5. `release` runs only with `publish_release=true`; it creates or updates tag `v<release_version>` and uploads the final assets.

Windows binaries are cross-compiled on Linux and smoke-tested on Windows.

## Releases

Release versions follow Arch's `pkgver-pkgrel` model:

- First build of upstream sing-box `1.14.4`: release `1.14.4-1`.
- Go/toolchain-only rebuild: increment `PKGREL` to `2`, release `1.14.4-2`.
- New upstream sing-box version: reset `PKGREL` to `1`.

The binary continues to report the upstream version (`sing-box version 1.14.4`). The `-PKGREL` suffix is used in the release tag, artifact names, build metadata, and release notes.

Publish with:

```bash
gh workflow run build-sing-box --ref main -f publish_release=true
```

See [UPDATING.md](UPDATING.md) for the complete version update procedure.

## Repository layout

```text
.
├── .github/workflows/build.yml
├── Makefile
├── README.md
├── UPDATING.md
├── versions.env
├── scripts/
│   ├── fetch-sing-box.sh
│   ├── resolve-version.sh
│   ├── build.sh
│   ├── verify-reproducible.sh
│   ├── assemble.sh
│   └── local-repro.sh
└── sing-box/        # ignored source clone, not a git submodule
```

The `sing-box/` directory is cloned at build time and excluded by `.gitignore`. This repository does not use a git submodule.

## Requirements and limits

- The binary requires an x86-64-v3 CPU (AVX2 and related extensions).
- The exact Go toolchain version from `versions.env` is required. `GOTOOLCHAIN=local` prevents automatic switching.
- The Linux PIE binary has an `INTERP` entry for `/lib64/ld-linux-x86-64.so.2` and no `DT_NEEDED` libraries. The glibc loader must exist at that path.
- Windows binaries use the Go linker's ASLR, DEP, and high-entropy VA defaults.
- Tags can move upstream; use a commit SHA for strict long-term pinning.
- Only `amd64` is built.
- Raw binaries are published; no tar or zip archives are produced.
