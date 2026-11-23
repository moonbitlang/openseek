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
/// The family of a user entry: an OpenAI-compatible endpoint that carries no
/// provider-specific thinking field.
const ModelFamilyCustom : String = "custom"

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
