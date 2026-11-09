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
