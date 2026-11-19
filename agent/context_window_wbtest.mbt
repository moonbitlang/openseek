///|
/// The launcher's window arrives as an environment variable, so the one place a
/// run builds its clients reads it without every caller threading it through.
/// Only a positive integer counts: anything else leaves the build's table for
/// the model in charge rather than making the run plan against nonsense.
test "the launcher's context window is read from the environment" {
  let previous = @env.get_env_var("OPENSEEK_CONTEXT_WINDOW")
  defer (match previous {
    Some(value) => @env.set_env_var("OPENSEEK_CONTEXT_WINDOW", value)
    None => @env.unset_env_var("OPENSEEK_CONTEXT_WINDOW")
  })
  @env.unset_env_var("OPENSEEK_CONTEXT_WINDOW")
  assert_true(configured_context_window() is None)
  @env.set_env_var("OPENSEEK_CONTEXT_WINDOW", " 1000000 ")
  assert_eq(configured_context_window(), Some(1_000_000))
  @env.set_env_var("OPENSEEK_CONTEXT_WINDOW", "131072")
  assert_eq(configured_context_window(), Some(131_072))
  @env.set_env_var("OPENSEEK_CONTEXT_WINDOW", "")
  assert_true(configured_context_window() is None)
  @env.set_env_var("OPENSEEK_CONTEXT_WINDOW", "0")
  assert_true(configured_context_window() is None)
  @env.set_env_var("OPENSEEK_CONTEXT_WINDOW", "-4096")
  assert_true(configured_context_window() is None)
  @env.set_env_var("OPENSEEK_CONTEXT_WINDOW", "plenty")
  assert_true(configured_context_window() is None)
}
