///|
/// Browser-test fixture: control the real preview service over stdio, without
/// needing a native window. EOF cancels its app-equivalent task group.
async fn main {
  let server = @static_preview.Server()
  @async.with_task_group(group => {
    server.start(group)
    @stdio.stdout.write("{\"ready\":true}\n")
    for ;; {
      guard @stdio.stdin.read_until("\n") is Some(line) else { break }
      let request = @json.parse(line)
      let reply : Json = match request {
        { "close": Number(id, ..), .. } => {
          server.close(id.to_int())
          { "closed": true }
        }
        { "id": Number(id, ..), "path": String(path), "root": String(root), .. } =>
          try {
            let url = server.open(id.to_int(), path, root~)
            { "url": url }
          } catch {
            error => { "error": error.to_string() }
          }
        _ => { "error": "Invalid fixture request" }
      }
      @stdio.stdout.write(reply.stringify() + "\n")
    }
    group.return_immediately(())
  })
}
