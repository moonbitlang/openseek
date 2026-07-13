// The JSON-RPC 2.0 message layer: the error a request can fail with, the
// envelope builders, and the classification the client routes inbound messages
// on. All pure (no transport), so it is unit-testable without a transport.

///|
/// Why a request did not yield a result: the peer answered with a JSON-RPC error
/// object, or the transport ended before any reply arrived.
pub(all) suberror ResponseError {
  /// The peer answered with a JSON-RPC error object, carrying its `code` and
  /// `message`.
  Failed(code~ : Int, message~ : String)
  /// The transport ended before a reply to the request arrived.
  Closed
}

///|
pub impl Show for ResponseError with fn output(self, logger) {
  match self {
    Failed(code~, message~) =>
      logger.write_string("JSON-RPC error \{code}: \{message}")
    Closed => logger.write_string("transport closed before a reply")
  }
}

///|
/// Build a request envelope with a numeric id. Numeric ids let the client
/// correlate replies by `Int` rather than carrying arbitrary id shapes.
fn build_request(id : Int, method_ : String, params : Json) -> Json {
  {
    "jsonrpc": "2.0",
    "id": Json::number(id.to_double()),
    "method": method_,
    "params": params,
  }
}

///|
/// Build a notification envelope — a request with no id, which the peer never
/// answers.
fn build_notification(method_ : String, params : Json) -> Json {
  { "jsonrpc": "2.0", "method": method_, "params": params }
}

///|
/// Build a success reply echoing a peer request's id (used to answer `ping`).
fn build_success_reply(id : Json, result : Json) -> Json {
  { "jsonrpc": "2.0", "id": id, "result": result }
}

///|
/// The JSON-RPC reserved code for an unimplemented method.
const MethodNotFound : Int = -32601

///|
/// Build a "method not found" error reply echoing a peer request's id. This
/// client advertises no capabilities, so any request the peer sends us (other
/// than `ping`) gets this — a proper JSON-RPC error rather than a misleading
/// empty success, while still answering so the peer does not block.
fn build_error_reply(id : Json) -> Json {
  {
    "jsonrpc": "2.0",
    "id": id,
    "error": {
      "code": Json::number(MethodNotFound.to_double()),
      "message": "Method not found",
    },
  }
}

///|
/// What an inbound message is, so the client can route it: a reply to one of our
/// requests (carrying the outcome to deliver), a request *from* the peer we must
/// answer, or a notification we hand to the notification handler.
priv enum Incoming {
  Reply(Int, Result[Json, ResponseError])
  // A peer-initiated request; carries the raw id to echo back and the method so
  // the client can answer `ping` with a success and everything else with an
  // error.
  PeerRequest(Json, String)
  // A peer-initiated notification: its method and params.
  Notification(String, Json)
  // Neither — malformed, or a reply with a non-numeric/non-integer id we never
  // issue.
  Unknown
}

///|
/// Classify an inbound message. A `method` field marks a request (with id) or a
/// notification (without); otherwise an `id` marks a reply.
fn classify_incoming(message : Json) -> Incoming {
  if message is { "method": String(method_), .. } {
    // JSON-RPC 2.0 defines a notification by the *omission* of `id`; a present
    // `id` — even the discouraged `null` — is a request whose reply must echo
    // that id. So any message that carries an `id` member is a peer request.
    match message {
      { "id": id, .. } => PeerRequest(id, method_)
      { "params": params, .. } => Notification(method_, params)
      _ => Notification(method_, Json::null())
    }
  } else {
    match message {
      { "id": Number(id, ..), .. } =>
        // JSON-RPC correlation requires the server to echo our exact id, and we
        // only ever issue integer ids. Accept a numeric id only when it is an
        // exact, in-range integer — `Double::to_int` truncates (1.5 -> 1) and
        // saturates out-of-range, which would misroute a reply to a real
        // pending id. A non-integer id is classified `Unknown` and dropped.
        if int_reply_id(id) is Some(reply_id) {
          Reply(reply_id, parse_outcome(message))
        } else {
          Unknown
        }
      _ => Unknown
    }
  }
}

///|
/// A numeric reply id as an `Int`, but only when it round-trips exactly (no
/// fractional part, in `Int` range). Otherwise `None`.
fn int_reply_id(id : Double) -> Int? {
  let as_int = id.to_int()
  if as_int.to_double() == id {
    Some(as_int)
  } else {
    None
  }
}

///|
/// Read the outcome of a reply. A present, non-null `error` wins (so a failure
/// is never masked as success even when a peer sends both), but an explicit
/// `error: null` alongside a result — which many hand-rolled servers emit — is
/// not a failure; a reply with neither is a successful empty result.
fn parse_outcome(message : Json) -> Result[Json, ResponseError] {
  match message {
    { "error": error, .. } if !(error is Null) => Err(parse_error(error))
    { "result": value, .. } => Ok(value)
    _ => Ok(Json::null())
  }
}

///|
/// Pull `code`/`message` out of a JSON-RPC error object, defaulting each when
/// the peer omits it.
fn parse_error(error : Json) -> ResponseError {
  let code = match error {
    { "code": Number(code, ..), .. } => code.to_int()
    _ => 0
  }
  let message = match error {
    { "message": String(message), .. } => message
    _ => ""
  }
  Failed(code~, message~)
}
