///|
/// This desktop host owns one language source shared by its code, Markdown,
/// diff and semantic-review editors. Other hosts retain independent sources.
let viewer_localization : @localization.Localization = @localization.Localization()

///|
fn viewer_locale() -> @i18n.Locale {
  match viewer_localization.language() {
    English => English
    SimplifiedChinese => SimplifiedChinese
    Japanese => Japanese
  }
}

///|
pub fn apply_language(locale : @i18n.Locale) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    viewer_localization.set_language(
      match locale {
        English => @localization.English
        SimplifiedChinese => @localization.SimplifiedChinese
        Japanese => @localization.Japanese
      },
    )
    if viewer_state.viewer is Some(viewer) {
      viewer.update_options(
        viewer.get_options().with_placeholder(file_placeholder(false)),
      )
    }
    if viewer_state.markdown_viewer is Some(viewer) {
      viewer.update_options(
        viewer.get_options().with_placeholder(file_placeholder(true)),
      )
    }
  })
}

///|
fn file_placeholder(markdown : Bool) -> String {
  match (viewer_localization.language(), markdown) {
    (English, false) => "Select a file to view"
    (English, true) => "Select a Markdown file to view"
    (SimplifiedChinese, false) => "选择要查看的文件"
    (Japanese, false) => "表示するファイルを選択"
    (SimplifiedChinese, true) => "选择要查看的 Markdown 文件"
    (Japanese, true) => "表示する Markdown ファイルを選択"
  }
}
