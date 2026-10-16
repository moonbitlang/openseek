///|
fn encode_question_response(
  request_id : String,
  questions : Array[@protocol.UserQuestion],
  answers : Map[String, String]?,
) -> String {
  let status = if answers is Some(_) { "answered" } else { "skipped" }
  let output = StringBuilder()
  output.write_string(
    "<user_question_response request_id=\"\{attribute(request_id)}\" status=\"\{status}\">\n",
  )
  for question in questions {
    output.write_string("<question id=\"\{attribute(question.id)}\">\n")
    output.write_string("<title>\{attribute(question.title)}</title>\n")
    if question.options is Some(options) {
      output.write_string("<options>\n")
      for option in options {
        output.write_string("<option>\{attribute(option)}</option>\n")
      }
      output.write_string("</options>\n")
    }
    if answers is Some(answers) && answers.get(question.id) is Some(answer) {
      output.write_string("<answer>\{attribute(answer)}</answer>\n")
    }
    output.write_string("</question>\n")
  }
  output.write_string("</user_question_response>")
  output.to_string()
}

///|
/// Parse the canonical envelope emitted by the host. Text nodes are escaped,
/// so a user's literal closing tag cannot terminate a question or an answer.
/// Incomplete/malformed envelopes fall back to the ordinary transcript text.
fn parse_question_response(content : StringView) -> Context? {
  guard content is [.. "<user_question_response request_id=\"", .. rest] &&
    rest.split_once("\" status=\"") is Some((request_id, rest)) &&
    rest.split_once("\">\n") is Some((status, rest)) &&
    rest is [.. body, .. "</user_question_response>"] &&
    !request_id.contains("\"") &&
    status is ("answered" | "skipped") else {
    return None
  }
  let questions : Array[@protocol.UserQuestion] = []
  let answers : Map[String, String] = Map([])
  let ids : Map[String, Unit] = Map([])
  for rest = body; !rest.is_empty(); {
    guard rest is [.. "<question id=\"", .. rest] &&
      rest.split_once("\">\n<title>") is Some((id, rest)) &&
      !id.contains("\"") &&
      rest.split_once("</title>\n") is Some((title, rest)) &&
      !title.contains("<") else {
      return None
    }
    let id = decode_attribute(id)
    let title = decode_attribute(title)
    guard !id.is_blank() && !title.is_blank() && !ids.contains(id) else {
      return None
    }
    ids[id] = ()
    let (options, rest) = if rest is [.. "<options>\n", .. rest] {
      let options : Array[String] = []
      let tail = for rest = rest {
        if rest is [.. "</options>\n", .. tail] {
          break tail
        }
        guard rest is [.. "<option>", .. rest] &&
          rest.split_once("</option>\n") is Some((option, tail)) &&
          !option.contains("<") else {
          return None
        }
        let option = decode_attribute(option)
        guard !option.is_blank() else { return None }
        options.push(option)
        continue tail
      }
      (Some(options), tail)
    } else {
      (None, rest)
    }
    let rest = if status == "answered" {
      guard rest is [.. "<answer>", .. rest] &&
        rest.split_once("</answer>\n") is Some((answer, tail)) &&
        !answer.contains("<") else {
        return None
      }
      let answer = decode_attribute(answer)
      guard !answer.is_blank() else { return None }
      answers[id] = answer
      tail
    } else {
      rest
    }
    guard rest is [.. "</question>\n", .. tail] else { return None }
    questions.push({ id, title, options, })
    continue tail
  }
  guard !questions.is_empty() else { return None }
  Some(
    UserQuestionResponse(
      request_id=decode_attribute(request_id),
      questions~,
      answers=if status == "answered" { Some(answers) } else { None },
    ),
  )
}
