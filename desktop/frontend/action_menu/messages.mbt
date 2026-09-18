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
    (SimplifiedChinese, ShowFinder) => "在访达中显示"
    (Japanese, ShowFinder) => "Finder に表示"
    (English, ShowExplorer) => "Show in File Explorer"
    (SimplifiedChinese, ShowExplorer) => "在文件资源管理器中显示"
    (Japanese, ShowExplorer) => "エクスプローラーに表示"
    (English, ShowFolder) => "Show in Folder"
    (SimplifiedChinese, ShowFolder) => "在文件夹中显示"
    (Japanese, ShowFolder) => "フォルダーに表示"
    (English, OpenNewTab) => "Open in New Tab"
    (SimplifiedChinese, OpenNewTab) => "在新标签页中打开"
    (Japanese, OpenNewTab) => "新しいタブで開く"
    (English, OpenLabel) => "Open"
    (SimplifiedChinese, OpenLabel) => "打开"
    (Japanese, OpenLabel) => "開く"
    (English, OpenDefaultBrowser) => "Open in Default Browser"
    (SimplifiedChinese, OpenDefaultBrowser) => "在默认浏览器中打开"
    (Japanese, OpenDefaultBrowser) => "既定のブラウザーで開く"
    (English, OpenSystemBrowser) => "Open in the system default browser"
    (SimplifiedChinese, OpenSystemBrowser) =>
      "在系统默认浏览器中打开"
    (Japanese, OpenSystemBrowser) =>
      "システムの既定ブラウザーで開く"
    (English, CopyLink) => "Copy Link"
    (SimplifiedChinese, CopyLink) => "复制链接"
    (Japanese, CopyLink) => "リンクをコピー"
    (English, CopyLinkAddress) => "Copy link address"
    (SimplifiedChinese, CopyLinkAddress) => "复制链接地址"
    (Japanese, CopyLinkAddress) => "リンク先のアドレスをコピー"
    (English, OpenEmail) => "Open email link"
    (SimplifiedChinese, OpenEmail) => "打开电子邮件链接"
    (Japanese, OpenEmail) => "メールリンクを開く"
    (English, CopyEmail) => "Copy Email Address"
    (SimplifiedChinese, CopyEmail) => "复制电子邮件地址"
    (Japanese, CopyEmail) => "メールアドレスをコピー"
    (English, CopyEmailHint) => "Copy email address"
    (SimplifiedChinese, CopyEmailHint) => "复制电子邮件地址"
    (Japanese, CopyEmailHint) => "メールアドレスをコピー"
    (English, OpenFile) => "Open file"
    (SimplifiedChinese, OpenFile) => "打开文件"
    (Japanese, OpenFile) => "ファイルを開く"
    (English, CopyPath) => "Copy Path"
    (SimplifiedChinese, CopyPath) => "复制路径"
    (Japanese, CopyPath) => "パスをコピー"
    (English, CopyFilePath) => "Copy file path"
    (SimplifiedChinese, CopyFilePath) => "复制文件路径"
    (Japanese, CopyFilePath) => "ファイルパスをコピー"
    (English, CopyLabel) => "Copy"
    (SimplifiedChinese, CopyLabel) => "复制"
    (Japanese, CopyLabel) => "コピー"
    (English, CopySelected) => "Copy selected text"
    (SimplifiedChinese, CopySelected) => "复制选中文本"
    (Japanese, CopySelected) => "選択したテキストをコピー"
    (English, ContextMenu) => "Context menu"
    (SimplifiedChinese, ContextMenu) => "上下文菜单"
    (Japanese, ContextMenu) => "コンテキストメニュー"
  }
}
