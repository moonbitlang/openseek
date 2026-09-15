# Review workflow CLI

Run the bundled script directly, without a hosted handoff or standing goal.
The build stays in cram's scratch directory. Successful hosted reviews and
baseline/goal resolution are covered by `just test-workflows`.

```mooncram
$ cat > review.sh <<'EOF'
> unset WORKFLOW_HOST OPENSEEK_GOAL OPENSEEK_GOAL_SHA OPENSEEK_GOAL_DIRTY
> moon run -q "$TESTDIR/../../share/workflow/review.mbtx" --target-dir _build -- "$@"
> EOF
```

Argparse generates the help without requiring a goal or a host.

```mooncram
$ sh review.sh --help
Usage: @builtin/review.mbtx [options] [criteria...]

With no arguments the reviewer audits the standing goal and the baseline
it recorded, which the engine supplies in OPENSEEK_GOAL (and
OPENSEEK_GOAL_SHA/OPENSEEK_GOAL_DIRTY). The remaining arguments, joined
with spaces, narrow that goal as an audit focus, or are the whole criteria
when no goal stands. --sha names the baseline commit the criteria were
recorded at (--dirty: the worktree was already dirty then) and overrides
the engine's. A blocker finding fails the call: the claim does not hold
yet. Requires the hosted handoff: call mbtx with subrun=true.

Arguments:
  criteria...  Audit focus, or the whole criteria when no goal stands.

Options:
  -h, --help   Show help information.
  --dirty      The worktree was already dirty at the baseline commit.
  --sha <sha>  Baseline commit; overrides the standing goal's baseline.
```

```mooncram
$ sh review.sh -h > short-help && sh review.sh --help > long-help && diff short-help long-help
```

Argument errors fail before starting a review. Pin the diagnostic and exit
status without repeating the generated help.

```mooncram
$ sh <<'EOF'
> sh review.sh --sha > output 2>&1
> status=$?
> sed -n '1p' output
> exit "$status"
> EOF
error: a value is required for '--sha' but none was supplied
[1]
```

```mooncram
$ sh <<'EOF'
> sh review.sh --unknown > output 2>&1
> status=$?
> sed -n '1p' output
> exit "$status"
> EOF
error: unexpected argument '--unknown' found
[1]
```

```mooncram
$ sh <<'EOF'
> sh review.sh --dirty audit > output 2>&1
> status=$?
> sed -n '1p' output
> exit "$status"
> EOF
error: the following required argument was not provided: 'sha' (required by 'dirty')
[1]
```

`--` makes option-looking words literal criteria. Valid criteria (including
multiple words and an explicit baseline) reach the hosted-context check.
Normalize only the source location in the runtime failure.

```mooncram
$ sh <<'EOF'
> sh review.sh -- --help --sha --dirty > output 2>&1
> status=$?
> sed -E 's/^Failure\([^ ]+ FAILED: /Failure(/' output
> exit "$status"
> EOF
Failure(This workflow needs OpenSeek: call mbtx with filename=@builtin/review.mbtx and subrun=true)
[1]
```

```mooncram
$ sh <<'EOF'
> sh review.sh Check CSV --sha=abc --dirty CRLF handling > output 2>&1
> status=$?
> sed -E 's/^Failure\([^ ]+ FAILED: /Failure(/' output
> exit "$status"
> EOF
Failure(This workflow needs OpenSeek: call mbtx with filename=@builtin/review.mbtx and subrun=true)
[1]
```
