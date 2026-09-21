// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  ShowFinder
  ShowExplorer
  ShowFolder
  OpenNewTab
  OpenLabel
  OpenDefaultBrowser
  OpenSystemBrowser
  CopyLink
  CopyLinkAddress
  OpenEmail
  CopyEmail
  CopyEmailHint
  OpenFile
  CopyPath
  CopyFilePath
  CopyLabel
  CopySelected
  ContextMenu
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, ShowFinder) => "Show in Finder"
    (Spanish, ShowFinder) => "Mostrar en Finder"
    (SimplifiedChinese, ShowFinder) => "在访达中显示"
    (TraditionalChinese, ShowFinder) => "在訪達中顯示"
    (Japanese, ShowFinder) => "Finder に表示"
    (English, ShowExplorer) => "Show in File Explorer"
    (Spanish, ShowExplorer) => "Mostrar en el Explorador de archivos"
    (SimplifiedChinese, ShowExplorer) => "在文件资源管理器中显示"
    (TraditionalChinese, ShowExplorer) => "在檔案資源管理器中顯示"
    (Japanese, ShowExplorer) => "エクスプローラーに表示"
    (English, ShowFolder) => "Show in Folder"
    (Spanish, ShowFolder) => "Mostrar en la carpeta"
    (SimplifiedChinese, ShowFolder) => "在文件夹中显示"
    (TraditionalChinese, ShowFolder) => "在資料夾中顯示"
    (Japanese, ShowFolder) => "フォルダーに表示"
    (English, OpenNewTab) => "Open in New Tab"
    (Spanish, OpenNewTab) => "Abrir en una pestaña nueva"
    (SimplifiedChinese, OpenNewTab) => "在新标签页中打开"
    (TraditionalChinese, OpenNewTab) => "在新標籤頁中開啟"
    (Japanese, OpenNewTab) => "新しいタブで開く"
    (English, OpenLabel) => "Open"
    (Spanish, OpenLabel) => "Abrir"
    (SimplifiedChinese, OpenLabel) => "打开"
    (TraditionalChinese, OpenLabel) => "開啟"
    (Japanese, OpenLabel) => "開く"
    (English, OpenDefaultBrowser) => "Open in Default Browser"
    (Spanish, OpenDefaultBrowser) => "Abrir en el navegador predeterminado"
    (SimplifiedChinese, OpenDefaultBrowser) => "在默认浏览器中打开"
    (TraditionalChinese, OpenDefaultBrowser) => "在預設瀏覽器中開啟"
    (Japanese, OpenDefaultBrowser) => "既定のブラウザーで開く"
    (English, OpenSystemBrowser) => "Open in the system default browser"
    (Spanish, OpenSystemBrowser) =>
      "Abrir en el navegador predeterminado del sistema"
    (SimplifiedChinese, OpenSystemBrowser) =>
      "在系统默认浏览器中打开"
    (TraditionalChinese, OpenSystemBrowser) =>
      "在系統預設瀏覽器中開啟"
    (Japanese, OpenSystemBrowser) =>
      "システムの既定ブラウザーで開く"
    (English, CopyLink) => "Copy Link"
    (Spanish, CopyLink) => "Copiar enlace"
    (SimplifiedChinese, CopyLink) => "复制链接"
    (TraditionalChinese, CopyLink) => "複製連結"
    (Japanese, CopyLink) => "リンクをコピー"
    (English, CopyLinkAddress) => "Copy link address"
    (Spanish, CopyLinkAddress) => "Copiar dirección del enlace"
    (SimplifiedChinese, CopyLinkAddress) => "复制链接地址"
    (TraditionalChinese, CopyLinkAddress) => "複製連結地址"
    (Japanese, CopyLinkAddress) => "リンク先のアドレスをコピー"
    (English, OpenEmail) => "Open email link"
    (Spanish, OpenEmail) => "Abrir enlace de correo"
    (SimplifiedChinese, OpenEmail) => "打开电子邮件链接"
    (TraditionalChinese, OpenEmail) => "開啟電子郵件連結"
    (Japanese, OpenEmail) => "メールリンクを開く"
    (English, CopyEmail) => "Copy Email Address"
    (Spanish, CopyEmail) => "Copiar dirección de correo"
    (SimplifiedChinese, CopyEmail) => "复制电子邮件地址"
    (TraditionalChinese, CopyEmail) => "複製電子郵件地址"
    (Japanese, CopyEmail) => "メールアドレスをコピー"
    (English, CopyEmailHint) => "Copy email address"
    (Spanish, CopyEmailHint) => "Copiar dirección de correo"
    (SimplifiedChinese, CopyEmailHint) => "复制电子邮件地址"
    (TraditionalChinese, CopyEmailHint) => "複製電子郵件地址"
    (Japanese, CopyEmailHint) => "メールアドレスをコピー"
    (English, OpenFile) => "Open file"
    (Spanish, OpenFile) => "Abrir archivo"
    (SimplifiedChinese, OpenFile) => "打开文件"
    (TraditionalChinese, OpenFile) => "開啟檔案"
    (Japanese, OpenFile) => "ファイルを開く"
    (English, CopyPath) => "Copy Path"
    (Spanish, CopyPath) => "Copiar ruta"
    (SimplifiedChinese, CopyPath) => "复制路径"
    (TraditionalChinese, CopyPath) => "複製路徑"
    (Japanese, CopyPath) => "パスをコピー"
    (English, CopyFilePath) => "Copy file path"
    (Spanish, CopyFilePath) => "Copiar ruta del archivo"
    (SimplifiedChinese, CopyFilePath) => "复制文件路径"
    (TraditionalChinese, CopyFilePath) => "複製檔案路徑"
    (Japanese, CopyFilePath) => "ファイルパスをコピー"
    (English, CopyLabel) => "Copy"
    (Spanish, CopyLabel) => "Copiar"
    (SimplifiedChinese, CopyLabel) => "复制"
    (TraditionalChinese, CopyLabel) => "複製"
    (Japanese, CopyLabel) => "コピー"
    (English, CopySelected) => "Copy selected text"
    (Spanish, CopySelected) => "Copiar texto seleccionado"
    (SimplifiedChinese, CopySelected) => "复制选中文本"
    (TraditionalChinese, CopySelected) => "複製選中文字"
    (Japanese, CopySelected) => "選択したテキストをコピー"
    (English, ContextMenu) => "Context menu"
    (Spanish, ContextMenu) => "Menú contextual"
    (SimplifiedChinese, ContextMenu) => "上下文菜单"
    (TraditionalChinese, ContextMenu) => "快顯選單"
    (Japanese, ContextMenu) => "コンテキストメニュー"
  }
}
