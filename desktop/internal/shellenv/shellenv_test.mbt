///|
test "path activation follows the target shell's syntax" {
  assert_eq(
    @shellenv.path_prepend_command(
      "/bin/zsh",
      [
        "/Applications/Seek Moon/toolchain/bin", "/Applications/Seek Moon/packaged/bin",
      ],
      windows=false,
    ),
    Some(
      "export PATH='/Applications/Seek Moon/toolchain/bin':'/Applications/Seek Moon/packaged/bin':\"$PATH\"\r",
    ),
  )
  assert_eq(
    @shellenv.path_prepend_command(
      "/opt/homebrew/bin/fish",
      ["/tmp/it's\\moon/bin", "/tmp/packaged tools/bin"],
      windows=false,
    ),
    Some(
      "set -gx PATH '/tmp/it\\'s\\\\moon/bin' '/tmp/packaged tools/bin' $PATH\r",
    ),
  )
  assert_eq(
    @shellenv.path_prepend_command(
      "/bin/tcsh",
      ["/tmp/it's moon/bin", "/tmp/packaged tools/bin"],
      windows=false,
    ),
    Some(
      "setenv PATH '/tmp/it'\\''s moon/bin':'/tmp/packaged tools/bin':\"$PATH\"\r",
    ),
  )
  assert_eq(
    @shellenv.path_prepend_command(
      "/usr/local/bin/pwsh",
      ["/tmp/it's moon/bin", "/tmp/packaged tools/bin"],
      windows=false,
    ),
    Some(
      "$env:PATH = '/tmp/it''s moon/bin:/tmp/packaged tools/bin:' + $env:PATH\r",
    ),
  )
  assert_eq(
    @shellenv.path_prepend_command(
      "C:/Program Files/PowerShell/pwsh.exe",
      [
        "C:\\Users\\Moon User\\toolchain\\bin", "C:\\Program Files\\SeekMoon\\bin",
      ],
      windows=true,
    ),
    Some(
      "$env:Path = 'C:\\Users\\Moon User\\toolchain\\bin;C:\\Program Files\\SeekMoon\\bin;' + $env:Path\r",
    ),
  )
  assert_eq(
    @shellenv.path_prepend_command(
      "C:\\Windows\\System32\\cmd.exe",
      [
        "C:\\Users\\Moon User\\toolchain\\bin", "C:\\Program Files\\SeekMoon\\bin",
      ],
      windows=true,
    ),
    Some(
      "set \"Path=C:\\Users\\Moon User\\toolchain\\bin;C:\\Program Files\\SeekMoon\\bin;%Path%\"\r",
    ),
  )
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
