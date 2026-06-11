// Tests for the pure workspace-path helpers. The full
// `session_workspace_dir` / `workspace_root` chain depends on the
// environment (HOME, an existing Documents folder), so the tests cover the
// pure pieces: date extraction and the components a session occupies under
// the root.

///|
test "desktop session ids embed their creation date" {
  inspect(
    session_date("desktop-20260611-093045-123"),
    content="Some(2026-06-11)",
  )
  inspect(session_date("desktop-20251231-000000-1"), content="Some(2025-12-31)")
}

///|
test "non-desktop and malformed ids carry no date" {
  inspect(session_date("my-cli-session"), content="None")
  inspect(session_date("desktop-2026061-093045"), content="None")
  inspect(session_date("desktop-2026O611-093045"), content="None")
  inspect(session_date("desktop-20260611"), content="None")
  inspect(session_date(""), content="None")
}

///|
test "dated sessions group under their date, others sit at the root" {
  inspect(
    session_workspace_components("desktop-20260611-093045-123"),
    content="Some([2026-06-11, desktop-20260611-093045-123])",
  )
  inspect(
    session_workspace_components("my-cli-session"),
    content="Some([my-cli-session])",
  )
}

///|
test "ids that could escape the workspace root are rejected" {
  inspect(session_workspace_components(""), content="None")
  inspect(session_workspace_components("."), content="None")
  inspect(session_workspace_components(".."), content="None")
  inspect(session_workspace_components("a/b"), content="None")
  inspect(session_workspace_components("a\\b"), content="None")
  inspect(session_workspace_components("../escape"), content="None")
}
