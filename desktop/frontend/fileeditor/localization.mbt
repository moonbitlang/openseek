///|
/// This desktop host owns one language source shared by its code, Markdown,
/// diff and semantic-review editors. Other hosts retain independent sources.
let viewer_localization : @localization.Localization = @localization.Localization()

///|
fn viewer_locale() -> @i18n.Locale {
  match viewer_localization.language() {
    English => English
    Spanish => Spanish
    SimplifiedChinese => SimplifiedChinese
    TraditionalChinese => TraditionalChinese
    Japanese => Japanese
  }
}

///|
pub fn apply_language(locale : @i18n.Locale) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    viewer_localization.set_language(
      match locale {
        English => @localization.English
        Spanish => @localization.Spanish
        SimplifiedChinese => @localization.SimplifiedChinese
        TraditionalChinese => @localization.TraditionalChinese
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
    (Spanish, false) => "Selecciona un archivo para verlo"
    (English, true) => "Select a Markdown file to view"
    (Spanish, true) => "Selecciona un archivo Markdown para verlo"
    (SimplifiedChinese, false) => "选择要查看的文件"
    (TraditionalChinese, false) => "選擇要檢視的檔案"
    (Japanese, false) => "表示するファイルを選択"
    (SimplifiedChinese, true) => "选择要查看的 Markdown 文件"
    (TraditionalChinese, true) => "選擇要檢視的 Markdown 檔案"
    (Japanese, true) => "表示する Markdown ファイルを選択"
  }
}

///|
fn source_preparation_notice(timed_out : Bool) -> String {
  match (viewer_localization.language(), timed_out) {
    (English, true) => "File preparation timed out. Reload the file to retry."
    (English, false) => "Could not prepare the file. Reload the file to retry."
    (Spanish, true) =>
      "La preparación del archivo agotó el tiempo. Recarga el archivo para reintentar."
    (Spanish, false) =>
      "No se pudo preparar el archivo. Recarga el archivo para reintentar."
    (SimplifiedChinese, true) => "文件准备超时，请重新加载文件。"
    (SimplifiedChinese, false) =>
      "无法准备文件，请重新加载文件。"
    (TraditionalChinese, true) =>
      "檔案準備逾時，請重新載入檔案。"
    (TraditionalChinese, false) =>
      "無法準備檔案，請重新載入檔案。"
    (Japanese, true) =>
      "ファイルの準備がタイムアウトしました。再読み込みして再試行してください。"
    (Japanese, false) =>
      "ファイルを準備できませんでした。再読み込みして再試行してください。"
  }
}
