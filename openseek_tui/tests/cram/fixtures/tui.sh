#!/usr/bin/env bash
# Independent scenarios for tui.md. Each runs in a fresh temporary directory.
case "$1" in
api-key-is-required)
sh <<'EOF'
stdout=$(mktemp)
stderr=$(mktemp)
if env -u DEEPSEEK -u KIMI -u OPENSEEK_MODEL openseek_tui.exe > "$stdout" 2> "$stderr"; then echo exit-zero; else echo exit-non-zero; fi
sed -n '1p' "$stderr"
if test -s "$stdout"; then echo stdout-not-empty; else echo stdout-empty; fi
rm -f "$stdout" "$stderr"
EOF
;;
unknown-options-are-rejected)
sh <<'EOF'
stdout=$(mktemp)
stderr=$(mktemp)
if env DEEPSEEK=test-key openseek_tui.exe --xxy he > "$stdout" 2> "$stderr"; then echo exit-zero; else echo exit-non-zero; fi
sed -n '1p' "$stderr"
if test -s "$stdout"; then echo stdout-not-empty; else echo stdout-empty; fi
rm -f "$stdout" "$stderr"
EOF
;;
the-default-engine-is-the-pinned-release-under-moonx)
sh <<'EOF'
bin=$(mktemp -d)
printf '#!/bin/sh\necho "$@" >> "%s/args"\nexit 0\n' "$bin" > "$bin/moonx"
cat > "$bin/tty-sidecar" <<'SIDECAR'
#!/bin/sh
printf '\203\027\000\000\000no controlling terminal'
SIDECAR
chmod +x "$bin/moonx" "$bin/tty-sidecar"
if PATH="$bin:$PATH" env DEEPSEEK=test-key TTY_SIDECAR="$bin/tty-sidecar" openseek_tui.exe > "$bin/stdout" 2> "$bin/stderr"; then echo exit-zero; else echo exit-non-zero; fi
cat "$bin/stderr"
if test -s "$bin/stdout"; then echo stdout-not-empty; else echo stdout-empty; fi
cat "$bin/args"
rm -rf "$bin"
EOF
;;
the-default-engine-is-the-pinned-release-under-moonx-2)
sh <<'EOF'
ui=$(command -v openseek_tui.exe)
env -i PATH=/usr/bin:/bin DEEPSEEK=test-key "$ui"
EOF
;;
the-default-engine-is-the-pinned-release-under-moonx-3)
sh <<'EOF'
bin=$(mktemp -d)
printf '#!/bin/sh\necho "fetching moonbitlang/openseek@0.7.5"\necho "error: failed to download from mooncakes.io" >&2\nexit 1\n' > "$bin/moonx"
chmod +x "$bin/moonx"
PATH="$bin:$PATH" env DEEPSEEK=test-key openseek_tui.exe
status=$?
rm -rf "$bin"
exit $status
EOF
;;
a-custom-system-prompt-comes-from-the-prompt-file-flags)
sh <<'EOF'
root=$(mktemp -d)
mkdir -p "$root/sessions/demo"
printf '{"version":1,"id":"demo","system_prompt":"system"}\n' > "$root/sessions/demo/openseek_session-demo.jsonl"
stderr=$(mktemp)
env DEEPSEEK=test-key openseek_tui.exe --session demo --session-root "$root" --system-prompt-file prompt.md > /dev/null 2> "$stderr"
status=$?
sed -E 's#--dir [^ ]+ --session-root [^ ]+#--dir <workspace> --session-root <root>#' "$stderr"
echo "status=$status"
rm -rf "$root" "$stderr"
EOF
;;
a-custom-system-prompt-comes-from-the-prompt-file-flags-2)
sh <<'EOF'
root=$(mktemp -d)
mkdir -p "$root/sessions/demo"
printf '{"version":1,"id":"demo","system_prompt":"system"}\n' > "$root/sessions/demo/openseek_session-demo.jsonl"
stderr=$(mktemp)
env DEEPSEEK=test-key openseek_tui.exe --continue --session-root "$root" --system-prompt-addendum-file addendum.md > /dev/null 2> "$stderr"
status=$?
sed -E 's#--dir [^ ]+ --session-root [^ ]+#--dir <workspace> --session-root <root>#' "$stderr"
echo "status=$status"
rm -rf "$root" "$stderr"
EOF
;;
*) echo "Unknown scenario: $1" >&2; exit 2 ;;
esac
