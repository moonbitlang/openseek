#!/usr/bin/env bash
# Release flow against openseek-api: each platform's build machine uploads
# its own artifact, then one explicit publish regenerates latest.json
# server-side and switches clients over. Rolling back is publishing an
# older version again.
#
#   scripts/publish-release.sh upload [file] [platform]  upload this platform's artifact
#   scripts/publish-release.sh publish [vX.Y.Z]          make a version the live release
#   scripts/publish-release.sh status                     list uploaded versions + current
# Current Proton filenames have defaults; legacy SeekMoon-<platform> names are inferred.
#
# Requires OPENSEEK_DEPLOY_TOKEN (one of the server's OPENSEEK_DEPLOY_TOKENS).
# Targets production by default; for staging:
#   OPENSEEK_API_ORIGIN=https://openseek-api-staging.moonbitlang.cn
set -euo pipefail

usage() {
  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

desktop_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
origin="${OPENSEEK_API_ORIGIN:-https://openseek-api.moonbitlang.cn}"
token="${OPENSEEK_DEPLOY_TOKEN:?set OPENSEEK_DEPLOY_TOKEN}"

version="$(sed -n 's/^version = "\(.*\)"$/\1/p' "$desktop_dir/moon.mod")"
if [[ -z "$version" ]]; then
  echo "could not read version from moon.mod" >&2
  exit 1
fi

# The default remains the ZIP consumed by the in-app updater. An explicit
# artifact, such as the DMG offered for manual installation, uploads under
# its own basename so both files can coexist under the same version.
default_artifact="$desktop_dir/dist/SeekMoon.app.zip"

case "${1:-}" in
  upload)
    artifact="${2:-$default_artifact}"
    if [[ ! -f "$artifact" ]]; then
      echo "artifact not found: $artifact" >&2
      echo "build it first: moon run ./package/macos -- --target dmg --target zip --sign '...'" >&2
      exit 1
    fi
    release_name="$(basename "$artifact")"
    platform="${3:-}"
    if [[ -z "$platform" ]]; then
      case "$release_name" in
        SeekMoon.app.zip) platform="macos-arm64" ;;
        SeekMoon.dmg) platform="macos-arm64-dmg" ;;
      esac
    fi
    url="$origin/desktop/releases/v$version/$release_name"
    if [[ -n "$platform" ]]; then
      if [[ ! "$platform" =~ ^[[:alnum:]][[:alnum:]_.-]*$ ]]; then
        echo "invalid release platform: $platform" >&2
        exit 64
      fi
      # The API needs an explicit manifest key for Proton artifact names such
      # as SeekMoon.app.zip, which do not encode the target platform.
      url="$url?platform=$platform"
    fi
    echo "uploading $artifact"
    echo "       to $url"
    curl_status=0
    response="$(curl -sS --fail-with-body -T "$artifact" \
      -H "Authorization: Bearer $token" "$url")" || curl_status=$?
    if ((curl_status != 0)); then
      if [[ -n "$response" ]]; then
        echo "$response" >&2
      fi
      exit "$curl_status"
    fi
    echo "$response"
    local_sha="$(shasum -a 256 "$artifact" | cut -d' ' -f1)"
    if [[ "$response" != *"\"sha256\":\"$local_sha\""* ]]; then
      echo "DIGEST MISMATCH: local sha256 is $local_sha — do not publish" >&2
      exit 1
    fi
    echo "digest verified — go live with: ${BASH_SOURCE[0]} publish"
    ;;
  publish)
    curl -sS --fail-with-body -X POST \
      -H "Authorization: Bearer $token" \
      "$origin/desktop/releases/${2:-v$version}/publish"
    echo
    ;;
  status)
    curl -sS --fail-with-body \
      -H "Authorization: Bearer $token" "$origin/desktop/releases"
    echo
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
