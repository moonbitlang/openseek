///|
fn quote(value : String) -> String {
  "'" + value.replace_all(old="'", new="'\\''") + "'"
}

///|
fn destination_valid(value : String) -> Bool {
  !value.is_empty() &&
  !value.has_prefix("-") &&
  !value.iter().any(ch => ch is ('\u0000'..<='\u0020' | '\u007f'))
}

///|
async fn read_marker(reader : &@io.Reader, marker : String) -> Unit {
  let pattern = @utf8.encode(marker + "\n")
  let prefixes = Array::make(pattern.length(), 0)
  let mut matched = 0
  for i = 1; i < pattern.length(); i = i + 1 {
    while matched > 0 && pattern[i] != pattern[matched] {
      matched = prefixes[matched - 1]
    }
    if pattern[i] == pattern[matched] {
      matched += 1
    }
    prefixes[i] = matched
  }
  matched = 0
  for _count = 0; _count < 65536; _count = _count + 1 {
    let byte = reader.read_exactly(1)[0]
    while matched > 0 && byte != pattern[matched] {
      matched = prefixes[matched - 1]
    }
    if byte == pattern[matched] {
      matched += 1
      if matched == pattern.length() {
        return
      }
    }
  }
  raise InstallError(
    "ssh", "Ready marker is missing or login banner exceeds 64 KiB",
  )
}

///|
async fn bounded_output(
  reader : &@io.Reader,
  limit : Int32,
  truncate~ : Bool,
) -> Bytes {
  let result = Buffer()
  while reader.read_some(max_len=65536) is Some(chunk) {
    if truncate {
      let available = Int32::min(chunk.length(), limit - result.length())
      result.write_bytes(chunk[:available])
    } else {
      guard chunk.length() <= limit - result.length() else {
        raise InstallError("ssh", "Installer output limit exceeded")
      }
      result.write_bytes(chunk)
    }
  }
  result.to_bytes()
}

///|
/// One owned SSH process. Every pipe is drained or closed on cancellation;
/// a structured success reply never overrides a failed SSH exit or upload.
async fn ssh_command(
  destination : String,
  command : String,
  ssh~ : String,
  archive? : String,
  timeout_ms~ : Int32,
) -> Json {
  guard destination_valid(destination) else {
    raise InstallError("ssh", "Invalid SSH destination")
  }
  @async.with_timeout(timeout_ms, () => {
    @async.with_task_group(group => {
      let marker = "__seekmoon_install_" + @uuid.mint() + "__"
      let payload = "printf '%s\\n' " + quote(marker) + "; exec " + command
      let (stdin, writer) = @process.write_to_process()
      let (reader, stdout) = @process.read_from_process()
      let (errors, stderr) = @process.read_from_process()
      group.add_defer(() => {
        writer.close()
        reader.close()
        errors.close()
      })
      let process = @process.spawn(
        group,
        ssh,
        [
          "-T",
          "-o",
          "BatchMode=yes",
          "-o",
          "ConnectTimeout=10",
          "-o",
          "ServerAliveInterval=15",
          "-o",
          "ServerAliveCountMax=4",
          "-o",
          "ForwardAgent=no",
          "-o",
          "ClearAllForwardings=yes",
          "--",
          destination,
          @ssh_shell.command(payload),
        ],
        stdin~,
        stdout~,
        stderr~,
        no_console_window=true,
        cancel_handler=@process.graceful_cancel(timeout=1000),
      )
      let upload = group.spawn(() => {
        defer writer.close()
        try {
          if archive is Some(path) {
            let file = @fs.open(path, mode=ReadOnly)
            defer file.close()
            writer.write_reader(file)
          }
          (None : Error?)
        } catch {
          error => Some(error)
        }
      })
      let diagnostics = group.spawn(() => {
        bounded_output(errors, 8192, truncate=true)
      })
      let output = group.spawn(() => {
        try {
          read_marker(reader, marker)
          Ok(bounded_output(reader, 1024 * 1024, truncate=false))
        } catch {
          error => {
            process.cancel()
            Err(error)
          }
        }
      })
      let code = process.wait()
      let bytes = match output.wait() {
        Ok(bytes) => bytes
        Err(error) =>
          raise InstallError(
            "ssh",
            "Invalid installer response: \{error}; " +
            @utf8.decode_lossy(diagnostics.wait()),
          )
      }
      let diagnostic = @utf8.decode_lossy(diagnostics.wait())
      let result = @json.parse(@utf8.decode(bytes)) catch {
        _ =>
          raise InstallError(
            "ssh",
            "Remote command returned no valid JSON response: " + diagnostic,
          )
      }
      guard code == 0 else {
        if result
          is {
            "ok": False,
            "stage": String(stage),
            "error": String(message),
            ..
          } {
          raise InstallError(stage, message)
        }
        raise InstallError(
          "ssh",
          "Remote process exited \{code}: " + diagnostic,
        )
      }
      if upload.wait() is Some(error) {
        raise InstallError("upload", "\{error}")
      }
      result
    })
  })
}

///|
async fn bootstrap_request(
  source : String,
  destination : String,
  request : Json,
  ssh~ : String,
  archive? : String,
) -> Json {
  let command = "python3 -c " + quote(source) + " " + quote(request.stringify())
  let reply = ssh_command(
    destination,
    command,
    ssh~,
    archive?,
    timeout_ms=if archive is Some(_) { 600000 } else { 60000 },
  )
  guard reply is { "ok": True, "result": result, .. } else {
    if reply is { "stage": String(stage), "error": String(message), .. } {
      raise InstallError(stage, message)
    }
    raise InstallError("ssh", "Invalid installer result")
  }
  result
}
