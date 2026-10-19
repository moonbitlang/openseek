// Deliberate exports with no in-repo production consumer (see
// shrink_package.md): kept for symmetry with mcp/streamhttp's
// HttpConnection::init and for callers that need the handshake result.

///|
/// What discovery or legacy initialization reported.
pub fn StdioConnection::init(self : StdioConnection) -> @mcp.InitializeResult {
  self.init
}
