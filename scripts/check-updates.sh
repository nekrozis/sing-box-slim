#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

versions_file="${VERSIONS_FILE:-versions.env}"
body_file="${VERSION_UPDATE_BODY:-version-update.md}"

if [ ! -f "$versions_file" ]; then
  echo "missing ${versions_file}" >&2
  exit 1
fi

read_value() {
  local key="$1"
  awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      sub(/^[[:space:]]*[^=]*=[[:space:]]*/, "")
      sub(/\r$/, "")
      sub(/[[:space:]]*$/, "")
      print
      exit
    }
  ' "$versions_file"
}

current_ref="$(read_value SING_BOX_REF)"
current_go="$(read_value GO_VERSION)"
current_pkgrel="$(read_value PKGREL)"

for value in "$current_ref" "$current_go" "$current_pkgrel"; do
  if [ -z "$value" ]; then
    echo "SING_BOX_REF, GO_VERSION, and PKGREL must all be set in ${versions_file}" >&2
    exit 1
  fi
done

current_go="${current_go#go}"

case "$current_pkgrel" in
  *[!0-9]*)
    echo "invalid PKGREL: ${current_pkgrel}" >&2
    exit 1
    ;;
esac

case "$current_ref" in
  v[0-9]*) ;;
  *)
    echo "SING_BOX_REF=${current_ref} is pinned; automated version checks only manage v-tags" >&2
    echo "changed=false"
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
      echo "changed=false" >>"$GITHUB_OUTPUT"
    fi
    exit 0
    ;;
esac

api_args=(-H "Accept: application/vnd.github+json")
if [ -n "${GITHUB_TOKEN:-}" ]; then
  api_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

latest_ref="$(curl -fsSL "${api_args[@]}" \
  "https://api.github.com/repos/SagerNet/sing-box/releases/latest" |
  python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])')"
latest_go="$(curl -fsSL "https://go.dev/VERSION?m=text" | head -n1)"
latest_go="${latest_go#go}"

version_gt() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

new_ref="$current_ref"
new_go="$current_go"
sing_box_updated=false
go_updated=false

if version_gt "${latest_ref#v}" "${current_ref#v}"; then
  new_ref="$latest_ref"
  sing_box_updated=true
fi

if version_gt "${latest_go#go}" "${current_go#go}"; then
  new_go="${latest_go#go}"
  go_updated=true
fi

if [ "$sing_box_updated" = false ] && [ "$go_updated" = false ]; then
  echo "changed=false"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "changed=false" >>"$GITHUB_OUTPUT"
  fi
  exit 0
fi

new_pkgrel="$current_pkgrel"
if [ "$sing_box_updated" = true ]; then
  new_pkgrel=1
elif [ "$go_updated" = true ]; then
  new_pkgrel=$((current_pkgrel + 1))
fi

sed -i "s|^[[:space:]]*SING_BOX_REF[[:space:]]*=.*|SING_BOX_REF=${new_ref}|" "$versions_file"
sed -i "s|^[[:space:]]*GO_VERSION[[:space:]]*=.*|GO_VERSION=${new_go}|" "$versions_file"
sed -i "s|^[[:space:]]*PKGREL[[:space:]]*=.*|PKGREL=${new_pkgrel}|" "$versions_file"

new_ref_number="${new_ref#v}"
release_version="${new_ref_number}-${new_pkgrel}"

if [ "$sing_box_updated" = true ] && [ "$go_updated" = true ]; then
  pr_title="Update sing-box to ${new_ref} and Go to ${new_go}"
elif [ "$sing_box_updated" = true ]; then
  pr_title="Update sing-box to ${new_ref}"
else
  pr_title="Rebuild sing-box ${new_ref_number} with Go ${new_go}"
fi

{
  echo "## Automated version update"
  echo
  echo "This PR updates \`versions.env\`."
  echo
  echo "| Item | Old | New |"
  echo "| --- | --- | --- |"
  echo "| sing-box | \`${current_ref}\` | \`${new_ref}\` |"
  echo "| Go | \`${current_go}\` | \`${new_go}\` |"
  echo "| PKGREL | \`${current_pkgrel}\` | \`${new_pkgrel}\` |"
  echo
  echo "Release version: \`${release_version}\`."
  echo
  if [ "$sing_box_updated" = true ]; then
    echo "PKGREL is reset to 1 because \`SING_BOX_REF\` changed."
  else
    echo "This is a Go/toolchain-only rebuild; PKGREL is incremented."
  fi
  echo
  echo "The binary keeps reporting the upstream sing-box version; \`${release_version}\` is used only for the release tag and artifact names."
  echo
  echo "### Verification"
  echo
  echo '```bash'
  echo "make build"
  echo "make repro"
  echo '```'
  echo
  echo "### Release"
  echo
  echo "After merge:"
  echo
  echo '```bash'
  echo "gh workflow run build-sing-box --ref main -f publish_release=true"
  echo '```'
  echo
  echo "See \`UPDATING.md\` for details."
} >"$body_file"

emit() {
  echo "$1=$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "$1=$2" >>"$GITHUB_OUTPUT"
  fi
}

emit changed true
emit pr_title "$pr_title"
emit commit_message "$pr_title"
emit old_sing_box "$current_ref"
emit new_sing_box "$new_ref"
emit old_go "$current_go"
emit new_go "$new_go"
emit old_pkgrel "$current_pkgrel"
emit new_pkgrel "$new_pkgrel"
emit release_version "$release_version"
