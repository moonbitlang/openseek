///|
async test "@builtin/ls.mbtx lists directories and globs inside the sandbox" {
  // Runs the embedded copy through the tool, so the sandbox has to allow the
  // directory reads and stats a listing needs.
  @vfs.with_tmpdir(ws => {
    @vfs.FileSystem({
      "src/a.mbt": "one\ntwo\n",
      "src/deep/b.mbt": "x",
      "src/notes.txt": "",
      "_build/c.mbt": "",
    }).write_to(ws)
    let out = run_in(ws, {
      "filename": "@builtin/ls.mbtx",
      "args": ["src", "**/*.mbt"],
    })
    assert_false(out.is_error, msg=out.content)
    assert_eq(
      out.content,
      (
        #|2 src/a.mbt
        #|- src/deep/
        #|0 src/notes.txt
        #|2 src/a.mbt
        #|1 src/deep/b.mbt
        #|<system>skipped=_build note=pass --all to list them</system>
        #|
      ),
    )
  })
}
