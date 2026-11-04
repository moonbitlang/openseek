///|
async test "append writes one JSON line per record" {
  let dir = @fs.tmpdir(prefix="openseek-log-file-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/desktop.log"
  let file = @log_file.LogFile::open(path)
  file.append({ "level": "INFO", "message": "start" })
  file.append({ "level": "WARN", "message": "line\nbreak" })
  assert_eq(
    @fs.read_file(path).text(),
    "{\"level\":\"INFO\",\"message\":\"start\"}\n{\"level\":\"WARN\",\"message\":\"line\\nbreak\"}\n",
  )
}

///|
async test "a second handle appends after the first instead of truncating" {
  let dir = @fs.tmpdir(prefix="openseek-log-file-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/desktop.log"
  let host = @log_file.LogFile::open(path)
  host.append({ "who": "host" })
  let child = @log_file.LogFile::open(path)
  child.append({ "who": "child" })
  host.append({ "who": "host again" })
  assert_eq(
    @fs.read_file(path).text(),
    "{\"who\":\"host\"}\n{\"who\":\"child\"}\n{\"who\":\"host again\"}\n",
  )
}

///|
async test "opening inside a missing directory fails" {
  let dir = @fs.tmpdir(prefix="openseek-log-file-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/missing/desktop.log"
  let failed = try {
    ignore(@log_file.LogFile::open(path))
    None
  } catch {
    OpenFailed(failed) => Some(failed)
    error => raise error
  }
  assert_eq(failed, Some(path))
}
