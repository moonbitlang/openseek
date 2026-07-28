///|
test "validates readonly remote workspace uris" {
  let uri = expect_uri(
    "readonly-remote://workspace/tests/fixtures/workspace/src/main.mbt",
  )
  match @server.resolve_remote_document_uri(uri) {
    ParsedRemotePath(path) =>
      assert_eq(path.to_string(), "tests/fixtures/workspace/src/main.mbt")
    RemotePathError(error) => fail(error.message)
  }

  let absolute = expect_uri("readonly-remote://workspace//tmp/main.mbt")
  match @server.resolve_remote_document_uri(absolute) {
    RemotePathError(error) => assert_true(error.code == ProtocolInvalidUri)
    ParsedRemotePath(path) => fail("unexpected path " + path.to_string())
  }

  let wrong_scheme = expect_uri(
    "file://local/tests/fixtures/workspace/src/main.mbt",
  )
  match @server.resolve_remote_document_uri(wrong_scheme) {
    RemotePathError(error) => assert_true(error.code == ProtocolInvalidUri)
    ParsedRemotePath(path) => fail("unexpected path " + path.to_string())
  }
}

///|
async test "resolves one directory level through the host" {
  let host = FakeServerHost::new()
  host.directories.set("", [
    {
      uri: expect_remote_uri("moon.mod"),
      name: "moon.mod",
      kind: File,
      children: None,
    },
    {
      uri: expect_remote_uri("src"),
      name: "src",
      kind: Directory,
      children: None,
    },
  ])
  host.directories.set("src", [
    {
      uri: expect_remote_uri("src/main.mbt"),
      name: "main.mbt",
      kind: File,
      children: None,
    },
  ])
  let server = test_remote_server("/workspace", host)

  let root_uri = expect_uri("readonly-remote://workspace")
  match server.resolve_directory({ id: "resolve-1", uri: root_uri }) {
    DirectoryResolved(payload) => {
      assert_eq(payload.id, "resolve-1")
      assert_eq(payload.stat.uri.to_string(), "readonly-remote://workspace")
      assert_eq(payload.stat.name, "workspace")
      assert_true(payload.stat.kind == Directory)
      match payload.stat.children {
        Some(children) => {
          assert_eq(children.length(), 2)
          assert_eq(children[1].name, "src")
          assert_true(children[1].children is None)
        }
        None => fail("expected resolved root children")
      }
    }
    _ => fail("expected directory resolved")
  }

  match
    server.resolve_directory({ id: "resolve-2", uri: expect_remote_uri("src") }) {
    DirectoryResolved(payload) => {
      assert_eq(payload.stat.name, "src")
      match payload.stat.children {
        Some(children) => assert_eq(children[0].name, "main.mbt")
        None => fail("expected resolved src children")
      }
    }
    _ => fail("expected directory resolved")
  }

  match
    server.resolve_directory({
      id: "resolve-3",
      uri: expect_remote_uri("missing"),
    }) {
    RemoteError(error) => {
      assert_eq(error.provider_code, "FileNotFound")
      assert_eq(error.request_id, "resolve-3")
    }
    _ => fail("expected provider error")
  }
}

///|
async test "maps host read errors to protocol provider errors" {
  let host = FakeServerHost::new()
  host.errors.set("missing.mbt", (FileNotFound, "missing file"))
  let server = test_remote_server("/workspace", host)
  let uri = expect_remote_uri("missing.mbt")

  match server.open_document({ id: "open-1", uri }) {
    RemoteError(error) => {
      assert_true(error.code == ProtocolProviderError)
      assert_eq(error.provider_code, "FileNotFound")
      assert_eq(error.request_id, "open-1")
    }
    _ => fail("expected provider error")
  }
}

///|
async test "routes watch events to document changed packets" {
  let host = FakeServerHost::new()
  host.files.set("main.mbt", "pub fn main {}\n")
  let server = test_remote_server("/workspace/", host)
  let uri = expect_remote_uri("main.mbt")
  let emitted = []

  match
    server.watch_document(
      { id: "watch-1", uri },
      packet => emitted.push(packet),
      noop_watch_spawner,
    ) {
    DocumentLoaded(payload) =>
      assert_eq(payload.document.text, "pub fn main {}\n")
    _ => fail("expected initial document load")
  }

  host.files.set("main.mbt", "pub fn main { 1 }\n")
  host.emit("main.mbt", Changed)
  assert_eq(emitted.length(), 1)
  match emitted[0] {
    DocumentChanged(payload) =>
      assert_eq(payload.document.text, "pub fn main { 1 }\n")
    _ => fail("expected document changed")
  }

  host.emit("main.mbt", Deleted)
  match emitted[1] {
    RemoteError(error) => assert_eq(error.provider_code, "FileNotFound")
    _ => fail("expected deletion error")
  }
}

///|
async test "server sessions dispose only their own document watches" {
  let host = FakeServerHost::new()
  host.files.set("main.mbt", "pub fn main {}\n")
  let template = test_remote_server("/workspace/", host)
  let first = template.new_session()
  let second = template.new_session()
  let uri = expect_remote_uri("main.mbt")
  let first_emitted = []
  let second_emitted = []

  ignore(
    first.watch_document(
      { id: "watch-first", uri },
      packet => first_emitted.push(packet),
      noop_watch_spawner,
    ),
  )
  ignore(
    second.watch_document(
      { id: "watch-second", uri },
      packet => second_emitted.push(packet),
      noop_watch_spawner,
    ),
  )

  host.files.set("main.mbt", "pub fn main { 1 }\n")
  host.emit("main.mbt", Changed)
  assert_eq(first_emitted.length(), 1)
  assert_eq(second_emitted.length(), 1)

  first.dispose_watches()
  host.files.set("main.mbt", "pub fn main { 22 }\n")
  host.emit("main.mbt", Changed)
  assert_eq(first_emitted.length(), 1)
  assert_eq(second_emitted.length(), 2)
  match second_emitted[1] {
    DocumentChanged(payload) => {
      assert_eq(payload.id, "watch-second")
      assert_eq(payload.document.text, "pub fn main { 22 }\n")
    }
    _ => fail("expected the remaining session's document change")
  }
}

///|
async test "notifies the document sync listener on open and watch change" {
  let host = FakeServerHost::new()
  host.files.set("main.mbt", "pub fn main {}\n")
  let server = test_remote_server("/workspace/", host)
  let uri = expect_remote_uri("main.mbt")
  let synced : Array[String] = []
  server.set_document_sync_listener(
    Some(document => synced.push(document.text)),
  )
  ignore(server.open_document({ id: "open-1", uri }))
  assert_eq(synced.length(), 1)
  assert_eq(synced[0], "pub fn main {}\n")
  ignore(
    server.watch_document(
      { id: "watch-1", uri },
      _packet => (),
      noop_watch_spawner,
    ),
  )
  assert_eq(synced.length(), 2)
  host.files.set("main.mbt", "pub fn main { 1 }\n")
  host.emit("main.mbt", Changed)
  assert_eq(synced.length(), 3)
  assert_eq(synced[2], "pub fn main { 1 }\n")
}

///|
async test "answers hover and definition from cached provider state" {
  let host = FakeServerHost::new()
  host.files.set("main.mbt", "pub fn main {}\n")
  let server = test_remote_server("/workspace", host)
  let uri = expect_remote_uri("main.mbt")
  ignore(server.open_document({ id: "open-1", uri }))

  match server.hover({ id: "hover-1", uri, document_revision: "", offset: 7 }) {
    HoverResult(payload) =>
      match payload.hover {
        Some(hover) => assert_plaintext_hover(hover, "Configured hover")
        None => fail("expected hover")
      }
    _ => fail("expected hover result")
  }

  match
    server.definition({ id: "def-1", uri, document_revision: "", offset: 7 }) {
    DefinitionResult(payload) =>
      match payload.location {
        Some(location) => assert_eq(location.uri.to_string(), uri.to_string())
        None => fail("expected definition")
      }
    _ => fail("expected definition result")
  }

  match
    server.references({ id: "refs-1", uri, document_revision: "", offset: 7 }) {
    ReferencesResult(payload) => {
      assert_eq(payload.id, "refs-1")
      assert_eq(payload.references.length(), 2)
      // Offset 7 of "pub fn main {}\n" sits on line 1, column 8.
      assert_eq(payload.references[0].uri.to_string(), uri.to_string())
      assert_eq(payload.references[0].line, 1)
      assert_eq(payload.references[0].column, 8)
      assert_eq(payload.references[0].line_text, "pub fn main {}")
      assert_eq(payload.references[1].line, 1)
      assert_eq(payload.references[1].column, 1)
    }
    _ => fail("expected references result")
  }
}

///|
async test "answers symbols from cached provider state" {
  let host = FakeServerHost::new()
  host.files.set("main.mbt", "pub fn main { // TODO }\n")
  let server = test_remote_server("/workspace", host)
  let uri = expect_remote_uri("main.mbt")
  ignore(server.open_document({ id: "open-1", uri }))
  match
    server.document_symbols({ id: "symbols-1", uri, document_revision: "" }) {
    DocumentSymbolsResult(payload) => {
      assert_eq(payload.symbols.length(), 1)
      assert_eq(payload.symbols[0].name, "configured")
    }
    _ => fail("expected document symbols result")
  }
}

///|
async test "dispatches language requests through configured providers" {
  let host = FakeServerHost::new()
  host.files.set("configured.mbt", "pub fn configured {}\n")
  let server = test_remote_server("/workspace", host)
  let uri = expect_remote_uri("configured.mbt")
  ignore(server.open_document({ id: "open-1", uri }))

  match server.hover({ id: "hover-1", uri, document_revision: "", offset: 7 }) {
    HoverResult(payload) =>
      match payload.hover {
        Some(hover) => assert_plaintext_hover(hover, "Configured hover")
        None => fail("expected configured hover")
      }
    _ => fail("expected hover result")
  }

  match
    server.definition({ id: "def-1", uri, document_revision: "", offset: 7 }) {
    DefinitionResult(payload) =>
      match payload.location {
        Some(location) => assert_eq(location.uri.to_string(), uri.to_string())
        None => fail("expected configured definition")
      }
    _ => fail("expected definition result")
  }

  match
    server.document_symbols({ id: "symbols-1", uri, document_revision: "" }) {
    DocumentSymbolsResult(payload) =>
      assert_eq(payload.symbols[0].name, "configured")
    _ => fail("expected document symbols result")
  }
}

///|
fn expect_remote_uri(path : String) -> @base_common.Uri raise {
  match @server.remote_document_uri(path) {
    Some(uri) => uri
    None => fail("invalid remote path " + path)
  }
}

///|
fn expect_uri(raw : String) -> @base_common.Uri raise {
  @base_common.Uri::parse(raw)
}

///|
fn test_remote_server(
  root : String,
  host : &@server.ServerHost,
) -> @server.RemoteServer {
  let provider = FakeLanguageProvider::{  }
  @server.RemoteServer::with_language_providers(
    root, host, provider, provider, provider, provider,
  )
}

///|
struct FakeServerHost {
  files : Map[String, String]
  errors : Map[String, (@workspace.FileSystemProviderErrorCode, String)]
  directories : Map[String, Array[@workspace.WorkspaceStat]]
  listeners : Map[String, Array[FakeWatchListener]]
}

///|
struct FakeWatchListener {
  listener : async (@workspace.FileChangeType) -> Unit
  active : Ref[Bool]
}

///|
fn FakeServerHost::new() -> FakeServerHost {
  {
    files: Default::default(),
    errors: Default::default(),
    directories: Default::default(),
    listeners: Default::default(),
  }
}

///|
async fn FakeServerHost::emit(
  self : FakeServerHost,
  path : String,
  change_type : @workspace.FileChangeType,
) -> Unit {
  match self.listeners.get(path) {
    Some(listeners) =>
      for watch in listeners {
        if watch.active.val {
          (watch.listener)(change_type)
        }
      }
    None => ()
  }
}

///|
impl @server.ServerHost for FakeServerHost with fn read_directory(
  self,
  _root,
  relative,
) {
  match self.directories.get(relative) {
    Some(children) => ServerHostResolveOk(children)
    None => ServerHostResolveError(FileNotFound, "Directory does not exist.")
  }
}

///|
impl @server.ServerHost for FakeServerHost with fn read_text_file(
  self,
  _root,
  path,
) {
  let key = path.to_string()
  match self.errors.get(key) {
    Some((code, message)) => ServerHostReadError(code, message)
    None =>
      match self.files.get(key) {
        Some(text) =>
          ServerHostReadOk(
            DocumentContent(
              text,
              display_name=path.display_name(),
              revision="rev-" + text.length().to_string(),
            ),
          )
        None => ServerHostReadError(FileNotFound, "missing file")
      }
  }
}

///|
impl @server.ServerHost for FakeServerHost with fn watch_text_file(
  self,
  _root,
  path,
  listener,
  _spawn_watch,
) {
  let key = path.to_string()
  let active = Ref(true)
  let watch = { listener, active }
  match self.listeners.get(key) {
    Some(listeners) => listeners.push(watch)
    None => self.listeners.set(key, [watch])
  }
  ServerWatch(() => active.val = false)
}

///|
fn noop_watch_spawner(_task : async () -> Unit) -> Unit {
  ()
}

///|
struct FakeLanguageProvider {}

///|
impl @language.HoverProvider for FakeLanguageProvider with fn provide_hover(
  _self,
  model,
  position,
  _token,
) {
  let offset = model.get_offset_at(position)
  Some({
    range: model.snapshot.range_of(OffsetRange(offset, offset + 4)),
    contents: [PlainText("Configured hover")],
  })
}

///|
fn assert_plaintext_hover(
  hover : @language.Hover,
  expected : String,
) -> Unit raise {
  match hover.contents {
    [PlainText(text)] => assert_eq(text, expected)
    _ => fail("expected plaintext hover")
  }
}

///|
impl @language.DefinitionProvider for FakeLanguageProvider with fn provide_definition(
  _self,
  model,
  position,
  _token,
) {
  let offset = model.get_offset_at(position)
  let end_pos = model.get_position_at(offset + 4)
  Some({
    uri: model.uri,
    range: @base_common.Range::from_positions(position, end_pos),
  })
}

///|
impl @language.ReferencesProvider for FakeLanguageProvider with fn provide_references(
  _self,
  model,
  position,
  _token,
) {
  let offset = model.get_offset_at(position)
  let end_pos = model.get_position_at(offset + 4)
  [
    {
      uri: model.uri,
      range: @base_common.Range::from_positions(position, end_pos),
    },
    {
      uri: model.uri,
      range: @base_common.Range::from_positions(
        model.get_position_at(0),
        model.get_position_at(4),
      ),
    },
  ]
}

///|
impl @language.DocumentSymbolProvider for FakeLanguageProvider with fn provide_document_symbols(
  _self,
  _model,
  _token,
) {
  [{ name: "configured", kind: "function", range: Range(1, 8, 1, 18) }]
}
