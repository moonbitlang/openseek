// A settings-form probe: ask the endpoint the user is typing whether it can
// serve the model they typed. It sends one minimal, non-streaming completion —
// the one request every OpenAI-compatible endpoint must implement — and turns
// the answer into a line the form can show. Nothing is stored, and nothing is
// retried: a wrong address should be reported, not hammered.

///|
/// How long a probe waits before calling the endpoint unreachable. A settings
/// form is a person waiting, so this is short on purpose.
const ProbeTimeoutMs : Int32 = 15_000

///|
/// How much of a provider's error body reaches the form: enough for its own
/// explanation, short enough for one line.
const ProbeExcerptChars : Int32 = 240

///|
fn probe_excerpt(text : String) -> String {
  let trimmed = text.trim()
  if trimmed.is_empty() {
    ""
  } else if trimmed.length() <= ProbeExcerptChars {
    trimmed.to_owned()
  } else {
    "\{trimmed[:ProbeExcerptChars]}…"
  }
}

///|
/// One status code and body turned into a verdict. Pure, so the wording and the
/// classification are exactly what the tests pin.
fn probe_verdict(code : Int32, body : String) -> @protocol.ModelProbeReply {
  if code >= 200 && code < 300 {
    return { ok: true, detail: "Connected.", }
  }
  let reason = match code {
    401 | 403 => "The endpoint rejected the API key."
    404 => "The endpoint or model was not found."
    429 => "The endpoint is rate limiting; try again shortly."
    _ => "The endpoint answered \{code}."
  }
  let excerpt = probe_excerpt(body)
  {
    ok: false,
    detail: if excerpt.is_empty() {
      reason
    } else {
      "\{reason} \{excerpt}"
    },
  }
}

///|
/// Ask one endpoint whether it serves one model, with the values a settings
/// form holds right now. The key leaves this process only in the request
/// header, and nothing about the attempt is stored.
pub async fn probe_model(
  api_url~ : String,
  model~ : String,
  full_url~ : Bool,
  api_key? : String,
) -> @protocol.ModelProbeReply {
  // The probe resolves the address exactly as the saved entry will, so a URL
  // that passes here cannot be stored in a shape that fails later.
  let url = normalize_model_url(api_url, full_url) catch {
    EngineError(message) => return { ok: false, detail: message, }
  }
  let model = model.trim().to_owned()
  if model.is_empty() {
    return { ok: false, detail: "Enter a model name.", }
  }
  // A one-token completion is the cheapest request every compatible endpoint
  // must serve, so a success means the address, key, and model all work.
  let body : Json = {
    "model": model,
    "messages": [{ "role": "user", "content": "ping" }],
    "max_tokens": 1,
    "stream": false,
  }
  let headers : Map[@http.CaseInsensitiveString, String] = {
    "Content-Type": "application/json",
  }
  match api_key {
    Some(key) =>
      if !key.trim().is_empty() {
        headers["Authorization"] = "Bearer \{key.trim()}"
      }
    None => ()
  }
  let (code, answer) = @async.with_timeout(ProbeTimeoutMs, () => {
    let (response, data) = @http.post_json(url, body, headers~)
    (response.code, data.text())
  }) catch {
    _ => return { ok: false, detail: "The endpoint did not answer in time.", }
  }
  probe_verdict(code, answer)
}

///|
test "a 2xx is a connection and a refusal names its cause" {
  assert_true(probe_verdict(200, "{}").ok)
  let unauthorized = probe_verdict(401, "{\"error\":{\"message\":\"bad key\"}}")
  assert_false(unauthorized.ok)
  assert_true(unauthorized.detail.contains("rejected the API key"))
  // The provider's own words are the useful half of a failure.
  assert_true(unauthorized.detail.contains("bad key"))
  assert_true(probe_verdict(404, "").detail.contains("not found"))
  assert_true(probe_verdict(500, "").detail.contains("500"))
}

///|
test "a long provider body is cut to one form line" {
  let body = Array::make(1_000, "x").join("")
  let verdict = probe_verdict(400, body)
  assert_true(verdict.detail.length() < 300)
  assert_true(verdict.detail.has_suffix("…"))
}
