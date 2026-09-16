///|
/// The bundled fix-deprecations script against a real module: the wasm script
/// runs `moon check` itself, computes one guarded `edit` per deprecation
/// site through the published SDK, and leaves what it cannot do to a human.
/// Two sites share a line (fixed right to left), one deprecation names no
/// replacement, and the guards never fire because every fix is clean.
async test "fix-deprecations fixes deprecation sites through guarded edits" {
  @vfs.with_tmpdir(ws => {
    @async.with_task_group(group => {
      let lib =
        #|///|
        #|#deprecated("use `len` instead")
        #|pub fn length(xs : Array[Int]) -> Int {
        #|  xs.length()
        #|}
        #|
        #|///|
        #|pub fn len(xs : Array[Int]) -> Int {
        #|  xs.length()
        #|}
        #|
        #|///|
        #|#deprecated("no longer supported")
        #|pub fn old() -> Int {
        #|  0
        #|}
        #|
        #|///|
        #|pub fn total() -> Int {
        #|  length([1, 2, 3]) + length([4])
        #|}
        #|
        #|///|
        #|pub fn other() -> Int {
        #|  old() + length([])
        #|}
        #|
      @vfs.FileSystem::from_pairs([
        ("moon.mod", "name = \"tmp/fixdep\"\n"),
        ("lib/moon.pkg", ""),
        ("lib/lib.mbt", lib),
      ]).write_to(ws)
      let state = @agent_tool.FileStateMap()
      let definitions = [
        state.serialize(@edit.definition(workspace_root=ws, file_state=state)),
        state.serialize(
          @multi_edit.definition(workspace_root=ws, file_state=state),
        ),
      ]
      let service = @ptc.Service::start(group, Tools(definitions))
      let tool = @mbtx.definition(
        workspace_root=ws,
        file_state=state,
        program_service=service,
        foreground_timeout_ms=180000,
      )
      let source = @fs.read_file(
        @fs.realpath("share/workflow/fix-deprecations.mbtx"),
      ).text()
      let output = @async.with_timeout(240000, () => {
        dispatch(tool, {
          "description": "fix deprecations",
          "ptc": true,
          "source": source,
          "cwd": ws,
        })
      })
      assert_false(output.is_error, msg=output.content)
      assert_true(
        output.content.contains(
          "3 deprecation site(s) with a bare replacement, 1 left to a human",
        ),
        msg=output.content,
      )
      assert_true(output.content.contains("fixed: 3"), msg=output.content)
      assert_true(
        output.content.contains("no bare replacement named"),
        msg=output.content,
      )
      assert_true(
        output.content.contains("after: 0 error(s), 1 warning(s) (was 0/4)"),
        msg=output.content,
      )
      let fixed = @fs.read_file("\{ws}/lib/lib.mbt").text()
      assert_true(fixed.contains("  len([1, 2, 3]) + len([4])\n"), msg=fixed)
      assert_true(fixed.contains("  old() + len([])\n"), msg=fixed)
      assert_true(fixed.contains("#deprecated(\"use `len` instead\")"))
      // A dry run plans the same three edits and writes nothing.
      @fs.write_file("\{ws}/lib/lib.mbt", lib, create_mode=CreateOrTruncate)
      let planned = @async.with_timeout(120000, () => {
        dispatch(tool, {
          "description": "plan deprecation fixes",
          "ptc": true,
          "source": source,
          "cwd": ws,
          "args": ["--dry-run"],
        })
      })
      assert_false(planned.is_error, msg=planned.content)
      assert_true(
        planned.content.contains("dry run: 3 edit(s) planned, none written"),
        msg=planned.content,
      )
      assert_eq(@fs.read_file("\{ws}/lib/lib.mbt").text(), lib)
      // The limit applies to a dry run too.
      let limited = @async.with_timeout(120000, () => {
        dispatch(tool, {
          "description": "plan one deprecation fix",
          "ptc": true,
          "source": source,
          "cwd": ws,
          "args": ["--dry-run", "--limit", "1"],
        })
      })
      assert_false(limited.is_error, msg=limited.content)
      assert_true(
        limited.content.contains("dry run: 1 edit(s) planned, none written"),
        msg=limited.content,
      )
      assert_true(limited.content.contains("limit reached: 1 attempted"))
    })
  })
}

///|
/// Deprecations used across packages: a qualified call `@a.length(...)`, a
/// method `p.size()` deprecated in favor of `p.count()`, and a message in the
/// core library's capitalized spelling (`Use \`total\` instead`). Whatever
/// moon reports as the span, the script must swap only the deprecated name.
async test "fix-deprecations handles qualified calls and methods across packages" {
  @vfs.with_tmpdir(ws => {
    @async.with_task_group(group => {
      let a =
        #|///|
        #|#deprecated("use `len` instead")
        #|pub fn length(xs : Array[Int]) -> Int {
        #|  xs.length()
        #|}
        #|
        #|///|
        #|pub fn len(xs : Array[Int]) -> Int {
        #|  xs.length()
        #|}
        #|
        #|///|
        #|pub struct Pile {
        #|  items : Array[Int]
        #|}
        #|
        #|///|
        #|#deprecated("use `count` instead")
        #|pub fn Pile::size(self : Pile) -> Int {
        #|  self.items.length()
        #|}
        #|
        #|///|
        #|pub fn Pile::count(self : Pile) -> Int {
        #|  self.items.length()
        #|}
        #|
        #|///|
        #|#deprecated("Use `total` instead")
        #|pub fn sum(xs : Array[Int]) -> Int {
        #|  xs.fold(init=0, (a, b) => a + b)
        #|}
        #|
        #|///|
        #|pub fn total(xs : Array[Int]) -> Int {
        #|  xs.fold(init=0, (a, b) => a + b)
        #|}
        #|
      let b =
        #|///|
        #|pub fn use_all(p : @a.Pile) -> Int {
        #|  @a.length([1, 2]) + p.size() + @a.length([]) + @a.sum([3])
        #|}
        #|
        #|///|
        #|pub fn twice(p : @a.Pile) -> Int {
        #|  p.size() +
        #|  p.size()
        #|}
        #|
      @vfs.FileSystem::from_pairs([
        ("moon.mod", "name = \"tmp/crossdep\"\n"),
        ("a/moon.pkg", ""),
        ("a/a.mbt", a),
        ("b/moon.pkg", "import {\n  \"tmp/crossdep/a\",\n}\n"),
        ("b/b.mbt", b),
      ]).write_to(ws)
      let state = @agent_tool.FileStateMap()
      let definitions = [
        state.serialize(@edit.definition(workspace_root=ws, file_state=state)),
      ]
      let service = @ptc.Service::start(group, Tools(definitions))
      let tool = @mbtx.definition(
        workspace_root=ws,
        file_state=state,
        program_service=service,
        foreground_timeout_ms=240000,
      )
      let source = @fs.read_file(
        @fs.realpath("share/workflow/fix-deprecations.mbtx"),
      ).text()
      let output = @async.with_timeout(300000, () => {
        dispatch(tool, {
          "description": "fix deprecations across packages",
          "ptc": true,
          "source": source,
          "cwd": ws,
        })
      })
      assert_false(output.is_error, msg=output.content)
      assert_true(output.content.contains("fixed: 6"), msg=output.content)
      // The one warning left is unrelated (the struct is never constructed).
      assert_true(
        output.content.contains("after: 0 error(s), 1 warning(s) (was 0/7)"),
        msg=output.content,
      )
      let fixed = @fs.read_file("\{ws}/b/b.mbt").text()
      assert_true(
        fixed.contains(
          "  @a.len([1, 2]) + p.count() + @a.len([]) + @a.total([3])\n",
        ),
        msg=fixed,
      )
      assert_true(fixed.contains("  p.count() +\n  p.count()\n"), msg=fixed)
    })
  })
}
