# agent_tool/internal/moon_check

The shared vocabulary for running a follow-up `moon check`: the command, its
bounds, how its result is rendered, and where it should run from.

Two callers need to agree on all four. `agent_tool/internal/auto_check` runs a
check after `write`, `edit`, `multi_edit`, and `remove` change a MoonBit file;
`agent_tool/shell` recognizes the same check when the model runs it itself. If
the two disagreed on the command or the output shape, the same failure would
reach the model looking like two different failures.

This package holds no policy about *when* to check — only what the check is.

## The bounds

```mbt check
///|
test "the command and its bounds are constants, not caller choices" {
  inspect(@moon_check.Command, content="moon check --diagnostic-limit 1")
  inspect(@moon_check.TimeoutMs, content="30000")
  inspect(@moon_check.MaxOutputChars, content="12000")
}
```

`--diagnostic-limit 1` is the reason this is cheap enough to run after every
write: the model needs to know *that* it broke the build and *where*, not the
full cascade. A 30-second ceiling and a 12000-character capture keep a
pathological project from stalling a tool call or flooding the conversation.

## `format_output` — success is the absence of an exit line

The rendering is deliberately terse. A clean check adds one header line and the
output; anything abnormal adds a labeled line for it. There is no `exit=0`,
because the common case should cost the model as little context as possible.

```mbt check
///|
test "a successful check renders as a header and the output" {
  inspect(
    @moon_check.format_output(
      Some(0),
      "Finished. moon: ran 2 tasks, now up to date",
      false,
    ),
    content=(
      #|moon check:
      #|Finished. moon: ran 2 tasks, now up to date
    ),
  )
}

///|
test "a failure carries its exit code" {
  inspect(
    @moon_check.format_output(
      Some(255),
      (
        #|Error: Failed to calculate build plan
        #|
        #|Caused by:
        #|    0: Failed to resolve the module dependency graph
      ),
      false,
    ),
    content=(
      #|moon check:
      #|exit=255
      #|Error: Failed to calculate build plan
      #|
      #|Caused by:
      #|    0: Failed to resolve the module dependency graph
    ),
  )
}
```

The two abnormal conditions are named rather than inferred. A cancelled check
has no exit code at all — distinct from exiting non-zero, and the model should
not read it as a build failure. A truncated capture is flagged so the model
knows the diagnostics it can see may not be all of them.

```mbt check
///|
test "cancellation and truncation are labeled, not implied" {
  inspect(
    @moon_check.format_output(None, "long output", true),
    content=(
      #|moon check:
      #|exit=cancelled
      #|output_limit_reached=true
      #|long output
    ),
  )
  // Empty output produces the header alone — never a trailing blank line.
  inspect(@moon_check.format_output(Some(0), "", false), content="moon check:")
  inspect(
    @moon_check.format_output(Some(1), "", false),
    content=(
      #|moon check:
      #|exit=1
    ),
  )
}
```

## `nearest_project_dir` — where to run from

`moon check` must run from a module or workspace root, not from the directory of
the file that changed. This walks up from `start` looking for a `moon.mod` or
`moon.work` marker and returns the first directory that has either.

Nearest wins, and the two markers are equal in rank: a `moon.mod` deeper in the
tree beats a `moon.work` above it, so editing a member of a workspace checks
that member rather than the whole workspace.

```mbt check
///|
#cfg(not(platform="windows"))
async test "the walk stops at the first marker it meets" {
  @vfs.with_tmpdir(prefix="openseek-moon-check-readme-", dir => {
    let module_dir = "\{dir}/packages/demo"
    let source = "\{module_dir}/src"
    @fs.mkdir(source, recursive=true)

    // Only a workspace marker at the top: the walk climbs all the way up.
    @fs.write_file(
      "\{dir}/moon.work",
      "members = []\n",
      create_mode=CreateOrTruncate,
    )
    inspect(
      @moon_check.nearest_project_dir(source) is Some(found) && found == dir,
      content="true",
    )

    // Add a module marker in between, and it wins — it is nearer.
    @fs.write_file(
      "\{module_dir}/moon.mod",
      "name = \"example/demo\"\n",
      create_mode=CreateOrTruncate,
    )
    inspect(
      @moon_check.nearest_project_dir(source) is Some(found) &&
      found == module_dir,
      content="true",
    )
    // A directory holding a marker is its own project root.
    inspect(
      @moon_check.nearest_project_dir(module_dir) is Some(found) &&
      found == module_dir,
      content="true",
    )
  })
}
```

The walk terminates at the filesystem root and returns `None` when it finds no
marker — a file outside any MoonBit project. Callers treat that as "do not
check" rather than as an error, which is what makes it safe to call this on any
path a tool just wrote.
