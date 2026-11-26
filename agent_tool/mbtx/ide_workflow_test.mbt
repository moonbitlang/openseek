///|
async test "@builtin/ide.mbtx runs moon ide doc and outline inside the sandbox" {
  @vfs.with_tmpdir(ws => {
    @vfs.FileSystem({
      "moon.mod": "name = \"example/ide_test\"\n",
      "moon.pkg": "",
      "lib.mbt": "///|\npub fn answer() -> Int {\n  42\n}\n",
    }).write_to(ws)
    let doc_out = run_in(ws, {
      "filename": "@builtin/ide.mbtx",
      "args": ["doc", "String::length"],
    })
    assert_false(doc_out.is_error, msg=doc_out.content)
    assert_true(doc_out.content.contains("length"), msg=doc_out.content)
    let outline_out = run_in(ws, {
      "filename": "@builtin/ide.mbtx",
      "args": ["outline", "."],
    })
    assert_false(outline_out.is_error, msg=outline_out.content)
    assert_true(outline_out.content.contains("answer"), msg=outline_out.content)
  })
}
