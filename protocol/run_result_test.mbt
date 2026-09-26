///|
/// The result files `openseek run --result-file` writes, one per status. Each
/// is the exact text `to_json` produces and reads back to the same value;
/// `docs/run-result.md` quotes the same shapes.
let run_result_fixtures : Array[(String, @openseek_protocol.RunResult)] = [
  (
    (
      #|{"version":1,"status":"completed","output":{"answer":"Fixed the parser; tests pass."},"session":"s-1","usage":{"prompt_tokens":120,"completion_tokens":30,"total_tokens":150,"prompt_cache_hit_tokens":100,"prompt_cache_miss_tokens":20},"steps":3}
    ),
    {
      request_id: None,
      kind: None,
      status: Completed(output={ "answer": "Fixed the parser; tests pass." }),
      session: Some("s-1"),
      usage: Some({
        prompt_tokens: 120,
        completion_tokens: 30,
        total_tokens: 150,
        prompt_cache_hit_tokens: 100,
        prompt_cache_miss_tokens: 20,
      }),
      steps: Some(3),
    },
  ),
  (
    (
      #|{"version":1,"status":"context_yield","reason":"[context yield] checkpointed","session":"s-1"}
    ),
    {
      request_id: None,
      kind: None,
      status: ContextYield(reason="[context yield] checkpointed"),
      session: Some("s-1"),
      usage: None,
      steps: None,
    },
  ),
  (
    (
      #|{"version":1,"status":"max_steps_exhausted"}
    ),
    {
      request_id: None,
      kind: None,
      status: MaxStepsExhausted,
      session: None,
      usage: None,
      steps: None,
    },
  ),
  (
    (
      #|{"version":1,"request_id":"r-2","kind":"explore","status":"no_report","session":"s-2","usage":{"prompt_tokens":9,"completion_tokens":1,"total_tokens":10,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":9},"steps":1}
    ),
    {
      request_id: Some("r-2"),
      kind: Some("explore"),
      status: NoReport,
      session: Some("s-2"),
      usage: Some({
        prompt_tokens: 9,
        completion_tokens: 1,
        total_tokens: 10,
        prompt_cache_hit_tokens: 0,
        prompt_cache_miss_tokens: 9,
      }),
      steps: Some(1),
    },
  ),
  (
    (
      #|{"version":1,"status":"aborted","reason":"the task is impossible"}
    ),
    {
      request_id: None,
      kind: None,
      status: Aborted(reason="the task is impossible"),
      session: None,
      usage: None,
      steps: None,
    },
  ),
  (
    (
      #|{"version":1,"status":"interrupted","reason":"cancelled"}
    ),
    {
      request_id: None,
      kind: None,
      status: Interrupted(reason="cancelled"),
      session: None,
      usage: None,
      steps: None,
    },
  ),
  (
    (
      #|{"version":1,"status":"failed","reason":"an API key is required"}
    ),
    {
      request_id: None,
      kind: None,
      status: Failed(reason="an API key is required"),
      session: None,
      usage: None,
      steps: None,
    },
  ),
]

///|
test "every result fixture is exactly what to_json writes, and reads back" {
  for fixture in run_result_fixtures {
    let (text, result) = fixture
    assert_eq(result.to_json().stringify(), text)
    assert_eq(@openseek_protocol.parse_run_result(@json.parse(text)), result)
  }
}

///|
fn run_result_error(text : String) -> @openseek_protocol.RunResultError? raise {
  let json = @json.parse(text)
  let _ = @openseek_protocol.parse_run_result(json) catch {
    error => return Some(error)
  }
  None
}

///|
test "unknown fields are ignored" {
  assert_eq(
    @openseek_protocol.parse_run_result(
      @json.parse(
        (
          #|{"version":1,"status":"max_steps_exhausted","attempt":2}
        ),
      ),
    ),
    {
      request_id: None,
      kind: None,
      status: MaxStepsExhausted,
      session: None,
      usage: None,
      steps: None,
    },
  )
}

///|
test "a result from another format version is refused, not half-read" {
  debug_inspect(
    run_result_error(
      (
        #|{"version":2,"status":"completed","output":{"answer":"ok"}}
      ),
    ),
    content="Some(UnsupportedVersion(2))",
  )
}

///|
test "malformed results name the offending field" {
  let cases = [
    ("[]", "result"),
    (
      (
        #|{"status":"completed","output":{"answer":"ok"}}
      ),
      "version",
    ),
    (
      (
        #|{"version":1.5,"status":"completed","output":{"answer":"ok"}}
      ),
      "version",
    ),
    (
      (
        #|{"version":1,"status":"blocked","reason":"needs input"}
      ),
      "status",
    ),
    (
      (
        #|{"version":1,"status":"completed","answer":"ok"}
      ),
      "output",
    ),
    (
      (
        #|{"version":1,"status":"failed"}
      ),
      "reason",
    ),
    (
      (
        #|{"version":1,"status":"failed","reason":"x","session":7}
      ),
      "session",
    ),
    (
      (
        #|{"version":1,"status":"max_steps_exhausted","usage":{"prompt_tokens":1.5,"completion_tokens":0,"total_tokens":0,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":0}}
      ),
      "usage",
    ),
    (
      (
        #|{"version":1,"status":"max_steps_exhausted","usage":{"prompt_tokens":1}}
      ),
      "usage",
    ),
    (
      (
        #|{"version":1,"status":"max_steps_exhausted","usage":{"prompt_tokens":-1,"completion_tokens":0,"total_tokens":0,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":0}}
      ),
      "usage",
    ),
  ]
  cases.push(
    (
      (
        #|{"version":1,"status":"max_steps_exhausted","steps":-1}
      ),
      "steps",
    ),
  )
  cases.push(
    (
      (
        #|{"version":1,"status":"max_steps_exhausted","steps":"3"}
      ),
      "steps",
    ),
  )
  cases.push(
    (
      (
        #|{"version":1,"status":"max_steps_exhausted","request_id":3}
      ),
      "request_id",
    ),
  )
  for case in cases {
    let (text, field) = case
    assert_eq(run_result_error(text), Some(Malformed(field)))
  }
}
