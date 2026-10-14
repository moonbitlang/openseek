// What `seekmoon` needs of the host's server, whichever way it is serving
// the host's tools: how a run of the command ends, and how one message is
// sent.

///|
/// What one run of the command came to: what it would print, and its exit
/// status. `code` is 2 for a command line that could not be run at all.
pub(all) struct CliOutcome {
  code : Int32
  stdout : String
  stderr : String
}

///|
/// The host could not be asked, or refused.
priv suberror Unavailable {
  Unavailable(String)
}

///|
/// What the command says when its environment holds no grant.
fn ungranted_message() -> String {
  "seekmoon talks to the SeekMoon desktop app that started this agent, and nothing here was started by one (\{UrlEnv} and \{TokenEnv} are not set)."
}

///|
/// The JSON-RPC error code for a request the host could not be asked: from
/// the range the protocol leaves to implementations.
const HostUnavailable : Int32 = -32000

///|
/// POST one JSON-RPC message to the server as written, returning its reply,
/// or `None` when the server accepted it and has nothing to say back.
async fn post_message(url : String, token : String, body : String) -> Json? {
  let (response, reply) = @http.post(url, body, headers={
    "Content-Type": "application/json",
    "Authorization": "Bearer \{token}",
  }) catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      raise Unavailable("could not reach the SeekMoon desktop app: \{error}")
  }
  match response.code {
    200 => Some(reply.json())
    202 => None
    // A token the server does not know is one from an earlier launch: the
    // app restarted under an agent that is still running.
    code =>
      raise Unavailable(
        "the SeekMoon desktop app refused the request (HTTP \{code}); it may have restarted since this agent started",
      )
  }
}
