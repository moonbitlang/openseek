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
        let read = group.spawn(() => read_script_snapshot(state, path))
        assert_true(@async.with_timeout_opt(50, () => read.wait()) is None)
        release.put(())
        edit.wait()
        assert_eq(read.wait(), "settled source")
      })
    })
  })
}
