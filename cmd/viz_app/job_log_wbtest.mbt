// The waterfall's job-log pane: the reply it reads, what a follow-up page does
// to it, and the words it draws.

///|
test "a job reply yields its state, size and text" {
  let reply = parse_job_reply(
    (
      #|{"found":true,"job":{"id":"job-7","generation":"gen-1","state":{"kind":"exited","code":0},
      #|"command":"mbtx run build.mbtx","output_bytes":27,"output_file":"fg-7.out",
      #|"output_truncated":false,"invalid_utf8":false},
      #|"output":{"text":"warning: unused import\n","start_offset":0,"next_offset":27,
      #|"size":27,"head_omitted":false,"stale":false}}
    ),
  )
  guard reply is Some(Logged(log)) else { fail("expected a job log") }
  assert_eq(log.text, "warning: unused import\n")
  assert_eq(log.summary.state, "exited")
  assert_eq(log.summary.exit_code, Some(0))
  assert_eq(log.summary.command, "mbtx run build.mbtx")
  assert_eq(log.summary.output_bytes, 27L)
  assert_eq(log.summary.output_file, Some("fg-7.out"))
  assert_eq(log.problem, None)
  assert_false(log.head_omitted)
  assert_false(log.stale)
}

///|
test "a reply with no record explains itself instead of reading as an empty log" {
  let reply = parse_job_reply(
    (
      #|{"found":false,"error":"no saved record for job job-7"}
    ),
  )
  guard reply is Some(Absent(why)) else {
    fail("expected an absent job, not an empty one")
  }
  assert_eq(why, "no saved record for job job-7")
  // A body this build does not understand is neither: the caller reports a
  // failed read rather than drawing an empty block.
  let garbage = parse_job_reply("not json")
  guard garbage is None else { fail("a non-JSON body is not a job") }
  let wrong = parse_job_reply(
    (
      #|{"events":""}
    ),
  )
  guard wrong is None else { fail("a body without a job is not a job") }
}

///|
test "an unreadable output file arrives as a problem, not as a job with no text" {
  let reply = parse_job_reply(
    (
      #|{"found":true,"job":{"id":"job-7","state":{"kind":"exited","code":0}},
      #|"output":{"error":"this job kept no output file"}}
    ),
  )
  guard reply is Some(Logged(log)) else { fail("expected a job log") }
  assert_eq(log.problem, Some("this job kept no output file"))
  assert_eq(log.text, "")
}

///|
test "a follow-up page appends to what the pane already holds" {
  let first = parse_job_reply(
    (
      #|{"found":true,"job":{"id":"job-7","state":{"kind":"running"}},
      #|"output":{"text":"one\n","start_offset":0,"next_offset":4,"size":4,
      #|"head_omitted":false,"stale":false}}
    ),
  )
  guard first is Some(Logged(first)) else { fail("expected a job log") }
  let second = parse_job_reply(
    (
      #|{"found":true,"job":{"id":"job-7","state":{"kind":"running"},"output_bytes":8},
      #|"output":{"text":"two\n","start_offset":4,"next_offset":8,"size":8,
      #|"head_omitted":false,"stale":false}}
    ),
  )
  guard second is Some(Logged(second)) else { fail("expected a job log") }
  let next = job_panel_after(Shown(first), Some(4L), Logged(second))
  guard next is Shown(log) else { fail("expected the panel to stay open") }
  assert_eq(log.text, "one\ntwo\n")
  assert_eq(log.next_offset, 8L)
  // A running job keeps being asked, because it cannot know whether the file
  // grew without another read.
  assert_true(job_log_wants_more(next))
  // A finished one is not.
  let finished = parse_job_reply(
    (
      #|{"found":true,"job":{"id":"job-7","state":{"kind":"exited","code":0}},
      #|"output":{"text":"done\n","start_offset":0,"next_offset":5,"size":5,
      #|"head_omitted":false,"stale":false}}
    ),
  )
  guard finished is Some(Logged(finished)) else { fail("expected a job log") }
  assert_false(job_log_wants_more(Shown(finished)))
}

///|
test "a cursor the file outgrew puts the panel back to reading" {
  let first = parse_job_reply(
    (
      #|{"found":true,"job":{"id":"job-7","state":{"kind":"running"}},
      #|"output":{"text":"one\n","start_offset":0,"next_offset":4,"size":4,
      #|"head_omitted":false,"stale":false}}
    ),
  )
  guard first is Some(Logged(first)) else { fail("expected a job log") }
  let stale = parse_job_reply(
    (
      #|{"found":true,"job":{"id":"job-7","state":{"kind":"running"}},
      #|"output":{"text":"","start_offset":400,"next_offset":400,"size":400,
      #|"head_omitted":false,"stale":true}}
    ),
  )
  guard stale is Some(Logged(stale)) else { fail("expected a job log") }
  assert_true(
    job_panel_after(Shown(first), Some(9_999L), Logged(stale)) is Loading,
  )
}

///|
test "the job request names the job, its start and a cursor" {
  assert_eq(job_url("run", "job-7"), "/api/sessions/run/jobs/job-7")
  assert_eq(
    job_url("run 1", "job-7", start=6_000L),
    "/api/sessions/run%201/jobs/job-7?start=6000",
  )
  assert_eq(
    job_url("run", "job-7", start=6_000L, cursor=12L),
    "/api/sessions/run/jobs/job-7?start=6000&cursor=12",
  )
  // The panel key is the job, so the job's own row and the wait that blocked
  // on it share one log.
  assert_eq(job_panel_key("run", "job-7"), "run/job-7")
  assert_eq(job_id_of_key("run/job-7"), "job-7")
}

///|
test "a job's header reads its state, exit code and size" {
  assert_eq(job_state_label("exited", Some(0)), "exited 0")
  assert_eq(job_state_label("exited", Some(3)), "exited 3")
  assert_eq(job_state_label("running", None), "running")
  assert_eq(job_state_label("interrupted", None), "interrupted")
  assert_eq(job_bytes_label(0L), "0 B")
  assert_eq(job_bytes_label(1_024L), "1 KB")
  assert_eq(job_bytes_label(4_200_000L), "4 MB")
  assert_eq(job_bytes_label(11_264L), "11 KB")
}

///|
test "a duplicate poll cursor does not append the same chunk twice" {
  let first = parse_job_reply(
    (
      #|{"found":true,"job":{"id":"job-7","state":{"kind":"running"}},
      #|"output":{"text":"one\n","start_offset":0,"next_offset":4,"size":4,
      #|"head_omitted":false,"stale":false}}
    ),
  )
  guard first is Some(Logged(first)) else { fail("expected a job log") }
  let second = parse_job_reply(
    (
      #|{"found":true,"job":{"id":"job-7","state":{"kind":"running"}},
      #|"output":{"text":"two\n","start_offset":4,"next_offset":8,"size":8,
      #|"head_omitted":false,"stale":false}}
    ),
  )
  guard second is Some(Logged(second)) else { fail("expected a job log") }
  let advanced = job_panel_after(Shown(first), Some(4L), Logged(second))
  // A late reply carrying the old cursor=4 must not append "two\n" again.
  let duplicate = job_panel_after(advanced, Some(4L), Logged(second))
  guard duplicate is Shown(log) else { fail("expected shown panel") }
  assert_eq(log.text, "one\ntwo\n")
}
