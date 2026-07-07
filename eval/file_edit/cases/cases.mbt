///|
/// One file-editing scenario: the `instructions` given to the agent, the
/// `initial` workspace to stage, the `expected` workspace afterwards, the
/// `unchanged_files` that must survive byte-for-byte, and extra `validation`
/// marker strings the agent must produce. `id` names the case in reports.
pub struct EvalCase {
  id : String
  instructions : String
  initial : @vfs.FileSystem
  expected : @vfs.FileSystem
  unchanged_files : Array[String]
  validation : Array[String]
}

///|
/// The fixed case suite, ordered: exact replace, ambiguous replace,
/// multiline replace, file creation, and a compile fix — one case per
/// editing skill the `edit`/`write` tools must get right.
pub fn eval_cases() -> Array[EvalCase] {
  [
    exact_replace_case(),
    ambiguous_replace_case(),
    multiline_replace_case(),
    create_file_case(),
    compile_fix_case(),
  ]
}

///|
/// The case trial `index` runs, cycling through `eval_cases()` so any trial
/// count covers the suite evenly.
pub fn case_for_trial(index : Int) -> EvalCase {
  let cases = eval_cases()
  cases[index % cases.length()]
}

///|
/// Render the full task prompt for a trial running in `workspace`: the
/// shared editing rules (absolute paths, no shell-based file mutation,
/// preserve unrelated files) followed by this case's instructions.
pub fn EvalCase::task(self : EvalCase, workspace : String) -> String {
  (
    $|You are running a file-editing eval.
    $|
    $|Workspace: \{workspace}
    $|
    $|Rules:
    $|- Use read/edit/write for file changes.
    $|- Every file path passed to read/edit/write must be an absolute path under the Workspace.
    $|- Do not use shell, sed, perl, python, or redirection to modify files.
    $|- Preserve unrelated files exactly.
    $|- Re-read if an exact edit is ambiguous or stale.
    $|- Finish with the exact marker: file-edit-eval:\{self.id}
    $|
    $|Task:
    $|\{self.instructions}
  )
}

///|
fn exact_replace_case() -> EvalCase {
  {
    id: "exact_replace",
    instructions: "In src/note.txt, replace the unique word `beta` with `delta`. Leave every other byte unchanged.",
    initial: FileSystem({
      "src/note.txt": "alpha\nbeta\ngamma\n",
      "src/keep.txt": "do not touch\n",
    }),
    expected: FileSystem({ "src/note.txt": "alpha\ndelta\ngamma\n" }),
    unchanged_files: ["src/keep.txt"],
    validation: [],
  }
}

///|
fn ambiguous_replace_case() -> EvalCase {
  {
    id: "ambiguous_replace",
    instructions: (
      #|In src/status.txt, change only the user-facing status line under `[user]`
      #|from `status = "todo"` to `status = "done"`. Leave the `[admin]`
      #|section unchanged.
    ),
    initial: FileSystem({
      "src/status.txt": (
        #|[user]
        #|name = "Ada"
        #|status = "todo"
        #|
        #|[admin]
        #|name = "Grace"
        #|status = "todo"
        #|
      ),
      "src/keep.txt": "unchanged\n",
    }),
    expected: FileSystem({
      "src/status.txt": (
        #|[user]
        #|name = "Ada"
        #|status = "done"
        #|
        #|[admin]
        #|name = "Grace"
        #|status = "todo"
        #|
      ),
    }),
    unchanged_files: ["src/keep.txt"],
    validation: [],
  }
}

///|
fn multiline_replace_case() -> EvalCase {
  {
    id: "multiline_replace",
    instructions: (
      #|In src/render.mbt, update `render_label` so it returns
      #|`"label: " + name.trim().to_owned()`. Preserve the helper function and
      #|the trailing newline exactly.
    ),
    initial: FileSystem({
      "src/render.mbt": (
        #|///|
        #|pub fn render_label(name : String) -> String {
        #|  "label: " + name
        #|}
        #|
        #|///|
        #|pub fn helper() -> String {
        #|  "helper"
        #|}
        #|
      ),
      "README.md": "render fixture\n",
    }),
    expected: FileSystem({
      "src/render.mbt": (
        #|///|
        #|pub fn render_label(name : String) -> String {
        #|  "label: " + name.trim().to_owned()
        #|}
        #|
        #|///|
        #|pub fn helper() -> String {
        #|  "helper"
        #|}
        #|
      ),
    }),
    unchanged_files: ["README.md"],
    validation: [],
  }
}

///|
fn create_file_case() -> EvalCase {
  {
    id: "create_file",
    instructions: (
      #|Create docs/summary.txt with exactly:
      #|
      #|OpenSeek file edit eval
      #|status: ready
      #|
      #|Do not change README.md.
    ),
    initial: FileSystem({ "README.md": "existing docs\n", "docs/.keep": "" }),
    expected: FileSystem({
      "docs/summary.txt": "OpenSeek file edit eval\nstatus: ready\n",
    }),
    unchanged_files: ["README.md", "docs/.keep"],
    validation: [],
  }
}

///|
fn compile_fix_case() -> EvalCase {
  {
    id: "compile_fix",
    instructions: (
      #|This MoonBit workspace has one type error in lib.mbt. Fix the function
      #|so `moon check` passes. Do not change moon.mod or moon.pkg.
    ),
    initial: FileSystem({
      "moon.mod": (
        #|name = "openseek/file_edit_fixture"
        #|
        #|version = "0.1.0"
        #|
        #|preferred_target = "native"
        #|
      ),
      "moon.pkg": "warnings = \"+unnecessary_annotation\"\n",
      "lib.mbt": (
        #|///|
        #|pub fn answer() -> Int {
        #|  "forty two"
        #|}
        #|
        #|///|
        #|test "answer" {
        #|  assert_eq(answer(), 42)
        #|}
        #|
      ),
    }),
    expected: FileSystem({
      "lib.mbt": (
        #|///|
        #|pub fn answer() -> Int {
        #|  42
        #|}
        #|
        #|///|
        #|test "answer" {
        #|  assert_eq(answer(), 42)
        #|}
        #|
      ),
    }),
    unchanged_files: ["moon.mod", "moon.pkg"],
    validation: ["moon", "check"],
  }
}
