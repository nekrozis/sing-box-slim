#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

source_dir="${SING_BOX_SOURCE:-sing-box}"

SING_BOX_REF="$(./scripts/resolve-version.sh SING_BOX_REF)"
GO_VERSION="$(./scripts/resolve-version.sh GO_VERSION)"
export SING_BOX_REF GO_VERSION

if [ ! -d "$source_dir/.git" ]; then
  ./scripts/fetch-sing-box.sh "$SING_BOX_REF" "$source_dir"
fi

version="${SING_BOX_VERSION:-}"
if [ -z "$version" ]; then
  if tag="$(git -C "$source_dir" describe --tags --exact-match 2>/dev/null)"; then
    version="$tag"
  elif described="$(git -C "$source_dir" describe --tags 2>/dev/null)"; then
    version="$described"
  else
    version="0.0.0-$(git -C "$source_dir" rev-parse --short=12 HEAD)"
  fi
fi
commit="$(git -C "$source_dir" rev-parse HEAD)"

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

cp -a "$source_dir" "${tmp}/source"

pids=()
for target in linux windows; do
  GOCACHE="${tmp}/cache-primary" \
    SING_BOX_SOURCE="$source_dir" \
    TARGET_OS="$target" \
    OUTPUT_DIR="${tmp}/artifacts/primary-${target}" \
    SING_BOX_VERSION="$version" \
    SING_BOX_COMMIT="$commit" \
    ./scripts/build.sh &
  pids+=("$!")
done
for pid in "${pids[@]}"; do
  wait "$pid"
done

pids=()
for target in linux windows; do
  GOCACHE="${tmp}/cache-repro" \
    SING_BOX_SOURCE="${tmp}/source" \
    TARGET_OS="$target" \
    OUTPUT_DIR="${tmp}/artifacts/repro-${target}" \
    SING_BOX_VERSION="$version" \
    SING_BOX_COMMIT="$commit" \
    ./scripts/build.sh &
  pids+=("$!")
done
for pid in "${pids[@]}"; do
  wait "$pid"
done

./scripts/verify-reproducible.sh "${tmp}/artifacts"
echo "local reproducibility check passed for ${version}"
