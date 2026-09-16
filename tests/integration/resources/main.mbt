///|
/// A copied executable exercises the public resource and workflow APIs from an
/// unrelated cwd. The launcher supplies distinct installation and cwd fixtures.
async fn main {
  let result : Json = try {
    let resources = @bundled.directory()
    let document = if resources is Some(root) {
      Some(@fs.read_file("\{root}/doc/moonbit/index.md").text())
    } else {
      None
    }
    let tool = @mbtx.definition(workspace_root=@fs.realpath("."))
    guard tool.execute is Async(execute) else { fail("expected async mbtx") }
    guard execute({ "filename": "@builtin/probe.mbtx" }) is Respond(output) else {
      fail("expected workflow output")
    }
    {
      "resources": resources.map(path => path.to_json()).unwrap_or(Json::null()),
      "document": document.map(text => text.to_json()).unwrap_or(Json::null()),
      "workflow": output.content,
      "workflow_error": output.is_error,
    }
  } catch {
    error => { "error": error.to_string() }
  }
  println(result.stringify())
}
