// Feature-owned UI messages; both locales are exhaustive.

///|
priv enum UiMessage {
  BackLabel
  ForwardLabel
  ReloadLabel
  EnterUrl
  OpenBrowser
}

///|
fn ui(locale : @i18n.Locale, message : UiMessage) -> String {
  match (locale, message) {
    (English, BackLabel) => "Back"
    (SimplifiedChinese, BackLabel) => "后退"
    (English, ForwardLabel) => "Forward"
    (SimplifiedChinese, ForwardLabel) => "前进"
    (English, ReloadLabel) => "Reload"
    (SimplifiedChinese, ReloadLabel) => "重新加载"
    (English, EnterUrl) => "Enter a URL"
    (SimplifiedChinese, EnterUrl) => "输入 URL"
    (English, OpenBrowser) => "Open in system browser"
    (SimplifiedChinese, OpenBrowser) => "在系统浏览器中打开"
  }
}
