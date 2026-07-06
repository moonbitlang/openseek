#!/usr/bin/env bash
# Release flow against openseek-api: each platform's build machine uploads
# its own artifact, then one explicit publish regenerates latest.json
# server-side and switches clients over. Rolling back is publishing an
# older version again.
#
#   scripts/publish-release.sh upload [file]      upload this platform's artifact
#   scripts/publish-release.sh publish [vX.Y.Z]   make a version the live release
#   scripts/publish-release.sh status             list uploaded versions + current
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

version="$(sed -n 's/^pub const AppVersion : String = "\(.*\)"$/\1/p' \
  "$desktop_dir/internal/version/version.mbt")"
if [[ -z "$version" ]]; then
  echo "could not read AppVersion from internal/version/version.mbt" >&2
  exit 1
fi

# The artifact publishes under the release naming convention: the
# `<platform>` infix is the manifest `platforms` key clients look
# themselves up by, and the name must pass the server's URL path guard
# (no spaces — hence the rename from the dist zip).
release_name="OpenSeek-Desktop-macos-arm64.zip"
default_artifact="$desktop_dir/dist/OpenSeek Desktop-macos-arm64.zip"

case "${1:-}" in
  upload)
    artifact="${2:-$default_artifact}"
    if [[ ! -f "$artifact" ]]; then
      echo "artifact not found: $artifact" >&2
      echo "build it first: moon run ./package/macos -- --sign '...'" >&2
      exit 1
    fi
    url="$origin/desktop/releases/v$version/$release_name"
    echo "uploading $artifact"
    echo "       to $url"
    response="$(curl -sS --fail-with-body -T "$artifact" \
      -H "Authorization: Bearer $token" "$url")"
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
