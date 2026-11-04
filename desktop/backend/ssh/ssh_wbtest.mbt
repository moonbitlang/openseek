// Whitebox tests for the package's own SSH argument builder. `arguments` is
// private: nothing outside this package calls it, so these tests moved here
// from `command_test.mbt` when it stopped being exported.

///|
test "SSH command preserves quoted identity and jump host arguments" {
  let args = arguments(
    "ssh -p 2222 -i '/tmp/key with spaces' -J jump user@host",
  )
  assert_eq(args[args.length() - 7:], [
    "-p", "2222", "-i", "/tmp/key with spaces", "-J", "jump", "user@host",
  ])
}

///|
test "SSH command refuses remote commands and stdio ownership flags" {
  for
    command in [
      "", "host", "ssh", "ssh -p host", "ssh host touch /tmp/file", "ssh -tt host",
      "ssh -N host", "ssh -L 8080:host:80 host", "ssh -i 'unfinished host", "ssh host\nsecond",
    ] {
    let rejected = try {
      ignore(arguments(command))
      false
    } catch {
      _ => true
    }
    assert_true(rejected, msg=command)
  }
}
