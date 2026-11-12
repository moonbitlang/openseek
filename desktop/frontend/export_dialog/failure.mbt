///|
#derive(Eq)
pub(all) enum Failure {
  Cloud(@cloud.Failure)
  Bridge(@interop.BridgeProblem)
  Diagnostic(String)
  SignInChanged
  ShareAuthorizationHttp(Int32)
  InvalidUploadPermission
  DownloadFromFilePanel
  SignInToExport
  AccountSignInExpired
  LocalConversationSharingUnavailable
  LocalFileSharingUnavailable
}

///|
pub extend Failure with Eq::{equal, not_equal}

///|
fn Failure::text(self : Failure, locale : @i18n.Locale) -> String {
  match (locale, self) {
    (_, Cloud(failure)) => failure.text(locale)
    (_, Bridge(problem)) => problem.text(locale)
    (_, Diagnostic(detail)) => detail
    (English, SignInChanged) =>
      "Sign-in changed before sharing. Try sharing again."
    (Spanish, SignInChanged) =>
      "La sesión cambió antes de compartir. Inténtalo de nuevo."
    (SimplifiedChinese, SignInChanged) =>
      "分享前登录状态已更改。请重新分享。"
    (TraditionalChinese, SignInChanged) =>
      "分享前登入狀態已變更。請重新分享。"
    (Japanese, SignInChanged) =>
      "共有前にログイン状態が変わりました。もう一度共有してください。"
    (English, ShareAuthorizationHttp(status)) =>
      "Could not prepare sharing (HTTP \{status}). Try sharing again."
    (Spanish, ShareAuthorizationHttp(status)) =>
      "No se pudo preparar el enlace compartido (HTTP \{status}). Inténtalo de nuevo."
    (SimplifiedChinese, ShareAuthorizationHttp(status)) =>
      "无法准备分享（HTTP \{status}）。请重新分享。"
    (TraditionalChinese, ShareAuthorizationHttp(status)) =>
      "無法準備分享（HTTP \{status}）。請重新分享。"
    (Japanese, ShareAuthorizationHttp(status)) =>
      "共有を準備できませんでした（HTTP \{status}）。もう一度共有してください。"
    (English, InvalidUploadPermission) => "Invalid share upload permission."
    (Spanish, InvalidUploadPermission) =>
      "El permiso de subida para compartir no es válido."
    (SimplifiedChinese, InvalidUploadPermission) =>
      "分享上传权限无效。"
    (TraditionalChinese, InvalidUploadPermission) =>
      "分享上傳權限無效。"
    (Japanese, InvalidUploadPermission) =>
      "共有アップロードの権限が無効です。"
    (English, DownloadFromFilePanel) => "Download files from the file panel."
    (Spanish, DownloadFromFilePanel) =>
      "Descarga los archivos desde el panel de archivos."
    (SimplifiedChinese, DownloadFromFilePanel) =>
      "请从文件面板下载文件。"
    (TraditionalChinese, DownloadFromFilePanel) =>
      "請從檔案面板下載檔案。"
    (Japanese, DownloadFromFilePanel) =>
      "ファイルパネルからファイルをダウンロードしてください。"
    (English, SignInToExport) => "Sign in to export Cloud history."
    (Spanish, SignInToExport) =>
      "Inicia sesión para exportar el historial de Cloud."
    (SimplifiedChinese, SignInToExport) => "请登录以导出云端历史。"
    (TraditionalChinese, SignInToExport) => "請登入以匯出雲端記錄。"
    (Japanese, SignInToExport) =>
      "クラウドの履歴をエクスポートするにはログインしてください。"
    (English, AccountSignInExpired) => "Your account sign-in expired."
    (Spanish, AccountSignInExpired) => "Tu sesión ha caducado."
    (SimplifiedChinese, AccountSignInExpired) => "账户登录已过期。"
    (TraditionalChinese, AccountSignInExpired) => "帳戶登入已過期。"
    (Japanese, AccountSignInExpired) =>
      "アカウントのログインが期限切れです。"
    (English, LocalConversationSharingUnavailable) =>
      "Sharing is unavailable in the local debug console. Use SeekMoonDev.app or the hosted browser console. You can still download this conversation."
    (Spanish, LocalConversationSharingUnavailable) =>
      "No se puede compartir desde la consola local de depuración. Usa SeekMoonDev.app o la consola web alojada. Aún puedes descargar esta conversación."
    (SimplifiedChinese, LocalConversationSharingUnavailable) =>
      "本机调试控制台不支持分享。请使用 SeekMoonDev.app 或托管的浏览器控制台。你仍可下载此对话。"
    (TraditionalChinese, LocalConversationSharingUnavailable) =>
      "本機偵錯主控台不支援分享。請使用 SeekMoonDev.app 或託管的瀏覽器主控台。你仍可下載此對話。"
    (Japanese, LocalConversationSharingUnavailable) =>
      "ローカルのデバッグコンソールでは共有できません。SeekMoonDev.app またはホストされたブラウザーコンソールを使用してください。この会話はダウンロードできます。"
    (English, LocalFileSharingUnavailable) =>
      "Sharing is unavailable in the local debug console. Use SeekMoonDev.app or the hosted browser console."
    (Spanish, LocalFileSharingUnavailable) =>
      "No se puede compartir desde la consola local de depuración. Usa SeekMoonDev.app o la consola web alojada."
    (SimplifiedChinese, LocalFileSharingUnavailable) =>
      "本机调试控制台不支持分享。请使用 SeekMoonDev.app 或托管的浏览器控制台。"
    (TraditionalChinese, LocalFileSharingUnavailable) =>
      "本機偵錯主控台不支援分享。請使用 SeekMoonDev.app 或託管的瀏覽器主控台。"
    (Japanese, LocalFileSharingUnavailable) =>
      "ローカルのデバッグコンソールでは共有できません。SeekMoonDev.app またはホストされたブラウザーコンソールを使用してください。"
  }
}
