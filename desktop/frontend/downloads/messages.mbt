// Feature-owned UI messages; all built-in languages are exhaustive.

///|
priv enum Message {
  Checking
  NotPublished
  NoTargets
  DownloadVersion(String)
  GitHubReleases
}

///|
fn text(locale : @i18n.Locale, message : Message) -> String {
  match (locale, message) {
    (English, Checking) => "Checking the latest release…"
    (Spanish, Checking) => "Buscando la última versión…"
    (SimplifiedChinese, Checking) => "正在获取最新版本…"
    (TraditionalChinese, Checking) => "正在取得最新版本…"
    (Japanese, Checking) => "最新リリースを確認中…"
    (English, NotPublished) =>
      "No packaged build is published on this server yet."
    (Spanish, NotPublished) =>
      "Este servidor todavía no publica ninguna versión empaquetada."
    (SimplifiedChinese, NotPublished) => "此服务器尚未发布安装包。"
    (TraditionalChinese, NotPublished) => "此伺服器尚未發布安裝包。"
    (Japanese, NotPublished) =>
      "このサーバーにはまだパッケージ版が公開されていません。"
    (English, NoTargets) => "No downloads are listed for this release."
    (Spanish, NoTargets) => "Esta versión no incluye descargas."
    (SimplifiedChinese, NoTargets) => "此版本没有可下载的安装包。"
    (TraditionalChinese, NoTargets) => "此版本沒有可下載的安裝包。"
    (Japanese, NoTargets) =>
      "このリリースにはダウンロードがありません。"
    (English, DownloadVersion(version)) => "Download v\{version}"
    (Spanish, DownloadVersion(version)) => "Descargar v\{version}"
    (SimplifiedChinese, DownloadVersion(version)) => "下载 v\{version}"
    (TraditionalChinese, DownloadVersion(version)) => "下載 v\{version}"
    (Japanese, DownloadVersion(version)) => "v\{version} をダウンロード"
    (English, GitHubReleases) => "All releases on GitHub"
    (Spanish, GitHubReleases) => "Todas las versiones en GitHub"
    (SimplifiedChinese, GitHubReleases) => "在 GitHub 查看全部版本"
    (TraditionalChinese, GitHubReleases) => "在 GitHub 查看全部版本"
    (Japanese, GitHubReleases) => "GitHub ですべてのリリースを見る"
  }
}
