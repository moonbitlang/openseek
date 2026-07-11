///|
const DeepSeekDefaultApiUrl : String = "https://api.deepseek.com/chat/completions"

///|
const KimiDefaultApiUrl : String = "https://api.moonshot.cn/v1/chat/completions"

///|
let default_model : @deepseek.Model = Deepseek(V4Pro)

///|
fn default_api_url_for_model(model : @deepseek.Model) -> String {
  match model {
    Kimi(_) => KimiDefaultApiUrl
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
  retry_attempts? : Int = 3,
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
/// fragment (it is simply not called when thinking is off). `Client::chat`
/// returns the fully accumulated response after the stream reaches `[DONE]`.
pub struct StreamHandler {
  priv on_content_delta : async (String) -> Unit
  priv on_reasoning_delta : async (String) -> Unit
}

///|
/// Constructs callbacks for `Client::chat(..., stream=...)`.
pub fn StreamHandler::StreamHandler(
  on_content_delta~ : async (String) -> Unit,
  on_reasoning_delta? : async (String) -> Unit = _ => (),
) -> StreamHandler {
  { on_content_delta, on_reasoning_delta }
}

///|
/// A response status worth retrying: rate limiting or a server-side failure.
/// Other 4xx are caller errors (bad key, malformed request) that a retry
/// cannot fix.
fn retryable_status(code : Int) -> Bool {
  code == 429 || (code >= 500 && code < 600)
}

///|
/// Marks an attempt failure the retry loop may absorb. Carries the
/// already-formatted public failure message so the final attempt re-raises
/// the same text a non-retrying client would have produced.
priv suberror RetryableApiError {
  RetryableApiError(String)
}

///|
/// Ceiling on a single backoff sleep. The doubling sequence from
/// `retry_backoff_ms` stops growing here, so a generous retry budget cannot
/// accumulate minutes-long sleeps between attempts.
let max_backoff_ms : Int = 60_000

///|
/// Run `attempt` up to `retry_attempts` total tries via `@async.retry`
/// (exponential backoff doubling from `retry_backoff_ms`, capped at
/// `max_backoff_ms`; `max_retry` counts restarts, hence the -1).
///
/// The `fatal_error` classification: cancellations, plain failures (our own
/// final verdicts — non-retryable HTTP statuses, malformed response bodies,
/// truncated streams), and malformed-api_url parse errors (which fail
/// identically every time, before any network I/O) propagate immediately;
/// anything else is transport-shaped (connect refused, reset, DNS) and
/// retries within budget. `bail` lets an attempt declare later retries
/// pointless — streaming chat sets it once the stream has produced any event,
/// since replaying a half-consumed completion would duplicate content (or
/// regenerate tool calls) downstream.
///
/// A `RetryableApiError` that survives the budget (or bail) re-raises as a
/// plain failure carrying the same text a non-retrying client would have
/// produced, so the private marker type never escapes the package.
async fn[T] Client::with_retries(
  self : Client,
  attempt : async () -> T,
  bail : () -> Bool,
) -> T {
  @async.retry(
    ExponentialDelay(
      initial=self.retry_backoff_ms,
      factor=2.0,
      maximum=max_backoff_ms,
    ),
    max_retry=self.retry_attempts - 1,
    fatal_error=error => {
      bail() ||
      @async.is_cancellation_error(error) ||
      error is Failure::Failure(_) ||
      error is @http.URIParseError::InvalidFormat ||
      error is @http.URIParseError::UnsupportedProtocol(_)
    },
    attempt,
  ) catch {
    RetryableApiError(message) => fail(message)
    error => raise error
  }
}

///|
/// Sends typed chat messages to DeepSeek and decodes the response.
///
/// Pass `tools` to enable native DeepSeek function tool calls. Pass
/// `response_format=JsonObject` only when the assistant content itself should
/// be constrained to a JSON object. Pass `stream=StreamHandler(...)` to send
/// the request in SSE streaming mode while still receiving the accumulated
/// response as the return value. Pass `max_tokens` to cap the completion;
/// omitted means the provider default.
pub async fn Client::chat(
  self : Client,
  messages : Array[@deepseek.ChatMessage],
  tools? : Array[@deepseek.ToolDefinition] = [],
  response_format? : @deepseek.ResponseFormat,
  max_tokens? : Int,
  stream? : StreamHandler,
) -> @deepseek.ChatResponse {
  let is_streaming = stream is Some(_)
  let body = @deepseek.encode_chat_request(
    model=self.model,
    tools~,
    thinking=self.thinking,
    stream=is_streaming,
    response_format?,
    max_tokens?,
  ) <| messages
  match stream {
    None => self.with_retries(() => self.chat_attempt(body), () => false)
    Some(stream) => {
      // Once the server has produced any complete SSE event the completion is
      // running and billed — text deltas, tool-call deltas, and usage alike,
      // even though only text reaches the callbacks. A retry past that point
      // could duplicate content or generate a different tool call, so the
      // first event (not just the first text delta) bails the retry loop and
      // failures surface instead (Codex review).
      let mut streamed = false
      self.with_retries(
        () => {
          self.chat_stream_attempt(
            body,
            on_stream_event=() => streamed = true,
            stream,
          )
        },
        () => streamed,
      )
    }
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
    let message = "DeepSeek API error \{resp.code}: \{text}"
    if retryable_status(resp.code) {
      raise RetryableApiError(message)
    }
    fail(message)
  }
  // A 2xx body that fails to parse or decode is a final verdict, not a
  // transport error: the completion already ran (and billed), so retrying
  // would duplicate it for the same bad payload.
  @json.from_json(
    @json.parse(text) catch {
      error => fail("DeepSeek response is not JSON: \{error}; body: \{text}")
    },
  ) catch {
    error => fail("DeepSeek response decode error: \{error}; body: \{text}")
  }
}

///|
async fn Client::chat_stream_attempt(
  self : Client,
  body : Json,
  on_stream_event~ : () -> Unit,
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
  client.write(body.stringify())
  // Bound the wait for response headers the same way the SSE loop bounds the
  // wait between events: a peer that accepts the connection then never sends a
  // status line would otherwise block here forever, before any event, with no
  // error for the retry loop to see.
  let resp = with_idle_timeout(
    self.idle_timeout_ms,
    "DeepSeek response headers",
    () => client.end_request(),
  )
  guard resp.code >= 200 && resp.code < 300 else {
    let text = client.read_all().text()
    let message = "DeepSeek API error \{resp.code}: \{text}"
    if retryable_status(resp.code) {
      raise RetryableApiError(message)
    }
    fail(message)
  }
  // The stream reader finalizes malformed SSE payloads at its parse site
  // (see decode_sse_data in stream.mbt), so a mid-stream transport error
  // reaches the retry loop with its own type and the delivered-event bail
  // decides whether retrying is allowed.
  read_chat_stream(
    client,
    idle_timeout_ms=self.idle_timeout_ms,
    on_stream_event~,
    on_content_delta=stream.on_content_delta,
    on_reasoning_delta=stream.on_reasoning_delta,
  )
}
