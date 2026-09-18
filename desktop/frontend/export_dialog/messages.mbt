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
    (TraditionalChinese, ExportConversation) => "匯出對話"
    (Japanese, ExportConversation) => "チャットをエクスポート"
    (English, CloseLabel) => "Close"
    (SimplifiedChinese, CloseLabel) => "关闭"
    (TraditionalChinese, CloseLabel) => "關閉"
    (Japanese, CloseLabel) => "閉じる"
    (English, CloseDialog) => "Close export dialog"
    (SimplifiedChinese, CloseDialog) => "关闭导出对话框"
    (TraditionalChinese, CloseDialog) => "關閉匯出對話方塊"
    (Japanese, CloseDialog) => "エクスポートダイアログを閉じる"
    (English, ExportDescription) =>
      "Download saves an HTML file. Share uploads HTML and JSON, including tool inputs and outputs. Anyone with the link can view it for 7 days, preview HTML, and download both files. Check for private information before sharing."
    (SimplifiedChinese, ExportDescription) =>
      "下载会保存 HTML 文件。分享会上传 HTML 和 JSON，包括工具的输入和输出。任何获得链接的人都可以在 7 天内查看、预览 HTML 并下载这两个文件。分享前请检查是否包含隐私信息。"
    (TraditionalChinese, ExportDescription) =>
      "下載會儲存 HTML 檔案。分享會上傳 HTML 和 JSON，包括工具的輸入和輸出。任何獲得連結的人都可以在 7 天內檢視、預覽 HTML 並下載這兩個檔案。分享前請檢查是否包含隱私資訊。"
    (Japanese, ExportDescription) =>
      "ダウンロードすると HTML ファイルが保存されます。共有するとツールの入出力を含む HTML と JSON がアップロードされます。リンクを知っている人は 7 日間、内容の閲覧、HTML のプレビュー、両ファイルのダウンロードが可能です。共有前に個人情報が含まれていないか確認してください。"
    (English, SavingLabel) => "Saving…"
    (SimplifiedChinese, SavingLabel) => "正在保存…"
    (TraditionalChinese, SavingLabel) => "正在儲存…"
    (Japanese, SavingLabel) => "保存中…"
    (English, DownloadLabel) => "Download"
    (SimplifiedChinese, DownloadLabel) => "下载"
    (TraditionalChinese, DownloadLabel) => "下載"
    (Japanese, DownloadLabel) => "ダウンロード"
    (English, SharingLabel) => "Sharing…"
    (SimplifiedChinese, SharingLabel) => "正在分享…"
    (TraditionalChinese, SharingLabel) => "正在分享…"
    (Japanese, SharingLabel) => "共有中…"
    (English, ShareLabel) => "Share"
    (SimplifiedChinese, ShareLabel) => "分享"
    (TraditionalChinese, ShareLabel) => "分享"
    (Japanese, ShareLabel) => "共有"
    (English, ChooseSavePath) => "Choose where to save the HTML file."
    (SimplifiedChinese, ChooseSavePath) =>
      "选择 HTML 文件的保存位置。"
    (TraditionalChinese, ChooseSavePath) =>
      "選擇 HTML 檔案的儲存位置。"
    (Japanese, ChooseSavePath) =>
      "HTML ファイルの保存先を選択してください。"
    (English, UploadingConversation) => "Uploading conversation…"
    (SimplifiedChinese, UploadingConversation) => "正在上传对话…"
    (TraditionalChinese, UploadingConversation) => "正在上傳對話…"
    (Japanese, UploadingConversation) =>
      "チャットをアップロード中…"
    (English, CompleteBrowserSignIn) =>
      "Complete sign-in in your browser, then click Share."
    (SimplifiedChinese, CompleteBrowserSignIn) =>
      "在浏览器中完成登录，然后点击“分享”。"
    (TraditionalChinese, CompleteBrowserSignIn) =>
      "在瀏覽器中完成登入，然後點選“分享”。"
    (Japanese, CompleteBrowserSignIn) =>
      "ブラウザーでログインを完了してから「共有」をクリックしてください。"
    (English, SignInDescription) =>
      "Sign in to your OpenSeek server to share this conversation."
    (SimplifiedChinese, SignInDescription) =>
      "登录 OpenSeek 服务器以分享此对话。"
    (TraditionalChinese, SignInDescription) =>
      "登入 OpenSeek 伺服器以分享此對話。"
    (Japanese, SignInDescription) =>
      "このチャットを共有するには OpenSeek サーバーにログインしてください。"
    (English, SignInLabel) => "Sign in"
    (SimplifiedChinese, SignInLabel) => "登录"
    (TraditionalChinese, SignInLabel) => "登入"
    (Japanese, SignInLabel) => "ログイン"
    (English, RetrySignIn) => "Try signing in again"
    (SimplifiedChinese, RetrySignIn) => "重新尝试登录"
    (TraditionalChinese, RetrySignIn) => "重新嘗試登入"
    (Japanese, RetrySignIn) => "ログインを再試行"
    (English, ShareLink) => "Share link"
    (SimplifiedChinese, ShareLink) => "分享链接"
    (TraditionalChinese, ShareLink) => "分享連結"
    (Japanese, ShareLink) => "共有リンク"
    (English, CopyClipboard) => "Copy to clipboard"
    (SimplifiedChinese, CopyClipboard) => "复制到剪贴板"
    (TraditionalChinese, CopyClipboard) => "複製到剪貼簿"
    (Japanese, CopyClipboard) => "クリップボードにコピー"
    (English, LinkCopied) => "Share link copied"
    (SimplifiedChinese, LinkCopied) => "已复制分享链接"
    (TraditionalChinese, LinkCopied) => "已複製分享連結"
    (Japanese, LinkCopied) => "共有リンクをコピーしました"
    (English, CopyShareLink) => "Copy share link"
    (SimplifiedChinese, CopyShareLink) => "复制分享链接"
    (TraditionalChinese, CopyShareLink) => "複製分享連結"
    (Japanese, CopyShareLink) => "共有リンクをコピー"
    (English, CannotCopy) =>
      "Could not copy. Select the link and copy it manually."
    (SimplifiedChinese, CannotCopy) =>
      "无法复制，请选中链接后手动复制。"
    (TraditionalChinese, CannotCopy) =>
      "無法複製，請選中連結後手動複製。"
    (Japanese, CannotCopy) =>
      "コピーできません。リンクを選択して手動でコピーしてください。"
  }
}
