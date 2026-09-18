///|
/// The native window's preference. Missing/null means no saved choice;
/// Unknown fields are ignored; malformed values are rejected by this decoder.
/// The native host validates supported language values before storing them.
pub(all) struct UiLanguagePreference {
  language : String?
} derive(Eq, Debug)

///|
pub impl FromJson for UiLanguagePreference with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "UI language preference")
  { language: object.optional_string("language"), }
}

///|
pub impl ToJson for UiLanguagePreference with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  if self.language is Some(language) {
    fields["language"] = Json(language)
  }
  Json(fields)
}

///|
pub extend UiLanguagePreference with FromJson::{from_json}

///|
pub extend UiLanguagePreference with ToJson::{to_json}

///|
pub extend UiLanguagePreference with Eq::{equal, not_equal}

///|
pub extend UiLanguagePreference with Debug::{to_repr}
