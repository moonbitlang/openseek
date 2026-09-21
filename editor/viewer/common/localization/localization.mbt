///|
/// Language of editor-owned controls. Document and provider text are unchanged.
pub(all) enum Language {
  English
  SimplifiedChinese
  TraditionalChinese
  Japanese
  Spanish
} derive(Eq, Debug)

///|
pub extend Language with Eq::{equal, not_equal}

///|
pub extend Language with Debug::{to_repr}

///|
/// A host-owned language source. Share it between related viewers, or create
/// separate sources for independent embeds. No process-wide language is used.
struct Localization {
  mut language : Language
  changes : @common.Emitter[Language]
}

///|
pub fn Localization::Localization(
  language? : Language = English,
) -> Localization {
  { language, changes: Emitter(), }
}

///|
pub fn Localization::language(self : Localization) -> Language {
  self.language
}

///|
pub fn Localization::text(self : Localization, message : Message) -> String {
  text(self.language, message)
}

///|
pub fn Localization::set_language(
  self : Localization,
  language : Language,
) -> Unit {
  if self.language != language {
    self.language = language
    self.changes.fire(language)
  }
}

///|
/// Bind a widget's labels and immediately render the current language. The
/// widget must dispose the returned binding with its other event listeners.
pub fn Localization::bind(
  self : Localization,
  render : (Language) -> Unit,
) -> @common.Disposable {
  render(self.language)
  self.changes.event(render)
}

///|
pub fn Localization::dispose(self : Localization) -> Unit {
  self.changes.dispose()
}
