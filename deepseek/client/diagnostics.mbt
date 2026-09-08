///|
priv enum RequestPhase {
  Connect
  WriteRequest
  ResponseHeaders
  ResponseBody
  Sse(SseProgress)
  Decode(event_count~ : Int, last_event_at~ : Int64?)
}

///|
priv struct SseProgress {
  mut event_count : Int
  mut last_event_at : Int64?
  mut buffered_data : Bool
}

///|
priv enum RetryStopReason {
  StreamStarted
  NotRetryable
  AttemptsExhausted
}

///|
/// Per-request observations used to enrich the final error message. The
/// elapsed clock spans all attempts and backoff. Never retain request contents.
priv struct RequestProgress {
  started_at : Int64
  mut attempts : Int
  mut phase : RequestPhase
  mut http_status : Int?
  mut stop_reason : RetryStopReason
}

///|
fn RequestProgress::RequestProgress() -> RequestProgress {
  {
    started_at: @async.now(),
    attempts: 0,
    phase: Connect,
    http_status: None,
    stop_reason: AttemptsExhausted,
  }
}

///|
fn RequestProgress::begin_attempt(self : Self) -> Unit {
  self.attempts += 1
  self.phase = Connect
  self.http_status = None
  self.stop_reason = AttemptsExhausted
}

///|
/// Whether the current attempt received any SSE event (or part of one). The
/// completion is then running and billed, so replaying it is unsafe unless the
/// consumer promised to discard what it already received.
fn RequestProgress::streamed(self : Self) -> Bool {
  match self.phase {
    Sse(sse) => sse.event_count > 0 || sse.buffered_data
    Decode(event_count~, ..) => event_count > 0
    Connect | WriteRequest | ResponseHeaders | ResponseBody => false
  }
}

///|
/// One line naming what went wrong, for both the final failure message and
/// the retry notice. Preserves the original payload, including errors not
/// classified here.
fn error_detail(error : Error) -> String {
  match error {
    IdleTimeout(context, timeout_ms) =>
      "Request idle for \{timeout_ms} ms: \{context}"
    HttpStatusError(code, body) => "HTTP \{code}: \{body}"
    StreamEnded => "Stream ended before [DONE]"
    StreamTransport(cause) => "Stream transport error: \{@debug.Repr(cause)}"
    @http.IncorrectBodyLength => "HTTP response body length mismatch"
    error => "\{@debug.Repr(error)}"
  }
}

///|
fn RequestProgress::failure_message(
  self : Self,
  client : Client,
  error : Error,
) -> String {
  let detail = error_detail(error)
  let reason = match self.stop_reason {
    StreamStarted => "Not retried because response data was already received."
    NotRetryable => "This error cannot be retried automatically."
    AttemptsExhausted => "The retry limit was reached."
  }
  let phase = match self.phase {
    Connect => "connect"
    WriteRequest => "write_request"
    ResponseHeaders => "response_headers"
    ResponseBody => "response_body"
    Sse(_) => "sse_read"
    Decode(..) => "decode"
  }
  let message = StringBuilder()
  message.write_string("Model request failed: \{detail}. \{reason}")
  message.write_string(
    " Model: \{client.model}; stage: \{phase}; attempts: \{self.attempts}/\{client.retry_attempts.max(1)}; elapsed: \{(@async.now() - self.started_at).max(0)} ms",
  )
  if self.http_status is Some(status) {
    message.write_string("; HTTP status: \{status}")
  }
  let last_event_at = match self.phase {
    Sse(sse) => {
      message.write_string(
        "; stream events: \{sse.event_count}; buffered event: \{sse.buffered_data}",
      )
      sse.last_event_at
    }
    Decode(event_count~, last_event_at~) => {
      message.write_string("; stream events: \{event_count}")
      last_event_at
    }
    Connect | WriteRequest | ResponseHeaders | ResponseBody => None
  }
  if last_event_at is Some(at) {
    message.write_string("; last event: \{(@async.now() - at).max(0)} ms ago")
  }
  message.to_string()
}
