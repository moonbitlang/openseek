///|
fn shell_quote(value : String) -> String {
  "'" + value.replace_all(old="'", new="'\"'\"'") + "'"
}

///|
/// A bootstrap script, not an RPC transport. Only progress and the eventual
/// endpoint use stdout; installer output belongs to stderr.
fn prepare_command(release_url : String, protocols : String) -> String {
  let script =
    #|set -eu
    #|export PATH="$HOME/.moon/bin:$HOME/.openseek/bin:$PATH"
    #|case "$(uname -s):$(uname -m)" in
    #|  Linux:x86_64) platform=linux-x64 ;;
    #|  Linux:aarch64|Linux:arm64) platform=linux-arm64 ;;
    #|  Darwin:arm64|Darwin:aarch64) platform=macos-arm64 ;;
    #|  *) echo 'Automatic SSH setup supports Linux x64/arm64 and macOS arm64.' >&2; exit 1 ;;
    #|esac
    #|base="$HOME/.openseek/ssh"
    #|mkdir -p "$base"
    #|stage=
    #|endpoint=
    #|trap 'if [ -n "$stage" ]; then rm -rf "$stage"; fi; if [ -n "$endpoint" ]; then rm -f "$endpoint"; fi' EXIT
    #|trap 'exit 1' HUP INT TERM
    #|if [ ! -f "$root/.prepared" ] || [ ! -x "$root/bin/openseek" ] || [ ! -x "$root/bin/openseek-app-server" ]; then
    #|  printf '%s\n' '{"stage":"downloading"}'
    #|  stage=$(mktemp -d "$base/.prepare.XXXXXX")
    #|  archive="openseek-$platform.tar.gz"
    #|  fetch() { curl --fail --location --silent --show-error --proto "$protocols" --proto-redir "$protocols" --connect-timeout 15 --max-time 600 --retry 2 "$url/$1" --output "$stage/$1"; }
    #|  fetch SHA256SUMS
    #|  fetch "$archive"
    #|  expected=$(awk -v name="$archive" '$2 == name { print $1 }' "$stage/SHA256SUMS")
    #|  if command -v sha256sum >/dev/null 2>&1; then
    #|    actual=$(sha256sum "$stage/$archive" | awk '{print $1}')
    #|  else
    #|    actual=$(shasum -a 256 "$stage/$archive" | awk '{print $1}')
    #|  fi
    #|  if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    #|    echo 'OpenSeek CLI archive checksum mismatch.' >&2; exit 1
    #|  fi
    #|  tar -xzf "$stage/$archive" -C "$stage"
    #|  distribution="$stage/openseek-$platform"
    #|  if [ ! -x "$distribution/bin/openseek" ] || [ ! -x "$distribution/bin/openseek-app-server" ]; then
    #|    echo 'This CLI release does not contain the matching app-server. Publish the matching native CLI release.' >&2; exit 1
    #|  fi
    #|  printf '%s\n' '{"stage":"installing"}'
    #|  "$distribution/bin/openseek" setup >&2
    #|  touch "$distribution/.prepared"
    #|  if [ -d "$root" ]; then
    #|    echo 'A prepared SSH distribution already exists; reconnect to use it.' >&2; exit 1
    #|  fi
    #|  mv "$distribution" "$root"
    #|  rm -rf "$stage"
    #|  stage=
    #|fi
    #|printf '%s\n' '{"stage":"connecting"}'
    #|export OPENSEEK_ENGINE="$root/bin/openseek"
    #|umask 077
    #|endpoint=$(mktemp "$base/.endpoint.XXXXXX")
    #|# Non-interactive shells replace background stdin with /dev/null before
    #|# applying redirections. Preserve the startup pipe on a separate fd.
    #|exec 3<&0
    #|nohup "$root/bin/openseek-app-server" <&3 3<&- >"$endpoint" 2>>"$base/app-server.log" &
    #|server=$!
    #|exec 3<&-
    #|while ! IFS= read -r announcement <"$endpoint"; do
    #|  if ! kill -0 "$server" 2>/dev/null; then
    #|    wait "$server" || exit "$?"
    #|    echo 'App-server exited before announcing its endpoint.' >&2; exit 1
    #|  fi
    #|  sleep 0.05
    #|done
    #|printf '%s\n' "$announcement"
    #|# Only EOF follows credential forwarding. Both this script and the server
    #|# may observe it: before initialize it cancels startup; afterwards only
    #|# this script exits, leaving ownership with the WebSocket.
    #|cat >/dev/null
  let prelude = "url=" +
    shell_quote(release_url) +
    "\nprotocols=" +
    shell_quote(protocols) +
    "\nroot=\"$HOME/.openseek/ssh/v" +
    CliRelease +
    "\"\n"
  "exec sh -c " + shell_quote(prelude + script)
}
