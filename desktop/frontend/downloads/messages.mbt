// Feature-owned UI messages; all built-in languages are exhaustive.

///|
priv enum Message {
  Checking
  NotPublished
  NoTargets
  DownloadVersion(String)
  GitHubReleases
  InstallStep
  SignInStep
  RemoteControlStep
  ListedWhileRunning
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
    (English, InstallStep) =>
      "Install SeekMoon on the computer you want to use."
    (Spanish, InstallStep) => "Instala SeekMoon en el equipo que quieras usar."
    (SimplifiedChinese, InstallStep) =>
      "在要使用的电脑上安装 SeekMoon。"
    (TraditionalChinese, InstallStep) =>
      "在要使用的電腦上安裝 SeekMoon。"
    (Japanese, InstallStep) =>
      "使いたいコンピューターに SeekMoon をインストールします。"
    (English, SignInStep) =>
      "Open it and sign in with this account under Settings → Account."
    (Spanish, SignInStep) =>
      "Ábrelo e inicia sesión con esta cuenta en Configuración → Cuenta."
    (SimplifiedChinese, SignInStep) =>
      "打开 SeekMoon，在“设置 → 账户”中登录此账户。"
    (TraditionalChinese, SignInStep) =>
      "開啟 SeekMoon，在「設定 → 帳戶」中登入此帳戶。"
    (Japanese, SignInStep) =>
      "SeekMoon を開き、「設定 → アカウント」でこのアカウントにログインします。"
    (English, RemoteControlStep) =>
      "Turn on Remote control under Settings → Connections → Remote access."
    (Spanish, RemoteControlStep) =>
      "Activa Control remoto en Configuración → Conexiones → Acceso remoto."
    (SimplifiedChinese, RemoteControlStep) =>
      "在“设置 → 连接 → 远程访问”中开启远程控制。"
    (TraditionalChinese, RemoteControlStep) =>
      "在「設定 → 連線 → 遠端存取」中開啟遠端控制。"
    (Japanese, RemoteControlStep) =>
      "「設定 → 接続 → リモートアクセス」でリモート操作を有効にします。"
    (English, ListedWhileRunning) =>
      "The computer then appears in the device menu whenever SeekMoon is running on it."
    (Spanish, ListedWhileRunning) =>
      "Después, el equipo aparecerá en el menú de dispositivos mientras SeekMoon esté abierto en él."
    (SimplifiedChinese, ListedWhileRunning) =>
      "之后，只要这台电脑上的 SeekMoon 正在运行，它就会出现在设备菜单中。"
    (TraditionalChinese, ListedWhileRunning) =>
      "之後，只要這台電腦上的 SeekMoon 正在執行，它就會出現在裝置選單中。"
    (Japanese, ListedWhileRunning) =>
      "以降、そのコンピューターで SeekMoon が起動している間はデバイスメニューに表示されます。"
  }
}
