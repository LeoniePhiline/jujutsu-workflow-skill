#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: Netresearch DTT GmbH
# install_jj.sh — Install a jj release binary (linux x86_64, musl) for CI.
#
# Usage: install_jj.sh <vX.Y.Z> <sha256>
#        install_jj.sh latest
#
# A pinned version is verified against the sha256 passed in, so it needs no
# GitHub API call. `latest` resolves the newest non-prerelease release through
# the GitHub API and verifies the download against the sha256 digest GitHub
# records for that asset (jj publishes no separate checksum file).
#
# Installs into $JJ_INSTALL_DIR (default: $HOME/.local/bin) and, inside GitHub
# Actions, appends that directory to $GITHUB_PATH for the following steps.
#
# Exit: 0 = installed, 2 = usage error, any other non-zero = download,
# checksum or extraction failure.
set -euo pipefail

want="${1:-}"
pin="${2:-}"
if [[ -z "$want" || ("$want" != latest && -z "$pin") || ("$want" == latest && -n "$pin") ]]; then
  echo "usage: install_jj.sh <vX.Y.Z> <sha256> | install_jj.sh latest" >&2
  exit 2
fi

if [[ "$want" == latest ]]; then
  meta="$(curl -fsSL --proto '=https' --retry 3 https://api.github.com/repos/jj-vcs/jj/releases/latest)"
  tag="$(jq -r '.tag_name // empty' <<<"$meta")"
  [[ -n "$tag" ]] || {
    echo "error: could not resolve the latest jj release" >&2
    exit 1
  }
  asset="jj-${tag}-x86_64-unknown-linux-musl.tar.gz"
  digest="$(jq -r --arg a "$asset" '.assets[] | select(.name == $a) | .digest // empty' <<<"$meta")"
  sha="${digest#sha256:}"
  [[ "$digest" == sha256:* && -n "$sha" ]] || {
    echo "error: GitHub records no sha256 digest for $asset" >&2
    exit 1
  }
else
  tag="$want"
  sha="$pin"
  asset="jj-${tag}-x86_64-unknown-linux-musl.tar.gz"
fi

dest="${JJ_INSTALL_DIR:-$HOME/.local/bin}"
tmpd="$(mktemp -d)"
trap 'rm -rf "$tmpd"' EXIT

curl -fsSL --proto '=https' --retry 3 -o "$tmpd/$asset" "https://github.com/jj-vcs/jj/releases/download/${tag}/${asset}"
echo "${sha}  $tmpd/$asset" | sha256sum -c -
tar -xzf "$tmpd/$asset" -C "$tmpd"
bin="$(find "$tmpd" -name jj -type f -print -quit)"
[[ -n "$bin" ]] || {
  echo "error: $asset holds no jj binary" >&2
  exit 1
}
mkdir -p "$dest"
install -m755 "$bin" "$dest/jj"
[[ -n "${GITHUB_PATH:-}" ]] && echo "$dest" >>"$GITHUB_PATH"
echo "installed: $("$dest/jj" --version) -> $dest/jj"
