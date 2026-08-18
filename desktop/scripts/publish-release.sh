#!/usr/bin/env bash
# Release flow against openseek-api: each platform's build machine uploads
# its own artifact, then one explicit publish regenerates latest.json
# server-side and switches clients over. Rolling back is publishing an
# older version again.
#
#   scripts/publish-release.sh upload [file] [platform]  upload this platform's artifact
#   scripts/publish-release.sh publish [vX.Y.Z]          make a version the live release
#   scripts/publish-release.sh status                     list uploaded versions + current
# Current Proton and browser filenames have defaults; legacy
# SeekMoon-<platform> names are inferred.
#
# Requires OPENSEEK_DEPLOY_TOKEN (one of the server's OPENSEEK_DEPLOY_TOKENS).
# Uploads also mirror the artifact to OSS behind the download CDN: requires
# OPENSEEK_OSS_BUCKET and OPENSEEK_OSS_REGION, plus ossutil 2.x credentials
# (OSS_ACCESS_KEY_ID/OSS_ACCESS_KEY_SECRET or ~/.ossutilconfig).
# OPENSEEK_API_ORIGIN must name the target deployment explicitly, e.g.
#   OPENSEEK_API_ORIGIN=https://openseek-api-staging.moonbitlang.cn
set -euo pipefail

usage() {
  sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

desktop_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# No production default: a stray local run must name its target on purpose.
origin="${OPENSEEK_API_ORIGIN:?set OPENSEEK_API_ORIGIN to the target deployment}"
token="${OPENSEEK_DEPLOY_TOKEN:?set OPENSEEK_DEPLOY_TOKEN}"

version="$(sed -n 's/^version = "\(.*\)"$/\1/p' "$desktop_dir/moon.mod")"
if [[ -z "$version" ]]; then
  echo "could not read version from moon.mod" >&2
  exit 1
fi

# The default remains the ZIP consumed by the in-app updater. An explicit
# artifact, such as the DMG or browser bundle, uploads under its own basename
# so every file can coexist under the same version.
default_artifact="$desktop_dir/dist/SeekMoon.app.zip"

case "${1:-}" in
  upload)
    artifact="${2:-$default_artifact}"
    if [[ ! -f "$artifact" ]]; then
      echo "artifact not found: $artifact" >&2
      echo "build it first: moon run ./package/macos -- --release --target dmg --target zip --sign '...'" >&2
      exit 1
    fi
    release_name="$(basename "$artifact")"
    platform="${3:-}"
    if [[ -z "$platform" ]]; then
      case "$release_name" in
        SeekMoon.app.zip) platform="macos-arm64" ;;
        SeekMoon.dmg) platform="macos-arm64-dmg" ;;
        SeekMoon.browser.tar.gz) platform="browser" ;;
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
    # Resolve the OSS mirror destination up front, so a missing or wrong
    # configuration fails before the slow API upload rather than after it.
    oss_bucket="${OPENSEEK_OSS_BUCKET:?set OPENSEEK_OSS_BUCKET}"
    oss_region="${OPENSEEK_OSS_REGION:?set OPENSEEK_OSS_REGION}"
    if [[ -n "${OPENSEEK_OSS_PREFIX:-}" ]]; then
      oss_prefix="$OPENSEEK_OSS_PREFIX"
    else
      case "$origin" in
        https://openseek-api.moonbitlang.cn)
          oss_prefix="openseek/desktop/releases"
          ;;
        https://openseek-api-staging.moonbitlang.cn)
          oss_prefix="openseek/staging/desktop/releases"
          ;;
        *)
          echo "no OSS prefix mapped for $origin; set OPENSEEK_OSS_PREFIX" >&2
          exit 64
          ;;
      esac
    fi
    # Content type and caching mirror what the API serves for these files.
    content_type="application/octet-stream"
    if [[ "$release_name" == *.dmg ]]; then
      content_type="application/x-apple-diskimage"
    fi
    oss_destination="oss://$oss_bucket/$oss_prefix/v$version/$release_name"
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
    # Clients download from OSS behind the CDN once the server's
    # OPENSEEK_RELEASES_BASE_URL points there, so every artifact the API
    # accepts is mirrored to the same version path on OSS. The API upload
    # above is the immutability gate — it rejects re-uploads of a published
    # version — so the mirror can only ever rewrite an unpublished file;
    # --force keeps that rewrite from asking for confirmation in CI.
    echo "mirroring to $oss_destination"
    ossutil cp --force --region "$oss_region" \
      --content-type "$content_type" \
      --cache-control "public, max-age=31536000, immutable" \
      "$artifact" "$oss_destination"
    echo "digest verified and mirrored — go live with: ${BASH_SOURCE[0]} publish"
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
