///|
const DeepSeekDefaultApiUrl : String = "https://api.deepseek.com/chat/completions"

///|
const KimiDefaultApiUrl : String = "https://api.moonshot.cn/v1/chat/completions"

///|
const GlmDefaultApiUrl : String = "https://api.z.ai/api/paas/v4/chat/completions"

///|
let default_model : @deepseek.Model = Deepseek(V4Pro)

///|
fn default_api_url_for_model(model : @deepseek.Model) -> String {
  match model {
    Kimi(_) => KimiDefaultApiUrl
    Glm(_) => GlmDefaultApiUrl
    Deepseek(_) => DeepSeekDefaultApiUrl
  }
}

///|
type API_KEY = String

///|
/// HTTP client for the DeepSeek chat completions API.
pub struct Client {
  priv api_key : API_KEY
  model : @deepseek.Model
  api_url : String
  thinking : @deepseek.ThinkingMode
  retry_attempts : Int
  retry_backoff_ms : Int
  idle_timeout_ms : Int
} derive(Debug(ignore=API_KEY))

///|
/// Constructs a DeepSeek HTTP client.
///
/// `model` defaults to `deepseek-v4-pro`; `api_url` defaults to the DeepSeek
/// endpoint, or the Kimi endpoint for Kimi models. `thinking` defaults to
/// `No`; pass `High` or `Max` to enable DeepSeek V4 thinking mode explicitly.
///
/// Transient failures — transport errors, HTTP 429, and 5xx — are retried up
/// to `retry_attempts` total tries with exponential backoff starting at
/// `retry_backoff_ms` (doubling per retry, capped at 60s). Client errors
/// other than 429 never retry, and a streaming call never retries once the
/// stream has produced any event — text, tool-call, or usage alike.
///
/// `idle_timeout_ms` bounds how long a streaming request may sit with no
/// progress: it caps both the wait for response headers and the wait between
/// SSE events. A silent stall (a connection the peer accepts then never feeds,
/// which TCP alone will not surface for a long time) trips it, and the stall is
/// converted to the same retryable class as a mid-stream drop — so a stall
/// before any event is retried on a fresh connection, while one after output
/// bails to a clean failure rather than duplicating a half-consumed completion.
/// The bound is measured per read — the header line, then each SSE event line —
/// so it resets on every event, not on every byte: a stream that keeps
/// delivering events never trips it. (The clock therefore covers one whole line;
/// with real DeepSeek deltas, which are small and sub-second apart, a single
/// line never approaches the default anyway.) Pass `0` (or less) to disable.
/// Defaults to 120s; it applies to the streaming path only (the mode the agent
/// and TUI use).
pub fn Client::Client(
  api_key~ : String,
  model? : @deepseek.Model = default_model,
  api_url? : String = default_api_url_for_model(model),
  thinking? : @deepseek.ThinkingMode = No,
  retry_attempts? : Int = 5,
  retry_backoff_ms? : Int = 500,
  idle_timeout_ms? : Int = 120_000,
) -> Client {
  {
    api_key,
    model,
    api_url,
    thinking,
    retry_attempts,
    retry_backoff_ms,
    idle_timeout_ms,
  }
}

///|
/// Callback hooks for a streaming DeepSeek chat request.
///
/// `on_content_delta` is called for each assistant content fragment as it
/// arrives; `on_reasoning_delta` likewise for each thinking-mode reasoning
/// fragment (it is simply not called when thinking is off).
///
/// Supplying `on_retry` explicitly says that the consumer can discard every
/// fragment from a failed attempt. When such an attempt emitted an SSE event,
/// the callback runs immediately before the next request starts, with the
/// 1-based attempt number, the total attempt budget, and the previous failure.
/// A pre-event retry needs no discard boundary and remains silent. Without the
/// callback, a failure after any SSE event keeps the conservative no-replay
/// behavior. `Client::chat` returns the fully accumulated response only after
/// one attempt reaches `[DONE]`.
pub struct StreamHandler {
  priv on_content_delta : async (String) -> Unit
  priv on_reasoning_delta : async (String) -> Unit
  priv on_retry : ((Int, Int, String) -> Unit)?
}

///|
/// Constructs callbacks for `Client::chat(..., stream=...)`.
pub fn StreamHandler::StreamHandler(
  on_content_delta~ : async (String) -> Unit,
  on_reasoning_delta? : async (String) -> Unit = _ => (),
  on_retry? : (Int, Int, String) -> Unit,
) -> StreamHandler {
  { on_content_delta, on_reasoning_delta, on_retry, }
}

///|
/// A response status worth retrying: rate limiting or a server-side failure.
/// Other 4xx are caller errors (bad key, malformed request) that a retry
/// cannot fix.
fn retryable_status(code : Int) -> Bool {
  code == 429 || (code >= 500 && code < 600)
}

///|
/// These failures may be retried before any response data is received.
/// The public chat boundary formats them as Failure messages.
priv suberror RetryableApiError {
  HttpStatusError(Int, String)
  IdleTimeout(String, Int)
  StreamEnded
  StreamTransport(String)
}

///|
/// Ceiling on a single backoff sleep. The doubling sequence from
/// `retry_backoff_ms` stops growing here — but this bounds each sleep, not
/// their sum, which stays a geometric series: raising `retry_attempts` buys
/// tries at superlinear wall-clock cost (from 500ms, 5 tries sleep 7.5s and
/// 10 sleep 183.5s).
let max_backoff_ms : Int = 60_000

///|
/// Run `attempt` up to `retry_attempts` total tries via `@async.retry`
/// (exponential backoff doubling from `retry_backoff_ms`, capped at
/// `max_backoff_ms`; `max_retry` counts restarts, hence the -1).
///
/// Cancellations, non-retryable HTTP statuses, malformed responses, plain
/// failures, and malformed-api_url parse errors propagate immediately;
/// anything else is transport-shaped (connect refused, reset, DNS) and
/// retries within budget. `bail` lets an attempt declare later retries
/// pointless based on the error it raised. Streaming chat uses that to keep
/// post-event replay disabled unless its handler explicitly opted in, and even
/// then permits only transport, EOF, and idle-timeout failures.
///
/// Errors propagate with their types intact. The chat boundary observes the
/// final cause before adding request context for the caller.
async fn[T] Client::with_retries(
  self : Client,
  attempt : async () -> T,
  bail : (Error) -> Bool,
  progress? : RequestProgress,
) -> T {
  @async.retry(
    ExponentialDelay(
      initial=self.retry_backoff_ms,
      factor=2.0,
      maximum=max_backoff_ms,
    ),
    max_retry=self.retry_attempts - 1,
    fatal_error=error => {
      let stopped = bail(error)
      let fatal = stopped ||
        @async.is_cancellation_error(error) ||
        error is Failure::Failure(_) ||
        error is @http.URIParseError::InvalidFormat ||
        error is @http.URIParseError::UnsupportedProtocol(_)
      if progress is Some(progress) {
        progress.stop_reason = if stopped {
          StreamStarted
        } else if fatal {
          NotRetryable
        } else {
          AttemptsExhausted
        }
      }
      fatal
    },
    attempt,
  )
}

///|
/// Sends typed chat messages to DeepSeek and decodes the response.
///
/// Pass `tools` to enable native DeepSeek function tool calls. Pass
/// `response_format=JsonObject` only when the assistant content itself should
/// be constrained to a JSON object. Pass `stream=StreamHandler(...)` to send
/// the request in SSE streaming mode while still receiving the accumulated
/// response as the return value.
/// Streaming failures include request progress in the Failure message after
/// retries stop. Cancellation propagates unchanged.
pub async fn Client::chat(
  self : Client,
  messages : Array[@deepseek.ChatMessage],
  tools? : Array[@deepseek.ToolDefinition] = [],
  response_format? : @deepseek.ResponseFormat,
  stream? : StreamHandler,
) -> @deepseek.ChatResponse {
  let is_streaming = stream is Some(_)
  let body = @deepseek.encode_chat_request(
    model=self.model,
    tools~,
    thinking=self.thinking,
    stream=is_streaming,
    response_format?,
  ) <| messages
  try {
    match stream {
      None => self.with_retries(() => self.chat_attempt(body), _ => false)
      Some(stream) => {
        // The handler, not this client, owns already-rendered deltas. An absent
        // retry callback preserves the conservative no-replay rule after the
        // first event. An opted-in consumer gets a boundary before the next
        // attempt and must clear that transient output there.
        let progress = RequestProgress()
        let mut previous_streamed = false
        let mut retry_reason = ""
        self.with_retries(
          () => {
            let attempt = progress.attempts + 1
            if attempt > 1 && previous_streamed {
              match stream.on_retry {
                Some(on_retry) =>
                  on_retry(attempt, self.retry_attempts, retry_reason)
                None => ()
              }
            }
            previous_streamed = false
            progress.begin_attempt()
            self.chat_stream_attempt(body, progress, stream)
          },
          error => {
            previous_streamed = match progress.phase {
              Sse(sse) => sse.event_count > 0 || sse.buffered_data
              Decode(event_count~, ..) => event_count > 0
              Connect | WriteRequest | ResponseHeaders | ResponseBody => false
            }
            retry_reason = match error {
              IdleTimeout(context, timeout_ms) =>
                "\{context} idle for \{timeout_ms}ms"
              StreamEnded => "DeepSeek stream ended before [DONE]"
              StreamTransport(detail) =>
                "DeepSeek stream transport error: \{detail}"
              HttpStatusError(code, body) =>
                "DeepSeek API error \{code}: \{body}"
              error => "\{error}"
            }
            // Malformed SSE and callback failures are plain Failure values and
            // remain final. Only transport, EOF, and idle-timeout failures may
            // cross a boundary after output has started.
            let retryable_stream_error = match error {
              IdleTimeout(_, _) | StreamEnded | StreamTransport(_) => true
              _ => false
            }
            previous_streamed &&
            (stream.on_retry is None || !retryable_stream_error)
          },
          progress~,
        ) catch {
          error if @async.is_being_cancelled() ||
            @async.is_cancellation_error(error) => raise error
          error => fail(progress.failure_message(self, error))
        }
      }
    }
  } catch {
    HttpStatusError(code, body) => fail("DeepSeek API error \{code}: \{body}")
    IdleTimeout(context, timeout_ms) =>
      fail("\{context} idle for \{timeout_ms}ms")
    StreamEnded => fail("DeepSeek stream ended before [DONE]")
    error => raise error
  }
}

///|
async fn Client::chat_attempt(
  self : Client,
  body : Json,
) -> @deepseek.ChatResponse {
  let (resp, data) = @http.post(self.api_url, body, headers={
    "Content-Type": "application/json",
    "Authorization": "Bearer \{self.api_key}",
  })
  let text = data.text()
  guard resp.code >= 200 && resp.code < 300 else {
    if retryable_status(resp.code) {
      raise HttpStatusError(resp.code, text)
    }
    fail("DeepSeek API error \{resp.code}: \{text}")
  }
  // A 2xx body that fails to parse or decode is a final verdict, not a
  // transport error: the completion already ran (and billed), so retrying
  // would duplicate it for the same bad payload.
  let json = @json.parse(text) catch {
    error => fail("DeepSeek response is not JSON: \{error}; body: \{text}")
  }
  @json.from_json(json) catch {
    error => fail("DeepSeek response decode error: \{error}; body: \{text}")
  }
}

///|
async fn Client::chat_stream_attempt(
  self : Client,
  body : Json,
  progress : RequestProgress,
  stream : StreamHandler,
) -> @deepseek.ChatResponse {
  let client = @http.post_stream(self.api_url, headers={
    "Content-Type": "application/json",
    "Authorization": "Bearer \{self.api_key}",
    // Without an explicit Accept-Encoding the HTTP client advertises gzip and
    // transparently decompresses. A gzip-compressing intermediary buffers
    // whole compression blocks, which would re-batch the SSE deltas this
    // request exists to stream — so pin the identity encoding.
    "Accept-Encoding": "identity",
  })
  defer client.close()
  progress.phase = WriteRequest
  client.write(body.stringify())
  // Bound the wait for response headers the same way the SSE loop bounds the
  // wait between events: a peer that accepts the connection then never sends a
  // status line would otherwise block here forever, before any event, with no
  // error for the retry loop to see.
  progress.phase = ResponseHeaders
  let resp = with_idle_timeout(
    self.idle_timeout_ms,
    "DeepSeek response headers",
    () => client.end_request(),
  )
  progress.http_status = Some(resp.code)
  guard resp.code >= 200 && resp.code < 300 else {
    progress.phase = ResponseBody
    let text = client.read_all().text()
    if retryable_status(resp.code) {
      raise HttpStatusError(resp.code, text)
    }
    fail("DeepSeek API error \{resp.code}: \{text}")
  }
  // The stream reader finalizes malformed SSE payloads at its parse site
  // (see decode_sse_data in stream.mbt), so a mid-stream transport error
  // reaches the retry loop with its own type and the delivered-event bail
  // decides whether retrying is allowed.
  read_chat_stream(
    client,
    progress,
    idle_timeout_ms=self.idle_timeout_ms,
    on_content_delta=stream.on_content_delta,
    on_reasoning_delta=stream.on_reasoning_delta,
  )
}

///|
pub extend Client with Debug::{to_repr}
