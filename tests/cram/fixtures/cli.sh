#!/usr/bin/env bash
# Independent scenarios for cli.md. Each runs in a fresh temporary directory.
case "$1" in
a-misspelled-subcommand-is-an-error-not-a-prompt)
sh <<'EOF'
stderr=$(mktemp)
if env -u DEEPSEEK openseek.exe serv 2> "$stderr" >/dev/null; then echo exit-zero; else echo exit-non-zero; fi
sed -n '1p' "$stderr"
rm -f "$stderr"
EOF
;;
ui-options-are-not-top-level-flags)
sh <<'EOF'
stderr=$(mktemp)
if env DEEPSEEK=test-key openseek.exe --prompt x run TASK 2> "$stderr" >/dev/null; then echo exit-zero; else echo exit-non-zero; fi
sed -n '1p' "$stderr"
rm -f "$stderr"
EOF
;;
ui-options-are-not-top-level-flags-2)
sh <<'EOF'
stderr=$(mktemp)
if env DEEPSEEK=test-key openseek.exe -- something 2> "$stderr" >/dev/null; then echo exit-zero; else echo exit-non-zero; fi
sed -n '1p' "$stderr"
rm -f "$stderr"
EOF
;;
bare-openseek-is-rejected)
sh <<'EOF'
stderr=$(mktemp)
if openseek.exe 2> "$stderr" >/dev/null; then echo exit-zero; else echo exit-non-zero; fi
sed -n '1p' "$stderr"
rm -f "$stderr"
EOF
;;
api-key-is-required-for-agent-runs)
sh <<'EOF'
stdout=$(mktemp)
stderr=$(mktemp)
if env -u DEEPSEEK -u KIMI -u OPENSEEK_MODEL openseek.exe run "summarize this project" > "$stdout" 2> "$stderr"; then echo exit-zero; else echo exit-non-zero; fi
cat "$stderr"
if test -s "$stdout"; then echo stdout-not-empty; else echo stdout-empty; fi
rm -f "$stdout" "$stderr"
EOF
;;
a-result-file-says-how-the-run-ended)
sh <<'EOF'
dir=$(mktemp -d)
echo stale > "$dir/result.json"
env -u DEEPSEEK -u KIMI -u OPENSEEK_MODEL openseek.exe run --no-session --dir "$dir/ws" --result-file "$dir/result.json" task > /dev/null 2>&1
echo "exit $?"
cat "$dir/result.json"
rm "$dir/result.json"
env -u DEEPSEEK -u KIMI -u OPENSEEK_MODEL openseek.exe run --no-session --dir "$dir/ws2" --result-file "$dir/result.json" task > /dev/null 2< /dev/null
echo "exit $?"
cat "$dir/result.json"
rm -rf "$dir"
EOF
;;
unknown-options-are-rejected-before-task-text)
sh <<'EOF'
stdout=$(mktemp)
stderr=$(mktemp)
if env -u DEEPSEEK openseek.exe run --xxy he > "$stdout" 2> "$stderr"; then echo exit-zero; else echo exit-non-zero; fi
sed -n '1p' "$stderr"
if test -s "$stdout"; then echo stdout-not-empty; else echo stdout-empty; fi
rm -f "$stdout" "$stderr"
EOF
;;
unknown-options-are-rejected-before-task-text-2)
sh <<'EOF'
stdout=$(mktemp)
stderr=$(mktemp)
if env -u DEEPSEEK -u KIMI -u OPENSEEK_MODEL openseek.exe run -- '--xxy he' > "$stdout" 2> "$stderr"; then echo exit-zero; else echo exit-non-zero; fi
cat "$stderr"
if test -s "$stdout"; then echo stdout-not-empty; else echo stdout-empty; fi
rm -f "$stdout" "$stderr"
EOF
;;
openseek-sessions-is-offline)
sh <<'EOF'
tmp=$(mktemp -d)
mkdir -p "$tmp/sessions/demo"
cat > "$tmp/sessions/demo/openseek_session-demo.jsonl" <<'JSONL'
{"version":1,"id":"demo","system_prompt":"system"}
{"sequence":1,"ts":0,"item":{"kind":"user","payload":{"content":"hello"}}}
{"sequence":2,"ts":0,"item":{"kind":"assistant","payload":{"content":"answer","tool_calls":[]}}}
JSONL
printf 'hello and answer' > "$tmp/summary.txt"
env -u DEEPSEEK openseek.exe sessions list --session-root "$tmp" | cut -f1
env -u DEEPSEEK openseek.exe sessions show demo --session-root "$tmp" | sed -E 's/"ts":[0-9]+,//g'
env -u DEEPSEEK openseek.exe sessions compact demo --session-root "$tmp" --file "$tmp/summary.txt" --from 1 --to 2
env -u DEEPSEEK openseek.exe sessions show demo --session-root "$tmp" | sed -E 's/"ts":[0-9]+,//g'
rm -rf "$tmp"
EOF
;;
openseek-sessions-fork-continues-a-conversation-another-way)
sh <<'EOF'
tmp=$(mktemp -d)
mkdir -p "$tmp/sessions/demo"
cat > "$tmp/sessions/demo/openseek_session-demo.jsonl" <<'JSONL'
{"version":1,"id":"demo","system_prompt":"system"}
{"sequence":1,"ts":0,"item":{"kind":"user","payload":{"content":"hello"}}}
{"sequence":2,"ts":0,"item":{"kind":"terminal","payload":{"kind":"finished","message":"answer"}}}
{"sequence":3,"ts":0,"item":{"kind":"user","payload":{"content":"go on"}}}
JSONL
env -u DEEPSEEK openseek.exe sessions fork demo --as retry --session-root "$tmp"
env -u DEEPSEEK openseek.exe sessions show retry --session-root "$tmp" | grep -o '"item":{"kind":"[a-z_]*"' | cut -d'"' -f6
env -u DEEPSEEK openseek.exe sessions show retry --session-root "$tmp" | grep -o 'sessions/[a-z]*/scratch'
env -u DEEPSEEK openseek.exe sessions fork demo --as retry --session-root "$tmp" 2>&1 || echo exit-non-zero
env -u DEEPSEEK openseek.exe sessions fork demo --as early --through 1 --session-root "$tmp" 2>&1 || echo exit-non-zero
env -u DEEPSEEK openseek.exe sessions list --session-root "$tmp" | cut -f1 | sort
rm -rf "$tmp"
EOF
;;
openseek-sessions-fork-continues-a-conversation-another-way-2)
sh <<'EOF'
tmp=$(mktemp -d)
mkdir -p "$tmp/sessions/demo"
cat > "$tmp/sessions/demo/openseek_session-demo.jsonl" <<'JSONL'
{"version":1,"id":"demo","system_prompt":"system"}
{"sequence":1,"ts":0,"item":{"kind":"user","payload":{"content":"hello"}}}
{"sequence":2,"ts":0,"item":{"kind":"terminal","payload":{"kind":"finished","message":"answer"}}}
JSONL
cat > "$tmp/mcp.json" <<'JSON'
{"mcpServers": {"tracker": {"command": "tracker-mcp"}, "host": {"url": "${OPENSEEK_CRAM_UNSET_URL}"}}}
JSON
env -u DEEPSEEK openseek.exe sessions fork demo --as with-mcp --session-root "$tmp" --mcp-config "$tmp/mcp.json" >/dev/null
env -u DEEPSEEK openseek.exe sessions show with-mcp --session-root "$tmp" | grep -o 'Configured MCP servers: [^.]*'
rm -rf "$tmp"
EOF
;;
openseek-run-records-a-session-by-default)
sh <<'EOF'
tmp=$(mktemp -d)
cd "$tmp"
if env DEEPSEEK=test-key OPENSEEK_RETRY_ATTEMPTS=1 openseek.exe run --api-url "http://127.0.0.1:9/chat/completions" "say hi" > out.txt 2> err.txt; then echo exit-zero; else echo exit-non-zero; fi
grep -c '^session cli-' err.txt
wc -c < out.txt | tr -d ' '
env -u DEEPSEEK openseek.exe sessions list | cut -f1 | sed -E 's/cli-[0-9]{8}-[0-9]{6}-[0-9]{3}(-[A-Za-z0-9]+)?/cli-<stamp>/'
rm -rf "$tmp"
EOF
;;
openseek-run-records-a-session-by-default-2)
sh <<'EOF'
tmp=$(mktemp -d)
cd "$tmp"
for level in warn error; do
  env DEEPSEEK=test-key OPENSEEK_RETRY_ATTEMPTS=1 MOON_XLOG=$level openseek.exe run --api-url "http://127.0.0.1:9/chat/completions" --dir "$tmp/$level" "say hi" > /dev/null 2> "err-$level.txt"
  echo "$level: $(grep -c '^session cli-' "err-$level.txt")"
done
rm -rf "$tmp"
EOF
;;
openseek-run-records-a-session-by-default-3)
sh <<'EOF'
tmp=$(mktemp -d)
cd "$tmp"
env DEEPSEEK=test-key OPENSEEK_RETRY_ATTEMPTS=1 openseek.exe run --no-session --api-url "http://127.0.0.1:9/chat/completions" "say hi" >/dev/null 2>&1
if test -d .openseek; then echo recorded; else echo ephemeral; fi
rm -rf "$tmp"
EOF
;;
dir-selects-the-workspace-root)
sh <<'EOF'
tmp=$(mktemp -d)
mkdir -p "$tmp/parent"
if env DEEPSEEK=test-key OPENSEEK_RETRY_ATTEMPTS=1 openseek.exe run --dir "$tmp/parent/new" --api-url "http://127.0.0.1:9/chat/completions" "say hi" > /dev/null 2> "$tmp/err.txt"; then echo exit-zero; else echo exit-non-zero; fi
if test -d "$tmp/parent/new"; then echo dir-created; else echo dir-missing; fi
grep -c '^created ' "$tmp/err.txt"
env -u DEEPSEEK openseek.exe sessions list --dir "$tmp/parent/new" | cut -f1 | sed -E 's/cli-[0-9]{8}-[0-9]{6}-[0-9]{3}(-[A-Za-z0-9]+)?/cli-<stamp>/'
env -u DEEPSEEK openseek.exe sessions list --dir "$tmp/parent/fresh" > "$tmp/session-list.out"
if test -d "$tmp/parent/fresh"; then echo session-dir-created; else echo session-dir-missing; fi
wc -l < "$tmp/session-list.out" | tr -d ' '
rm -rf "$tmp"
EOF
;;
openseek-serve-speaks-jsonl-commands-on-stdin)
printf '{"command":"reboot"}\n{"command":"cancel"}\n' | env DEEPSEEK=test-key openseek.exe serve 2>/dev/null | grep -o '"event":"command_error"'
;;
openseek-serve-speaks-jsonl-commands-on-stdin-2)
printf '{"command":"steer","text":"too late"}\n' | env DEEPSEEK=test-key openseek.exe serve 2>/dev/null | grep -o '"event":"steer_dropped"'
;;
openseek-serve-speaks-jsonl-commands-on-stdin-3)
printf '{"command":"steer","text":"too late","submission_id":"late-steer"}\n' | env DEEPSEEK=test-key openseek.exe serve 2>/dev/null | grep '"event":"steer_dropped"'
;;
openseek-serve-speaks-jsonl-commands-on-stdin-4)
env DEEPSEEK=test-key openseek.exe serve </dev/null 2>/dev/null | grep '"event":"mcp_status"'
;;
openseek-serve-speaks-jsonl-commands-on-stdin-5)
sh <<'EOF'
printf '{"mcpServers":{"notes":{"command":"openseek-no-such-mcp-server"}}}' > mcp.json
env DEEPSEEK=test-key openseek.exe serve --mcp-config mcp.json </dev/null 2>/dev/null | grep -o '"event":"mcp_status".*"state":"failed"'
rm -f mcp.json
EOF
;;
openseek-serve-speaks-jsonl-commands-on-stdin-6)
sh <<'EOF'
stderr=$(mktemp)
if env DEEPSEEK=test-key openseek.exe serve "do something" 2> "$stderr" >/dev/null; then echo exit-zero; else echo exit-non-zero; fi
sed -n '1p' "$stderr"
rm -f "$stderr"
EOF
;;
moonbit-cli-argument-parsing-pattern)
sh <<'EOF'
tmp=$(mktemp -d)
mkdir -p "$tmp/cmd/echoargs"
cat > "$tmp/moon.mod" <<'MOD'
name = "example/cli"
version = "0.1.0"
MOD
cat > "$tmp/cmd/echoargs/moon.pkg" <<'PKG'
import {
  "moonbitlang/core/argparse"
}
warnings = "+unnecessary_annotation"
supported_targets = "+native"
options(
  "is-main": true,
)
PKG
cat > "$tmp/cmd/echoargs/main.mbt" <<'MBT'
///|
fn main raise {
  let matches = @argparse.parse(
    Command(
      "echoargs",
      about="Tiny argparse example.",
      flags=[FlagArg("stdin", long="stdin", about="Read stdin.")],
      positionals=[PositionArg("input", default_values=["-"])],
    ),
  )
  let input = match matches.values.get("input") {
    Some([value, ..]) => value
    _ => fail("missing input")
  }
  let stdin = match matches.flags.get("stdin") {
    Some(value) => value
    None => false
  }
  println("input=\{input}")
  println("stdin=\{stdin}")
}
MBT
(cd "$tmp" && moon run --target native cmd/echoargs -- --stdin sample.toml)
rm -rf "$tmp"
EOF
;;
multiple-mcp-configuration-files)
sh <<'EOF'
d=$(mktemp -d)
cd "$d"
printf '{"mcpServers":{}}' > first.json
printf '{"mcpServers":{}}' > second.json
OPENSEEK_MCP_CONFIG=missing.json openseek.exe mcp --mcp-config first.json --mcp-config= --mcp-config=second.json
cd /
rm -rf "$d"
EOF
;;
*) echo "Unknown scenario: $1" >&2; exit 2 ;;
esac
