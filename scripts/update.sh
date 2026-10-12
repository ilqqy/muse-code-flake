#!/usr/bin/env bash
# Resolve the latest Muse Code release the same way Meta's launcher
# (https://api.meta.ai/muse-launcher.sh) does -- channel manifest, then release
# manifest, then per-platform artifact -- prefetch each binary into the Nix
# store, check it against the manifest's sha256 and size, and rewrite
# sources.json. Does nothing when the channel still points at the pinned
# version, unless --force is given.
#
# Requires curl, jq and nix. Usage: scripts/update.sh [--force]
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
sources="$root/sources.json"
user_agent="muse-code-flake-update (+https://github.com/ilqqy/muse-code-flake)"
# Same pattern the launcher accepts.
version_pattern='^[0-9]+\.[0-9]+\.[0-9]+-R[0-9]+(\.[0-9]+)?$'

die() {
  printf 'update.sh: %s\n' "$*" >&2
  exit 1
}

# Nix system -> artifact key in the release manifest (the launcher's detect_platform).
platform_key() {
  case "$1" in
    x86_64-linux) echo x86_linux ;;
    aarch64-linux) echo aarch64_linux ;;
    x86_64-darwin) echo x86_macos ;;
    aarch64-darwin) echo aarch64_macos ;;
    *) return 1 ;;
  esac
}

fetch_json() {
  curl --fail --silent --show-error --location --max-redirs 3 \
    --proto '=https' --proto-redir '=https' --tlsv1.2 --retry 3 \
    --user-agent "$user_agent" --header 'Accept: application/json' "$1"
}

force=0
case "${1:-}" in
  "") ;;
  --force) force=1 ;;
  *) die "usage: $0 [--force]" ;;
esac

channel="$(jq -r .channel "$sources")"
current="$(jq -r .version "$sources")"

channel_json="$(fetch_json "https://api.meta.ai/muse-code/channels/$channel")" ||
  die "could not fetch the $channel channel manifest"
[[ "$(jq -r .channel <<<"$channel_json")" == "$channel" ]] ||
  die "channel manifest is not for $channel"
version="$(jq -r .version <<<"$channel_json")"
[[ "$version" =~ $version_pattern ]] || die "unexpected version: $version"
manifest_url="$(jq -r .manifest_url <<<"$channel_json")"

if [[ "$version" == "$current" && "$force" == 0 ]]; then
  echo "muse-code is up to date ($current)"
  exit 0
fi

release_json="$(fetch_json "$manifest_url")" ||
  die "could not fetch the release manifest for $version"
[[ "$(jq -r .version <<<"$release_json")" == "$version" ]] ||
  die "release manifest does not describe $version"
[[ "$(jq -r .checksum_algorithm <<<"$release_json")" == sha256 ]] ||
  die "release manifest does not use sha256 checksums"

platforms='{}'
for system in $(jq -r '.platforms | keys[]' "$sources"); do
  key="$(platform_key "$system")" || die "no manifest platform known for $system"
  artifact="$(jq -ce --arg key "$key" '.artifacts[$key]' <<<"$release_json")" ||
    die "$version publishes no $key artifact"
  url="$(jq -r .url <<<"$artifact")"
  checksum="$(jq -r .checksum <<<"$artifact")"
  size="$(jq -r .size <<<"$artifact")"

  echo "prefetching $system ($size bytes)" >&2
  # The name must match fetchurl's name in package.nix so the path is reused.
  prefetch="$(nix store prefetch-file --json --hash-type sha256 \
    --name "muse-$version-$system" "$url")"
  path="$(jq -r .storePath <<<"$prefetch")"
  [[ "$(stat -c %s "$path")" == "$size" ]] ||
    die "$system: size does not match the release manifest"
  [[ "$(sha256sum "$path" | cut -d' ' -f1)" == "$checksum" ]] ||
    die "$system: sha256 does not match the release manifest"

  platforms="$(jq --arg system "$system" --arg url "$url" \
    --arg hash "$(jq -r .hash <<<"$prefetch")" \
    '.[$system] = {url: $url, hash: $hash}' <<<"$platforms")"
done

jq --arg version "$version" --argjson platforms "$platforms" \
  '.version = $version | .platforms = $platforms' "$sources" >"$sources.tmp"
mv -- "$sources.tmp" "$sources"
echo "muse-code: $current -> $version"
