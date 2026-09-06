///|
test "encodes and decodes document client packets" {
  let uri = expect_uri(
    "readonly-remote://workspace/tests/fixtures/workspace/src/main.mbt",
  )
  let packet = @remote_protocol.OpenDocument({ id: "open-1", uri, })
  let encoded = packet.to_json().stringify()
  assert_true(encoded.contains("\"type\":\"OpenDocument\""))
  assert_true(encoded.contains("\"version\":6"))
  guard expect_client_packet(encoded) is OpenDocument(request) else {
    fail("unexpected client packet")
  }
  assert_eq(request.id, "open-1")
  assert_eq(request.uri.to_string(), uri.to_string())
}

///|
test "encodes and decodes semantic client packets" {
  let uri = expect_uri("readonly-remote://workspace/src/main.mbt")
  let hover = @remote_protocol.Hover({
    id: "hover-1",
    uri,
    document_revision: "rev-4",
    offset: 17,
  })
  guard expect_client_packet(hover.to_json().stringify())
    is Hover(hover_request) else {
    fail("unexpected hover packet")
  }
  assert_eq(hover_request.id, "hover-1")
  assert_eq(hover_request.document_revision, "rev-4")
  assert_eq(hover_request.offset, 17)
  let definition = @remote_protocol.Definition({
    id: "def-1",
    uri,
    document_revision: "rev-4",
    offset: 18,
  })
  guard expect_client_packet(definition.to_json().stringify())
    is Definition(definition_request) else {
    fail("unexpected definition packet")
  }
  assert_eq(definition_request.id, "def-1")
  assert_eq(definition_request.offset, 18)
  let references = @remote_protocol.References({
    id: "refs-1",
    uri,
    document_revision: "rev-4",
    offset: 19,
  })
  guard expect_client_packet(references.to_json().stringify())
    is References(references_request) else {
    fail("unexpected references packet")
  }
  assert_eq(references_request.id, "refs-1")
  assert_eq(references_request.document_revision, "rev-4")
  assert_eq(references_request.offset, 19)
  let symbols = @remote_protocol.DocumentSymbols({
    id: "symbols-1",
    uri,
    document_revision: "rev-5",
  })
  guard expect_client_packet(symbols.to_json().stringify())
    is DocumentSymbols(symbols_request) else {
    fail("unexpected document symbols packet")
  }
  assert_eq(symbols_request.id, "symbols-1")
  assert_eq(symbols_request.document_revision, "rev-5")
}

///|
test "encodes and decodes directory resolve packets" {
  let root_uri = expect_uri("readonly-remote://workspace")
  let request = @remote_protocol.ResolveDirectory({
    id: "resolve-1",
    uri: root_uri,
  })
  let encoded = request.to_json().stringify()
  assert_true(encoded.contains("\"type\":\"ResolveDirectory\""))
  guard expect_client_packet(encoded) is ResolveDirectory(decoded) else {
    fail("unexpected resolve directory packet")
  }
  assert_eq(decoded.id, "resolve-1")
  assert_eq(decoded.uri.to_string(), "readonly-remote://workspace")
  let src_uri = expect_uri("readonly-remote://workspace/src")
  let resolved = @remote_protocol.DirectoryResolved({
    id: "resolve-1",
    stat: {
      uri: root_uri,
      name: "workspace",
      kind: Directory,
      children: Some([
        {
          uri: expect_uri("readonly-remote://workspace/moon.mod"),
          name: "moon.mod",
          kind: File,
          children: None,
        },
        { uri: src_uri, name: "src", kind: Directory, children: None, },
      ]),
    },
  })
  guard expect_server_packet(resolved.to_json().stringify())
    is DirectoryResolved(payload) else {
    fail("unexpected directory resolved packet")
  }
  assert_eq(payload.id, "resolve-1")
  assert_eq(payload.stat.uri.to_string(), "readonly-remote://workspace")
  assert_eq(payload.stat.name, "workspace")
  assert_true(payload.stat.kind == Directory)
  guard payload.stat.children is Some(children) else {
    fail("expected resolved children")
  }
  assert_eq(children.length(), 2)
  assert_eq(children[0].name, "moon.mod")
  assert_true(children[0].kind == File)
  assert_true(children[0].children is None)
  assert_eq(children[1].uri.to_string(), "readonly-remote://workspace/src")
  assert_true(children[1].kind == Directory)
  assert_true(children[1].children is None)

  // An empty resolved directory stays Some([]) across the wire; only
  // unresolved children round-trip as None.
  let empty = @remote_protocol.DirectoryResolved({
    id: "resolve-2",
    stat: { uri: src_uri, name: "src", kind: Directory, children: Some([]), },
  })
  guard expect_server_packet(empty.to_json().stringify())
    is DirectoryResolved(empty_payload) else {
    fail("unexpected empty directory packet")
  }
  guard empty_payload.stat.children is Some(empty_children) else {
    fail("expected empty children")
  }
  assert_eq(empty_children.length(), 0)
}

///|
test "encodes and decodes server document and language packets" {
  let uri = expect_uri(
    "readonly-remote://workspace/tests/fixtures/workspace/src/main.mbt",
  )
  let document = @workspace.DocumentSnapshot(
    uri, "main.mbt", "moonbit", "rev-2", "pub fn main {}\n",
  )
  let loaded = @remote_protocol.DocumentLoaded({ id: "open-1", document, })
  guard expect_server_packet(loaded.to_json().stringify())
    is DocumentLoaded(loaded_payload) else {
    fail("unexpected server packet")
  }
  assert_eq(loaded_payload.id, "open-1")
  assert_eq(loaded_payload.document.uri.to_string(), uri.to_string())
  assert_eq(loaded_payload.document.revision, "rev-2")
  let hover = @remote_protocol.HoverResult({
    id: "hover-1",
    uri,
    revision: "rev-2",
    hover: Some({
      range: Range(1, 8, 1, 12),
      contents: [PlainText("fn main"), Markdown("**main**")],
    }),
  })
  guard expect_server_packet(hover.to_json().stringify())
    is HoverResult(hover_payload) else {
    fail("unexpected hover result packet")
  }
  guard hover_payload.hover is Some(item) else { fail("missing hover") }
  assert_eq(hover_payload.revision, "rev-2")
  assert_eq(item.contents.length(), 2)
  assert_hover_plaintext(item, 0, "fn main")
  assert_hover_markdown(item, 1, "**main**")
  assert_true(item.range == Range(1, 8, 1, 12))
  let definitions = @remote_protocol.DefinitionResult({
    id: "def-1",
    uri,
    revision: "rev-2",
    locations: [
      { uri, range: Range(1, 8, 1, 12), },
      {
        uri: expect_uri("readonly-remote://workspace/src/lib.mbt"),
        range: Range(4, 2, 4, 7),
      },
    ],
  })
  let encoded_definitions = definitions.to_json().stringify()
  assert_true(encoded_definitions.contains("\"locations\":["))
  assert_true(!encoded_definitions.contains("\"location\":"))
  guard expect_server_packet(encoded_definitions)
    is DefinitionResult(definition_payload) else {
    fail("unexpected definition result packet")
  }
  assert_eq(definition_payload.id, "def-1")
  assert_eq(definition_payload.revision, "rev-2")
  assert_eq(definition_payload.locations.length(), 2)
  assert_true(definition_payload.locations[0].range == Range(1, 8, 1, 12))
  assert_eq(
    definition_payload.locations[1].uri.to_string(),
    "readonly-remote://workspace/src/lib.mbt",
  )
  let no_definitions = @remote_protocol.DefinitionResult({
    id: "def-2",
    uri,
    revision: "rev-3",
    locations: [],
  })
  guard expect_server_packet(no_definitions.to_json().stringify())
    is DefinitionResult(empty_definition_payload) else {
    fail("unexpected empty definition result packet")
  }
  assert_eq(empty_definition_payload.locations.length(), 0)
  let references_result = @remote_protocol.ReferencesResult({
    id: "refs-1",
    uri,
    revision: "rev-2",
    references: [
      {
        uri,
        range: Range(1, 8, 1, 12),
        line: 1,
        column: 8,
        line_text: "pub fn main {}",
      },
      {
        uri,
        range: Range(2, 1, 2, 5),
        line: 2,
        column: 1,
        line_text: "main()",
      },
    ],
  })
  guard expect_server_packet(references_result.to_json().stringify())
    is ReferencesResult(references_payload) else {
    fail("unexpected references result packet")
  }
  assert_eq(references_payload.id, "refs-1")
  assert_eq(references_payload.revision, "rev-2")
  assert_eq(references_payload.references.length(), 2)
  assert_eq(references_payload.references[0].line, 1)
  assert_eq(references_payload.references[0].column, 8)
  assert_eq(references_payload.references[0].line_text, "pub fn main {}")
  assert_true(references_payload.references[1].range == Range(2, 1, 2, 5))
  let empty_references = @remote_protocol.ReferencesResult({
    id: "refs-2",
    uri,
    revision: "rev-3",
    references: [],
  })
  guard expect_server_packet(empty_references.to_json().stringify())
    is ReferencesResult(empty_references_payload) else {
    fail("unexpected empty references packet")
  }
  assert_eq(empty_references_payload.references.length(), 0)
  assert_eq(empty_references_payload.revision, "rev-3")

  // Diagnostics packets are server pushes: no request id on the wire.
  let diagnostics = @remote_protocol.ServerPacket::Diagnostics({
    uri,
    revision: "rev-2",
    diagnostics: [
      {
        range: Range(1, 1, 1, 4),
        severity: Warning,
        message: "check me",
        tags: None,
      },
    ],
  })
  let encoded_diagnostics = diagnostics.to_json().stringify()
  assert_true(!encoded_diagnostics.contains("\"id\""))
  guard expect_server_packet(encoded_diagnostics)
    is Diagnostics(diagnostics_payload) else {
    fail("unexpected diagnostics packet")
  }
  assert_eq(diagnostics_payload.uri.to_string(), uri.to_string())
  assert_eq(diagnostics_payload.revision, "rev-2")
  assert_eq(diagnostics_payload.diagnostics.length(), 1)
  assert_eq(diagnostics_payload.diagnostics[0].message, "check me")
  let hint_diagnostics = @remote_protocol.ServerPacket::Diagnostics({
    uri,
    revision: "rev-3",
    diagnostics: [
      {
        range: Range(1, 1, 1, 4),
        severity: Hint,
        message: "unused",
        tags: Some([Unnecessary, Deprecated]),
      },
    ],
  })
  guard expect_server_packet(hint_diagnostics.to_json().stringify())
    is Diagnostics(hint_payload) else {
    fail("unexpected diagnostics packet")
  }
  assert_eq(hint_payload.diagnostics.length(), 1)
  assert_true(hint_payload.diagnostics[0].severity == Hint)
  assert_true(
    hint_payload.diagnostics[0].tags == Some([Unnecessary, Deprecated]),
  )
  let symbols = @remote_protocol.DocumentSymbolsResult({
    id: "symbols-1",
    uri,
    revision: "rev-2",
    symbols: [{ name: "main", kind: "function", range: Range(1, 8, 1, 12), }],
  })
  guard expect_server_packet(symbols.to_json().stringify())
    is DocumentSymbolsResult(symbols_payload) else {
    fail("unexpected document symbols result packet")
  }
  assert_eq(symbols_payload.symbols.length(), 1)
  assert_eq(symbols_payload.symbols[0].name, "main")
}

///|
test "round-trips document text containing control characters" {
  // Form feed and vertical tab are valid in source files but invalid in
  // JSON strings unless escaped; the old hand-rolled escaping emitted
  // MoonBit-style `\u{c}` and broke the peer's decode.
  let uri = expect_uri("readonly-remote://workspace/src/control.mbt")
  let text = "form\u{0c}feed\u{0b}tab\tquote\"backslash\\\nend"
  let document = @workspace.DocumentSnapshot(
    uri, "control.mbt", "moonbit", "rev-1", text,
  )
  let loaded = @remote_protocol.DocumentLoaded({ id: "open-ctl", document, })
  guard expect_server_packet(loaded.to_json().stringify())
    is DocumentLoaded(payload) else {
    fail("unexpected server packet")
  }
  assert_eq(payload.document.text, text)
}

///|
test "reports protocol decode errors" {
  match @remote_protocol.decode_client_packet("{") {
    ClientPacketDecodeError(error) =>
      assert_true(error.code == ProtocolInvalidJson)
    DecodedClientPacket(_) => fail("expected invalid JSON error")
  }

  match
    @remote_protocol.decode_client_packet(
      "{\"version\":99,\"type\":\"OpenDocument\",\"id\":\"x\",\"uri\":\"readonly-remote://workspace/a.mbt\"}",
    ) {
    ClientPacketDecodeError(error) =>
      assert_true(error.code == ProtocolUnsupportedVersion)
    DecodedClientPacket(_) => fail("expected unsupported version error")
  }

  match
    @remote_protocol.decode_client_packet(
      "{\"version\":6,\"type\":\"OpenDocument\",\"id\":\"x\",\"uri\":\"bad\"}",
    ) {
    ClientPacketDecodeError(error) =>
      assert_true(error.code == ProtocolInvalidUri)
    DecodedClientPacket(_) => fail("expected invalid URI error")
  }
}

///|
test "negotiates protocol versions" {
  match @remote_protocol.negotiate_protocol_version(6) {
    ProtocolAccepted(version) => assert_eq(version, 6)
    ProtocolRejected(error) => fail(error.message)
  }

  match @remote_protocol.negotiate_protocol_version(5) {
    ProtocolRejected(error) =>
      assert_true(error.code == ProtocolUnsupportedVersion)
    ProtocolAccepted(_) => fail("expected rejected protocol")
  }
}

///|
test "encodes and decodes host browse client packets" {
  let list = @remote_protocol.ListHostDirectory({
    id: "list-1",
    path: "/repos",
  })
  let encoded = list.to_json().stringify()
  assert_true(encoded.contains("\"type\":\"ListHostDirectory\""))
  guard expect_client_packet(encoded) is ListHostDirectory(request) else {
    fail("unexpected client packet")
  }
  assert_eq(request.id, "list-1")
  assert_eq(request.path, "/repos")

  // An empty path means "start from the current workspace root".
  let start = @remote_protocol.ListHostDirectory({ id: "list-2", path: "", })
  guard expect_client_packet(start.to_json().stringify())
    is ListHostDirectory(start_request) else {
    fail("unexpected client packet")
  }
  assert_eq(start_request.path, "")
  let switch = @remote_protocol.SwitchWorkspace({
    id: "switch-1",
    path: "/repos/demo",
  })
  guard expect_client_packet(switch.to_json().stringify())
    is SwitchWorkspace(switch_request) else {
    fail("unexpected client packet")
  }
  assert_eq(switch_request.id, "switch-1")
  assert_eq(switch_request.path, "/repos/demo")
}

///|
test "encodes and decodes host browse server packets" {
  let listed = @remote_protocol.HostDirectoryListed({
    id: "list-1",
    listing: {
      path: "/repos",
      parent: Some("/"),
      entries: [
        { name: "demo", path: "/repos/demo", is_workspace: true, },
        { name: "notes", path: "/repos/notes", is_workspace: false, },
      ],
    },
  })
  let encoded = listed.to_json().stringify()
  assert_true(encoded.contains("\"isWorkspace\":true"))
  guard expect_server_packet(encoded) is HostDirectoryListed(payload) else {
    fail("unexpected server packet")
  }
  assert_eq(payload.id, "list-1")
  assert_eq(payload.listing.path, "/repos")
  assert_eq(payload.listing.parent, Some("/"))
  assert_eq(payload.listing.entries.length(), 2)
  assert_eq(payload.listing.entries[0].name, "demo")
  assert_eq(payload.listing.entries[0].path, "/repos/demo")
  assert_true(payload.listing.entries[0].is_workspace)
  assert_true(!payload.listing.entries[1].is_workspace)

  // The filesystem root omits `parent`.
  let rooted = @remote_protocol.HostDirectoryListed({
    id: "list-2",
    listing: { path: "/", parent: None, entries: [], },
  })
  guard expect_server_packet(rooted.to_json().stringify())
    is HostDirectoryListed(rooted_payload) else {
    fail("unexpected server packet")
  }
  assert_true(rooted_payload.listing.parent is None)
  let switched = @remote_protocol.WorkspaceSwitched({
    id: "switch-1",
    root: "/repos/demo",
    name: "demo",
  })
  guard expect_server_packet(switched.to_json().stringify())
    is WorkspaceSwitched(switched_payload) else {
    fail("unexpected server packet")
  }
  assert_eq(switched_payload.id, "switch-1")
  assert_eq(switched_payload.root, "/repos/demo")
  assert_eq(switched_payload.name, "demo")

  // A broadcast push carries no id and never resolves a pending request.
  let push = @remote_protocol.WorkspaceSwitched({
    id: "",
    root: "/repos/demo",
    name: "demo",
  })
  guard expect_server_packet(push.to_json().stringify())
    is WorkspaceSwitched(push_payload) else {
    fail("unexpected server packet")
  }
  assert_eq(push_payload.id, "")
}

///|
fn assert_hover_plaintext(
  hover : @language.Hover,
  index : Int,
  expected : String,
) -> Unit raise {
  match hover.contents.get(index) {
    Some(PlainText(text)) => assert_eq(text, expected)
    Some(Markdown(_)) => fail("expected plaintext hover")
    None => fail("missing hover content")
  }
}

///|
fn assert_hover_markdown(
  hover : @language.Hover,
  index : Int,
  expected : String,
) -> Unit raise {
  match hover.contents.get(index) {
    Some(Markdown(text)) => assert_eq(text, expected)
    Some(PlainText(_)) => fail("expected markdown hover")
    None => fail("missing hover content")
  }
}

///|
fn expect_uri(raw : String) -> @base_common.Uri raise {
  @base_common.Uri::parse(raw)
}

///|
/// Decodes a client packet, failing the test with the decoder's own message
/// when the wire form is rejected.
fn expect_client_packet(
  encoded : String,
) -> @remote_protocol.ClientPacket raise {
  match @remote_protocol.decode_client_packet(encoded) {
    DecodedClientPacket(packet) => packet
    ClientPacketDecodeError(error) => fail(error.message)
  }
}

///|
/// Decodes a server packet, failing the test with the decoder's own message
/// when the wire form is rejected.
fn expect_server_packet(
  encoded : String,
) -> @remote_protocol.ServerPacket raise {
  match @remote_protocol.decode_server_packet(encoded) {
    DecodedServerPacket(packet) => packet
    ServerPacketDecodeError(error) => fail(error.message)
  }
}
