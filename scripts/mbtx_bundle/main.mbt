///|
/// Usage: mbtx_bundle OUTPUT INPUT...
///
/// Embeds each INPUT script into OUTPUT as one arm of `bundled_workflow`,
/// keyed by its basename — the name after `@builtin/`. The files on disk stay
/// the editable source; the generated copy is what the binary runs.
async fn main {
  guard @env.args() is [_, output, .. inputs] && !inputs.is_empty() else {
    fail("usage: mbtx_bundle OUTPUT INPUT...")
  }
  let scripts : Array[(String, String)] = []
  for input in inputs {
    let name = @path.Path(input).basename().to_owned()
    guard scripts.iter().all(script => script.0 != name) else {
      fail("mbtx_bundle: duplicate script name \{name}")
    }
    scripts.push((name, @fs.read_file(input).text()))
  }
  let source = generated_source(scripts)
  let current = @fs.read_file(output).text() catch { _ => "" }
  if current == source {
    return
  }
  let tmp = "\{output}.tmp"
  @fs.write_file(tmp, source, create_mode=CreateOrTruncate)
  @fs.rename(tmp, output, replace=true)
}

///|
fn generated_source(scripts : Array[(String, String)]) -> String {
  let out = StringBuilder()
  out.write_string(
    (
      $|// Generated from share/workflow/*.mbtx by moon dev_build. DO NOT EDIT.
      $|
      $|///|
      $|/// The source of the bundled workflow `@builtin/<name>`, or `None`.
      $|fn bundled_workflow(name : StringView) -> String? {
      $|  match name {
      $|
    ),
  )
  for script in scripts {
    let (name, text) = script
    out.write_string("    \"\{name}\" =>\n      Some(\n        (\n")
    for line in text.replace_all(old="\r\n", new="\n").split("\n") {
      out.write_string("          #|\{line}\n")
    }
    out.write_string("        ),\n      )\n")
  }
  out.write_string("    _ => None\n  }\n}\n")
  out.to_string()
}

///|
test "generated source embeds each script under its name" {
  inspect(
    generated_source([("a.mbtx", "fn main {\n}\n")]),
    content=(
      #|// Generated from share/workflow/*.mbtx by moon dev_build. DO NOT EDIT.
      #|
      #|///|
      #|/// The source of the bundled workflow `@builtin/<name>`, or `None`.
      #|fn bundled_workflow(name : StringView) -> String? {
      #|  match name {
      #|    "a.mbtx" =>
      #|      Some(
      #|        (
      #|          #|fn main {
      #|          #|}
      #|          #|
      #|        ),
      #|      )
      #|    _ => None
      #|  }
      #|}
      #|
    ),
  )
}
