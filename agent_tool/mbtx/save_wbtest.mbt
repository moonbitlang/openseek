///|
#cfg(not(platform="windows"))
async test "builtin namespace refuses symlinks outside its root" {
  @vfs.with_tmpdir(root => {
    @fs.mkdir("\{root}/workflow")
    @fs.write_file("\{root}/outside.mbtx", "fn main {}")
    @fs.symlink(target="\{root}/outside.mbtx", "\{root}/workflow/escape.mbtx")
    try check_builtin_containment("\{root}/workflow/escape.mbtx", root) catch {
      error => assert_true(error.to_string().contains("inside @builtin/"))
    } noraise {
      _ => fail("namespace escape accepted")
    }
  })
}

///|
async test "saved script reads wait for a shared edit and rollback to settle" {
  @vfs.with_tmpdir(ws => {
    @async.with_timeout(3000, () => {
      @async.with_task_group(group => {
        let state = @agent_tool.FileStateMap()
        let path = "\{ws}/saved.mbtx"
        let entered : @async.Queue[Unit] = Queue(kind=Unbounded)
        let release : @async.Queue[Unit] = Queue(kind=Unbounded)
        let edit = group.spawn(() => {
          state.with_access(() => {
            @fs.write_file(path, "transient source")
            entered.put(())
            release.get()
            @fs.write_file(path, "settled source")
          })
        })
        entered.get()
        let read = group.spawn(() => read_script_snapshot(state, path, None))
        assert_true(@async.with_timeout_opt(50, () => read.wait()) is None)
        release.put(())
        edit.wait()
        assert_eq(read.wait(), "settled source")
      })
    })
  })
}
