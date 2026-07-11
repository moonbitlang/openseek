///|
/// Fidelity eval: does a checkpoint summary let the next turn continue
/// accurately? For each fixture in `fixture/`:
///
/// - Tier A (facts): generate a real checkpoint over the fixture session and
///   check the summary text still carries every planted fact verbatim —
///   error codes, crash sites, versions: the details a lossy summary drops
///   first.
/// - Tier B (probes): append the summary as a real `Summary` event, then ask
///   scripted questions from the compacted projection; a probe passes when
///   the answer contains any accepted phrasing (ASCII-case-insensitive).
/// - Decay round: extend the compacted session with follow-up work and
///   checkpoint AGAIN — the second summary summarizes the first, measuring
///   the summary-of-summary decay of the original facts directly.
///
/// Each checkpoint also prints its cost row (token usage, prompt-cache
/// hit/miss, wall-clock duration) from the summary request's telemetry.
///
/// The scorecard is informational (model behavior varies run to run); the
/// eval exits non-zero only when the harness itself misbehaves. Run manually:
///
///   moon run --target native eval/compaction_fidelity
async fn main {
  // `DEEPSEEK` is the engine's API-key env var; blank means the engine would
  // reject it at startup, so both count as unset.
  guard @env.get_env_var("DEEPSEEK") is Some(key) && !key.trim().is_empty() else {
    println("SKIP: DEEPSEEK is not set; this eval drives the live model")
    return
  }
  @async.with_task_group(_group => {
    // The production checkpoint path summarizes with the session model and
    // `thinking=No`; the eval must measure that configuration, not a
    // cheaper stand-in.
    let client = @client.Client(api_key=key, thinking=No)
    for fixture in @fixture.all_fixtures() {
      run_fixture(client, fixture)
    }
  })
}

///|
async fn run_fixture(
  client : @client.Client,
  fixture : @fixture.Fixture,
) -> Unit {
  println("== fixture \{fixture.name} ==")
  let summary = @compact.generate_compaction_summary(client~, fixture.session)
  print_cost("checkpoint", summary)
  score_facts("summary", summary.content, fixture.facts)
  let compacted = fixture.session.compact(
    content=summary.content,
    from_sequence=1,
    to_sequence=fixture.session.last_sequence(),
    unix_ms=@env.now().reinterpret_as_int64(),
  )
  run_probes(client, compacted, fixture.probes)
  decay_round(client, compacted, fixture)
}

///|
/// Ask each scripted question from the compacted projection, exactly as a
/// resumed turn would see it: the summary in place of the covered events,
/// the question as the newest user message. The question is prefixed with a
/// no-tools instruction because the projection keeps the fixture's agent
/// system prompt, which tells the model to keep working — without the
/// prefix a probe can come back as tool-call markup instead of an answer
/// (the summarizer-side twin of this problem is why compaction isolates
/// its system prompt).
async fn run_probes(
  client : @client.Client,
  compacted : @agent_session.Session,
  probes : Array[@fixture.Probe],
) -> Unit {
  let mut passed = 0
  for probe in probes {
    let messages = compacted.chat_messages()
    messages.push(
      ChatMessage(
        User,
        content="Answer from the conversation context only; do not call tools. \{probe.question}",
      ),
    )
    let answer = client.chat(messages).content
    let verdict = if answer_accepted(answer, probe.accept) {
      passed += 1
      "PASS"
    } else {
      "FAIL"
    }
    println("probe \{verdict}: \{probe.question}")
    println("  -> \{answer}")
  }
  println("probes passed: \{passed}/\{probes.length()}")
}

///|
/// Second checkpoint over the compacted session plus its follow-up work: the
/// new summary can only restate the first one, so re-scoring the original
/// facts measures summary-of-summary decay.
async fn decay_round(
  client : @client.Client,
  compacted : @agent_session.Session,
  fixture : @fixture.Fixture,
) -> Unit {
  let mut extended = compacted
  for item in fixture.followup {
    extended = extended.append(item)
  }
  let second = @compact.generate_compaction_summary(client~, extended)
  print_cost("re-checkpoint", second)
  score_facts("decay round", second.content, fixture.facts)
}

///|
fn print_cost(label : String, summary : @compact.CompactionSummary) -> Unit {
  let usage = summary.usage
  println(
    "\{label}: prompt=\{usage.prompt_tokens} completion=\{usage.completion_tokens} " +
    "cache_hit=\{usage.prompt_cache_hit_tokens} cache_miss=\{usage.prompt_cache_miss_tokens} " +
    "duration_ms=\{summary.duration_ms} summary_chars=\{summary.content.length()}",
  )
}

///|
fn score_facts(
  label : String,
  summary : String,
  facts : Array[@fixture.PlantedFact],
) -> Unit {
  let mut preserved = 0
  for fact in facts {
    let verdict = if summary.contains(fact.needle) {
      preserved += 1
      "PASS"
    } else {
      "FAIL"
    }
    println("fact \{verdict} (\{label}): \{fact.label} [\{fact.needle}]")
  }
  println("facts preserved (\{label}): \{preserved}/\{facts.length()}")
}

///|
/// True when the answer contains any accepted phrasing as a standalone
/// token, compared ASCII-case-insensitively. Plain substring matching
/// scores "yes, it is now fixed" as containing "no"; the boundary check
/// rejects matches embedded in a longer word or number.
fn answer_accepted(answer : String, accept : Array[String]) -> Bool {
  let lowered = ascii_lower(answer)
  for needle in accept {
    if contains_token(lowered, ascii_lower(needle)) {
      return true
    }
  }
  false
}

///|
/// True when `needle` occurs in `haystack` delimited by non-word characters
/// or the string edges: "no" must not match inside "now" or "unknown", and
/// "cli/emit.mbt:42" must not match "cli/emit.mbt:428".
fn contains_token(haystack : String, needle : String) -> Bool {
  guard !needle.is_empty() else { return false }
  let mut base = 0
  while haystack[base:].find(needle) is Some(offset) {
    let start = base + offset
    let end = start + needle.length()
    let left_ok = start == 0 || !is_word_char(haystack[start - 1].to_int())
    let right_ok = end == haystack.length() ||
      !is_word_char(haystack[end].to_int())
    if left_ok && right_ok {
      return true
    }
    // Advance past the rejected match start by a whole code point: stepping
    // one UTF-16 unit into a surrogate pair would make the next slice panic.
    base = start +
      (if is_high_surrogate(haystack[start].to_int()) { 2 } else { 1 })
  }
  false
}

///|
fn is_high_surrogate(code : Int) -> Bool {
  code >= 0xD800 && code <= 0xDBFF
}

///|
/// Whether a UTF-16 code unit is an ASCII letter or digit.
fn is_word_char(code : Int) -> Bool {
  (code >= 'a'.to_int() && code <= 'z'.to_int()) ||
  (code >= 'A'.to_int() && code <= 'Z'.to_int()) ||
  (code >= '0'.to_int() && code <= '9'.to_int())
}

///|
fn ascii_lower(text : String) -> String {
  let buf = StringBuilder::new()
  for ch in text {
    buf.write_char(
      if ch >= 'A' && ch <= 'Z' {
        (ch.to_int() + 32).unsafe_to_char()
      } else {
        ch
      },
    )
  }
  buf.to_string()
}
