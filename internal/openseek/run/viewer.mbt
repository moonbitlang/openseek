///|
/// The session viewer release `--inspect` starts, run through `moonx`.
let inspect_package : String = "moonbitlang/inspect@0.1.0"

///|
/// How long `--inspect` waits for the viewer to report its URL. The first
/// launch downloads the viewer, so this is generous; a failure usually shows
/// up much sooner as an `Error` line.
let inspect_wait_ms : Int = 60_000

///|
/// `--inspect`: start (or reuse) the session viewer for `session_root` and
/// print a link to `session` on stderr, before the agent starts. The viewer is
/// its own process and outlives the run; it exits after an hour without a
/// request or once its session root is deleted. If it cannot start, that is
/// said once and the run goes on.
async fn show_in_viewer(session_root : String, session : String) -> Unit {
  let line = try {
    // `spawn_orphan` leaves the viewer in this terminal's session, so closing
    // the terminal would hang it up; `nohup` makes it ignore that. Where there
    // is no `nohup` (Windows, which has no hangup signal), start it directly.
    let url = start_viewer(
      ["nohup", "moonx", inspect_package],
      session_root,
      wait_ms=inspect_wait_ms,
    ) catch {
      @os_error.OSError(_) as error if error.is_ENOENT() =>
        start_viewer(
          ["moonx", inspect_package],
          session_root,
          wait_ms=inspect_wait_ms,
        )
      error => raise error
    }
    Ok("\{url}#s=\{@percent.encode(session)}")
  } catch {
    error => Err("\{error}")
  }
  match line {
    Ok(link) => {
      // The link is printed first, so it is there to use whatever happens
      // to the browser.
      @stdio.stderr.write("watch live: \{link}\n")
      @stdio.stderr.write("\{browser_notice(@open_in_browser.open(link))}\n")
    }
    Err(error) =>
      @stdio.stderr.write(
        "could not start the session viewer (\{error}); the run goes on\n",
      )
  }
}

///|
/// Launch `command --ensure --watch --session-root <root>` detached, and read
/// the URL from the `openseek viz: open <url>` line it prints (whether it
/// started a server or found one already running). Its output goes to a
/// private temporary file, never to the run's own stdout and stderr.
async fn start_viewer(
  command : Array[String],
  session_root : String,
  wait_ms~ : Int,
) -> String {
  let dir = @fs.tmpdir(prefix="openseek-inspect-")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let out = "\{dir}/inspect.out"
  // One handle for both streams, as `redirect_to_file` intends; opening the
  // file twice kept the viewer's output from showing up on Windows.
  let output = @process.redirect_to_file(out)
  let _ = @process.spawn_orphan(
    command[0],
    [..command[1:], "--ensure", "--watch", "--session-root", session_root],
    stdout=output,
    stderr=output,
  )
  let result = @async.with_timeout_opt(wait_ms, () => {
    while true {
      let text = @fs.read_file(out).text() catch { _ => "" }
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
    None => fail("no URL after \{wait_ms}ms")
  }
}

///|
/// What the viewer's output says so far.
priv enum ViewerOutput {
  Opened(String)
  Failed(String)
  Pending
} derive(Eq, Debug)

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
    viewer_output("nohup: moonx: No such file or directory\n"),
    Failed("nohup: moonx: No such file or directory"),
  )
  @debug.assert_eq(viewer_output("openseek viz: serving 1"), Pending)
  @debug.assert_eq(viewer_output(""), Pending)
}

///|
/// The stderr line saying what opening the link did, under the link.
fn browser_notice(outcome : @open_in_browser.Outcome) -> String {
  match outcome {
    Launched => "opened it in your default browser"
    Skipped(reason) => "not opening a browser \{reason}; use the link above"
    Failed(error) => "could not open a browser (\{error}); use the link above"
  }
}

///|
test "browser_notice says what happened under the link" {
  inspect(browser_notice(Launched), content="opened it in your default browser")
  inspect(
    browser_notice(Skipped("over SSH")),
    content="not opening a browser over SSH; use the link above",
  )
  inspect(
    browser_notice(Failed("`xdg-open` not found")),
    content="could not open a browser (`xdg-open` not found); use the link above",
  )
}
