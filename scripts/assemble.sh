#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

artifacts="${1:?usage: $0 <artifacts-directory> [dist-directory]}"
dist="${2:-dist}"
version="${SING_BOX_VERSION:?SING_BOX_VERSION is required}"
version_number="${version#v}"

case "$dist" in
  "" | "/" | "." | "..")
    echo "refusing to remove unsafe directory: ${dist}" >&2
    exit 2
    ;;
esac

linux_src="${artifacts}/primary-linux/sing-box"
windows_src="${artifacts}/primary-windows/sing-box.exe"
linux_info="${artifacts}/primary-linux/build-info.txt"
windows_info="${artifacts}/primary-windows/build-info.txt"

for path in "$linux_src" "$windows_src" "$linux_info" "$windows_info"; do
  if [ ! -f "$path" ]; then
    echo "missing input: ${path}" >&2
    exit 1
  fi
done

rm -rf "$dist"
mkdir -p "$dist"

linux_name="sing-box_${version_number}_linux_amd64v3"
windows_name="sing-box_${version_number}_windows_amd64v3.exe"

cp "$linux_src" "${dist}/${linux_name}"
cp "$windows_src" "${dist}/${windows_name}"
cp "$linux_info" "${dist}/build-info-linux.txt"
cp "$windows_info" "${dist}/build-info-windows.txt"
chmod 0755 "${dist}/${linux_name}" "${dist}/${windows_name}"

(
  cd "$dist"
  sha256sum "$linux_name" "$windows_name" >SHA256SUMS
  sha256sum -c SHA256SUMS
)

commit="$(sed -n 's/^sing-box commit: //p' "${dist}/build-info-linux.txt")"
go_version="$(sed -n 's/^Go version: //p' "${dist}/build-info-linux.txt")"
tags="$(sed -n 's/^Tags: //p' "${dist}/build-info-linux.txt")"

cat >"${dist}/README.txt" <<EOF
sing-box ${version} (${commit})
Go toolchain ${go_version}, CGO disabled, GOAMD64=v3
CPU requirement: x86-64-v3 (AVX2)
Tags: ${tags}

Linux:
  chmod +x ${linux_name}
  ./${linux_name} version

Windows:
  ${windows_name} version

Verify checksums:
  sha256sum -c SHA256SUMS
EOF

ls -l "$dist"
