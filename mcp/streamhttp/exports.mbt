// Deliberate exports with no in-repo production consumer (see
// shrink_package.md): test seams, round-trip/protocol surface, and
// future-proof API kept on purpose. Each entry documents its reason.

///|
/// What discovery or legacy initialization reported.
pub fn HttpConnection::init(self : HttpConnection) -> @mcp.InitializeResult {
  self.init
}
