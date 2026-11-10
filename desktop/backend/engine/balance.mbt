///|
/// The `settings.balance` reply: ask the selected provider what the
/// configured key can still spend. The DeepSeek key resolves the same way a
/// run's does, so an environment-configured install reports too.
pub async fn api_balance(manager : EngineManager) -> @protocol.ApiBalanceReply {
  let (settings, _) = manager.settings_snapshot()
  let account : @api_balance.Account? = match settings.provider {
    Deepseek => settings.deepseek_key().map(key => Deepseek(key~))
    Custom if settings.custom_api_url
      is Some(@protocol.OpenRouterChatCompletionsUrl) =>
      settings.custom_api_key.map(key => OpenRouter(key~))
    Glm | Custom => None
  }
  guard account is Some(account) else { return BalanceUnsupported }
  account.balance()
}
