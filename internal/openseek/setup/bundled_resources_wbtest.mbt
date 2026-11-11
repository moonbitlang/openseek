///|
async test "resource layout is sorted, directory-only, skips build output and tutorials, and refreshed on changes" {
  @vfs.with_tmpdir(root => {
    @fs.mkdir("\{root}/workflow")
    @fs.mkdir("\{root}/aardvark")
    @fs.mkdir("\{root}/z")
    @fs.mkdir("\{root}/doc/moonbit/language", recursive=true)
    @fs.mkdir("\{root}/.hidden")
    @fs.mkdir("\{root}/workflow/_build/wasm", recursive=true)
    @fs.mkdir("\{root}/doc/moonbit/gmachine-tutorial")
    @fs.write_text("\{root}/doc/moonbit/index.md", "docs")
    inspect(
      resource_layout(root),
      content=(
        #|.
        #|├── aardvark
        #|├── doc
        #|│   └── moonbit
        #|│       └── language
        #|├── workflow
        #|└── z
      ),
    )
    // A tutorial directory is listed, but the two tutorials that only walk a
    // human through learning the language are not: `tutorial` stays a leaf.
    @fs.mkdir("\{root}/doc/moonbit/tutorial/for-go-programmers", recursive=true)
    let with_tutorial = resource_layout(root)
    assert_true(with_tutorial.contains("└── tutorial"))
    assert_false(with_tutorial.contains("for-go-programmers"))
    @fs.rmdir("\{root}/doc/moonbit/tutorial", recursive=true)
    assert_false(resource_layout(root).contains("tutorial"))
  })
}
