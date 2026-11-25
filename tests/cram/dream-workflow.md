# Consolidating memories and skills with `dream.mbtx`

This page is both a usage guide and an executable offline test of
[`dream.mbtx`](../../share/workflow/dream.mbtx) in `--no-llm` mode. Run it from
the repository root:

```sh
moon cram test tests/cram/dream-workflow.md --shell bash
```

In OpenSeek, run `/dream` or call:

```json
{"filename":"@builtin/dream.mbtx"}
```

## Set up synthetic session fixtures

```mooncram
$ DREAM="$TESTDIR/../../share/workflow/dream.mbtx"
```

Create a workspace store with one session containing a user steering correction,
an error-to-recovery sequence, and a completed multi-step workflow, plus one
subagent session (`*-sr-*`):

```mooncram
$ mkdir -p .openseek/sessions/sess-1 .openseek/sessions/sess-1-sr-1
```

```mooncram
$ printf 'Fix build and release\n' > .openseek/sessions/sess-1/session-title
```

```mooncram
$ cat > .openseek/sessions/sess-1/openseek_session-sess-1.jsonl <<'EOF'
> {"version":1,"id":"sess-1","system_prompt":"test"}
> {"sequence":1,"ts":1758700001000,"item":{"kind":"user","payload":{"content":"run tests"}}}
> {"sequence":2,"ts":1758700002000,"item":{"kind":"assistant","payload":{"content":"","tool_calls":[{"id":"c1","name":"mbtx","arguments":"{\"filename\":\"@builtin/test.mbtx\"}"}]}}}
> {"sequence":3,"ts":1758700003000,"item":{"kind":"tool_result","payload":{"tool_call_id":"c1","tool_name":"mbtx","content":"test failed on js target","is_error":true}}}
> {"sequence":4,"ts":1758700004000,"item":{"kind":"user","payload":{"content":"记住以后先跑 moon test --target native"}}}
> {"sequence":5,"ts":1758700005000,"item":{"kind":"tool_result","payload":{"tool_call_id":"c2","tool_name":"mbtx","content":"Total tests: 12, passed: 12, failed: 0.","is_error":false}}}
> {"sequence":6,"ts":1758700006000,"item":{"kind":"tool_result","payload":{"tool_call_id":"c3","tool_name":"edit","content":"ok","is_error":false}}}
> {"sequence":7,"ts":1758700007000,"item":{"kind":"terminal","payload":{"kind":"finished","message":"done"}}}
> EOF
```

```mooncram
$ cat > .openseek/sessions/sess-1-sr-1/openseek_session-sess-1-sr-1.jsonl <<'EOF'
> {"version":1,"id":"sess-1-sr-1","system_prompt":"child"}
> {"sequence":1,"ts":1758700002500,"item":{"kind":"user","payload":{"content":"subagent"}}}
> {"sequence":2,"ts":1758700002600,"item":{"kind":"terminal","payload":{"kind":"finished","message":"ok"}}}
> EOF
```

## Deterministic signal preview (`--no-llm`)

```mooncram
$ moonx "$DREAM" --no-llm
# OpenSeek Dream Signal Preview (--no-llm)
Roots: .openseek | New sessions: 1 (already consolidated: 0, subagents skipped: 1)
Signals: corrections=1 error_recoveries=1 workflow_candidates=1
- correction [sess-1]: 记住以后先跑 moon test --target native
- recovery [sess-1]: `mbtx` (1x `test failed on js target`) -> Total tests: 12, passed: 12, failed: 0.
sessions=1 corrections=1 recoveries=1 workflows=1 memory=0 topics=0 pruned=0 skills=0 tokens=0
```

## Watermark skipping and `--force`

Write a `dream-state.json` watermark marking `sess-1` as already consolidated at
its latest timestamp:

```mooncram
$ cat > .openseek/dream-state.json <<'EOF'
> {"version":1,"last_ts":1758700007000,"processed_sessions":{"sess-1":1758700007000}}
> EOF
```

```mooncram
$ moonx "$DREAM" --no-llm | tail -n 1
sessions=0 corrections=0 recoveries=0 workflows=0 memory=0 topics=0 pruned=0 skills=0 tokens=0
```

`--force` ignores the watermark and re-extracts signals:

```mooncram
$ moonx "$DREAM" --force --no-llm | tail -n 1
sessions=1 corrections=1 recoveries=1 workflows=1 memory=0 topics=0 pruned=0 skills=0 tokens=0
```

## Discovering registered workspaces via `workspaces.json`

```mooncram
$ mkdir -p global-root ws-demo/.openseek/sessions/sess-ws
```

```mooncram
$ cat > ws-demo/.openseek/sessions/sess-ws/openseek_session-sess-ws.jsonl <<'EOF'
> {"version":1,"id":"sess-ws","system_prompt":"test"}
> {"sequence":1,"ts":1758700009000,"item":{"kind":"user","payload":{"content":"always run moon fmt"}}}
> {"sequence":2,"ts":1758700010000,"item":{"kind":"terminal","payload":{"kind":"finished","message":"ok"}}}
> EOF
```

```mooncram
$ printf '{"workspaces":["%s/ws-demo"]}\n' "$PWD" > global-root/workspaces.json
```

```mooncram
$ moonx "$DREAM" --session-root global-root --no-llm --json | grep -o '"sessions_selected":1'
"sessions_selected":1
```

## Help and invalid arguments

```mooncram
$ moonx "$DREAM" --since-days 0 2> dream.err
[1]
```

```mooncram
$ grep -o -- '--since-days takes an integer from 1 to 3650' dream.err
--since-days takes an integer from 1 to 3650
```

```mooncram
$ moonx "$DREAM" --help | head -n 1
usage: @builtin/dream.mbtx [--session-root PATH ...] [--all-workspaces]
```
