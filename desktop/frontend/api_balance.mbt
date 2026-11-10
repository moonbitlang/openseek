// The provider balance of the focused host's configured key. The key never
// reaches a client, so the host asks the provider (`settings.balance`) and
// the page only mirrors the answer: Settings shows it beside the key, and
// the composer warns when it is about to stop runs.

///|
/// Only DeepSeek reports an account balance in CNY or USD; these are the
/// amounts below which a few more turns would exhaust it.
const LowBalanceCny : Double = 2.0

///|
const LowBalanceUsd : Double = 0.3

///|
#derive(Eq)
priv struct ApiBalanceState {
  // The newest applied answer; None before the first one for this host.
  reply : @protocol.ApiBalanceReply?
  loading : Bool
  // The newest request id. Replies to older requests are dropped, so a slow
  // answer for a replaced key never overwrites the current one.
  request : Int32
  // The host settings revision the newest request was made for, so the
  // settings echo of one save (reply plus broadcast) asks only once. None
  // before the first request for this host.
  revision : Int32?
}

///|
fn ApiBalanceState::empty() -> ApiBalanceState {
  { reply: None, loading: false, request: 0, revision: None, }
}

///|
/// Drop what belongs to the previous host or connection. The request counter keeps
/// counting so a reply still in flight from that host can never match.
fn ApiBalanceState::forget(self : ApiBalanceState) -> ApiBalanceState {
  { ..ApiBalanceState::empty(), request: self.request, }
}

///|
/// Whether the focused host's settings name a provider that can report a
/// balance for its key. A native SSH host keeps its own settings, which
/// this page does not mirror.
fn Model::api_balance_queryable(self : Model) -> Bool {
  self.host_settings_loaded() &&
  !@interop.is_native_ssh(self.focused) &&
  self.api_provider() is (Deepseek | OpenRouter) &&
  self.api_ready()
}

///|
/// Ask the focused host for the balance. `force` re-asks for a settings
/// revision already asked about: the Refresh button, and a finished run that
/// has just spent some of it.
fn Model::refresh_api_balance(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  force~ : Bool,
) -> (@cmd.Cmd, Model) {
  guard self.api_balance_queryable() else {
    return (@cmd.none, { ..self, api_balance: self.api_balance.forget(), })
  }
  let revision = self.host_settings().map(settings => settings.revision)
  if !force && self.api_balance.revision == revision {
    return (@cmd.none, self)
  }
  let request = self.api_balance.request + 1
  (
    fetch_api_balance(dispatch, self.focused, request),
    {
      ..self,
      api_balance: { ..self.api_balance, loading: true, request, revision, },
    },
  )
}

///|
fn fetch_api_balance(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  request : Int32,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply = @interop.bridge_request(
        channel,
        @commands.settings_balance,
        @protocol.EmptyPayload::NoPayload,
      ) catch {
        error => BalanceFailed(@interop.bridge_error_text(error))
      }
      scheduler.add(dispatch(ApiBalanceLoaded(reply, request~)))
    })
    |> ignore
  })
}

///|
/// Apply a reply when it answers the newest request for the focused host.
fn Model::receive_api_balance(
  self : Model,
  channel : @interop.ChannelId,
  reply : @protocol.ApiBalanceReply,
  request : Int32,
) -> Model {
  guard channel == self.focused && request == self.api_balance.request else {
    return self
  }
  {
    ..self,
    api_balance: { ..self.api_balance, reply: Some(reply), loading: false, },
  }
}

///|
/// An amount as money: two decimals, with the symbol for the currencies the
/// providers report and the ISO code for anything else.
fn format_balance_amount(amount : @protocol.ApiBalanceAmount) -> String {
  let cents = (amount.amount * 100.0).round().to_int64()
  let sign = if cents < 0L { "-" } else { "" }
  let cents = cents.abs()
  let fraction = cents % 100L
  let number = "\{sign}\{cents / 100L}.\{if fraction < 10L { "0" } else { "" }}\{fraction}"
  match amount.currency {
    "CNY" => "¥\{number}"
    "USD" => "$\{number}"
    currency => "\{number} \{currency}"
  }
}

///|
fn format_balance(balance : @protocol.ApiBalance) -> String {
  balance.amounts.map(format_balance_amount).join(" · ")
}

///|
/// The composer's warning for `provider`'s balance, if one is due: exhausted
/// when the provider says requests can no longer be paid for, low when every
/// reported amount is under its currency's threshold.
fn balance_warning(
  balance : @protocol.ApiBalance,
  provider : String,
) -> @settings.Message? {
  if !balance.available {
    return Some(ExhaustedBalanceNotice(provider))
  }
  let low = !balance.amounts.is_empty() &&
    balance.amounts.all(amount => {
      match amount.currency {
        "CNY" => amount.amount < LowBalanceCny
        "USD" => amount.amount < LowBalanceUsd
        _ => false
      }
    })
  if low {
    Some(LowBalanceNotice(provider, format_balance(balance)))
  } else {
    None
  }
}

///|
/// The composer's balance notice for the focused host, if one is due.
fn Model::balance_notice(self : Model) -> @composer.ContextComponent? {
  guard self.api_balance_queryable() &&
    self.api_balance.reply is Some(BalanceReported(balance)) &&
    balance_warning(
      balance,
      if self.api_provider() is OpenRouter {
        "OpenRouter"
      } else {
        "DeepSeek"
      },
    )
    is Some(warning) else {
    return None
  }
  Some(
    @composer.BalanceNotice(
      text=@settings.text(self.locale, warning),
      button=@settings.text(self.locale, ViewBalance),
    ),
  )
}

///|
/// The Settings row under the key field. Absent when the provider has no
/// balance query or the key is not saved yet.
fn api_balance_row(dispatch : @cmd.Emit[Msg], model : Model) -> @html.Html? {
  guard model.api_balance_queryable() else { return None }
  let locale = model.locale
  let state = model.api_balance
  let (text, warning) = match state.reply {
    None => (@settings.text(locale, CheckingBalance), false)
    Some(BalanceReported(balance)) =>
      if balance.available {
        (format_balance(balance), false)
      } else {
        (
          "\{format_balance(balance)} — \{@settings.text(locale, BalanceExhausted)}",
          true,
        )
      }
    Some(BalanceUnsupported) =>
      (@settings.text(locale, OpenRouterUncapped), false)
    Some(BalanceFailed(message)) => (message, true)
  }
  Some(
    @ui.form_row(
      @settings.text(locale, Balance),
      [
        @html.span(
          class=if warning {
            "api-balance-value error"
          } else {
            "api-balance-value"
          },
          attrs=@html.Attrs::build().role("status"),
          text,
        ),
        @html.button(
          class="button secondary",
          type_="button",
          disabled=state.loading,
          on_click=dispatch(RefreshApiBalance),
          if state.loading {
            @settings.text(locale, CheckingBalance)
          } else {
            shell_text(locale, RefreshLabel)
          },
        ),
      ],
      desc?=if model.api_provider() is OpenRouter {
        Some(@settings.text(locale, OpenRouterBalanceDescription))
      } else {
        None
      },
    ),
  )
}
