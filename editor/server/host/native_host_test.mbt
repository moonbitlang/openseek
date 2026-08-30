// Native filesystem tests use an atomically created directory per test because
// async tests run in parallel.

///|
async test "native host reads root-relative text files" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="openseek-native-host-read")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    @fs.mkdir("\{root}/src", recursive=true)
    @fs.write_file(
      "\{root}/src/main.mbt",
      "pub fn main {}\n",
      create_mode=CreateOrTruncate,
    )
    let host = @host.native_server_host()
    match host.read_text_file(root, expect_path("src/main.mbt")) {
      ServerHostReadOk(content) => {
        let document = @workspace.DocumentSnapshot::from_content(
          @base_common.Uri::file(root + "/src/main.mbt"),
          content,
        )
        assert_eq(document.text, "pub fn main {}\n")
        assert_eq(document.display_name, "src/main.mbt")
        assert_eq(document.language_id, "moonbit")
      }
      ServerHostReadError(_code, message) => fail(message)
    }

    match host.read_text_file(root, expect_path("src")) {
      ServerHostReadError(code, _) => assert_true(code == IsDirectory)
      ServerHostReadOk(_) => fail("expected directory read rejection")
    }
  }
}

///|
async test "native host resolves one directory level with minted uris" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="openseek-native-host-resolve")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    @fs.mkdir("\{root}/src/lib", recursive=true)
    @fs.mkdir("\{root}/_build", recursive=true)
    @fs.write_file(
      "\{root}/moon.mod",
      "name = \"fixture\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{root}/src/main.mbt",
      "pub fn main {}\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{root}/src/lib/util.mbt",
      "pub fn util {}\n",
      create_mode=CreateOrTruncate,
    )

    let host = @host.native_server_host()
    match host.read_directory(root, "") {
      ServerHostResolveOk(children) => {
        // One level only, with generated trees filtered out and every
        // child carrying a minted URI and unresolved children.
        assert_eq(
          stat_kind(children, "readonly-remote://workspace/moon.mod"),
          "file",
        )
        assert_eq(
          stat_kind(children, "readonly-remote://workspace/src"),
          "directory",
        )
        assert_eq(children.length(), 2)
        for child in children {
          assert_true(child.children is None)
        }
      }
      ServerHostResolveError(_code, message) => fail(message)
    }

    match host.read_directory(root, "src") {
      ServerHostResolveOk(children) => {
        assert_eq(
          stat_kind(children, "readonly-remote://workspace/src/lib"),
          "directory",
        )
        assert_eq(
          stat_kind(children, "readonly-remote://workspace/src/main.mbt"),
          "file",
        )
        assert_eq(children.length(), 2)
      }
      ServerHostResolveError(_code, message) => fail(message)
    }

    match host.read_directory(root, "missing") {
      ServerHostResolveError(code, _) => assert_true(code == FileNotFound)
      ServerHostResolveOk(_) => fail("expected missing directory error")
    }

    match host.read_directory(root, "moon.mod") {
      ServerHostResolveError(code, _) => assert_true(code == FileNotADirectory)
      ServerHostResolveOk(_) => fail("expected non-directory error")
    }
  }
}

///|
fn stat_kind(stats : Array[@workspace.WorkspaceStat], uri : String) -> String {
  for stat in stats {
    if stat.uri.to_string() == uri {
      return stat.kind.to_string()
    }
  }
  ""
}

///|
async test "native host polling watch emits changed and deleted" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="openseek-native-host-watch")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    @fs.write_file(
      "\{root}/watched.mbt",
      "pub fn watched { 1 }\n",
      create_mode=CreateOrTruncate,
    )

    let events : Array[@workspace.FileChangeType] = []
    let host : &@server.ServerHost = @host.NativeServerHost::with_poll_interval(
      20,
    )
    let watch = host.watch_text_file(
      root,
      expect_path("watched.mbt"),
      change => events.push(change),
      task => group.spawn_bg(task, no_wait=true, allow_failure=true),
    )
    @async.sleep(30)
    @fs.write_file(
      "\{root}/watched.mbt",
      "pub fn watched { 2 }\n",
      create_mode=CreateOrTruncate,
    )
    wait_for_events(events, 1)
    @fs.remove("\{root}/watched.mbt")
    wait_for_events(events, 2)
    watch.dispose()
    assert_true(events[0] == Changed)
    assert_true(events[1] == Deleted)
  }
}

///|
async fn wait_for_events(
  events : Array[@workspace.FileChangeType],
  count : Int,
) -> Unit {
  let mut remaining = 50
  while events.length() < count && remaining > 0 {
    @async.sleep(20)
    remaining -= 1
  }
  if events.length() < count {
    fail("timed out waiting for native watch event")
  }
}

///|
test "parses moon ide hover json output" {
  let raw =
    #|{"range":"20:15-20:33","contents":["```moonbit\nenum DiagnosticSeverity {}\n```","\n Doc text."]}
  match @host.parse_moon_hover_output(raw, Position(3, 7)) {
    Some(hover) => {
      assert_true(hover.range == Range(20, 15, 20, 33))
      match hover.contents {
        [Markdown(code), Markdown(doc)] => {
          assert_true(code.has_prefix("```moonbit"))
          assert_eq(doc, "\n Doc text.")
        }
        _ => fail("expected two markdown contents")
      }
    }
    None => fail("expected hover")
  }

  // A payload without a range degrades to a one-column range at the request
  // position.
  let rangeless =
    #|{"contents":["plain"]}
  match @host.parse_moon_hover_output(rangeless, Position(3, 7)) {
    Some(hover) => assert_true(hover.range == Range(3, 7, 3, 8))
    None => fail("expected rangeless hover")
  }
  assert_true(
    @host.parse_moon_hover_output(
      "No hover information found at src/main.mbt:1:1",
      Position(1, 1),
    )
    is None,
  )
  assert_true(
    @host.parse_moon_hover_output("{\"contents\":[]}", Position(1, 1)) is None,
  )
}

///|
test "parses ordered moon definition results and rejects unsafe entries" {
  let raw =
    #|[
    #|  {"path":"/workspace/demo/src/first.mbt","range":"2:3-2:9"},
    #|  {"path":"src/second.mbt","range":"8:1-9:4"},
    #|  {"path":"/workspace/other/outside.mbt","range":"1:1-1:2"},
    #|  {"path":"/workspace/demo/../outside.mbt","range":"1:1-1:2"},
    #|  {"path":"/workspace/demo/src/zero.mbt","range":"0:1-1:2"},
    #|  {"path":"/workspace/demo/src/reversed.mbt","range":"4:3-2:1"},
    #|  {"path":"/workspace/demo/src/malformed.mbt","range":"bad"},
    #|  {"path":"/workspace/demo/src/missing-range.mbt"}
    #|]
  let locations = @host.parse_moon_definition_output("/workspace/demo", raw)
  assert_eq(locations.length(), 2)
  assert_eq(
    locations[0].uri.to_string(),
    "readonly-remote://workspace/src/first.mbt",
  )
  assert_true(locations[0].range == Range(2, 3, 2, 9))
  assert_eq(
    locations[1].uri.to_string(),
    "readonly-remote://workspace/src/second.mbt",
  )
  assert_true(locations[1].range == Range(8, 1, 9, 4))
  assert_eq(
    @host.parse_moon_definition_output(
      "/workspace/demo", "{\"path\":\"src/main.mbt\",\"range\":\"1:1-1:2\"}",
    ).length(),
    0,
  )
  assert_eq(
    @host.parse_moon_definition_output("/workspace/demo", "not json").length(),
    0,
  )
}

///|
#cfg(all(not(platform="windows"), target="native"))
async test "moon definition provider invokes exact peek-def command" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="openseek-native-definition")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    @fs.mkdir("\{root}/src", recursive=true)
    let command = "\{root}/moon-probe"
    let script =
      #|#!/bin/sh
      #|test "$#" -eq 5 || exit 41
      #|test "$1" = "ide" || exit 42
      #|test "$2" = "peek-def" || exit 43
      #|test "$3" = "--loc" || exit 44
      #|test "$4" = "src/main.mbt:2:5" || exit 45
      #|test "$5" = "--json" || exit 46
      #|printf '[{"path":"src/target.mbt","range":"3:2-3:8"}]\n'
      #|
    @fs.write_file(command, script, create_mode=CreateOrTruncate)
    @fs.chmod(command, 0o755)
    let uri = match @server.remote_document_uri("src/main.mbt") {
      Some(uri) => uri
      None => fail("expected remote document uri")
    }
    let model = @model.TextModel(
      uri, "src/main.mbt", "moonbit", 1, "rev-1", "fn main {}\n",
    )
    let provider : &@language.DefinitionProvider = @host.MoonWorkspaceLanguageProvider(
      Ref(root),
      moon_command=command,
    )
    let locations = provider.provide_definition(
      model,
      Position(2, 5),
      @language.CancellationToken::none(),
    )
    assert_eq(locations.length(), 1)
    assert_eq(
      locations[0].uri.to_string(),
      "readonly-remote://workspace/src/target.mbt",
    )
    assert_true(locations[0].range == Range(3, 2, 3, 8))
  }
}

///|
#cfg(all(not(platform="windows"), target="native"))
async test "moon references provider invokes exact find-references command" {
  @async.with_task_group() <| group => {
    let root = @fs.tmpdir(prefix="openseek-native-references")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(root, recursive=true))
    }
    @fs.mkdir(root + "/src", recursive=true)
    let command = root + "/moon-probe"
    let script =
      #|#!/bin/sh
      #|test "$#" -eq 5 || exit 41
      #|test "$1" = "ide" || exit 42
      #|test "$2" = "find-references" || exit 43
      #|test "$3" = "--loc" || exit 44
      #|test "$4" = "src/main.mbt:2:5" || exit 45
      #|test "$5" = "--json" || exit 46
      #|printf '[{"path":"src/target.mbt","range":"3:2-3:8"},{"path":"src/main.mbt","range":"2:5-2:11"}]\n'
      #|
    @fs.write_file(command, script, create_mode=CreateOrTruncate)
    @fs.chmod(command, 0o755)
    let uri = match @server.remote_document_uri("src/main.mbt") {
      Some(uri) => uri
      None => fail("expected remote document uri")
    }
    let model = @model.TextModel(
      uri, "src/main.mbt", "moonbit", 1, "rev-1", "fn main {}\n",
    )
    let provider : &@language.ReferencesProvider = @host.MoonWorkspaceLanguageProvider(
      Ref(root),
      moon_command=command,
    )
    let locations = provider.provide_references(
      model,
      Position(2, 5),
      @language.CancellationToken::none(),
    )
    assert_eq(locations.length(), 2)
    assert_eq(
      locations[0].uri.to_string(),
      "readonly-remote://workspace/src/target.mbt",
    )
    assert_true(locations[0].range == Range(3, 2, 3, 8))
    assert_eq(
      locations[1].uri.to_string(),
      "readonly-remote://workspace/src/main.mbt",
    )
    assert_true(locations[1].range == Range(2, 5, 2, 11))
  }
}

///|
test "parses moon check json diagnostics grouped by workspace uri" {
  let raw =
    #|{"$message_type":"diagnostic","level":"warning","error_code":1,"path":"/workspace/demo/src/bad.mbt","loc":"2:4-2:17","message":"Warning (unused_value): Unused function 'unused_helper'","context":"1 |///|\n"}
    #|{"$message_type":"diagnostic","level":"error","error_code":4014,"path":"/workspace/demo/src/bad.mbt","loc":"4:7-4:8","message":"Expr Type Mismatch"}
    #|{"$message_type":"diagnostic","level":"error","error_code":1,"path":"/elsewhere/other.mbt","loc":"1:1-1:2","message":"outside the workspace root"}
    #|Finished. moon: no work to do
    #|
  let grouped = @host.parse_moon_check_diagnostics("/workspace/demo", raw)
  assert_eq(grouped.length(), 1)
  match grouped.get("readonly-remote://workspace/src/bad.mbt") {
    Some(diagnostics) => {
      assert_eq(diagnostics.length(), 2)
      assert_true(diagnostics[0].severity == Warning)
      assert_true(diagnostics[0].range == Range(2, 4, 2, 17))
      assert_true(
        diagnostics[0].message.contains("Unused function 'unused_helper'"),
      )
      assert_true(diagnostics[1].severity == Error)
      assert_true(diagnostics[1].range == Range(4, 7, 4, 8))
    }
    None => fail("expected diagnostics for src/bad.mbt")
  }
}

///|
fn expect_path(raw : String) -> @workspace.SourcePath raise {
  match @workspace.SourcePath::normalize_root_relative_path(raw) {
    ParsedSourcePath(path) => path
    SourcePathError(error) => fail("unexpected path error \{error.to_string()}")
  }
}
