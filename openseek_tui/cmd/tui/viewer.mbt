///|
/// The session viewer release `/inspect` starts, run through `moonx`. It is
/// the same `--ensure` server `openseek run --inspect` uses, so every run and
/// TUI in a project shares one.
const InspectPackage : String = "moonbitlang/inspect@0.1.0"

///|
/// How long `/inspect` waits for the viewer's URL. The first launch downloads
/// the viewer, so this is generous; a failure usually shows up much sooner as
/// an `Error` line.
const InspectWaitMs : Int32 = 60_000

///|
/// `/inspect`: start (or reuse) the session viewer for `session_root` and
/// return the link to `session`. The viewer is its own detached process and
/// outlives the TUI; it exits after an hour without a request.
async fn open_viewer(session_root : String, session : String) -> String {
  // `spawn_orphan` leaves the viewer in this terminal's session, so closing
  // the terminal would hang it up; `nohup` makes it ignore that. Where there
  // is no `nohup` (Windows, which has no hangup signal), start it directly.
  let url = start_viewer(
    ["nohup", "moonx", InspectPackage],
    session_root,
    wait_ms=InspectWaitMs,
  ) catch {
    @os_error.OsError(NotFound, ..) =>
      start_viewer(
        ["moonx", InspectPackage],
        session_root,
        wait_ms=InspectWaitMs,
      )
    error => raise error
  }
  "\{url}#s=\{@percent.encode(session)}"
}

///|
/// Launch `command --ensure --watch --session-root <root>` detached, and read
/// the URL from the `openseek viz: open <url>` line it prints (whether it
/// started a server or found one already running). Its output goes to a
/// private temporary file, never to the terminal the UI owns.
async fn start_viewer(
  command : Array[String],
  session_root : String,
  wait_ms~ : Int32,
) -> String {
  let dir = @fs.tmpdir(prefix="openseek-tui-inspect-")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let out = "\{dir}/inspect.out"
  // One handle for both streams: opening the file twice gives two writers
  // that Windows does not let share it.
  let _ = @process.spawn_orphan(
    command[0],
    [..command[1:], "--ensure", "--watch", "--session-root", session_root],
    stdout=ToFile(out),
    stderr=DuplicateStdout,
  )
  let result = @async.with_timeout_opt(wait_ms, () => {
    while true {
      let text = @fs.read_text(out) catch { _ => "" }
      match viewer_output(text) {
        Opened(url) => return Ok(url)
        Failed(message) => return Err(message)
        Pending => @async.sleep(100)
      }
    }
    Err("unreachable")
  })
  match result {
    Some(Ok(url)) => url
    Some(Err(message)) => fail(message)
    None => {
      // Say what the viewer did print, if anything, so a hang is diagnosable.
      let printed = (@fs.read_text(out) catch { _ => "" }).trim()
      if printed.is_empty() {
        fail("no URL after \{wait_ms}ms (the viewer printed nothing)")
      } else {
        fail("no URL after \{wait_ms}ms; the viewer printed: \{printed}")
      }
    }
  }
}

///|
/// What the viewer's output says so far.
#derive(Eq, Debug)
priv enum ViewerOutput {
  Opened(String)
  Failed(String)
  Pending
}

///|
/// Read the viewer's output: its URL once `openseek viz: open <url>` appears,
/// or the first `Error` line (`moonx` reports a missing package or a failed
/// download that way, and `inspect` its own failures).
fn viewer_output(text : String) -> ViewerOutput {
  for line in text.split("\n") {
    let line = line.trim()
    if line.strip_prefix("openseek viz: open ") is Some(rest) {
      // `(already running)` may follow the URL.
      return Opened(
        match rest.split_once(" ") {
          Some((url, _)) => url.to_owned()
          None => rest.to_owned()
        },
      )
    }
    // `nohup:` is how a missing `moonx` shows up behind `nohup`.
    if line.has_prefix("Error") ||
      line.has_prefix("error:") ||
      line.has_prefix("nohup:") {
      return Failed(line.to_owned())
    }
  }
  Pending
}

///|
test "viewer_output finds the URL, an error, or nothing yet" {
  @debug.assert_eq(
    viewer_output(
      "openseek viz: serving 1 session root(s)\nopenseek viz: open http://127.0.0.1:41612/?t=abc\n",
    ),
    Opened("http://127.0.0.1:41612/?t=abc"),
  )
  @debug.assert_eq(
    viewer_output(
      "openseek viz: open http://127.0.0.1:41612/?t=abc (already running)\n",
    ),
    Opened("http://127.0.0.1:41612/?t=abc"),
  )
  @debug.assert_eq(
    viewer_output("Error: Prebuilt wasm asset does not exist\n"),
    Failed("Error: Prebuilt wasm asset does not exist"),
  )
  @debug.assert_eq(
    viewer_output("nohup: can't execute 'moonx': No such file or directory\n"),
    Failed("nohup: can't execute 'moonx': No such file or directory"),
  )
  @debug.assert_eq(viewer_output("openseek viz: serving 1"), Pending)
}

///|
async test "start_viewer reads the URL the viewer prints" {
  let url = start_viewer(
    [
      "sh", "-c", "echo 'openseek viz: open http://127.0.0.1:41612/?t=abc (already running)'",
    ],
    ".openseek",
    wait_ms=10_000,
  )
  assert_eq(url, "http://127.0.0.1:41612/?t=abc")
}

///|
async test "start_viewer fails fast on an error, a missing command, or silence" {
  let started = @async.now()
  let error = try
    start_viewer(
      ["sh", "-c", "echo 'Error: Prebuilt wasm asset does not exist' >&2"],
      ".openseek",
      wait_ms=10_000,
    )
  catch {
    e => "\{e}"
  } noraise {
    url => fail("expected an error, got \{url}")
  }
  assert_true(error.contains("Prebuilt wasm asset does not exist"))
  assert_true(@async.now() - started < 5_000L)
  let missing = try
    start_viewer(["openseek-no-such-viewer-xyz"], ".openseek", wait_ms=1000)
  catch {
    _ => None
  } noraise {
    url => Some(url)
  }
  assert_true(missing is None)
  let silent = try
    start_viewer(["sh", "-c", "sleep 2"], ".openseek", wait_ms=200)
  catch {
    e => "\{e}"
  } noraise {
    url => fail("expected a timeout, got \{url}")
  }
  assert_true(silent.contains("no URL after 200ms"))
}

///|
test "/inspect starts the viewer, and its answer lands in the transcript" {
  let state = drain_test_state()
  let cmds = update(state, UiInput(SlashCommand(name="inspect", arguments="")))
  assert_eq(cmds.length(), 2)
  assert_true(
    cmds[0] is AppendItem(Input(Notice("starting the session viewer…"))),
  )
  assert_true(cmds[1] is OpenViewer)
  // The viewer runs beside any turn: /inspect never waits for one to end.
  assert_true(state.run is Idle)
  let rejected = update(
    state,
    UiInput(SlashCommand(name="inspect", arguments="now")),
  )
  assert_eq(error_item_count(rejected), 1)
  assert_false(rejected.iter().any(cmd => cmd is OpenViewer))
  let opened = update(
    state,
    ViewerOpened(Ok("http://127.0.0.1:41612/?t=abc#s=s1")),
  )
  assert_true(
    opened
    is [
      AppendItem(
        Input(
          Notice("watch this session live:\nhttp://127.0.0.1:41612/?t=abc#s=s1"),
        ),
      ),
    ],
  )
  let failed = update(state, ViewerOpened(Err("Error: offline")))
  assert_eq(error_item_count(failed), 1)
}

///|
/// The transcript line saying what opening the link did, under the link.
fn browser_notice(outcome : @open_in_browser.Outcome) -> String {
  match outcome {
    Launched => "opened it in your default browser"
    Skipped(reason) => "not opening a browser \{reason}; use the link above"
    Failed(error) => "could not open a browser (\{error}); use the link above"
  }
}

///|
test "each browser outcome lands in the transcript under the link" {
  let state = drain_test_state()
  assert_true(
    update(state, BrowserOpened(Launched))
    is [AppendItem(Input(Notice("opened it in your default browser")))],
  )
  assert_true(
    update(state, BrowserOpened(Skipped("over SSH")))
    is [
      AppendItem(
        Input(Notice("not opening a browser over SSH; use the link above")),
      ),
    ],
  )
  assert_true(
    update(state, BrowserOpened(Failed("`xdg-open` not found")))
    is [
      AppendItem(
        Input(
          Notice(
            "could not open a browser (`xdg-open` not found); use the link above",
          ),
        ),
      ),
    ],
  )
}
