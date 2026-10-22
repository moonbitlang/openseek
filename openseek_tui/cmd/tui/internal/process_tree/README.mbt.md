# moonbitlang/openseek_tui/cmd/tui/internal/process_tree

Makes a spawned process's whole tree die with it on native Windows.

`moonbitlang/async/process` cancels a spawned process by signalling its PID
alone. That is enough when the PID *is* the program you care about, but not
when it is a launcher that starts the real program as a child and waits for it.
Kill the launcher and the child lives on, still holding whatever it inherited:
its stdout and stderr pipes (so a reader never sees end-of-file), and any files
or locks it opened.

The TUI hits this with its default engine, `moonx moonbitlang/openseek@… serve`.
On Unix `moonx` `exec`s `moonrun`, so the spawned PID is the engine. On Windows
`moonx` runs `moonrun` as a child and waits for it, ignoring Ctrl-C and
Ctrl-Break, so killing the engine used to kill only `moonx`.

## Usage

Call `contain` right after spawning, in the same task group:

```mbt check
///|
/// A command that exits with status 3 on this platform.
let exit_3 : (String, Array[String]) = match @async.platform {
  Windows => ("cmd.exe", ["/c", "exit", "3"])
  Linux | MacOS => ("sh", ["-c", "exit 3"])
}

///|
async test "contain a spawned process" {
  @async.with_task_group(group => {
    let (cmd, args) = exit_3
    let proc = @process.spawn(group, cmd, args, no_wait=true)
    @process_tree.contain(group, proc)
    // Containment does not change how the process itself runs or exits.
    inspect(proc.wait(), content="3")
  })
}
```

On native Windows, `proc.cancel()` (or `proc` exiting for any other reason)
also ends everything `proc` started when the process joined the job.

## How it works

**Native Windows.** `contain` creates a Job Object with
`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, without the breakaway flags, and assigns
`proc` to it. Every process `proc` starts from then on joins the job. The
async runtime's own job does allow silent breakaway, which is why it doesn't
catch grandchildren. A child that `proc` started *before* the assignment is
found by walking process snapshots: a process whose parent is already in the
tree, and that was created after that parent, is assigned too. Snapshots are
retaken until one finds nothing new, at which point every member is in the job.

A background task in the given group then waits for `proc` to exit and
terminates the job:
- after a graceful exit the job is already empty, so this does nothing;
- after a kill, it takes down every descendant `proc` left behind.

The task also terminates the job if the group is torn down first, and the job's
kill-on-close limit cleans up if the whole program dies.

**Unix.** `contain` does nothing. The process library signals only the spawned
PID there too, so a child that forks instead of `exec`ing still leaves its own
children behind. Containing them would need the child to start in its own
process group, which `@process.spawn` does not do.

**Wasm.** `contain` does nothing. `moonrun` exposes process spawning and
cancellation, but has no host API for assigning Windows Job Objects. As on
Unix, cancellation only guarantees termination of the spawned process. Use
the native TUI on Windows when the default `moonx` engine needs tree-wide
cleanup.

## Limits

- **Best effort.** If the job cannot be created or assigned (for example,
  before Windows 8 a process already in a job cannot join another), `proc`
  runs exactly as it would without `contain`.
- **Bounded sweep.** The pre-assignment sweep tracks at most 64 processes. It
  only has to catch what `proc` started in the moment between spawning and
  `contain`, so for a launcher like `moonx` that is one child.

## Tests

`process_tree_test.mbt` exercises the real problem on Windows with
`cmd.exe /c ping …`, which, like `moonx`, runs a child and waits for it while the
child inherits stdout. Each test kills only `cmd.exe` and checks whether stdout
reaches end-of-file:
1. without `contain`, `ping` keeps the pipe open (the problem exists);
2. with `contain`, the whole tree dies;
3. the whole tree still dies when `ping` was already running before `contain`.

These run on the native `windows-latest` CI job. On wasm and other platforms
only the usage example above runs.
