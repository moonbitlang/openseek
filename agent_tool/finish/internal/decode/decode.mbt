///|
/// Decoded arguments of the `finish` control tool: the final answer the agent
/// ends its run with.
pub struct FinishInput {
  answer : String
} derive(Debug)

///|
/// Decode `finish` tool-call arguments.
///
/// Lenient by design: `finish` ends the run, so a missing or non-string
/// `answer` becomes an empty answer rather than an error that would keep an
/// otherwise completed run alive.
pub fn decode(arguments : Json) -> FinishInput {
  let answer = match arguments {
    { "answer": String(answer), .. } => answer
    _ => ""
  }
  { answer, }
}
