///|
/// `ExploreReport` is the bounded, citation-carrying answer an explore child
/// submits. Every bound here is load-bearing: the rendered result must stay
/// far below the loop's 60K tool-result clamp AND keep the parent's
/// char-denominated batch budget honest, so validation — not hope — caps
/// every field and count.

///|
/// The schema version this build emits and accepts.
let current_schema_version : Int = 1

///|
/// Field and count ceilings, enforced by `validate`.
let max_answer_chars : Int = 8_000

///|
/// Citation-count ceiling, enforced by `validate`.
let max_citations : Int = 20

///|
/// Per-citation file-path length ceiling.
let max_citation_file_chars : Int = 300

///|
/// Per-citation note length ceiling.
let max_citation_note_chars : Int = 200

///|
/// `unresolved` length ceiling.
let max_unresolved_chars : Int = 1_000

///|
/// One supporting reference: a workspace `file:line`, or the source/`.mbti`
/// path `moon ide doc` reported for a stdlib or dependency claim.
struct Citation {
  file : String
  line : Int?
  note : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// The child's full answer. `unresolved` names what it could NOT determine —
/// stated ignorance beats a fabricated claim.
pub struct ExploreReport {
  priv schema_version : Int
  answer : String
  citations : Array[Citation]
  priv unresolved : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Validate a report against the contract. Returns the list of problems; an
/// empty list means the report is valid. The `submit_answer` capture tool
/// uses this to reject oversized or empty output so the model retries with
/// a bounded report instead of finishing with an unusable one.
fn ExploreReport::validate(self : ExploreReport) -> Array[String] {
  let problems : Array[String] = []
  if self.schema_version != current_schema_version {
    problems.push(
      "schema_version must be \{current_schema_version}, got \{self.schema_version}",
    )
  }
  if self.answer.is_blank() {
    problems.push("answer must not be empty")
  }
  if self.answer.length() > max_answer_chars {
    problems.push(
      "answer exceeds \{max_answer_chars} chars (\{self.answer.length()}); tighten it",
    )
  }
  if self.citations.length() > max_citations {
    problems.push(
      "at most \{max_citations} citations (\{self.citations.length()} given); keep the strongest",
    )
  }
  for citation in self.citations {
    if citation.file == "" {
      problems.push("a citation has an empty file path")
    }
    if citation.file.length() > max_citation_file_chars {
      problems.push(
        "a citation file path exceeds \{max_citation_file_chars} chars",
      )
    }
    if citation.note is Some(note) && note.length() > max_citation_note_chars {
      problems.push("a citation note exceeds \{max_citation_note_chars} chars")
    }
  }
  if self.unresolved is Some(unresolved) &&
    unresolved.length() > max_unresolved_chars {
    problems.push("unresolved exceeds \{max_unresolved_chars} chars")
  }
  problems
}

///|
/// Parse a report from JSON, returning the report or a human-readable error.
fn ExploreReport::parse(json : Json) -> Result[ExploreReport, String] {
  let report : ExploreReport = @json.from_json(json) catch {
    e => return Err("invalid explore report JSON: \{e}")
  }
  Ok(report)
}

///|
fn sample_report() -> ExploreReport {
  {
    schema_version: 1,
    answer: "Use @buffer.new(size_hint?) and Buffer::to_bytes.",
    citations: [
      { file: "protocol/event.mbt", line: Some(14), note: Some("Event enum"), },
      { file: "moonbitlang/core/buffer", line: None, note: None, },
    ],
    unresolved: Some("did not check the js backend"),
  }
}

///|
test "explore report round-trips through json" {
  let report = sample_report()
  guard ExploreReport::parse(ToJson::to_json(report)) is Ok(parsed) else {
    fail("parse failed")
  }
  assert_eq(parsed, report)
}

///|
test "validate accepts a good report" {
  assert_eq(sample_report().validate().length(), 0)
}

///|
test "validate rejects empties and oversizes" {
  assert_true({ ..sample_report(), answer: "  ", }.validate().length() > 0)
  assert_true({ ..sample_report(), schema_version: 2, }.validate().length() > 0)
  let long = "a".repeat(max_answer_chars + 1)
  assert_true({ ..sample_report(), answer: long, }.validate().length() > 0)
  let many : Array[Citation] = []
  for i in 0..<=max_citations {
    many.push({ file: "f\{i}.mbt", line: None, note: None, })
  }
  assert_true({ ..sample_report(), citations: many, }.validate().length() > 0)
  assert_true(
    { ..sample_report(), citations: [{ file: "", line: None, note: None, }], }
    .validate()
    .length() >
    0,
  )
}

///|
test "parse reports an error on malformed json" {
  guard ExploreReport::parse(Json::null()) is Err(_) else {
    fail("expected parse error")
  }
}

///|
pub extend Citation with Eq::{not_equal, equal}

///|
pub extend Citation with Debug::{to_repr}

///|
pub extend Citation with ToJson::{to_json}

///|
pub extend Citation with FromJson::{from_json}

///|
pub extend ExploreReport with Eq::{not_equal, equal}

///|
pub extend ExploreReport with Debug::{to_repr}

///|
pub extend ExploreReport with ToJson::{to_json}

///|
pub extend ExploreReport with FromJson::{from_json}
