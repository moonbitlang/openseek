// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  ExportConversation
  CloseLabel
  CloseDialog
  ExportDescription
  SavingLabel
  DownloadLabel
  SharingLabel
  ShareLabel
  ChooseSavePath
  UploadingConversation
  CompleteBrowserSignIn
  SignInDescription
  SignInLabel
  RetrySignIn
  ShareLink
  CopyClipboard
  LinkCopied
  CopyShareLink
  CannotCopy
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, ExportConversation) => "Export conversation"
    (SimplifiedChinese, ExportConversation) => "导出对话"
    (English, CloseLabel) => "Close"
    (SimplifiedChinese, CloseLabel) => "关闭"
    (English, CloseDialog) => "Close export dialog"
    (SimplifiedChinese, CloseDialog) => "关闭导出对话框"
    (English, ExportDescription) =>
      "Download saves an HTML file. Share uploads HTML and JSON, including tool inputs and outputs. Anyone with the link can view it for 7 days, preview HTML, and download both files. Check for private information before sharing."
    (SimplifiedChinese, ExportDescription) =>
      "下载会保存 HTML 文件。分享会上传 HTML 和 JSON，包括工具的输入和输出。任何获得链接的人都可以在 7 天内查看、预览 HTML 并下载这两个文件。分享前请检查是否包含隐私信息。"
    (English, SavingLabel) => "Saving…"
    (SimplifiedChinese, SavingLabel) => "正在保存…"
    (English, DownloadLabel) => "Download"
    (SimplifiedChinese, DownloadLabel) => "下载"
    (English, SharingLabel) => "Sharing…"
    (SimplifiedChinese, SharingLabel) => "正在分享…"
    (English, ShareLabel) => "Share"
    (SimplifiedChinese, ShareLabel) => "分享"
    (English, ChooseSavePath) => "Choose where to save the HTML file."
    (SimplifiedChinese, ChooseSavePath) =>
      "选择 HTML 文件的保存位置。"
    (English, UploadingConversation) => "Uploading conversation…"
    (SimplifiedChinese, UploadingConversation) => "正在上传对话…"
    (English, CompleteBrowserSignIn) =>
      "Complete sign-in in your browser, then click Share."
    (SimplifiedChinese, CompleteBrowserSignIn) =>
      "在浏览器中完成登录，然后点击“分享”。"
    (English, SignInDescription) =>
      "Sign in to your OpenSeek server to share this conversation."
    (SimplifiedChinese, SignInDescription) =>
      "登录 OpenSeek 服务器以分享此对话。"
    (English, SignInLabel) => "Sign in"
    (SimplifiedChinese, SignInLabel) => "登录"
    (English, RetrySignIn) => "Try signing in again"
    (SimplifiedChinese, RetrySignIn) => "重新尝试登录"
    (English, ShareLink) => "Share link"
    (SimplifiedChinese, ShareLink) => "分享链接"
    (English, CopyClipboard) => "Copy to clipboard"
    (SimplifiedChinese, CopyClipboard) => "复制到剪贴板"
    (English, LinkCopied) => "Share link copied"
    (SimplifiedChinese, LinkCopied) => "已复制分享链接"
    (English, CopyShareLink) => "Copy share link"
    (SimplifiedChinese, CopyShareLink) => "复制分享链接"
    (English, CannotCopy) =>
      "Could not copy. Select the link and copy it manually."
    (SimplifiedChinese, CannotCopy) =>
      "无法复制，请选中链接后手动复制。"
  }
}
