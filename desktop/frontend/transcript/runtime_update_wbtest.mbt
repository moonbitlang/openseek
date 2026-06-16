///|
test "parse runtime update strips moon_check metadata" {
  let update = parse_runtime_update(
    "[moon_check update]\nevents=3\nid=moon-check-1\ncwd=.\ncommand=moon check --watch --diagnostic-limit 10\nstatus=running\nseq=3\nWarning: unused variable x\nFinished.",
  )
  inspect(update.status, content="running")
  inspect(
    update.diagnostics.join("|"),
    content="Warning: unused variable x|Finished.",
  )
}

///|
test "parse runtime update keeps diagnostic assignment lines" {
  let update = parse_runtime_update(
    "[moon_check update]\nstatus=running\nlet buf = Buffer()\nFinished.",
  )
  inspect(update.status, content="running")
  inspect(update.diagnostics.join("|"), content="let buf = Buffer()|Finished.")
}
