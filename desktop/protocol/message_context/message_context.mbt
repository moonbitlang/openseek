// Tagged context shared by host delivery and transcript presentation. As with
// user_shell_command, bodies stay verbatim for the model; attributes are escaped.
// Closing tags are anchored at the end, so tags inside a message stay its text.

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
} derive(Eq, Debug)

///|
pub extend Context with Eq::{equal, not_equal}

///|
pub extend Context with @debug.Debug::{to_repr}

///|
fn attribute(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\r", new="&#13;")
  .replace_all(old="\n", new="&#10;")
}

///|
fn decode_attribute(text : StringView) -> String {
  text
  .to_owned()
  .replace_all(old="&quot;", new="\"")
  .replace_all(old="&lt;", new="<")
  .replace_all(old="&gt;", new=">")
  .replace_all(old="&#13;", new="\r")
  .replace_all(old="&#10;", new="\n")
  .replace_all(old="&amp;", new="&")
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
  None
}
