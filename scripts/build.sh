#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

source_dir="${SING_BOX_SOURCE:-sing-box}"
target_os="${TARGET_OS:?TARGET_OS must be linux or windows}"
output_dir="${OUTPUT_DIR:-dist/${target_os}-amd64v3}"
version="${SING_BOX_VERSION:-}"
expected_commit="${SING_BOX_COMMIT:-}"

case "$target_os" in
  linux | windows) ;;
  *)
    echo "unsupported TARGET_OS: ${target_os}" >&2
    exit 2
    ;;
esac

if [ ! -d "$source_dir/.git" ]; then
  echo "missing git checkout at ${source_dir}; run scripts/fetch-sing-box.sh first" >&2
  exit 2
fi

source_dir="$(cd "$source_dir" && pwd)"
actual_commit="$(git -C "$source_dir" rev-parse HEAD)"

if [ -n "$expected_commit" ] && [ "$actual_commit" != "$expected_commit" ]; then
  echo "source commit mismatch: expected ${expected_commit}, got ${actual_commit}" >&2
  exit 1
fi

if [ -z "$version" ]; then
  if tag="$(git -C "$source_dir" describe --tags --exact-match 2>/dev/null)"; then
    version="$tag"
  elif described="$(git -C "$source_dir" describe --tags 2>/dev/null)"; then
    version="$described"
  else
    version="0.0.0-$(git -C "$source_dir" rev-parse --short=12 HEAD)"
  fi
fi

version="${version#v}"
if [ -z "$version" ]; then
  echo "empty version" >&2
  exit 2
fi

tags="with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_tailscale,with_cloudflared,with_openvpn,with_openconnect,badlinkname,tfogo_checklinkname0"
removed_tags="with_naive_outbound with_purego with_usbip with_ccm with_ocm"

if [ "$target_os" = "windows" ]; then
  # Keep WinDivert and USB/IP drivers out of the executable. WinDivert is read
  # from next to the executable if bridge or TLS spoofing is used at runtime.
  tags="${tags},with_external_windivert,with_external_usbip_drivers"
fi

ldflags="-X github.com/sagernet/sing-box/constant.Version=${version} -X runtime.godebugDefault=multipathtcp=0,tlssha1=1 -checklinkname=0 -s -w -buildid="

binary="sing-box"
if [ "$target_os" = "windows" ]; then
  binary="sing-box.exe"
fi

mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
output="${output_dir}/${binary}"

# Keep the build independent from user-level Go configuration.
export CGO_ENABLED=0
export GOOS="$target_os"
export GOARCH=amd64
export GOAMD64=v3
export GOTOOLCHAIN=local
export GOWORK=off
export GOENV=off
export TZ=UTC
export LC_ALL=C
unset GOFLAGS GOEXPERIMENT GODEBUG GOPRIVATE GONOSUMDB GONOSUMCHECK GOINSECURE

if [ -n "${GO_VERSION:-}" ]; then
  expected_go="$GO_VERSION"
  case "$expected_go" in
    go*) ;;
    *) expected_go="go${expected_go}" ;;
  esac
  actual_go="$(go env GOVERSION)"
  if [ "$actual_go" != "$expected_go" ]; then
    echo "Go toolchain mismatch: expected ${expected_go}, got ${actual_go}" >&2
    exit 1
  fi
fi

echo "building sing-box ${version} for ${target_os}/amd64 (GOAMD64=v3, CGO disabled)"
echo "source commit: ${actual_commit}"

(
  cd "$source_dir"
  go build \
    -trimpath \
    -buildvcs=false \
    -mod=readonly \
    -tags "$tags" \
    -ldflags "$ldflags" \
    -o "$output" \
    ./cmd/sing-box
  go mod verify
)

build_info="$(go version -m "$output")"
for needle in \
  "CGO_ENABLED=0" \
  "GOARCH=amd64" \
  "GOOS=${target_os}" \
  "GOAMD64=v3" \
  "-tags=${tags}" \
  "-trimpath=true"; do
  if ! grep -Fq -- "$needle" <<<"$build_info"; then
    echo "build metadata check failed: missing ${needle}" >&2
    echo "$build_info" >&2
    exit 1
  fi
done

if grep -Eq 'vcs\.(revision|time|modified)=|(^|[[:space:]])vcs=' <<<"$build_info"; then
  echo "build metadata check failed: VCS metadata is present" >&2
  echo "$build_info" >&2
  exit 1
fi

if grep -aFq -- "$source_dir" "$output"; then
  echo "build metadata check failed: source path is embedded in the binary" >&2
  exit 1
fi

nm_output="$(go tool nm "$output" 2>&1 || true)"
if ! grep -Fq "no symbols" <<<"$nm_output"; then
  echo "build metadata check failed: symbol table was not stripped" >&2
  echo "$nm_output" >&2
  exit 1
fi

if [ "$target_os" = "linux" ]; then
  version_output="$("$output" version)"
  echo "$version_output"
  if ! grep -Fq "sing-box version ${version}" <<<"$version_output"; then
    echo "runtime version check failed" >&2
    exit 1
  fi
  if ! grep -Fq "CGO: disabled" <<<"$version_output"; then
    echo "runtime CGO check failed" >&2
    exit 1
  fi
  if ! grep -Fq "Tags: ${tags}" <<<"$version_output"; then
    echo "runtime tag check failed" >&2
    exit 1
  fi
  for removed in $removed_tags; do
    if grep -Fq "$removed" <<<"$version_output"; then
      echo "removed tag is still present: ${removed}" >&2
      exit 1
    fi
  done
fi

go_version="$(go env GOVERSION)"
epoch="${SOURCE_DATE_EPOCH:-$(git -C "$source_dir" log -1 --format=%ct)}"

{
  echo "sing-box version: ${version}"
  echo "sing-box commit: ${actual_commit}"
  echo "Go version: ${go_version}"
  echo "GOOS: ${target_os}"
  echo "GOARCH: amd64"
  echo "GOAMD64: v3"
  echo "CGO_ENABLED: 0"
  echo "Tags: ${tags}"
  echo "Source date epoch: ${epoch}"
} >"${output_dir}/build-info.txt"

(
  cd "$output_dir"
  sha256sum "$binary" >"${binary}.sha256"
)

echo "output: ${output}"
cat "${output_dir}/${binary}.sha256"
