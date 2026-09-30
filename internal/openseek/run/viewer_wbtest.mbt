///|
async test "start_viewer reads the URL the viewer prints" {
  let url = start_viewer(
    [
      "sh", "-c", "echo 'openseek viz: serving 1 session root(s)'; echo 'openseek viz: open http://127.0.0.1:41612/?t=abc (already running)'",
    ],
    ".openseek",
    wait_ms=10_000,
  )
  assert_eq(url, "http://127.0.0.1:41612/?t=abc")
}

///|
async test "start_viewer reports the viewer's error instead of waiting it out" {
  let started = @async.now()
  let message = try
    start_viewer(
      ["sh", "-c", "echo 'Error: Prebuilt wasm asset does not exist' >&2"],
      ".openseek",
      wait_ms=10_000,
    )
  catch {
    error => "\{error}"
  } noraise {
    url => fail("expected an error, got \{url}")
  }
  assert_true(message.contains("Prebuilt wasm asset does not exist"))
  assert_true(@async.now() - started < 5_000L)
}

///|
async test "start_viewer fails when the command is missing or never answers" {
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
    error => "\{error}"
  } noraise {
    url => fail("expected a timeout, got \{url}")
  }
  assert_true(silent.contains("no URL after 200ms"))
}
