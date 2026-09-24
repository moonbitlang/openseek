///|
/// Run `f` in a tmpdir, with best-effort clean up.
///
/// We duplicate the `with_tmpdir` implementation here because we need the
/// dev rules to be ran before type-checking the main openseek repo, and
/// we cannot import the testkit/filesystem package here.
async fn[T] with_tmpdir(f : async (String) -> T) -> T {
  let dir = @fs.tmpdir(prefix="")
  async fn rmdir() {
    @fs.rmdir(dir, recursive=true) catch {
      _ => ()
    }
  }
  defer rmdir()
  f(dir)
}

///|
async test "CRLF markdown still expands example links" {
  with_tmpdir(dir => {
    @fs.write_file("\{dir}/ex.mbtx", "fn main {\n  ()\n}\n")
    inspect(
      expand_example_links("a\r\n[x](ex.mbtx)\r\nb\r\n", dir),
      content=(
        #|a
        #|```mbtx
        #|fn main {
        #|  ()
        #|}
        #|```
        #|b
        #|
      ),
    )
  })
}

///|
async test "an expanded example survives comment stripping and a missing final newline" {
  with_tmpdir(dir => {
    @fs.write_file(
      "\{dir}/ex.mbtx",
      "fn main {\n  println(\"<!-- kept: code -->\")\n}",
    )
    let markdown = "a<!-- dropped -->\n[x](ex.mbtx)\n"
    let source = generated_source(
      base="p.md",
      function_name="p",
      markdown=expand_example_links(markdown, dir),
    )
    inspect(
      source,
      content=(
        #|// Generated from p.md by moon dev_build. DO NOT EDIT.
        #|
        #|///|
        #|fn p() -> String {
        #|  (
        #|    #|a
        #|    #|```mbtx
        #|    #|fn main {
        #|    #|  println("<!-- kept: code -->")
        #|    #|}
        #|    #|```
        #|    #|
        #|  )
        #|}
        #|
      ),
    )
  })
}

///|
async test "output match detects unchanged generated file" {
  with_tmpdir(dir => {
    let path = "\{dir}/output-match.mbt"
    // The fresh directory guarantees the file is absent to start with.
    assert_false(output_matches(path, "same"))
    @fs.write_file(path, "same", create_mode=CreateOrTruncate)
    assert_true(output_matches(path, "same"))
    assert_false(output_matches(path, "different"))
  })
}

///|
async test "resource layout is sorted, directory-only, skips build output and tutorials, and refreshed on changes" {
  with_tmpdir(root => {
    @fs.mkdir("\{root}/workflow")
    @fs.mkdir("\{root}/aardvark")
    @fs.mkdir("\{root}/z")
    @fs.mkdir("\{root}/doc/moonbit/language", recursive=true)
    @fs.mkdir("\{root}/.hidden")
    @fs.mkdir("\{root}/workflow/_build/wasm", recursive=true)
    @fs.mkdir("\{root}/doc/moonbit/gmachine-tutorial")
    @fs.write_file("\{root}/doc/moonbit/index.md", "docs")
    let template = "before\n{{BUNDLED_RESOURCES_LAYOUT}}\nafter"
    inspect(
      expand_resource_layout(template, root),
      content=(
        #|before
        #|.
        #|├── aardvark
        #|├── doc
        #|│   └── moonbit
        #|│       └── language
        #|├── workflow
        #|└── z
        #|after
      ),
    )
    // A tutorial directory is listed, but the two tutorials that only walk a
    // human through learning the language are not: `tutorial` stays a leaf.
    @fs.mkdir("\{root}/doc/moonbit/tutorial/for-go-programmers", recursive=true)
    let with_tutorial = expand_resource_layout(template, root)
    assert_true(with_tutorial.contains("└── tutorial"))
    assert_false(with_tutorial.contains("for-go-programmers"))
    @fs.rmdir("\{root}/doc/moonbit/tutorial", recursive=true)
    assert_false(expand_resource_layout(template, root).contains("tutorial"))
    // Prompts without the placeholder do not depend on a resources directory.
    assert_eq(
      expand_resource_layout("unchanged", "\{root}/missing"),
      "unchanged",
    )
  })
}

///|
async test "whole-line example links expand into fenced blocks" {
  with_tmpdir(dir => {
    @fs.write_file("\{dir}/ex.mbtx", "fn main {\n  ()\n}\n")
    let markdown = "a\n[x](ex.mbtx)\nsee [y](ex.mbtx) inline\n"
    inspect(
      expand_example_links(markdown, dir),
      content=(
        #|a
        #|```mbtx
        #|fn main {
        #|  ()
        #|}
        #|```
        #|see [y](ex.mbtx) inline
        #|
      ),
    )
  })
}
