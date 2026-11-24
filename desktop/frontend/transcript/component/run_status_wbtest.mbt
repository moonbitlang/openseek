///|
test "the heartbeat reports only the detail it actually has" {
  let clock_ms = 1_000_000.0
  let full : @transcript.RunHeartbeat = {
    stage: Thinking,
    step: None,
    started_ms: Some(clock_ms - 134_000.0),
    tokens: 12_345,
  }
  assert_eq(
    run_status_label(English, full, clock_ms),
    "Thinking… (2m 14s · 12.3k tokens)",
  )
  assert_eq(
    run_status_label(SimplifiedChinese, full, clock_ms),
    "正在思考… (2m 14s · 12.3k 个词元)",
  )
  assert_eq(
    run_status_label(English, { ..full, started_ms: None, }, clock_ms),
    "Thinking… (12.3k tokens)",
  )
  assert_eq(
    run_status_label(English, { ..full, tokens: 0, }, clock_ms),
    "Thinking… (2m 14s)",
  )
  assert_eq(
    run_status_label(
      English,
      { ..full, started_ms: None, tokens: 0, },
      clock_ms,
    ),
    "Thinking…",
  )
  assert_eq(
    run_status_label(English, { ..full, started_ms: Some(clock_ms), }, clock_ms),
    "Thinking… (12.3k tokens)",
  )
  assert_eq(run_stage_label(English, Starting), "Starting…")
  assert_eq(
    run_status_label(
      English,
      { stage: Working, step: Some(3), started_ms: None, tokens: 0, },
      clock_ms,
    ),
    "Working · step 3",
  )
  assert_eq(
    run_stage_label(
      English,
      Retrying(attempt=2, max_attempts=5, reason="Stream ended before [DONE]"),
    ),
    "Retrying · attempt 2/5 · Stream ended before [DONE]",
  )
  assert_eq(run_stage_label(English, Working), "Working…")
  assert_eq(run_stage_label(English, Stopping), "Stopping…")
}
