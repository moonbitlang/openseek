///|
test "artifact file requests retain their owning workspace session and archive identity" {
  let request : @protocol.ArtifactFilePayload = {
    session: "chat",
    workspace: "/project",
    archived: true,
    reference: "artifact://chart.html",
  }
  assert_eq(@json.from_json(request.to_json()), request)
  let reply : @protocol.ArtifactFileReply = {
    path: "/documents/output/chart.html",
    content: Some("<html></html>"),
  }
  assert_eq(@json.from_json(reply.to_json()), reply)
  let binary : @protocol.ArtifactFileReply = {
    path: "/documents/output/data.xlsx",
    content: None,
  }
  assert_eq(@json.from_json(binary.to_json()), binary)
}
