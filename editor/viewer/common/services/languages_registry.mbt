///| Reachable subset of vscode's `LanguageIdCodec` from
/// `src/vs/editor/common/services/languagesRegistry.ts` (pinned `vscode/`
/// submodule). Maps string language ids to a stable numeric id, the
/// value a token metadata word's low 8 bits carry (`ILanguageIdCodec`,
/// `common/languages.ts`).

///|
/// The built-in languages the codec is seeded with, so their numeric ids are
/// stable across documents. Mirrors Monaco reserving `null`/`plaintext` at ids
/// `0`/`1` (`LanguageId.Null` / `LanguageId.PlainText`), followed by the
/// languages the shell registers via `Languages::set_tokens_provider`
/// (`internal/shell/workbench/app.mbt`). Any other language (e.g. a test
/// language) is allocated an id on demand by `register`.
let builtin_language_ids : Array[String] = [
  "null", "plaintext", "moonbit", "javascript", "typescript", "json",
]

///|
/// Encoding half of `ILanguageIdCodec` (`languagesRegistry.ts`). Seeded with
/// the built-in languages; `register` extends it.
struct LanguageIdCodec {
  language_id_to_language : Array[String]
  language_to_language_id : Map[String, Int]
  mut next_language_id : Int
}

///|
/// Shows the ordered numeric-id table. The reverse lookup map and next id are
/// omitted because both are derived from this array.
pub impl Debug for LanguageIdCodec with fn to_repr(self) {
  Repr(self.language_id_to_language)
}

///|
fn LanguageIdCodec::LanguageIdCodec() -> LanguageIdCodec {
  let codec = {
    language_id_to_language: [],
    language_to_language_id: Map([]),
    next_language_id: 0,
  }
  for language in builtin_language_ids {
    codec.register(language) |> ignore
  }
  codec
}

///|
/// The process-wide codec instance, the role of Monaco's
/// `LanguageService.languageIdCodec` (one `LanguagesRegistry` threads through
/// every model). Construction stays internal so all token users share one
/// stable numeric mapping.
pub let language_id_codec : LanguageIdCodec = LanguageIdCodec()

///|
/// Registers `language`, returning its numeric id (the existing id if already
/// registered). Mirrors Monaco's `register` + `encodeLanguageId` allocation:
/// ids are handed out sequentially, so the first registered language is `0`.
pub fn LanguageIdCodec::register(
  self : LanguageIdCodec,
  language : String,
) -> Int {
  match self.language_to_language_id.get(language) {
    Some(id) => id
    None => {
      let id = self.next_language_id
      self.next_language_id = id + 1
      self.language_id_to_language.push(language)
      self.language_to_language_id[language] = id
      id
    }
  }
}

///|
/// Numeric id for `language`, or `0` (the null language) when unregistered.
/// Mirrors Monaco's `encodeLanguageId` (lookup only — `register` allocates).
pub fn LanguageIdCodec::encode_language_id(
  self : LanguageIdCodec,
  language : String,
) -> Int {
  self.language_to_language_id.get(language).unwrap_or(0)
}

///|
pub extend LanguageIdCodec with Debug::{to_repr}
