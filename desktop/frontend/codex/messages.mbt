///|
priv enum StatusMessage {
  Starting
  Running
  Connected
  CheckingAccount
  SignInRequired
  NoAccountRequired
}

///|
fn status_text(locale : @i18n.Locale, message : StatusMessage) -> String {
  match (locale, message) {
    (English, Starting) => "Starting Codex…"
    (SimplifiedChinese, Starting) => "正在启动 Codex…"
    (English, Running) => "Running"
    (SimplifiedChinese, Running) => "运行中"
    (English, Connected) => "Connected"
    (SimplifiedChinese, Connected) => "已连接"
    (English, CheckingAccount) => "Checking account…"
    (SimplifiedChinese, CheckingAccount) => "正在检查账户…"
    (English, SignInRequired) => "Sign in required"
    (SimplifiedChinese, SignInRequired) => "需要登录"
    (English, NoAccountRequired) => "No account required"
    (SimplifiedChinese, NoAccountRequired) => "无需账户"
  }
}
