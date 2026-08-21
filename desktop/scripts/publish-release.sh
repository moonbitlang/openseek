#!/usr/bin/env bash
# Upload Desktop release artifacts to OSS, then ask openseek-api to generate
# and atomically replace its release manifest from the uploaded filenames and
# SHA-256 digests. OSS stores artifacts only; it does not own latest.json.
#
#   scripts/publish-release.sh upload [vX.Y.Z]   upload the checkout's artifacts
#   scripts/publish-release.sh publish [vX.Y.Z]  make the uploaded version live
#   scripts/publish-release.sh rollback vX.Y.Z   republish an existing version
#   scripts/publish-release.sh status            list API-owned release state
#
# Requires OPENSEEK_OSS_BUCKET, OPENSEEK_OSS_REGION, OPENSEEK_API_ORIGIN,
# and OPENSEEK_DEPLOY_TOKEN, plus ossutil 2.x credentials. The standard API
# origins select their OSS prefixes automatically; nonstandard deployments can
# set OPENSEEK_OSS_PREFIX explicitly.
set -euo pipefail

# ossutil appends an elapsed-time line to structured output unless quiet mode
# is enabled. Every HeadObject JSON response below must remain valid for jq.

desktop_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(sed -n 's/^version = "\(.*\)"$/\1/p' "$desktop_dir/moon.mod")"
if [[ -z "$version" ]]; then
  echo "could not read version from moon.mod" >&2
  exit 1
fi

case "${1:-}" in
  upload)
    upload_version="${2:-v$version}"
    if [[ "$upload_version" != "v$version" ]]; then
      echo "upload version $upload_version does not match checkout version v$version" >&2
      echo "use rollback for an already-published version" >&2
      exit 64
    fi
    oss_bucket="${OPENSEEK_OSS_BUCKET:?set OPENSEEK_OSS_BUCKET}"
    oss_region="${OPENSEEK_OSS_REGION:?set OPENSEEK_OSS_REGION}"
    api_origin="${OPENSEEK_API_ORIGIN:?set OPENSEEK_API_ORIGIN}"
    deploy_token="${OPENSEEK_DEPLOY_TOKEN:?set OPENSEEK_DEPLOY_TOKEN}"
    api_origin="${api_origin%/}"
    if [[ -n "${OPENSEEK_OSS_PREFIX:-}" ]]; then
      oss_prefix="${OPENSEEK_OSS_PREFIX#/}"
      oss_prefix="${oss_prefix%/}"
    else
      case "$api_origin" in
        https://openseek-api.moonbitlang.cn)
          oss_prefix="openseek/desktop/releases"
          ;;
        https://openseek-api-staging.moonbitlang.cn)
          oss_prefix="openseek/staging/desktop/releases"
          ;;
        *)
          echo "no OSS prefix mapped for $api_origin; set OPENSEEK_OSS_PREFIX" >&2
          exit 64
          ;;
      esac
    fi

    artifacts=(
      "$desktop_dir/dist/SeekMoon.app.zip"
      "$desktop_dir/dist/SeekMoon.dmg"
      "$desktop_dir/dist/SeekMoon.browser.tar.gz"
    )
    platforms=("macos-arm64" "macos-arm64-dmg" "browser")
    content_types=("application/zip" "application/x-apple-diskimage" "application/gzip")
    artifact_shas=()

    # A published Browser directory is the API-owned per-version seal. If a
    # previous attempt reached API publish but the job failed afterwards, its
    # OSS bytes must be reused instead of overwritten by a fresh rebuild.
    browser_status="$(curl -sS -o /dev/null -w '%{http_code}' \
      "$api_origin/console/releases/$upload_version/index.html")"
    if [[ "$browser_status" == 200 ]]; then
      echo "$upload_version is already published by the API; reusing its OSS artifacts"
      for index in 0 1 2; do
        artifact="${artifacts[$index]}"
        platform="${platforms[$index]}"
        release_name="$(basename "$artifact")"
        oss_key="$oss_prefix/$upload_version/$release_name"
        oss_destination="oss://$oss_bucket/$oss_key"
        head_json="$(
          ossutil api head-object \
            --region "$oss_region" \
            --bucket "$oss_bucket" \
            --key "$oss_key" \
            --output-format json \
            --quiet
        )"
        served_size="$(jq -er '.Header["Content-Length"][0]' <<< "$head_json")"
        served_sha="$(jq -er '.Header["X-Oss-Meta-Sha256"][0]' <<< "$head_json")"
        served_crc64="$(jq -er '.Header["X-Oss-Hash-Crc64ecma"][0]' <<< "$head_json")"
        ossutil cp --force --region "$oss_region" "$oss_destination" "$artifact"
        local_size="$(wc -c < "$artifact" | tr -d '[:space:]')"
        local_sha="$(shasum -a 256 "$artifact" | cut -d' ' -f1)"
        if [[ "$served_size" != "$local_size" || \
          "$served_sha" != "$local_sha" || \
          -z "$served_crc64" ]]; then
          echo "published OSS artifact does not match its metadata: $platform" >&2
          exit 1
        fi
        artifact_shas+=("$local_sha")
        echo "$platform restored: $oss_destination"
      done

      # The Actions artifact and Browser-content verification must use the
      # same archive bytes that the API already published.
      rm -rf "$desktop_dir/dist/browser"
      COPYFILE_DISABLE=1 tar -xzf "${artifacts[2]}" -C "$desktop_dir/dist"
      echo "$upload_version is ready to publish again"
      exit 0
    fi
    if [[ "$browser_status" != 404 ]]; then
      echo "could not determine whether $upload_version is published: HTTP $browser_status" >&2
      exit 1
    fi

    echo "$upload_version is unpublished; uploading replaceable OSS artifacts"
    for index in 0 1 2; do
      artifact="${artifacts[$index]}"
      platform="${platforms[$index]}"
      content_type="${content_types[$index]}"
      if [[ ! -f "$artifact" ]]; then
        echo "artifact not found: $artifact" >&2
        exit 1
      fi
      release_name="$(basename "$artifact")"
      oss_key="$oss_prefix/$upload_version/$release_name"
      oss_destination="oss://$oss_bucket/$oss_key"
      local_sha="$(shasum -a 256 "$artifact" | cut -d' ' -f1)"
      local_size="$(wc -c < "$artifact" | tr -d '[:space:]')"

      # Rebuilds are not byte-identical. Until the API publishes this version,
      # a retry must replace provisional bytes instead of keeping an older run.
      echo "uploading $artifact"
      echo "       to $oss_destination"
      ossutil cp --force --region "$oss_region" \
        --content-type "$content_type" \
        --cache-control "public, max-age=31536000, immutable" \
        --metadata "sha256=$local_sha" \
        "$artifact" "$oss_destination"

      # Verify against OSS directly. Accessing the CDN before publication can
      # cache provisional bytes under the immutable version URL.
      head_json="$(
        ossutil api head-object \
          --region "$oss_region" \
          --bucket "$oss_bucket" \
          --key "$oss_key" \
          --output-format json \
          --quiet
      )"
      served_size="$(jq -er '.Header["Content-Length"][0]' <<< "$head_json")"
      served_sha="$(jq -er '.Header["X-Oss-Meta-Sha256"][0]' <<< "$head_json")"
      served_crc64="$(jq -er '.Header["X-Oss-Hash-Crc64ecma"][0]' <<< "$head_json")"
      if [[ "$served_size" != "$local_size" || \
        "$served_sha" != "$local_sha" || \
        -z "$served_crc64" ]]; then
        echo "OSS verification failed for $platform" >&2
        exit 1
      fi
      artifact_shas+=("$local_sha")
      echo "$platform verified in OSS"
    done

    # `/console/` remains on the API origin, so only the much smaller Browser
    # archive is uploaded twice. ZIP and DMG exist only in OSS.
    browser_archive="${artifacts[2]}"
    browser_upload_url="$api_origin/desktop/releases/$upload_version/SeekMoon.browser.tar.gz?platform=browser"
    upload_response="$(curl -sS --fail-with-body -T "$browser_archive" \
      -H "Authorization: Bearer $deploy_token" "$browser_upload_url")"
    response_sha="$(jq -er '.sha256' <<< "$upload_response")"
    if [[ "$response_sha" != "${artifact_shas[2]}" ]]; then
      echo "DIGEST MISMATCH: API recorded $response_sha for Browser" >&2
      exit 1
    fi
    echo "$upload_version is ready to publish"
    exit 0
    ;;

  publish)
    publish_version="${2:-v$version}"
    if [[ "$publish_version" != "v$version" ]]; then
      echo "publish version $publish_version does not match checkout version v$version" >&2
      echo "use rollback for an already-published version" >&2
      exit 64
    fi
    publish_from_checkout=true
    ;;

  rollback)
    publish_version="${2:?usage: publish-release.sh rollback vX.Y.Z}"
    if [[ ! "$publish_version" =~ ^v[[:alnum:]][[:alnum:]_.-]*$ ]]; then
      echo "invalid rollback version: $publish_version" >&2
      exit 64
    fi
    publish_from_checkout=false
    ;;

  status)
    api_origin="${OPENSEEK_API_ORIGIN:?set OPENSEEK_API_ORIGIN}"
    deploy_token="${OPENSEEK_DEPLOY_TOKEN:?set OPENSEEK_DEPLOY_TOKEN}"
    curl -sS --fail-with-body \
      -H "Authorization: Bearer $deploy_token" \
      "${api_origin%/}/desktop/releases"
    echo
    exit 0
    ;;

  *)
    sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 64
    ;;
esac

# Publish and rollback share the same API contract. The runner knows OSS and
# supplies trusted filenames and SHA-256 values; the API knows only the public
# release base URL and owns latest.json generation.
oss_bucket="${OPENSEEK_OSS_BUCKET:?set OPENSEEK_OSS_BUCKET}"
oss_region="${OPENSEEK_OSS_REGION:?set OPENSEEK_OSS_REGION}"
api_origin="${OPENSEEK_API_ORIGIN:?set OPENSEEK_API_ORIGIN}"
deploy_token="${OPENSEEK_DEPLOY_TOKEN:?set OPENSEEK_DEPLOY_TOKEN}"
api_origin="${api_origin%/}"
if [[ -n "${OPENSEEK_OSS_PREFIX:-}" ]]; then
  oss_prefix="${OPENSEEK_OSS_PREFIX#/}"
  oss_prefix="${oss_prefix%/}"
else
  case "$api_origin" in
    https://openseek-api.moonbitlang.cn)
      oss_prefix="openseek/desktop/releases"
      ;;
    https://openseek-api-staging.moonbitlang.cn)
      oss_prefix="openseek/staging/desktop/releases"
      ;;
    *)
      echo "no OSS prefix mapped for $api_origin; set OPENSEEK_OSS_PREFIX" >&2
      exit 64
      ;;
  esac
fi

artifacts=(
  "$desktop_dir/dist/SeekMoon.app.zip"
  "$desktop_dir/dist/SeekMoon.dmg"
  "$desktop_dir/dist/SeekMoon.browser.tar.gz"
)
files=("SeekMoon.app.zip" "SeekMoon.dmg" "SeekMoon.browser.tar.gz")
platforms=("macos-arm64" "macos-arm64-dmg" "browser")
artifact_shas=()

for index in 0 1 2; do
  artifact="${artifacts[$index]}"
  platform="${platforms[$index]}"
  release_name="${files[$index]}"
  oss_key="$oss_prefix/$publish_version/$release_name"
  head_json="$(
    ossutil api head-object \
      --region "$oss_region" \
      --bucket "$oss_bucket" \
      --key "$oss_key" \
      --output-format json \
      --quiet
  )"
  served_size="$(jq -er '.Header["Content-Length"][0]' <<< "$head_json")"
  served_sha="$(jq -er '.Header["X-Oss-Meta-Sha256"][0]' <<< "$head_json")"
  served_crc64="$(jq -er '.Header["X-Oss-Hash-Crc64ecma"][0]' <<< "$head_json")"
  if [[ -z "$served_crc64" || ! "$served_sha" =~ ^[0-9a-f]{64}$ ]]; then
    echo "OSS metadata is incomplete for $platform" >&2
    exit 1
  fi
  if [[ "$publish_from_checkout" == true ]]; then
    if [[ ! -f "$artifact" ]]; then
      echo "artifact not found: $artifact" >&2
      exit 1
    fi
    local_size="$(wc -c < "$artifact" | tr -d '[:space:]')"
    local_sha="$(shasum -a 256 "$artifact" | cut -d' ' -f1)"
    if [[ "$served_size" != "$local_size" || "$served_sha" != "$local_sha" ]]; then
      echo "OSS object does not match the built artifact: $platform" >&2
      exit 1
    fi
  fi
  artifact_shas+=("$served_sha")
done

publish_payload="$(jq -cn \
  --arg archive_file "${files[0]}" \
  --arg archive_sha "${artifact_shas[0]}" \
  --arg dmg_file "${files[1]}" \
  --arg dmg_sha "${artifact_shas[1]}" \
  --arg browser_file "${files[2]}" \
  --arg browser_sha "${artifact_shas[2]}" \
  '{
    platforms: {
      "macos-arm64": {file: $archive_file, sha256: $archive_sha},
      "macos-arm64-dmg": {file: $dmg_file, sha256: $dmg_sha},
      browser: {file: $browser_file, sha256: $browser_sha}
    }
  }')"

publish_status=0
publish_response="$(curl -sS --fail-with-body -X POST \
  -H "Authorization: Bearer $deploy_token" \
  -H "Content-Type: application/json" \
  --data-binary "$publish_payload" \
  "$api_origin/desktop/releases/$publish_version/publish")" || publish_status=$?
if ((publish_status != 0)); then
  if [[ -n "$publish_response" ]]; then
    printf '%s\n' "$publish_response" >&2
  fi
  exit "$publish_status"
fi

expected_version="${publish_version#v}"
jq -e \
  --arg version "$expected_version" \
  --arg archive_file "/$publish_version/${files[0]}" \
  --arg archive_sha "${artifact_shas[0]}" \
  --arg dmg_file "/$publish_version/${files[1]}" \
  --arg dmg_sha "${artifact_shas[1]}" \
  --arg browser_file "/$publish_version/${files[2]}" \
  --arg browser_sha "${artifact_shas[2]}" '
    .published.version == $version and
    (.published.platforms | keys) == ["browser", "macos-arm64", "macos-arm64-dmg"] and
    .published.platforms["macos-arm64"].sha256 == $archive_sha and
    (.published.platforms["macos-arm64"].url | endswith($archive_file)) and
    .published.platforms["macos-arm64-dmg"].sha256 == $dmg_sha and
    (.published.platforms["macos-arm64-dmg"].url | endswith($dmg_file)) and
    .published.platforms.browser.sha256 == $browser_sha and
    (.published.platforms.browser.url | endswith($browser_file))
  ' <<< "$publish_response" >/dev/null

# Read the canonical file back from the API. This verifies that publish wrote
# the same manifest it returned; no manifest is copied to OSS.
latest="$(curl -fsSL --retry 3 "$api_origin/desktop/releases/latest.json")"
jq -e \
  --arg version "$expected_version" \
  --arg archive_sha "${artifact_shas[0]}" \
  --arg dmg_sha "${artifact_shas[1]}" \
  --arg browser_sha "${artifact_shas[2]}" '
    .version == $version and
    .platforms["macos-arm64"].sha256 == $archive_sha and
    .platforms["macos-arm64-dmg"].sha256 == $dmg_sha and
    .platforms.browser.sha256 == $browser_sha
  ' <<< "$latest" >/dev/null
echo "$latest"
