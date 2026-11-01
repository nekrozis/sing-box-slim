# sing-box slim reproducible builds

用 GitHub Actions 构建无 CGO 的 sing-box，覆盖 Linux 和 Windows 的 `amd64` 目标，按 `GOAMD64=v3` 编译，并在 CI 中通过两次独立构建逐字节校验可重现性。

## 结论

可以实现。本仓库已经在本地用两个不同源码路径、两个独立 `GOCACHE` 验证过同一目标的 SHA256 完全一致：

| 目标 | SHA256 |
| --- | --- |
| `linux/amd64` (`GOAMD64=v3`, CGO off) | `8c049a001c1ffd185a9fe60cf23ca9fb71d774fcd7192b9280a2b27474af07cd` |
| `windows/amd64` (`GOAMD64=v3`, CGO off) | `cd97efc17cdaa83305dba8a94b021dd51d50c82afe3104a3bca7474ddd2d9176` |

以上哈希对应 sing-box `v1.14.4`（commit `c005f35300ce76427dc285481ec5695f5b179cd2`）和 Go `1.27.3`。

## 构建配置

- sing-box 版本：默认 `v1.14.4`，可通过 workflow input 指定 tag、branch 或 commit。
- Go 版本：默认 `1.27.3`，精确锁定，`GOTOOLCHAIN=local` 禁止自动切换。
- `CGO_ENABLED=0`。
- 目标：`linux/amd64`、`windows/amd64`。
- `GOAMD64=v3`，产物需要支持 AVX2 等 x86-64-v3 指令集的 CPU。
- 保留的 tags：

  ```text
  with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,
  with_clash_api,with_tailscale,with_cloudflared,with_openvpn,
  with_openconnect,badlinkname,tfogo_checklinkname0
  ```

- 移除的 tags：`with_naive_outbound`、`with_purego`、`with_usbip`、`with_ccm`、`with_ocm`。
- 版本号通过 `-X github.com/sagernet/sing-box/constant.Version=<version>` 注入，不依赖构建目录的 VCS 状态。
- 链接参数沿用上游 release 配置：

  ```text
  -X runtime.godebugDefault=multipathtcp=0,tlssha1=1 -checklinkname=0 -s -w -buildid=
  ```

- `-trimpath` 去除本地路径。
- `-buildvcs=false` 去除 VCS 元数据。
- `-s -w` 去除 ELF/PE 符号表和 DWARF。
- `-buildid=` 清空 Go build ID。
- `-mod=readonly` 和 `go mod verify` 保证依赖与 `go.sum` 一致。

`-s` 不能去掉 Go 运行时需要的 pclntab（函数名和行号表），否则 panic 栈和 `runtime` 功能会受影响；它去掉的是链接符号表和 DWARF 调试信息。

`go version -m` 仍会显示模块版本、`GOOS`、`GOARCH`、`GOAMD64`、`CGO_ENABLED` 和 `-tags` 等构建信息；其中不再包含 `vcs.revision`、`vcs.time`、`vcs.modified`。这些保留的字段是 Go 运行时和 `go version -m` 需要的，不影响可重现性。

## 可重现性约定

两次构建只有在以下输入完全相同时才保证得到相同字节：

1. sing-box 源码 commit（建议用 commit SHA，不要依赖可能移动的 tag 名）。
2. Go toolchain 版本和发行版（CI 使用 `actions/setup-go` 下载的官方工具链）。
3. `GOOS`、`GOARCH`、`GOAMD64`。
4. 构建 tags 列表。
5. 编译和链接参数，包括 `CGO_ENABLED=0`。

CI 的 `build` job 在 `ubuntu-24.04` 和 `ubuntu-22.04` 上分别构建同一目标，`verify` job 用 `cmp` 和 SHA256 比较两组产物；任何字节差异都会让 workflow 失败。`build.sh` 还会检查：

- 构建信息中的 `CGO_ENABLED=0`、`GOOS`、`GOARCH=amd64`、`GOAMD64=v3`、`-trimpath=true`、`-tags`。
- 构建信息中不存在 VCS 字段。
- 二进制中不存在源码目录路径。
- ELF/PE 符号表已经被剥离。
- Linux 二进制可以运行，`sing-box version` 输出正确，且不含被移除的 tags。
- Windows 二进制由 `windows-latest` job 下载后校验 SHA256 并实际运行 `version`。

## 目录结构

```text
.
├── .github/workflows/build.yml   # GitHub Actions
├── Makefile
├── README.md
├── scripts/
│   ├── fetch-sing-box.sh         # 拉取指定 tag/branch/commit
│   ├── build.sh                  # 单目标构建 + 元数据检查
│   ├── verify-reproducible.sh    # 两次构建逐字节比较
│   ├── assemble.sh               # 汇总最终产物和 SHA256SUMS
│   └── local-repro.sh            # 本地双构建校验
└── sing-box/                     # 源码克隆目录，已被 .gitignore 忽略
```

`sing-box/` 不进入本仓库。`.gitignore` 同时忽略 `dist/`、`out/` 和 `repro-artifacts/`。

## 本地使用

```bash
# 克隆 sing-box v1.14.4 到 ./sing-box
make source

# 构建 Linux + Windows
make build

# 用两个不同源码路径和独立 GOCACHE 做可重现性校验
make repro
```

产物：

```text
dist/linux-amd64v3/sing-box
dist/linux-amd64v3/sing-box.sha256
dist/linux-amd64v3/build-info.txt

dist/windows-amd64v3/sing-box.exe
dist/windows-amd64v3/sing-box.exe.sha256
dist/windows-amd64v3/build-info.txt
```

指定其他版本：

```bash
make fetch SING_BOX_REF=v1.14.4
make build SING_BOX_VERSION=v1.14.4
```

`make fetch` 会删除并重新克隆 `sing-box/`，本地对该目录的修改会丢失。

## GitHub Actions

把仓库推送到 GitHub 后，在 Actions 中运行 `build-sing-box`，或直接 push 到 `main`。`workflow_dispatch` 输入：

| 输入 | 默认值 | 说明 |
| --- | --- | --- |
| `sing_box_ref` | `v1.14.4` | sing-box tag、branch 或 commit SHA |
| `sing_box_version` | 空 | 可选的版本标签；留空时 tag 用 tag 名，commit 用 `0.0.0-<sha>` |
| `go_version` | `1.27.3` | Go 工具链版本，必须是精确版本，不能写 `1.27` 或版本范围 |

Job 流程：

1. `meta`：拉取源码，解析 commit、版本号和 commit 时间戳。
2. `build`：4 个矩阵任务，Linux/Windows × `ubuntu-24.04`/`ubuntu-22.04`。Windows 目标在 Linux runner 上交叉编译。
3. `verify`：下载 4 组产物，逐字节比较；运行 Linux 产物；汇总最终 artifact。
4. `smoke-windows`：在 `windows-latest` 上校验 SHA256 并实际运行 `sing-box.exe version`，确认交叉编译产物可用。

最终 artifact 名为 `sing-box-<version>-amd64v3`，包含：

```text
sing-box_<version>_linux_amd64v3
sing-box_<version>_windows_amd64v3.exe
SHA256SUMS
build-info-linux.txt
build-info-windows.txt
README.txt
```

校验：

```bash
sha256sum -c SHA256SUMS
```

## 注意事项

- `GOAMD64=v3` 产物不能在只支持 x86-64-v1/v2 的 CPU 上运行；会因非法指令崩溃。
- 只构建 `amd64`，没有 ARM64 产物。
- 严格复现需要相同的源码 commit 和相同的 Go 版本。tag 可能被上游移动，长期归档建议使用 commit SHA。
- GitHub 托管 runner 镜像会更新。CI 的双 runner 比较可以发现 toolchain 或环境导致的差异；如果需要完全固定的构建用户态，可以把构建放进固定 digest 的容器镜像，例如 `golang:1.27.3-bookworm`。
- `ubuntu-22.04` 未来可能被 GitHub 退役；届时修改 `.github/workflows/build.yml` 的 matrix 即可。
- CI 首次运行会下载 Go 工具链和 Go modules，之后 runner 上的构建缓存不会跨 job 复用；这不影响产物字节。
