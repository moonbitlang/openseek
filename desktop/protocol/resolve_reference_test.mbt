///|
test "resolved references preserve optional positions and reject invalid wire targets" {
  let replies : Array[@protocol.ResolveReferenceReply] = [
    ReferenceText(path="/remote/中文.txt", line=None, column=None),
    ReferenceText(path="/remote/source.mbt", line=Some(12), column=Some(4)),
    ReferenceDirectory(path="src"),
    ReferenceDirectory(path=""),
    ReferenceBinary(path="/remote/image.png"),
    ReferenceRefused(message="missing"),
  ]
  for reply in replies {
    let decoded : @protocol.ResolveReferenceReply = @json.from_json(
      reply.to_json(),
    )
    assert_eq(decoded, reply)
  }
  let malformed : Array[Json] = [
    { "kind": "text", "path": "relative" },
    { "kind": "text", "path": "/remote", "line": 0 },
    { "kind": "text", "path": "/remote", "column": 3 },
    { "kind": "directory", "path": "../outside" },
    { "kind": "directory", "path": "/absolute" },
    { "kind": "other", "path": "/remote" },
    { "kind": "refused" },
  ]
  for value in malformed {
    let rejected = try {
      let _ : @protocol.ResolveReferenceReply = @json.from_json(value)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
