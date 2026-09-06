///|
test "path activation follows the target shell's syntax" {
  let posix_quoted = ["/tmp/it's moon/bin", "/tmp/packaged tools/bin"]
  let windows_dirs = [
    "C:\\Users\\Moon User\\toolchain\\bin", "C:\\Program Files\\SeekMoon\\bin",
  ]
  // shell command, PATH entries, windows, the line the shell should receive
  let cases = [
    (
      "/bin/zsh",
      [
        "/Applications/Seek Moon/toolchain/bin", "/Applications/Seek Moon/packaged/bin",
      ],
      false,
      "export PATH='/Applications/Seek Moon/toolchain/bin':'/Applications/Seek Moon/packaged/bin':\"$PATH\"\r",
    ),
    (
      "/opt/homebrew/bin/fish",
      ["/tmp/it's\\moon/bin", "/tmp/packaged tools/bin"],
      false,
      "set -gx PATH '/tmp/it\\'s\\\\moon/bin' '/tmp/packaged tools/bin' $PATH\r",
    ),
    (
      "/bin/tcsh", posix_quoted, false, "setenv PATH '/tmp/it'\\''s moon/bin':'/tmp/packaged tools/bin':\"$PATH\"\r",
    ),
    (
      "/usr/local/bin/pwsh", posix_quoted, false, "$env:PATH = '/tmp/it''s moon/bin:/tmp/packaged tools/bin:' + $env:PATH\r",
    ),
    (
      "C:/Program Files/PowerShell/pwsh.exe", windows_dirs, true, "$env:Path = 'C:\\Users\\Moon User\\toolchain\\bin;C:\\Program Files\\SeekMoon\\bin;' + $env:Path\r",
    ),
    (
      "C:\\Windows\\System32\\cmd.exe", windows_dirs, true, "set \"Path=C:\\Users\\Moon User\\toolchain\\bin;C:\\Program Files\\SeekMoon\\bin;%Path%\"\r",
    ),
  ]
  for row in cases {
    let (shell, bin_dirs, windows, expected) = row
    assert_eq(
      @shellenv.path_prepend_command(shell, bin_dirs, windows~),
      Some(expected),
      msg="shell: \{shell}",
    )
  }
}

///|
test "path activation leaves unknown shells untouched" {
  assert_eq(
    @shellenv.path_prepend_command(
      "/opt/homebrew/bin/nu",
      ["/Applications/Seek Moon/toolchain/bin"],
      windows=false,
    ),
    None,
  )
  assert_eq(
    @shellenv.path_prepend_command(
      "/usr/local/bin/xonsh",
      ["/Applications/Seek Moon/toolchain/bin"],
      windows=false,
    ),
    None,
  )
  assert_eq(@shellenv.path_prepend_command("/bin/zsh", [], windows=false), None)
}
