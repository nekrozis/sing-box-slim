#!/usr/bin/env bash
set -euo pipefail

artifacts="${1:?usage: $0 <artifacts-directory>}"

status=0
for target in linux windows; do
  binary="sing-box"
  if [ "$target" = "windows" ]; then
    binary="sing-box.exe"
  fi

  primary="${artifacts}/primary-${target}/${binary}"
  repro="${artifacts}/repro-${target}/${binary}"

  if [ ! -f "$primary" ] || [ ! -f "$repro" ]; then
    echo "missing ${target} artifact: ${primary} or ${repro}" >&2
    exit 1
  fi

  primary_hash="$(sha256sum "$primary" | awk '{print $1}')"
  repro_hash="$(sha256sum "$repro" | awk '{print $1}')"

  if cmp -s "$primary" "$repro"; then
    echo "reproducible: ${target}: ${primary_hash}"
  else
    echo "NOT reproducible: ${target}: ${primary_hash} != ${repro_hash}" >&2
    status=1
  fi

  if ! cmp -s "${artifacts}/primary-${target}/build-info.txt" "${artifacts}/repro-${target}/build-info.txt"; then
    echo "NOT reproducible: ${target} build-info.txt differs" >&2
    status=1
  fi

  if ! (cd "${artifacts}/primary-${target}" && sha256sum -c "${binary}.sha256" >/dev/null); then
    echo "checksum file is invalid: primary-${target}" >&2
    status=1
  fi
  if ! (cd "${artifacts}/repro-${target}" && sha256sum -c "${binary}.sha256" >/dev/null); then
    echo "checksum file is invalid: repro-${target}" >&2
    status=1
  fi
done

exit "$status"
