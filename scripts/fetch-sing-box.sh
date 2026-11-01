#!/usr/bin/env bash
set -euo pipefail

ref="${1:?usage: $0 <tag|branch|commit> [directory]}"
dir="${2:-sing-box}"
repo="${SING_BOX_REPO:-https://github.com/SagerNet/sing-box.git}"

export GIT_TERMINAL_PROMPT=0

case "$dir" in
  "" | "/" | "." | "..")
    echo "refusing to remove unsafe directory: ${dir}" >&2
    exit 2
    ;;
esac

rm -rf "$dir"
git init -q "$dir"
git -C "$dir" remote add origin "$repo"

if git ls-remote --exit-code --tags "$repo" "refs/tags/${ref}" >/dev/null 2>&1; then
  git -C "$dir" fetch --depth 1 origin "refs/tags/${ref}:refs/tags/${ref}"
  git -C "$dir" checkout -q --detach "refs/tags/${ref}"
elif git ls-remote --exit-code --heads "$repo" "refs/heads/${ref}" >/dev/null 2>&1; then
  git -C "$dir" fetch --depth 1 origin "refs/heads/${ref}:refs/remotes/origin/${ref}"
  git -C "$dir" checkout -q --detach FETCH_HEAD
else
  # A raw commit SHA. GitHub accepts fetching reachable SHAs by value.
  git -C "$dir" fetch --depth 1 origin "$ref"
  git -C "$dir" checkout -q --detach FETCH_HEAD
fi

commit="$(git -C "$dir" rev-parse HEAD)"
echo "sing-box source: ${commit}"
