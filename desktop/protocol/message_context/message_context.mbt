// Tagged context shared by host delivery and transcript presentation. Agent
// message bodies stay verbatim, with closing tags anchored at the end. Question
// responses escape their nested text as well as attributes (see question_response).

///|
pub(all) enum Context {
  Message(source_session~ : String, message_id~ : String, text~ : String)
  DeliveryResult(
    message_id~ : String,
    request_id~ : String,
    target~ : String,
    status~ : String,
    error~ : String?
  )
  UserQuestionResponse(
    request_id~ : String,
    questions~ : Array[@protocol.UserQuestion],
    answers~ : Map[String, String]?
  )
} derive(Eq, Debug)

///|
pub extend Context with Eq::{equal, not_equal}

///|
pub extend Context with @debug.Debug::{to_repr}

///|
fn attribute(text : String) -> String {
  let output = StringBuilder()
  for char in text {
    match char {
      '&' => output.write_string("&amp;")
      '"' => output.write_string("&quot;")
      '<' => output.write_string("&lt;")
      '>' => output.write_string("&gt;")
      '\r' => output.write_string("&#13;")
      '\n' => output.write_string("&#10;")
      _ => output.write_char(char)
    }
  }
  output.to_string()
}

///|
fn decode_attribute(text : StringView) -> String {
  let output = StringBuilder()
  for rest = text {
    let (char, tail) = match rest {
      [.. "&quot;", .. tail] => ('"', tail)
      [.. "&lt;", .. tail] => ('<', tail)
      [.. "&gt;", .. tail] => ('>', tail)
      [.. "&#13;", .. tail] => ('\r', tail)
      [.. "&#10;", .. tail] => ('\n', tail)
      [.. "&amp;", .. tail] => ('&', tail)
      [char, .. tail] => (char, tail)
      [] => break
    }
    output.write_char(char)
    continue tail
  }
  output.to_string()
}

///|
pub fn Context::encode(self : Context) -> String {
  match self {
    Message(source_session~, message_id~, text~) =>
      (
        $|<agent_message source_session="\{attribute(source_session)}" message_id="\{attribute(message_id)}">
        $|\{text}
        $|</agent_message>
      )
    DeliveryResult(message_id~, request_id~, target~, status~, error~) =>
      (
        $|<session_message_result message_id="\{attribute(message_id)}" request_id="\{attribute(request_id)}" target="\{attribute(target)}" status="\{attribute(status)}">
        $|\{error.unwrap_or("")}
        $|</session_message_result>
      )
    UserQuestionResponse(request_id~, questions~, answers~) =>
      encode_question_response(request_id, questions, answers)
  }
}

///|
/// Recognize only a complete envelope, never a partial tag inside prose.
pub fn parse(content : String) -> Context? {
  let content = content.trim()
  if content is [.. "<agent_message source_session=\"", .. rest] &&
    rest.split_once("\" message_id=\"") is Some((source, rest)) &&
    rest.split_once("\">\n") is Some((id, rest)) &&
    rest is [.. text, .. "\n</agent_message>"] &&
    !source.contains("\"") &&
    !id.contains("\"") {
    return Some(
      Message(
        source_session=decode_attribute(source),
        message_id=decode_attribute(id),
        text=text.to_owned(),
      ),
    )
  }
  if content is [.. "<session_message_result message_id=\"", .. rest] &&
    rest.split_once("\" request_id=\"") is Some((id, rest)) &&
    rest.split_once("\" target=\"") is Some((request, rest)) &&
    rest.split_once("\" status=\"") is Some((target, rest)) &&
    rest.split_once("\">\n") is Some((status, rest)) &&
    rest is [.. error, .. "\n</session_message_result>"] &&
    !id.contains("\"") &&
    !request.contains("\"") &&
    !target.contains("\"") &&
    !status.contains("\"") {
    return Some(
      DeliveryResult(
        message_id=decode_attribute(id),
        request_id=decode_attribute(request),
        target=decode_attribute(target),
        status=decode_attribute(status),
        error=if error.is_empty() { None } else { Some(error.to_owned()) },
      ),
    )
  }
  parse_question_response(content)
}
