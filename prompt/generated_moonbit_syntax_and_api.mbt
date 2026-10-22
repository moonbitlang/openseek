// Generated from moonbit_syntax_and_api.mbt.md by moon dev_build. DO NOT EDIT.

///|
fn moonbit_syntax_and_api() -> String {
  (
    #|# MoonBit Syntax And Library APIs
    #|
    #|Each language section states its rules and links a verified example: a script under
    #|`share/examples/` that CI type-checks under deny-warn and runs, shown inline.
    #|
    #|## Writing mbtx programs
    #|
    #|A script is a whole program — imports plus vanilla MoonBit
    #|
    #|- Import every package it uses separately, core packages included and by
    #|  their real path: `moonbitlang/core/encoding/base64`, not
    #|  `moonbitlang/core/base64` — `moon ide doc "@base64"` prints the path.
    #|- Keep `async fn main` for async IO.
    #|- Helpers that run an async command/IO are `async fn` too;
    #|  a plain `fn` cannot call them. (so async is contagious)
    #|- There is no `await`: async calls are written normally, and async functions
    #|  and tests are marked `async`.
    #|- Use `println` (no `print`).
    #|
    #|A minimal `moon check` script:
    #|
    #|```mbtx
    #|import {
    #|  "moonbitlang/async",
    #|  "moonbitlang/async/shell",
    #|  "moonbitlang/core/env",
    #|}
    #|
    #|async fn main {
    #|  let code = @shell.Cmd("moon", ["check", ..@env.args()[1:]]).each_line(line => println(line))
    #|  if code != 0 { fail("moon check failed (exit=\{code})") }
    #|}
    #|```
    #|
    #|`mbtx` is powerful since it can reuse the whole MoonBit ecosystem
    #|
    #|## CLI Parsing with moonbitlang/core/argparse and env
    #|
    #|- Read `@env.args()[1:]` (from `moonbitlang/core/env`; the `[1:]` skips the
    #|  executable name) when the script only forwards or glances at its arguments —
    #|  the `check.mbtx` above passes them straight through to `moon check`.
    #|
    #|Below is a complete example of CLI parsing using argparse:
    #|
    #|```mbtx
    #|///|
    #|/// Arguments: [--stdin] [<input>].
    #|import {
    #|  "moonbitlang/async",
    #|  "moonbitlang/async/fs",
    #|  "moonbitlang/async/stdio",
    #|  "moonbitlang/core/argparse",
    #|}
    #|
    #|///|
    #|/// Reading a path or stdin is async IO, so `main` is `async fn main`.
    #|async fn main {
    #|  let matches : @argparse.Matches = @argparse.parse(
    #|      Command(
    #|        "count-input",
    #|        about="Print the length of a file or stdin.",
    #|        flags=[
    #|          // `long` omits the dashes: `long="stdin"`, not `long="--stdin"`.
    #|          FlagArg("stdin", long="stdin", about="Read stdin instead of a file."),
    #|        ],
    #|        positionals=[
    #|          PositionArg("input", default_values=["-"], about="Input file path."),
    #|        ],
    #|      ),
    #|    )
    #|  guard matches is {
    #|    values: { "input"? : Some([input, ..]), .. },
    #|    flags: { "stdin"? : (Some(stdin) | (None with stdin=false)), .. },
    #|    ..
    #|  } else {
    #|    fail("missing parsed argument: input")
    #|  }
    #|  let input = if stdin {
    #|    @stdio.stdin.read_all().text()
    #|    // we also have @stdio.stderr
    #|  } else {
    #|    @fs.read_file(input).text()
    #|  }
    #|  println(input.length())
    #|}
    #|```
    #|
    #|For a nonzero exit,import `"moonbitlang/x/sys"`, and call `@sys.exit(1)`.
    #|
    #|## Shell EDSL with moonbitlang/async/shell
    #|
    #|Use `@shell.Cmd` to run an external program and capture its output.
    #|
    #|Shell utilities can be expressed in MoonBit, including on Windows:
    #|
    #|| Command     | Alternatives     |
    #||-------------|------------------|
    #|| ls          | @fs.readdir(dir) |
    #|| find        | @shell.glob(pattern), spread into args as `[..files]` |
    #|| cat         | @fs.read_file(p).text() |
    #|| head/tail   | slice the split text; wc -l → count it |
    #|| grep        | `@builtin/rg.mbtx` (ripgrep flags and regex, not POSIX grep), or .split("\n").filter(...) on captured output |
    #|| sort/uniq   | .sort(), a Set, or a Map |
    #|| pwd         | @env.current_dir(); printenv → @env.get_env_var(name) — both `String?` |
    #|| mkdir -p    | @fs.mkdir(d, recursive=true) |
    #|| test -f     | @fs.exists(p); test -d → @fs.kind(p) is Directory |
    #|| echo/printf | println |
    #|| rm/mv/cp    | the `remove` and `write` tools; `remove` requests approval when automatic deletion is not allowed; do not bypass a refusal |
    #|| sh -c, xargs, make | write the logic as MoonBit statements |
    #|
    #|`@fs.kind(p)` returns a `FileKind` enum — `Directory`, `Regular`, `SymLink`,
    #|`BlockDevice`, `CharDevice`, `Pipe`, `Socket`, `Unknown` — which does **not**
    #|implement `Show`, so never interpolate or `println` it directly:
    #|`"\{@fs.kind(p)}"` is a type error. Test it with `is`
    #|(`@fs.kind(p) is Directory`, `@fs.kind(p) is Regular`); `match` it only when
    #|you need the full set. To print one for debugging, use `"\{Repr(k)}"`
    #|
    #|An example of using rg in `mbtx`:
    #|
    #|```mbtx
    #|///|
    #|import {
    #|  "moonbitlang/async",
    #|  "moonbitlang/async/shell",
    #|}
    #|
    #|///|
    #|async fn main {
    #|  // `Cmd` takes an argv array, not a shell line: nothing expands `*.mbt`
    #|  // before rg sees it, so rg applies it as its own glob. A glob with no `/`
    #|  // matches the basename at any depth. rg ships no `moonbit` file type, so
    #|  // `-g` is the filter — and `*.mbt` excludes `.mbti` and `.mbt.md`; widen it
    #|  // to `*.mbt*` when those should count.
    #|  let out = @shell.Cmd("rg", [
    #|    // A regex needle is one ordinary string element, so double the
    #|    // backslashes MoonBit needs (`"\\("`), or pass `-F` to match literally.
    #|    "-n", "protect_from_cancel\\(",
    #|    "-g", "*.mbt", "src",
    #|  ]).output()
    #|  // For redirect with `Cmd(.., stdout=ToFile(...))` to a file under
    #|  // `@fs.tmpdir(prefix="run-")` — the label is required, the call creates the
    #|  // directory, and that directory is the one place a snippet may write (`/tmp`
    #|  // itself is refused)
    #|
    #|  // `test` is a keyword, don't write `let test = ...`
    #|  // Slicing clamps instead of panicking, so this is safe on shorter output.
    #|  println(out.stdout()[:8000]) // at most 8000 UTF-16 code units
    #|  println(out.stderr()[:8000])
    #|  println("exit=\{out.exit_code()}") // `rg` exits 1 when nothing matched
    #|}
    #|```
    #|
    #|Use `moon ide doc @moonbitlang/async/shell` for the full API.
    #|
    #|For compiler feedback, stream the line-delimited JSON from one `moon check`
    #|rather than collecting it and parsing it afterward:
    #|
    #|```mbtx
    #|///|
    #|import {
    #|  "moonbitlang/async",
    #|  "moonbitlang/async/shell",
    #|  "moonbitlang/core/json",
    #|}
    #|
    #|///|
    #|async fn main {
    #|  let mut errors = 0
    #|  let exit_code = @shell.Cmd(
    #|    "moon",
    #|    ["check", "--output-json", "--diagnostic-limit", "5"],
    #|    env={ "NO_COLOR": "1" },
    #|    // argv is passed literally
    #|    // `|`, `>`, `&&`, `$()`, and `*` receive no shell interpretation.
    #|  // `<|` is sugar for a trailing lambda: `f() <| x => {...}` is the last
    #|  // argument of `f`, written after the call instead of inside it.
    #|  ).each_line() <| line => {
    #|    // Stderr is inherited, try to parse jsonl
    #|    let diagnostic = @json.parse(line) catch { _ => return }
    #|    if diagnostic
    #|      is {
    #|        "level": "error", // literal does not need `String(..)`
    #|        "path": String(path),
    #|        "loc": String(loc),
    #|        "message": String(message),
    #|        ..
    #|      } {
    #|      errors += 1
    #|      println("\{path}:\{loc}  \{message}")
    #|    }
    #|  }
    #|  println("exit=\{exit_code} errors=\{errors}")
    #|}
    #|```
    #|
    #|## Guarded edits through PTC
    #|
    #|A script may run `moon check --output-json` itself to find its targets:
    #|
    #|```mbtx
    #|///|
    #|/// One guarded edit from a script. The host checks the tree before and
    #|/// after the write and restores the file unless the warning total decreases
    #|/// without increasing the reported error total; the script reads the
    #|/// outcome from `result.data` instead of parsing prose. Arguments:
    #|/// <path> <old_string> <new_string> [<start_line>]. Verified end to end by
    #|/// a host-backed test that runs it through the real sandbox and host.
    #|import {
    #|  "moonbitlang/openseek_tools@0.2.0",
    #|  "moonbitlang/async",
    #|  "moonbitlang/core/env",
    #|  "moonbitlang/core/string",
    #|}
    #|
    #|///|
    #|async fn main {
    #|  let args = @env.args()[1:]
    #|  guard args is [path, old_string, new_string, ..] else {
    #|    fail(
    #|      "usage: ptc_guarded_edit.mbtx <path> <old_string> <new_string> [<start_line>]",
    #|    )
    #|  }
    #|  let start_line : Int32 = match args {
    #|    [_, _, _, line, ..] =>
    #|      @string.from_str(line) catch { _ => fail("start_line must be an integer") }
    #|    _ => 1
    #|  }
    #|  // Require no error-count increase and a net decrease in warning count.
    #|  let result = @openseek_tools.call("edit", {
    #|    "path": path,
    #|    "start_line": start_line,
    #|    "old_string": old_string,
    #|    "new_string": new_string,
    #|    "revert_if_error_delta_greater_or_equal": 1,
    #|    "revert_if_warning_delta_greater_or_equal": 0,
    #|  })
    #|  // A tool error is a result (`is_error` set, `content` explains). Only a
    #|  // transport failure raises, and a mutation may already have happened
    #|  // then, so a script never retries one blindly.
    #|  match result.data {
    #|    Some(
    #|      {
    #|        "outcome": "applied",
    #|        "check": { "warning_count": Number(warnings, ..), .. },
    #|        ..
    #|      }
    #|    ) => println("applied; \{warnings} warning(s) remain")
    #|    Some({ "outcome": "applied", .. }) => println("applied")
    #|    // A revert whose restore failed (a concurrent save, an IO error) leaves
    #|    // the file in an unknown state: report that first, with the host's
    #|    // explanation, never as an ordinary revert.
    #|    Some({ "outcome": "reverted", "restore_failed": true, .. }) =>
    #|      println("reverted but NOT restored: \{result.content}")
    #|    Some({ "outcome": "reverted", .. }) =>
    #|      println(result.content)
    #|    Some({ "outcome": String(outcome), .. }) =>
    #|      println("\{outcome}: \{result.content}")
    #|    _ => println("no data: \{result.content}")
    #|  }
    #|  // Only what the script prints reaches the model; the nested call itself is
    #|  // kept in the transcript. Every call finishes before main returns.
    #|}
    #|```
    #|
    #|## Delegating from a script
    #|
    #|The following example starts child agents through the host-tool SDK:
    #|
    #|```mbtx
    #|///|
    #|import {
    #|  "moonbitlang/openseek_tools@0.2.0" @tools,
    #|  "moonbitlang/async",
    #|  "moonbitlang/core/json",
    #|}
    #|
    #|///|
    #|/// Start one explore subagent; its job id.
    #|async fn scout(question : String, label : String) -> String {
    #|  let started = @tools.call("subagent", {
    #|    "kind": "explore",
    #|    "input": { "query": question },
    #|    "label": label,
    #|  })
    #|  guard started.data is Some({ "job_id": String(id), .. }) else {
    #|    fail(started.content)
    #|  }
    #|  id
    #|}
    #|
    #|///|
    #|/// A child's report, read in chunks until complete; `None` when it ended
    #|/// without one.
    #|async fn report(id : String) -> Json? {
    #|  let text = StringBuilder()
    #|  for ;; {
    #|    let read = @tools.call("job_output", {
    #|      "job_id": id,
    #|      "offset": text.to_string().char_length(),
    #|    })
    #|    guard read.data
    #|      is Some({ "report": { "chunk": String(chunk), "complete": complete, .. }, .. }) else {
    #|      return None
    #|    }
    #|    text.write_string(chunk)
    #|    if complete is True {
    #|      return Some(@json.parse(text.to_string()))
    #|    }
    #|  }
    #|}
    #|
    #|///|
    #|async fn main {
    #|  let ids = [
    #|    scout("Where is X constructed, and by whom? Cite file:line.", "scout:x"),
    #|    scout("Who calls Y, and what do the callers pass? Cite file:line.", "scout:y"),
    #|    scout("How does Z reach the network? Cite file:line.", "scout:z"),
    #|  ]
    #|  // Each wait returns within a minute with every child's state: drop the
    #|  // ended ones and wait for the rest.
    #|  let mut running = ids
    #|  while running.length() > 0 {
    #|    let waited = @tools.call("job_wait", {
    #|      "job_ids": Json::array(running.map(Json::string)),
    #|    })
    #|    guard waited.data is Some({ "jobs": Array(jobs), .. }) else {
    #|      fail(waited.content)
    #|    }
    #|    let still : Array[String] = []
    #|    for job in jobs {
    #|      if job is { "state": "running", "job_id": String(id), .. } {
    #|        still.push(id)
    #|      }
    #|    }
    #|    running = still
    #|  }
    #|  // Conclude in code when the conclusion is mechanical; otherwise print the
    #|  // reports and conclude yourself from the tool result.
    #|  for id in ids {
    #|    match report(id) {
    #|      Some(answer) => println(answer.stringify())
    #|      None => println("no report from \{id}")
    #|    }
    #|  }
    #|}
    #|```
    #|
    #|## CI monitoring program
    #|
    #|This bounded monitor discovers the current branch's PR, watches registered
    #|checks, then gives late workflows one settle interval to appear:
    #|
    #|```mbtx
    #|import {
    #|  "moonbitlang/async",
    #|  "moonbitlang/async/shell",
    #|}
    #|
    #|async fn main {
    #|  @shell.Cmd("gh", ["pr", "view", "--json", "number"]).output().check()
    #|  for pass in 0..<12; previous = None {
    #|    ignore(
    #|      @shell.Cmd("gh", ["pr", "checks", "--watch"]).output(),
    #|    )
    #|    let snapshot = @shell.Cmd("gh", ["pr", "checks"]).output()
    #|    let stdout = snapshot.stdout()
    #|    let count = [..stdout.split("\n")]
    #|      .filter(line => !line.is_blank())
    #|      .length()
    #|    println("CI monitor pass \{pass + 1}: \{count} check(s)")
    #|    let stable = count > 0 && previous == Some(count)
    #|    if stable || pass == 11 {
    #|      let output = [stdout, snapshot.stderr()]
    #|        .filter(text => !text.is_blank())
    #|        .join("\n")
    #|      if !stable {
    #|        println("CI monitor reached its 12-pass bound; inspect the output below.")
    #|      }
    #|      println <| (
    #|        $|\{output}
    #|        $|gh pr checks exit=\{snapshot.exit_code()}
    #|      )
    #|      return
    #|    }
    #|    @async.sleep(10_000)
    #|    continue Some(count)
    #|  }
    #|}
    #|```
    #|
    #|The single `mbtx` call hands itself off after five seconds; do not poll it.
    #|
    #|## Method resolution
    #|
    #|Do not find edit sites with `regex` or by syntax/AST-based reasoning — `expr.method()`
    #|resolves by the *type* of `expr`, so text matching hits the wrong occurrences,
    #|comments, strings, and other types, and misses spacing variants; only the type
    #|checker knows which uses are real.
    #|
    #|## Test annotations
    #|
    #|To keep a test but not run it, annotate it `#skip("reason")`: still
    #|type-checked, but run only with `--include-skipped` (or `-i <index>`, which
    #|implies it) — plain `moon test --filter` will not run it. To keep code that
    #|need only parse — not type-check, not run — annotate it `#cfg(false)`: a
    #|structured alternative to commenting it out.
    #|
    #|## Packages, imports, and visibility
    #|
    #|Files inside one package share a flat namespace; file names do not create modules.
    #|
    #|- Declare executable packages with `pkgtype(kind: "executable")`. The legacy
    #|  `"is-main"` option is deprecated; use `pkgtype` instead.
    #|- Treat files like Go package files: splitting a package into small focused
    #|  `.mbt` files does not affect visibility, and is preferred when it avoids
    #|  large fragile edits.
    #|- Import local packages by their full package path from `moon.mod` plus the
    #|  package directory. For module `name = "user/toml"` and package `lib/moon.pkg`,
    #|  import `"user/toml/lib"` and call it as `@lib.parse(...)`; import
    #|  `"user/toml/src"` and call `@src.name(...)` for a `src` package.
    #|- Configure imports in `moon.pkg`, not in `.mbt` files. Use `@alias.name` in
    #|  code to call imported package APIs.
    #|- Do not import `moonbitlang/core` as a package. Prelude types such as `Array`,
    #|  `Map`, `Json`, and `StringBuilder` are already available. Import specific
    #|  core subpackages only when needed, for example
    #|  `moonbitlang/core/string` for typed `@string.from_str` parsing,
    #|  `moonbitlang/core/argparse` for CLI parsing, or `moonbitlang/core/json` for
    #|  `@json.parse`.
    #|- Use `pub fn` for APIs called from another package. Plain `fn` is private.
    #|- Types are abstract by default: a plain `struct X { ... }` (no `pub`) leaves
    #|  only the type *name* visible to other packages — they can call its `pub`
    #|  methods but cannot construct it or read its fields. Prefer that over
    #|  `pub struct X { priv ... }` when every field is internal: the per-field
    #|  `priv` markers are redundant and `pub` (readonly) exposes nothing when no
    #|  field is readable. Reserve `pub` for types with readable fields, and
    #|  `priv struct X` for a type whose name itself must not leave the package.
    #|
    #|## Top-level declarations
    #|
    #|- Top-level MoonBit items are separated by `///|`.
    #|
    #|To add NEW top-level code (functions, tests, types) to an existing file,
    #|append at end of file: `edit` with an empty `old_string` and any
    #|`start_line` past the last line (e.g. 999999) — top-level order does not
    #|matter in MoonBit, and an append cannot mismatch an anchor. The result
    #|reports the actual inclusive line range the new code landed on. Insert
    #|mid-file only when grouping related code.
    #|
    #|## Manifest examples
    #|
    #|Example module skeleton:
    #|
    #|```moon.mod
    #|name = "username/project"
    #|version = "0.1.0"
    #|preferred_target = "native"
    #|
    #|import {
    #|  "moonbitlang/async@0.22.5", // import modules(`username/modulename`) with version
    #|}
    #|warnings = "+test_unqualified_package" // `moon explain --diagnostic test_unqualified_package` to learn more
    #|```
    #|
    #|Example native CLI package:
    #|
    #|```moon.pkg
    #|import {
    #|  "moonbitlang/async",
    #|  "moonbitlang/async/fs", // package
    #|  "moonbitlang/async/stdio",
    #|  "moonbitlang/core/argparse",
    #|}
    #|
    #|supported_targets = "+native"
    #|
    #|pkgtype(kind: "executable")
    #|```
    #|
    #|## Syntax And API Discipline
    #|
    #|- Prefer `Int32` over `Int` for 32-bit integers. They are aliases today, but
    #|  the current toolchain names the type and its APIs `Int32`; use `Int32` in
    #|  new annotations and when parsing integers.
    #|- Syntax the compiler rejects, each shown working in the verified example
    #|  below: parameters and `self` are never `mut`, a mutable local is
    #|  `let mut` (there is no `var`), and only a struct field you assign is
    #|  declared `mut field : T`; keywords such as `test`, `type`, `method`,
    #|  and `ref` cannot name a binding; negation is the `!` prefix, not `.not()`;
    #|  a bare `{}` is ambiguous and an error under deny-warn, so an empty map is
    #|  `Map([])` and the no-op expression is `()`; match arms are separated by
    #|  newlines, never `|`; lambdas are arrows (`x => ...`, `(a, b) => { ... }`),
    #|  and an async lambda is `async fn(x) { ... }`.
    #|
    #|```mbtx
    #|///|
    #|/// Parameters including `self` are never `mut`: a function that needs a changed
    #|/// value rebinds a local with `let mut`.
    #|fn collatz_steps(start : Int32) -> Int32 {
    #|  let mut value = start
    #|  let mut steps = 0
    #|  while value != 1 {
    #|    value = if value % 2 == 0 { value / 2 } else { 3 * value + 1 }
    #|    steps += 1
    #|  }
    #|  steps
    #|}
    #|
    #|///|
    #|/// Only a struct field that is assigned is marked `mut`; a method assigns it
    #|/// through `self`, which itself is never `mut`.
    #|struct Counter {
    #|  mut count : Int32
    #|  step : Int32
    #|}
    #|
    #|///|
    #|fn Counter::bump(self : Counter) -> Unit {
    #|  self.count += self.step
    #|}
    #|
    #|///|
    #|fn main raise {
    #|  // A mutable local is `let mut`; there is no `var`. Mutable maps and arrays
    #|  // are updated in place without `mut`.
    #|  let mut total = 0
    #|  for n in [1, 2, 3] {
    #|    total += n
    #|  }
    #|  assert_eq(total, 6)
    #|  assert_eq(total.clamp(min=0, max=5), 5)
    #|  assert_eq(collatz_steps(6), 8)
    #|  let counter = { count: 0, step: 2 }
    #|  counter.bump()
    #|  assert_eq(counter.count, 2)
    #|  // Negation is the `!` prefix; `Bool` has no `not` method.
    #|  let pending = false
    #|  assert_true(!pending)
    #|  // A bare `{}` is ambiguous (empty map, block, struct, or JSON object) and
    #|  // an error under deny-warn: an empty map is `Map([])`, and the no-op
    #|  // expression is `()`.
    #|  let empty : Map[String, Int32] = Map([])
    #|  assert_eq(empty.length(), 0)
    #|  if pending {
    #|    ()
    #|  }
    #|  // Match arms are separated by newlines (or `;`), never by `|`, which joins
    #|  // alternatives inside one pattern.
    #|  let label = match total {
    #|    0 => "none"
    #|    1 | 2 => "few"
    #|    _ => "many"
    #|  }
    #|  assert_eq(label, "many")
    #|  // Lambdas are arrows: `x => expr` or `(a, b) => { ... }`, not `fn(x) { ... }`.
    #|  // A lambda that must be async is spelled `async fn(x) { ... }`.
    #|  let words = ["moon", "bit", "shell"]
    #|  assert_eq(words.map(w => w.length()), [4, 3, 5])
    #|  let pairs = words.map(w => (w, w.length()))
    #|  pairs.sort_by((a, b) => a.1.compare(b.1))
    #|  assert_eq(pairs[0], ("bit", 3))
    #|  // Keywords (`test`, `type`, `method`, `ref`, ...) cannot name a binding:
    #|  // `let test = ...` is a parse error, so write `test_count`.
    #|  let test_count = pairs.length()
    #|  assert_eq(test_count, 3)
    #|  println("syntax: ok")
    #|}
    #|```
    #|
    #|## Checked Error Handling
    #|
    #|Errors are a checked effect on the function, not a value it returns: a parser
    #|returns `Json` on success and its failures travel in `raise`. Call raising
    #|functions directly from functions marked `raise` and handle errors only at a
    #|real boundary, such as a CLI path that needs its own stderr text. Use
    #|`fail("message")` for a one-off internal failure and a small `suberror` for
    #|user-facing errors; never encode failure as `null`, `()`, or another
    #|success sentinel. `async fn` raises by default; mark an async helper `noraise`
    #|when it must not. In tests, call raising functions directly and let a raise
    #|fail the test. The verified example, compiled and run by CI:
    #|
    #|```mbtx
    #|///|
    #|/// Checked errors are an effect on a function, not a value it returns: a
    #|/// parser returns its result directly and failures travel in `raise`. This
    #|/// file is verified by CI (type-checked under deny-warn and run), so what it
    #|/// shows is what the compiler accepts today.
    #|import {
    #|  "moonbitlang/core/string",
    #|}
    #|
    #|///|
    #|/// A custom error is a `suberror`, never `type Error` or a trait. Match its
    #|/// constructors when callers need to tell cases apart.
    #|suberror ParseError {
    #|  InvalidInput(String)
    #|} derive(Debug)
    #|
    #|///|
    #|/// `raise ParseError` names the exact error this function may let escape.
    #|/// A helper that raises a broader error is caught and translated, as the
    #|/// `from_str` call shows. The success path stays direct: an `Int32`, not a
    #|/// wrapper around success and failure.
    #|fn parse_count(text : String) -> Int32 raise ParseError {
    #|  let trimmed = text.trim()
    #|  if trimmed.is_empty() {
    #|    raise InvalidInput("empty input")
    #|  }
    #|  let n : Int32 = @string.from_str(trimmed) catch {
    #|    _ => raise InvalidInput("not an integer: \{trimmed}")
    #|  }
    #|  n
    #|}
    #|
    #|///|
    #|/// Plain `raise` is enough for an ordinary failing helper, and `fail` raises
    #|/// a one-off failure with a message.
    #|fn require_positive(n : Int32) -> Int32 raise {
    #|  if n <= 0 {
    #|    fail("expected a positive count, got \{n}")
    #|  }
    #|  n
    #|}
    #|
    #|///|
    #|/// A function marked `raise` calls raising helpers directly; nothing is
    #|/// wrapped or unwrapped between the layers.
    #|fn count_from(text : String) -> Int32 raise {
    #|  require_positive(parse_count(text))
    #|}
    #|
    #|///|
    #|/// Handle errors only at a real boundary, such as a CLI path that needs its
    #|/// own message. Constructor patterns pick the cases you care about; the
    #|/// last arm covers the rest. Never encode failure as a success sentinel
    #|/// (`null`, `()`, `-1`): return early with the message instead.
    #|fn describe(text : String) -> String {
    #|  let n = count_from(text) catch {
    #|    InvalidInput(reason) => return "invalid: \{reason}"
    #|    other => return "rejected: \{other}"
    #|  }
    #|  "count = \{n}"
    #|}
    #|
    #|///|
    #|/// A sync `main` that calls raising functions is `fn main raise`; an async
    #|/// `main` raises by default, and `noraise` marks an async helper that must not.
    #|fn main raise {
    #|  assert_eq(parse_count(" 42 "), 42)
    #|  assert_eq(describe("7"), "count = 7")
    #|  assert_eq(describe(""), "invalid: empty input")
    #|  assert_eq(describe("x"), "invalid: not an integer: x")
    #|  assert_true(describe("-3").has_prefix("rejected: "))
    #|  println("checked errors: ok")
    #|}
    #|```
    #|
    #|## Strings, Maps, JSON, And Tests
    #|
    #|- String interpolation is `\{expr}` and works for any `Show` value; `\(expr)`
    #|  is not MoonBit. Build strings with interpolation rather than `+`, which
    #|  needs a `String` on both sides. Multi-line raw strings use `#|` lines and
    #|  interpolated ones `$|` lines.
    #|- `s[i]` is a UTF-16 code unit, not a `Char`; literals adapt to the expected
    #|  type, so never write casts such as `UInt16(92)`. To compare a `Char`
    #|  variable, write `s.get_char(i) is Some(c) && c == ch`, not `is Some(ch)`:
    #|  a lowercase name in a pattern binds a new variable.
    #|- `String` compares in SHORTLEX order (length first, then code units), so the
    #|  default sort is deterministic but not dictionary order; sort with an
    #|  explicit comparator when a reader expects dictionary order. `sort` and
    #|  `sort_by` work in place and return `Unit`; `rev` returns a new value; for a
    #|  sorted directory listing pass `@fs.readdir(dir, sort=true)`.
    #|- Slices are zero-copy `StringView`s whose offsets clamp instead of
    #|  panicking; `map[key]` panics when the key is missing, `map.get(key)`
    #|  returns `T?`. Parse with `@string.from_str` and an annotation on the
    #|  binding, `let n : Int32 = @string.from_str(text)` (import
    #|  `moonbitlang/core/string`); it raises on bad input. Do not write
    #|  `@string.from_str[:Int32](text)` or `@string.from_str[Int32](text)`.
    #|
    #|The verified example, compiled and run by CI:
    #|
    #|```mbtx
    #|///|
    #|/// Strings, views, collections, and JSON values as the compiler accepts them
    #|/// today: this file is verified by CI (type-checked under deny-warn and run).
    #|import {
    #|  "moonbitlang/core/string",
    #|}
    #|
    #|///|
    #|fn main raise {
    #|  // Interpolation is `\{expr}` and takes any `Show` value; `"n: " + n` needs
    #|  // a `String` on both sides, so with an `Int32` it is a type error.
    #|  let n = 3
    #|  assert_eq("n: \{n}", "n: 3")
    #|  // Multi-line literals: `#|` lines keep text literally, `$|` lines interpolate.
    #|  let raw =
    #|    #|first line
    #|    #|second line
    #|  let rendered =
    #|    $|count: \{n}
    #|    $|lines: \{raw.split("\n").count()}
    #|  assert_eq(raw, "first line\nsecond line")
    #|  assert_eq(rendered, "count: 3\nlines: 2")
    #|  // `re"..."` is a regex literal; classes are POSIX-style, `\d` is deprecated.
    #|  assert_true(rendered =~ re"^count: [[:digit:]]+")
    #|  // `s[i]` is a UTF-16 code unit, not a `Char`; a char literal adapts to it.
    #|  let s = "name=value"
    #|  assert_true(s[4] == '=')
    #|  // `s[a:b]` is a zero-copy `StringView` and offsets clamp, so truncation
    #|  // needs no length guard. Pass views to string APIs; `.to_owned()` only
    #|  // where an owned `String` is stored or required.
    #|  let key : StringView = s[:4]
    #|  guard s.split_once("=") is Some((prefix, value)) else { fail("missing =") }
    #|  assert_eq(prefix, key)
    #|  assert_eq(value.to_owned(), "value")
    #|  assert_eq(s[:400].to_owned(), s)
    #|  // `split` yields an iterator: loop over it, or `collect()` for an array.
    #|  assert_eq(s.split("=").collect(), ["name", "value"])
    #|  // Typed parsing: `from_str` picks the type from the annotated binding and
    #|  // raises on bad input.
    #|  let parsed : Int32 = @string.from_str("42")
    #|  assert_eq(parsed, 42)
    #|  // `String` orders SHORTLEX (length first, then code units), so the default
    #|  // sort is deterministic but not dictionary order.
    #|  let names = ["port", "debug"]
    #|  names.sort() // in place, returns Unit: `names.sort()[0]` does not compile
    #|  assert_eq(names, ["port", "debug"])
    #|  // The cascade `..sort()` runs the call and yields the array; `rev()`
    #|  // returns a new array (`rev_in_place` mutates; there is no `reverse`).
    #|  assert_eq([3, 1, 2]..sort(), [1, 2, 3])
    #|  assert_eq([1, 2].rev(), [2, 1])
    #|  // `m[k]` panics on a missing key; `m.get(k)` returns `T?`.
    #|  let counts = { "a": 1 }
    #|  assert_eq(counts.get("b"), None)
    #|  assert_eq(counts["a"], 1)
    #|  // JSON literals are `Json`; read them with patterns, where numbers are
    #|  // `Number(d, ..)` doubles, and print them with `stringify()`.
    #|  let json : Json = { "n": 1, "tags": ["x"] }
    #|  guard json is { "n": Number(one, ..), "tags": [String(tag), ..], .. } else {
    #|    fail("unexpected shape")
    #|  }
    #|  assert_eq(one.to_int(), 1)
    #|  assert_eq(tag, "x")
    #|  assert_eq(json.stringify(), "{\"n\":1,\"tags\":[\"x\"]}")
    #|  println("strings and views: ok")
    #|}
    #|```
    #|
    #|- Build JSON values with the `Json(value)` constructor — it accepts any value
    #|  whose type implements `ToJson`. Use `null` for a JSON null and
    #|  `Json::empty_object()` for an empty object. Do not create JSON with
    #|  `Json::Object(...)`, `Json::String(...)`, or `Json::True`; use variants
    #|  mainly for pattern matching.
    #|- For integer JSON numbers, use `Json::number(n.to_double(), repr=text.to_owned())`
    #|  when you need output to preserve integer spelling.
    #|- For JSON CLI stdout and tests, use `json.stringify()` or inspect
    #|  `json.stringify()`; do not rely on `println(json)` or Debug/Show snapshots.
    #|- In black-box tests for a library returning `Json`, match `Json::Object(...)`,
    #|  not `@library.Json::Object(...)`.
    #|
  )
}
