///|
async test "lines are appended after existing content, in order" {
  let dir = @fs.tmpdir(prefix="openseek-log-file-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/desktop.log"
  @fs.write_file(path, "{\"earlier\":true}\n", create_mode=CreateNew)
  @log_file.with_log_file(path, log => {
    log.append({ "level": "INFO", "message": "start" })
    log.append({ "level": "WARN", "message": "line\nbreak" })
  })
  assert_eq(
    @fs.read_file(path).text(),
    "{\"earlier\":true}\n{\"level\":\"INFO\",\"message\":\"start\"}\n{\"level\":\"WARN\",\"message\":\"line\\nbreak\"}\n",
  )
}

///|
async test "lines queued before the body fails are still written" {
  let dir = @fs.tmpdir(prefix="openseek-log-file-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/desktop.log"
  let raised = try {
    @log_file.with_log_file(path, log => {
      log.append({ "message": "before failure" })
      fail("startup failed")
    })
    false
  } catch {
    Failure(_) => true
    error => raise error
  }
  assert_true(raised)
  assert_eq(@fs.read_file(path).text(), "{\"message\":\"before failure\"}\n")
}

///|
async test "two writers share the file without losing lines" {
  let dir = @fs.tmpdir(prefix="openseek-log-file-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/desktop.log"
  @log_file.with_log_file(path, host => {
    @log_file.with_log_file(path, child => {
      for i in 0..<50 {
        host.append({ "who": "host", "i": i })
        child.append({ "who": "child", "i": i })
      }
    })
  })
  let lines = @fs.read_file(path).text().split("\n").to_array()
  assert_eq(lines.length(), 101)
  assert_eq(lines.filter(line => line.contains("\"host\"")).length(), 50)
  assert_eq(lines.filter(line => line.contains("\"child\"")).length(), 50)
}

///|
async test "appending after the file is closed raises" {
  let dir = @fs.tmpdir(prefix="openseek-log-file-")
  defer @fs.rmdir(dir, recursive=true)
  let mut kept = None
  @log_file.with_log_file("\{dir}/desktop.log", log => kept = Some(log))
  guard kept is Some(log) else { fail("body did not run") }
  let raised = try {
    log.append({ "message": "late" })
    false
  } catch {
    _ => true
  }
  assert_true(raised)
}
