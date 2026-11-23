// The model catalog: the entries this build offers plus the ones the user
// saved. An entry is data, not a type — its id is an opaque wire name that no
// code here interprets, and the behaviours the engine used to derive from a
// model family (context window, image input, reasoning field) are read from
// the entry instead.
//
// Built-in entries are synthesised, never stored: their credential lives in
// the provider slot (`engine-settings.json`'s `providers`) and their endpoint
// is the engine's own default for that family. Only user entries are written
// under `models`, and `update_settings` deliberately rewrites that array only
// when a patch edits it, so a field a newer build added survives a save.

///|
/// The context window assumed for a user entry that names none: the current
/// generation of frontier models serves 1M, so that is what a new entry starts
/// from. An endpoint that serves less is lowered per entry, because an
/// over-estimate overflows the endpoint's real window (a 400 mid-conversation)
/// while an under-estimate only compacts earlier.
const DefaultModelContextWindow : Int32 = 1_000_000

///|
/// The range a saved entry may name. A typo must not make a run plan against a
/// window no endpoint serves: far too small compacts on the first turn, far too
/// large lets a request overflow.
const MinModelContextWindow : Int32 = 1_024

///|
const MaxModelContextWindow : Int32 = 10_000_000

///|
/// The family of a user entry: an OpenAI-compatible endpoint that carries no
/// provider-specific thinking field.
const ModelFamilyCustom : String = "custom"

///|
/// How long a display name may be. The limit keeps one entry from pushing the
/// model chip and the menu rows out of shape.
const MaxModelLabelChars : Int32 = 64

///|
/// Where a request for this entry is posted. A base URL gains the endpoint
/// path the client posts to; a URL the user marked complete is used as typed.
fn normalize_model_url(
  value : String,
  full_url : Bool,
) -> String raise EngineError {
  let url = @url.Url::parse(value) catch {
    _ => raise EngineError("Enter a valid HTTP or HTTPS endpoint URL")
  }
  guard (url.scheme == "http" || url.scheme == "https") && url.host is Some(_) else {
    raise EngineError("Enter a valid HTTP or HTTPS endpoint URL")
  }
  guard url.fragment is None else {
    raise EngineError("Endpoint URL must not contain a fragment (#)")
  }
  if full_url {
    value
  } else {
    let path = url.pathname().trim_end(chars="/").to_owned()
    // Idempotent: a URL that already ends at the endpoint is not given the
    // path twice, which is what an entry saved once and then edited re-opens
    // with.
    if path.has_suffix("/chat/completions") {
      value
    } else {
      url.set_pathname(path + "/chat/completions")
      url.to_string()
    }
  }
}

///|
/// One model the UI may offer. `family` decides how a request is encoded and
/// where the credential comes from; every other capability is data, because
/// an opaque id cannot be pattern-matched.
priv struct ModelEntry {
  id : String
  // The name the model list shows; absent means show the id.
  label : String?
  // `deepseek`, `glm`, `openrouter`, or `custom`.
  family : String
  // Absent when the entry relies on the engine's default for its family.
  api_url : String?
  // Whether `api_url` already ends at the endpoint, so no path is appended.
  full_url : Bool
  api_key : String?
  // Whether the endpoint accepts image parts.
  images : Bool
  context_window : Int32
}

///|
/// A user entry with its defaults, used when the stored object omits a field.
fn model_entry(id : String, family : String) -> ModelEntry {
  {
    id,
    label: None,
    family,
    api_url: None,
    full_url: false,
    api_key: None,
    images: false,
    context_window: DefaultModelContextWindow,
  }
}

///|
fn model_flag(
  fields : Map[String, Json],
  key : String,
  default~ : Bool,
) -> Bool {
  match fields.get(key) {
    Some(True) => true
    Some(False) => false
    _ => default
  }
}

///|
/// One stored entry, or `None` when the object names no usable id — a corrupt
/// entry costs that entry only.
fn decode_model_entry(json : Json) -> ModelEntry? {
  guard json is Object(fields) else { return None }
  guard fields.get("id") is Some(String(raw_id)) && !raw_id.trim().is_empty() else {
    return None
  }
  Some({
    id: raw_id.trim().to_owned(),
    label: settings_text(fields, "label"),
    family: match fields.get("family") {
      Some(String(value)) if !value.trim().is_empty() => value.trim().to_owned()
      _ => ModelFamilyCustom
    },
    api_url: settings_text(fields, "api_url"),
    full_url: model_flag(fields, "full_url", default=false),
    api_key: settings_text(fields, "api_key"),
    images: model_flag(fields, "images", default=false),
    context_window: match fields.get("context_window") {
      Some(Number(value, ..)) if value > 0.0 => value.to_int()
      _ => DefaultModelContextWindow
    },
  })
}

///|
/// The user's entries in stored order. A repeated id keeps its first
/// occurrence, so one id always names one model.
fn decode_model_entries(raw : Map[String, Json]) -> Array[ModelEntry] {
  let entries : Array[ModelEntry] = []
  guard raw.get("models") is Some(Array(items)) else { return entries }
  for item in items {
    guard decode_model_entry(item) is Some(entry) else { continue }
    if entries.any(existing => existing.id == entry.id) {
      continue
    }
    entries.push(entry)
  }
  entries
}

///|
/// The stored form of one entry: the id and everything needed to talk to it,
/// including its credential (this object only ever reaches the settings file).
fn ModelEntry::to_json(self : ModelEntry) -> Json {
  let fields : Map[String, Json] = {
    "id": Json(self.id),
    "family": Json(self.family),
    "full_url": Json(self.full_url),
    "images": Json(self.images),
    "context_window": Json(self.context_window),
  }
  if self.label is Some(value) {
    fields["label"] = Json(value)
  }
  if self.api_url is Some(value) {
    fields["api_url"] = Json(value)
  }
  if self.api_key is Some(value) {
    fields["api_key"] = Json(value)
  }
  Json(fields)
}

///|
test "a stored entry reads with defaults" {
  let entry : Json = {
    "id": "  gemini-4-carbon  ",
    "api_url": "https://gateway.example/v1",
    "api_key": "sk-test",
  }
  guard decode_model_entry(entry) is Some(entry) else {
    fail("a named entry must decode")
  }
  assert_eq(entry.id, "gemini-4-carbon")
  assert_eq(entry.family, "custom")
  assert_eq(entry.context_window, DefaultModelContextWindow)
  assert_true(entry.label is None)
  assert_false(entry.full_url)
  assert_false(entry.images)
}

///|
test "an entry keeps every value the user set" {
  let entry : Json = {
    "id": "gemini-4-carbon",
    "label": "Gemini 4 Carbon",
    "family": "custom",
    "full_url": true,
    "images": true,
    "context_window": 32768,
    "api_url": "https://gateway.example/v1/chat/completions",
  }
  guard decode_model_entry(entry) is Some(entry) else { fail("must decode") }
  assert_eq(entry.label, Some("Gemini 4 Carbon"))
  assert_true(entry.full_url)
  assert_true(entry.images)
  assert_eq(entry.context_window, 32768)
}

///|
test "an unnamed entry is dropped and a repeated id keeps its first" {
  let raw : Map[String, Json] = {
    "models": [
      { "id": "" },
      { "id": "a", "images": true },
      { "id": "a", "images": false },
      { "id": "b" },
      "not an entry",
    ],
  }
  let entries = decode_model_entries(raw)
  assert_eq(entries.map(entry => entry.id), ["a", "b"])
  // The first occurrence wins, so a later duplicate cannot silently flip a
  // capability the user set.
  assert_true(entries[0].images)
}

///|
async test "models survive a save that does not edit them" {
  with_settings_dir((dir, manager) => {
    let file = settings_file(dir)
    let stored =
      #|{"version": 3, "provider": "deepseek", "models": [{"id": "gemini-4-carbon", "future_field": 7}]}
    @openseek/atomic_file.write_text_atomic(file.to_string(), stored)
    let settings = load_engine_settings(manager.runtime_dir)
    assert_eq(settings.models.map(entry => entry.id), ["gemini-4-carbon"])
    // Saving an unrelated setting stamps the new version but leaves the
    // array's own text alone, so a field this build does not know survives.
    let _ = update_settings(manager, {
      provider: Some("deepseek"),
      providers: None,
    })
    let text = @fsx.try_read_text(file).unwrap_or("")
    assert_true(text.contains("gemini-4-carbon"))
    assert_true(text.contains("future_field"))
    assert_true(text.contains("\"version\": 4"))
  })
}

///|
test "an entry round-trips through its stored form" {
  let entry = model_entry("gemini-4-carbon", ModelFamilyCustom)
  guard decode_model_entry(entry.to_json()) is Some(stored) else {
    fail("a stored entry must decode")
  }
  assert_eq(stored.id, entry.id)
  assert_eq(stored.family, entry.family)
  assert_eq(stored.context_window, entry.context_window)
  assert_true(stored.label is None)
  assert_false(stored.full_url)
  assert_false(stored.images)
  // No endpoint or credential was set, so neither is invented on the way out.
  assert_true(stored.api_url is None)
  assert_true(stored.api_key is None)
}

///|
/// The most entries one settings file may hold. A cap keeps a runaway client
/// from turning the file into a list the UI must render without bound.
const MaxModelEntries : Int32 = 50

///|
fn entry_id(json : Json) -> String? {
  match json {
    Object(fields) =>
      match fields.get("id") {
        Some(String(id)) => Some(id)
        _ => None
      }
    _ => None
  }
}

///|
fn find_entry(entries : Array[Json], id : String) -> Int32? {
  for index, item in entries {
    if entry_id(item) == Some(id) {
      return Some(index)
    }
  }
  None
}

///|
fn copy_fields(source : Map[String, Json]) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([])
  for key, value in source {
    fields[key] = value
  }
  fields
}

///|
/// The object a brand-new entry starts from: every capability written out, so
/// the file states what the model does instead of relying on a reader default.
fn new_entry_fields(id : String) -> Map[String, Json] {
  {
    "id": Json(id),
    "family": Json(ModelFamilyCustom),
    "full_url": Json(false),
    "images": Json(false),
    "context_window": Json(DefaultModelContextWindow),
  }
}

///|
/// One upsert merged into an entry: a present field replaces, an empty string
/// clears, and an absent field is left alone. The URL is normalised exactly as
/// the custom provider's is, so a base URL and a full endpoint both work.
fn apply_model_patch(
  fields : Map[String, Json],
  patch : @protocol.ModelPatch,
) -> Unit raise EngineError {
  match patch.label {
    Some(label) => {
      let label = label.trim()
      guard label.length() <= MaxModelLabelChars else {
        raise EngineError("a model name is limited to 64 characters")
      }
      if label.is_empty() {
        fields.remove("label")
      } else {
        fields["label"] = Json(label.to_owned())
      }
    }
    None => ()
  }
  if patch.full_url is Some(value) {
    fields["full_url"] = Json(value)
  }
  match patch.api_url {
    Some(url) => {
      let url = url.trim()
      if url.is_empty() {
        fields.remove("api_url")
      } else {
        // The switch decides whether the endpoint path is appended, so it is
        // settled before the URL is normalised.
        let full_url = match fields.get("full_url") {
          Some(True) => true
          _ => false
        }
        fields["api_url"] = Json(normalize_model_url(url.to_owned(), full_url))
      }
    }
    None => ()
  }
  match patch.api_key {
    Some(key) => {
      let key = key.trim()
      if key.is_empty() {
        fields.remove("api_key")
      } else {
        fields["api_key"] = Json(key.to_owned())
      }
    }
    None => ()
  }
  if patch.images is Some(value) {
    fields["images"] = Json(value)
  }
  if patch.context_window is Some(value) {
    guard value >= MinModelContextWindow && value <= MaxModelContextWindow else {
      raise EngineError(
        "a model's context window must be between \{MinModelContextWindow} and \{MaxModelContextWindow} tokens",
      )
    }
    fields["context_window"] = Json(value)
  }
}

///|
/// Apply one `settings.set` instruction to the stored array: removals first,
/// then upserts in the order given, each merged into the object it names so a
/// field this build does not know survives an edit.
fn apply_model_patches(
  stored : Array[Json],
  upserts : Array[@protocol.ModelPatch],
  removals : Array[String],
) -> Array[Json] raise EngineError {
  let dropped = removals.map(id => id.trim().to_owned())
  let entries : Array[Json] = []
  for item in stored {
    let keep = match entry_id(item) {
      // A malformed object is dropped: it names no model to run.
      Some(id) => !dropped.contains(id)
      None => false
    }
    if keep {
      entries.push(item)
    }
  }
  for patch in upserts {
    let id = patch.id.trim().to_owned()
    guard !id.is_empty() else { raise EngineError("a model needs a name") }
    let existing = find_entry(entries, id)
    let fields = match existing {
      Some(index) =>
        match entries[index] {
          Object(stored) => copy_fields(stored)
          _ => new_entry_fields(id)
        }
      None => new_entry_fields(id)
    }
    apply_model_patch(fields, patch)
    match existing {
      Some(index) => entries[index] = Json(fields)
      None => {
        guard entries.length() < MaxModelEntries else {
          raise EngineError("too many saved models; remove one first")
        }
        entries.push(Json(fields))
      }
    }
  }
  entries
}

///|
test "a new entry is written with explicit values" {
  let patch : @protocol.ModelPatch = {
    id: "  gemini-4-carbon  ",
    label: Some("  Gemini 4 Carbon  "),
    api_url: Some("https://gateway.example/v1"),
    full_url: None,
    api_key: Some("  sk-test  "),
    images: Some(true),
    context_window: None,
  }
  let entries = apply_model_patches([], [patch], [])
  assert_eq(entries.length(), 1)
  let stored = decode_model_entry(entries[0]).unwrap()
  assert_eq(stored.id, "gemini-4-carbon")
  assert_eq(stored.label, Some("Gemini 4 Carbon"))
  // The base URL gains the endpoint path the client posts to.
  assert_eq(stored.api_url, Some("https://gateway.example/v1/chat/completions"))
  assert_eq(stored.api_key, Some("sk-test"))
  assert_false(stored.full_url)
  assert_true(stored.images)
  assert_eq(stored.context_window, DefaultModelContextWindow)
}

///|
test "an edit keeps a field this build does not know" {
  let stored : Array[Json] = [{ "id": "g", "future_field": 7 }]
  let patch : @protocol.ModelPatch = {
    id: "g",
    label: None,
    api_url: Some("https://gw.example/v1/chat"),
    full_url: Some(true),
    api_key: None,
    images: None,
    context_window: Some(32768),
  }
  let entries = apply_model_patches(stored, [patch], [])
  assert_eq(entries.length(), 1)
  assert_true(entries[0].stringify().contains("future_field"))
  let entry = decode_model_entry(entries[0]).unwrap()
  // A URL the user marked complete is used as typed, with no path appended.
  assert_eq(entry.api_url, Some("https://gw.example/v1/chat"))
  assert_true(entry.full_url)
  assert_eq(entry.context_window, 32768)
}

///|
/// The error one patch would raise, or `None` when it applies cleanly. `catch`
/// yields a value rather than a flag, so the tests share this one boundary.
fn model_patch_error(
  stored : Array[Json],
  upserts : Array[@protocol.ModelPatch],
  removals : Array[String],
) -> String? {
  let _ = apply_model_patches(stored, upserts, removals) catch {
    EngineError(message) => return Some(message)
  }
  None
}

///|
test "an empty value clears and a removal wins" {
  let stored : Array[Json] = [
    { "id": "a", "api_url": "https://gw.example/v1", "api_key": "sk-a" },
    { "id": "b" },
  ]
  let cleared = apply_model_patches(
    stored,
    [
      {
        id: "a",
        label: Some(""),
        api_url: None,
        full_url: None,
        api_key: Some(""),
        images: None,
        context_window: None,
      },
    ],
    [],
  )
  assert_true(decode_model_entry(cleared[0]).unwrap().api_key is None)
  assert_eq(apply_model_patches(stored, [], ["b"]).length(), 1)
}

///|
test "a blank id is refused and a built-in id is accepted" {
  let blank : @protocol.ModelPatch = {
    id: "   ",
    label: None,
    api_url: None,
    full_url: None,
    api_key: None,
    images: None,
    context_window: None,
  }
  let builtin : @protocol.ModelPatch = { ..blank, id: "deepseek-flash", }
  assert_true(model_patch_error([], [blank], []) is Some(_))
  assert_true(model_patch_error([], [builtin], []) is None)
  let saved = apply_model_patches([], [builtin], [])
  assert_eq(decode_model_entry(saved[0]).unwrap().id, "deepseek-flash")
}

///|
test "the entry count is capped" {
  let upserts : Array[@protocol.ModelPatch] = []
  for index in 0..<MaxModelEntries {
    upserts.push({
      id: "m-\{index}",
      label: None,
      api_url: Some("https://gw.example/v1"),
      full_url: None,
      api_key: None,
      images: None,
      context_window: None,
    })
  }
  let stored = apply_model_patches([], upserts, [])
  assert_eq(stored.length(), MaxModelEntries)
  let overflow : @protocol.ModelPatch = {
    id: "one-too-many",
    label: None,
    api_url: Some("https://gw.example/v1"),
    full_url: None,
    api_key: None,
    images: None,
    context_window: None,
  }
  assert_true(model_patch_error(stored, [overflow], []) is Some(_))
  // Removing one first makes room again, which is what a client that replaces
  // its whole list sends.
  assert_true(model_patch_error(stored, [overflow], ["m-0"]) is None)
}

///|
async test "an added model reaches the status and can be removed" {
  with_settings_dir((_dir, manager) => {
    let patch : @protocol.ModelPatch = {
      id: "gemini-4-carbon",
      label: Some("Gemini 4 Carbon"),
      api_url: Some("https://gateway.example/v1"),
      full_url: None,
      api_key: Some("sk-test"),
      images: Some(true),
      context_window: None,
    }
    let status = update_settings(
      manager,
      { provider: None, providers: None, },
      models=[patch],
    )
    assert_eq(status.models.map(model => model.id), ["gemini-4-carbon"])
    assert_true(status.models[0].has_api_key)
    assert_true(status.models[0].images)
    // Key material never leaves the host — only its presence does.
    assert_false(status.to_json().stringify().contains("sk-test"))
    // A fresh read of the file sees the same entry.
    assert_eq(settings_status(manager).models.map(model => model.id), [
      "gemini-4-carbon",
    ])
    let removed = update_settings(
      manager,
      { provider: None, providers: None, },
      removed_models=["gemini-4-carbon"],
    )
    assert_true(removed.models.is_empty())
  })
}

///|
/// One patch naming `window`, for the tests that care only about it.
fn window_patch(window : Int32) -> @protocol.ModelPatch {
  {
    id: "gemini-4-hydrogen",
    label: None,
    api_url: None,
    full_url: None,
    api_key: None,
    images: None,
    context_window: Some(window),
  }
}

///|
/// The window a saved entry may name is bounded: a typo must not make a run
/// plan against a number no endpoint serves, while anything a real endpoint
/// serves — and the default — passes.
test "a model's context window is bounded" {
  match model_patch_error([], [window_patch(MinModelContextWindow - 1)], []) {
    Some(message) => assert_true(message.contains("between"))
    None => fail("a window below the minimum must be refused")
  }
  match model_patch_error([], [window_patch(MaxModelContextWindow + 1)], []) {
    Some(message) => assert_true(message.contains("between"))
    None => fail("a window above the maximum must be refused")
  }
  let at_max = apply_model_patches([], [window_patch(MaxModelContextWindow)], [])
  assert_eq(
    decode_model_entry(at_max[0]).unwrap().context_window,
    MaxModelContextWindow,
  )
  let at_min = apply_model_patches([], [window_patch(MinModelContextWindow)], [])
  assert_eq(
    decode_model_entry(at_min[0]).unwrap().context_window,
    MinModelContextWindow,
  )
}
