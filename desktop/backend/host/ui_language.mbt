///|
/// Native UI state is independent of temporary CEF profiles and remote hosts.
pub async fn read_ui_language(
  runtime_dir : String?,
) -> @protocol.UiLanguagePreference {
  guard runtime_dir is Some(dir) else { return { language: None, } }
  let path : @pathx.Path = dir
  guard @fsx.read_text_if_exists(path.join("ui-language.json")) is Some(text) else {
    return { language: None, }
  }
  let preference : @protocol.UiLanguagePreference = @json.from_json(
    @json.parse(text),
  )
  validate_ui_language(preference.language)
  preference
}

///|
fn validate_ui_language(language : String?) -> Unit raise {
  match language {
    None | Some("system" | "en" | "zh-Hans" | "zh-Hant" | "ja" | "es") => ()
    Some(_) => raise HostError("Unknown UI language preference")
  }
}

///|
pub async fn write_ui_language(
  runtime_dir : String?,
  preference : @protocol.UiLanguagePreference,
) -> @protocol.EmptyReply {
  validate_ui_language(preference.language)
  guard runtime_dir is Some(dir) else {
    raise HostError("UI preference storage is unavailable")
  }
  let path : @pathx.Path = dir
  // Each writer has its own temporary file, including multiple desktop instances.
  let unique_dir = @fs.tmpdir(prefix="ui-language-")
  defer @fs.rmdir(unique_dir)
  let unique_path : @pathx.Path = unique_dir
  let temp = path.join(unique_path.basename().to_owned())
  defer @fsx.remove_if_exists(temp)
  @fs.write_file(
    temp.to_string(),
    preference.to_json().stringify(),
    create_mode=CreateOrTruncate,
  )
  @fs.rename(temp.to_string(), path.join("ui-language.json").to_string())
  Acknowledged
}
