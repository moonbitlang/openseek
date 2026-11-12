# Running a command with `cmd.mbtx`

This page is both a usage guide and an executable test of
[`cmd.mbtx`](../../share/workflow/cmd.mbtx). Each `mooncram` block shows a
shell command after `$`, followed by its expected output. `[N]` means the
command must exit with status N; without it, success is expected.

Run this page from the repository root:

```sh
moon cram test tests/cram/cmd-workflow.md --shell bash
```

In OpenSeek, the equivalent of the first `diff` example below is:

```json
{"description":"Compare the fixtures","filename":"@builtin/cmd.mbtx","args":["diff","a.txt","a.txt"]}
```

These tests run the script directly with `moonx`, outside the mbtx sandbox, so
they check its output and exit status only. Inside OpenSeek the program is
also checked against the mbtx spawn allowlist; the
[mbtx package test](../../agent_tool/mbtx/cmd_workflow_test.mbt) runs the
script through the tool and covers an allowlisted program and a refused one.

## Set up the examples

```mooncram
$ CMD="$TESTDIR/../../share/workflow/cmd.mbtx"
```

```mooncram
$ printf 'same\n' > a.txt
```

```mooncram
$ printf 'other\n' > b.txt
```

## Usage

With no arguments, or only `--help`, the script prints its usage. It names
the allowlist and where the tool description lists the allowed programs.

```mooncram
$ moonx "$CMD"
Usage: mbtx(description="...", filename="@builtin/cmd.mbtx", args=["PROGRAM", "ARG", ...])
Runs one program with these arguments, unchanged: args[0] is the program and
each later item is one argument. There is no shell, so no pipes, redirection,
globbing, `&&`, or quoting; e.g. args=["git", "log", "--oneline", "-5"].
The program is subject to the mbtx sandbox spawn allowlist, exactly like
`@shell.Cmd` in a script: the mbtx tool description lists the allowed
programs under "Which programs a snippet may start". A program not listed
there is refused with the sandbox's refusal message.
Standard output and standard error are merged and streamed. Output is
bounded to 40000 UTF-8 bytes: the first and last lines are kept and a note
counts the omitted ones; lines over 2000 bytes are cut. Stdin is empty.
The last line is `exit=N`, and the call exits with the program's status.
Relative paths use cwd (default workspace).
```

```mooncram
$ moonx "$CMD" --help | head -n 1
Usage: mbtx(description="...", filename="@builtin/cmd.mbtx", args=["PROGRAM", "ARG", ...])
```

## Run a program

`args[0]` is the program and the rest are its arguments. The program's output
comes first, then `exit=N`:

```mooncram
$ moonx "$CMD" diff a.txt a.txt
exit=0
```

## Report a non-zero exit

A failing program's status is printed and becomes the script's own exit
status. `diff` exits 1 when the files differ:

```mooncram
$ moonx "$CMD" diff a.txt b.txt
1c1
< same
---
> other
exit=1
[1]
```

Standard error is merged into the same stream, so a program's error message
appears in place. `diff` exits 2 on a missing file:

```mooncram
$ moonx "$CMD" diff missing.txt a.txt
diff: missing.txt: No such file or directory
exit=2
[2]
```

## Arguments are not split

Each list item is exactly one argument: no shell parses it, so the space
below is part of a single filename rather than separating two.

```mooncram
$ moonx "$CMD" diff 'a.txt b.txt' a.txt
diff: a.txt b.txt: No such file or directory
exit=2
[2]
```

## A program that cannot be started

A program that cannot be started exits 127 without an `exit=` line. Inside
OpenSeek, a program refused by the allowlist fails here too, and its error
text, `@process.spawn(): Permission denied`, is what lets mbtx append the
sandbox's refusal explanation.

```mooncram
$ moonx "$CMD" no-such-program-for-cmd-workflow
error: could not start no-such-program-for-cmd-workflow: @process.spawn(): No such file or directory
[127]
```

## Bounded output

Output is bounded to 40000 bytes. The first lines stream as they arrive; the
last lines are printed when the program ends, after a note counting the lines
omitted between them. Comparing a 5000-line file with an empty one prints
a header and 5000 lines, too many to show:

```mooncram
$ seq 1 5000 | sed 's/^/line /' > big.txt
```

```mooncram
$ moonx "$CMD" diff big.txt /dev/null > big.out
[1]
```

```mooncram
$ head -n 2 big.out
1,5000d0
< line 1
```

```mooncram
$ grep '<system>' big.out
<system>truncated=true omitted_lines=1659 total_lines=5001 note=the first and last lines are shown; narrow the command's output to see the rest</system>
```

```mooncram
$ tail -n 2 big.out
< line 5000
exit=1
```

A line longer than 2000 bytes is cut and marked with the number of bytes
removed:

```mooncram
$ printf '%05000d\n' 0 > long.txt
```

```mooncram
$ moonx "$CMD" diff long.txt /dev/null | sed -n 2p | tail -c 19
0 [3002 bytes cut]
```
