///|
/// Built-in UI languages. Product content and protocol values are independent.
pub(all) enum Locale {
  English
  SimplifiedChinese
  TraditionalChinese
  Japanese
} derive(Debug, Eq)

///|
/// The saved user choice, distinct from the effective UI language.
pub(all) enum Preference {
  System
  English
  SimplifiedChinese
  TraditionalChinese
  Japanese
} derive(Debug, Eq)

///|
/// Parse a stored or selected value without assigning meaning to invalid input.
pub fn Preference::parse(value : String) -> Preference? {
  match value {
    "system" => Some(System)
    "en" => Some(English)
    "zh-Hans" => Some(SimplifiedChinese)
    "zh-Hant" => Some(TraditionalChinese)
    "ja" => Some(Japanese)
    _ => None
  }
}

///|
/// Stable persistence value; never a translated label.
pub fn Preference::wire(self : Preference) -> String {
  match self {
    System => "system"
    English => "en"
    SimplifiedChinese => "zh-Hans"
    TraditionalChinese => "zh-Hant"
    Japanese => "ja"
  }
}

///|
/// Document language tag for accessibility and browser text behavior.
pub fn Locale::tag(self : Locale) -> String {
  match self {
    English => "en"
    SimplifiedChinese => "zh-Hans"
    TraditionalChinese => "zh-Hant"
    Japanese => "ja"
  }
}

///|
fn supported_language(tag : String) -> Locale? {
  let parts = tag.to_lower().split("-").collect()
  guard parts.length() > 0 else { return None }
  match parts[0] {
    "en" => Some(English)
    "ja" => Some(Japanese)
    "zh" => {
      // Script takes precedence over region (for example zh-Hant-CN).
      if parts.contains("hant") {
        return Some(TraditionalChinese)
      }
      if parts.contains("hans") {
        return Some(SimplifiedChinese)
      }
      if parts.contains("tw") || parts.contains("hk") || parts.contains("mo") {
        return Some(TraditionalChinese)
      }
      if parts.length() == 1 || parts.contains("cn") || parts.contains("sg") {
        Some(SimplifiedChinese)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// Resolve ordered browser preferences, falling back to English.
pub fn Preference::resolve(
  self : Preference,
  languages : Array[String],
) -> Locale {
  match self {
    English => English
    SimplifiedChinese => SimplifiedChinese
    TraditionalChinese => TraditionalChinese
    Japanese => Japanese
    System => {
      for language in languages {
        if supported_language(language) is Some(locale) {
          return locale
        }
      }
      English
    }
  }
}

///|
pub extend Locale with Eq::{equal, not_equal}

///|
pub extend Locale with Debug::{to_repr}

///|
pub extend Preference with Eq::{equal, not_equal}

///|
pub extend Preference with Debug::{to_repr}
