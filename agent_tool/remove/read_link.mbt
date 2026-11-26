///|
/// async/fs exposes lstat and unlink but no readlink. Keep the raw output so
/// different target spellings (including trailing newlines) stay distinct.
async fn read_link_target(location : String) -> Bytes {
  if @path.sep == '\\' {
    return read_windows_link_target(location)
  }
  // Use the system utility even when the session runs with a workspace PATH.
  let program = if @fs.exists("/usr/bin/readlink") {
    "/usr/bin/readlink"
  } else if @fs.exists("/bin/readlink") {
    "/bin/readlink"
  } else {
    "/system/bin/readlink"
  }
  let result = @process.run(program, ["-n", location], stdout=Collect, accepted_exit_code=code => {
    code == 0
  })
  result.stdout_binary()
}

///|
async fn read_windows_link_target(location : String) -> Bytes {
  let script =
    #|$ErrorActionPreference = 'Stop'
    #|$target = @((Get-Item -Force -LiteralPath $env:OPENSEEK_LINK_PATH).Target)
    #|if ($target.Count -ne 1 -or $null -eq $target[0]) { throw 'Cannot read symbolic link target' }
    #|$bytes = [Text.Encoding]::Unicode.GetBytes([string]$target[0])
    #|[Console]::OpenStandardOutput().Write($bytes, 0, $bytes.Length)
  guard @env.get_env_var("SystemRoot") is Some(root) else {
    fail("Missing SystemRoot")
  }
  let result = @process.run(
    "\{root}/System32/WindowsPowerShell/v1.0/powershell.exe",
    ["-NoProfile", "-NonInteractive", "-Command", script],
    extra_env={ "OPENSEEK_LINK_PATH": location },
    no_console_window=true,
    stdout=Collect,
    accepted_exit_code=code => code == 0,
  )
  result.stdout_binary()
}
