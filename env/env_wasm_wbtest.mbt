///|
#unsafe_skip_stub_check
fn close_invalid_handle(handle : UInt64) -> Int = "moonbitlang/async" "fd_util/close_fd"

///|
test "failed executable imports preserve the OS error and query context" {
  for context in ["@env.current_exe()", "@env.current_exe_dir()"] {
    // Closing a null host handle sets errno without touching an OS resource.
    assert_eq(close_invalid_handle(0), -1)
    let expected = @os_error.get_errno()
    assert_true(expected != 0)
    // Zero is the host ABI's failed-query handle. The adapter must raise
    // before attempting to decode or free this invalid resource.
    try executable_path_from_buffer(0, context) catch {
      OSError(code, context=actual) => {
        assert_eq(code, expected)
        assert_eq(actual, context)
      }
    } noraise {
      _ => fail("a failed executable query must raise OSError")
    }
    // A successful query must not mistake a previous OS error for failure.
    assert_false(current_exe().is_empty())
    assert_false(current_exe_dir().is_empty())
  }
}
