#!/usr/bin/env bash
# Independent scenarios for run-requests.md. Each runs in a fresh temporary directory.
case "$1" in
a-request-from-a-file-stdin-eof-ends-the-input)
sh <<'EOF'
d=$(mktemp -d)
printf '{"version":1,"request_id":"r-1","kind":"echo","input":{"probe":42}}' > "$d/request.json"
openseek.exe run --input-format json --no-session --dir "$d/ws" --result-file "$d/result.json" < "$d/request.json" > /dev/null 2>&1
echo "exit $?"
cat "$d/result.json"
rm -rf "$d"
EOF
;;
kind-and-the-request-s-kind-must-agree)
sh <<'EOF'
d=$(mktemp -d)
printf '{"version":1,"input":"hi"}' | openseek.exe run --kind echo --input-format json --no-session --dir "$d/ws" --result-file "$d/result.json" > /dev/null 2>&1
echo "exit $?"
cat "$d/result.json"
printf '{"version":1,"kind":"echo","input":"hi"}' | openseek.exe run --kind explore --input-format json --no-session --dir "$d/ws" --result-file "$d/result.json" 2>&1 > /dev/null
echo "exit $?"
cat "$d/result.json"
rm -rf "$d"
EOF
;;
requests-that-cannot-run-are-refused-up-front)
sh <<'EOF'
d=$(mktemp -d)
try() { openseek.exe run --no-session --dir "$d/ws" "$@" 2>&1 > /dev/null; echo "exit $?"; }
printf '{"version":1,"kind":"nope","input":{}}' | try --input-format json
printf '{"version":1,"kind":"worker","input":{"task":"fix things"}}' | try --input-format json
printf '{"version":1,"kind":"review","input":{"goal":"g","base":"origin/main"}}' | try --input-format json
printf '{"version":1,"kind":"review","input":{"base":" "}}' | try --input-format json
printf '{"version":2,"input":{}}' | try --input-format json
printf '{"version":1,"input":{"task":"t"},"schema":{"type":"object"}}' | try --input-format json
printf '{"version":1,"input":{"prompt":"t"}}' | try --input-format json
printf '{"version":1,"input":{"task":"t"}}' | try --input-format json words
try --kind echo words
try --cancel-on-stdin-eof words
printf 'not json' | try --input-format json
printf '{"version":1,"input":{"task":"t"}}\n' | try --input-format json --cancel-on-stdin-eof --review-gate
rm -rf "$d"
EOF
;;
a-refused-request-still-answers-under-its-id-and-leaves-nothing-behind)
sh <<'EOF'
d=$(mktemp -d)
printf '{"version":1,"request_id":"r-3","kind":"explore","input":{}}' | openseek.exe run --input-format json --no-session --dir "$d/ws" --result-file "$d/result.json" 2>&1 > /dev/null
cat "$d/result.json"
test -e "$d/ws" && echo "ws exists" || echo "no ws"
printf '{"version":1,"kind":"echo","input":0}' | openseek.exe run --input-format json --session s-echo --session-root "$d/sessions" --dir "$d/ws" --result-file "$d/result.json" > /dev/null 2>&1
cat "$d/result.json"
rm -rf "$d"
EOF
;;
a-claimed-session-is-accepted-once-with-its-token)
sh <<'EOF'
d=$(mktemp -d)
mkdir -p "$d/ws" "$d/store/sessions/p-sr-1"
printf '{"sha256":"46e9bc3476c92ea24fb17adac6cd9cdacff7a34a5c753100787da5a29984f836"}' > "$d/store/sessions/p-sr-1/claim.json"
child() { printf '{"version":1,"kind":"echo","input":0}' | openseek.exe run --input-format json --dir "$d/ws" "$@" 2>&1 > /dev/null; echo "exit $?"; }
child --session p-sr-1 --session-root "$d/store"
child --session p-sr-1 --session-root "$d/store" --claim t-2
child --session p-sr-1 --session-root "$d/store" --claim t-1
ls "$d/store/sessions/p-sr-1"
child --session p-sr-1 --session-root "$d/store" --claim t-1
child --no-session --claim t-1
openseek.exe run --no-session --dir "$d/ws" --claim t-1 words 2>&1 > /dev/null
rm -rf "$d"
EOF
;;
a-parent-managed-run-one-line-in-stdin-held-open)
sh <<'EOF'
d=$(mktemp -d)
(printf '{"version":1,"kind":"echo","input":[1,2]}\n'; sleep 1) | openseek.exe run --input-format json --cancel-on-stdin-eof --no-session --dir "$d/ws" --result-file "$d/result.json" > /dev/null 2>&1
echo "exit $?"
cat "$d/result.json"
(printf '{"version":1,"kind":"echo","input":"inherited"}\n'; sleep 1) | env OPENSEEK_APPROVAL=ask openseek.exe run --input-format json --cancel-on-stdin-eof --no-session --dir "$d/ws" --result-file "$d/result.json" > /dev/null 2>&1
cat "$d/result.json"
printf '{"version":1,"kind":"echo","input":0}\n' | openseek.exe run --input-format json --cancel-on-stdin-eof --approval always --no-session --dir "$d/ws" 2>&1 > /dev/null
openseek.exe run --input-format json --cancel-on-stdin-eof --no-session --dir "$d/ws" --result-file "$d/result.json" < /dev/null 2>&1 > /dev/null
echo "exit $?"
cat "$d/result.json"
rm -rf "$d"
EOF
;;
a-delegated-run-takes-only-what-its-launch-grants)
sh <<'EOF'
d=$(mktemp -d)
mkdir "$d/out" "$d/ws"
echo keep > "$d/out/existing.json"
managed() { openseek.exe run --input-format json --cancel-on-stdin-eof --no-session "$@"; }
printf '{"version":1,"kind":"echo","input":0}\n' | managed --dir "$d/ws" --dir / 2>&1 > /dev/null | head -1
printf '{"version":1,"kind":"echo","input":0}\n' | managed --dir "$d/ws" --mcp-config "$d/mcp.json" 2>&1 > /dev/null
printf '{"version":1,"kind":"echo","input":0}\n' | env OPENSEEK_MCP_CONFIG="$d/mcp.json" openseek.exe run --input-format json --cancel-on-stdin-eof --no-session --dir "$d/ws" 2>&1 > /dev/null
printf '{"version":1,"kind":"echo","input":0}\n' | managed --dir "$d/ws" --result-root "$d/out" --result-file "$d/elsewhere.json" 2>&1 > /dev/null | sed "s#$d#DIR#g; s#/private##g"
test -e "$d/elsewhere.json" && echo "elsewhere written" || echo "nothing written elsewhere"
printf '{"version":1,"kind":"echo","input":0}\n' | managed --dir "$d/ws" --result-root "$d/out" --result-file "$d/out/existing.json" 2>&1 > /dev/null | sed "s#$d#DIR#g; s#/private##g"
cat "$d/out/existing.json"
printf '{"version":1,"kind":"echo","input":0}\n' | managed --dir "$d/ws" --result-root "$d/out" --result-file "$d/out/result.json" > /dev/null 2>&1
cat "$d/out/result.json"
rm -rf "$d"
EOF
;;
a-delegated-run-takes-only-what-its-launch-grants-2)
printf '{"version":1,"input":{"task":"t"},"limits":{"max_steps":2}}' | env -u DEEPSEEK -u KIMI -u OPENSEEK_MODEL OPENSEEK_MAX_STEPS=bad openseek.exe run --input-format json --no-session --dir "$(mktemp -d)" 2>&1 | tail -1
;;
closing-stdin-cancels-a-managed-run-which-still-reports)
sh <<'EOF'
d=$(mktemp -d)
(printf '{"version":1,"request_id":"r-9","input":{"task":"say hi"}}\n'; sleep 1) | env DEEPSEEK=test-key OPENSEEK_RETRY_ATTEMPTS=20 OPENSEEK_RETRY_BACKOFF_MS=500 openseek.exe run --input-format json --cancel-on-stdin-eof --no-session --dir "$d/ws" --api-url http://127.0.0.1:9/chat/completions --result-file "$d/result.json" > /dev/null 2>&1
echo "exit $?"
cat "$d/result.json"
rm -rf "$d"
EOF
;;
one-delegated-general-run-per-workspace)
sh <<'EOF'
d=$(mktemp -d)
mkdir "$d/ws"
export DEEPSEEK=test-key OPENSEEK_RETRY_ATTEMPTS=20 OPENSEEK_RETRY_BACKOFF_MS=500
sh -c 'printf "{\"version\":1,\"input\":{\"task\":\"first\"}}\n"; sleep 3' | openseek.exe run --input-format json --cancel-on-stdin-eof --no-session --dir "$d/ws" --api-url http://127.0.0.1:9/chat/completions --result-file "$d/first.json" > /dev/null 2>&1 &
sleep 1
(printf '{"version":1,"input":{"task":"second"}}\n'; sleep 1) | openseek.exe run --input-format json --cancel-on-stdin-eof --no-session --dir "$d/ws" --api-url http://127.0.0.1:9/chat/completions --result-file "$d/second.json" 2>&1 > /dev/null | sed -E 's#in [^;]*/ws;#in WORKSPACE;#'
wait
sed -E 's#in [^;]*/ws;#in WORKSPACE;#' "$d/second.json"
rm -rf "$d"
EOF
;;
*) echo "Unknown scenario: $1" >&2; exit 2 ;;
esac
