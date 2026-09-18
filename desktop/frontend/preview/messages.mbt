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
    (TraditionalChinese, BackLabel) => "後退"
    (Japanese, BackLabel) => "戻る"
    (English, ForwardLabel) => "Forward"
    (SimplifiedChinese, ForwardLabel) => "前进"
    (TraditionalChinese, ForwardLabel) => "前進"
    (Japanese, ForwardLabel) => "進む"
    (English, ReloadLabel) => "Reload"
    (SimplifiedChinese, ReloadLabel) => "重新加载"
    (TraditionalChinese, ReloadLabel) => "重新載入"
    (Japanese, ReloadLabel) => "再読み込み"
    (English, EnterUrl) => "Enter a URL"
    (SimplifiedChinese, EnterUrl) => "输入 URL"
    (TraditionalChinese, EnterUrl) => "輸入 URL"
    (Japanese, EnterUrl) => "URL を入力"
    (English, OpenBrowser) => "Open in system browser"
    (SimplifiedChinese, OpenBrowser) => "在系统浏览器中打开"
    (TraditionalChinese, OpenBrowser) => "在系統瀏覽器中開啟"
    (Japanese, OpenBrowser) => "システムブラウザーで開く"
  }
}
