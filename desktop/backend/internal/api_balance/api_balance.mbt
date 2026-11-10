// Balance queries against the providers that expose one to an ordinary
// inference key. DeepSeek reports the account balance; OpenRouter only lets
// an inference key read its own spending cap (account credits need a
// management key), so an uncapped OpenRouter key has nothing to report.

///|
const DeepseekBalanceUrl = "https://api.deepseek.com/user/balance"

///|
const OpenRouterKeyUrl = "https://openrouter.ai/api/v1/key"

///|
/// A balance read is a quick GET; a provider that has not answered by then
/// is reported as unreachable instead of leaving Settings spinning.
const BalanceTimeoutMs = 15000

///|
/// The account whose balance to ask for, with the key that authenticates it.
pub(all) enum Account {
  Deepseek(key~ : String)
  OpenRouter(key~ : String)
}

///|
/// A 200 whose body is not the documented shape.
priv suberror Malformed

///|
/// Ask the provider. Never raises: every failure becomes `BalanceFailed`
/// with a reason the Settings row can show as-is.
pub async fn Account::balance(self : Account) -> @protocol.ApiBalanceReply {
  let (name, url, key) = match self {
    Deepseek(key~) => ("DeepSeek", DeepseekBalanceUrl, key)
    OpenRouter(key~) => ("OpenRouter", OpenRouterKeyUrl, key)
  }
  let answer = @async.with_timeout_opt(BalanceTimeoutMs, () => {
    @http.get_text(url, headers={ "Authorization": "Bearer \{key}" })
  }) catch {
    error => return BalanceFailed("\{name} is unreachable: \{error}")
  }
  guard answer is Some((response, body)) else {
    return BalanceFailed(
      "\{name} is unreachable: no answer within \{BalanceTimeoutMs / 1000}s",
    )
  }
  guard response.code == 200 else {
    return BalanceFailed("\{name} answered HTTP \{response.code}")
  }
  let parsed = try {
    let json = @json.parse(body)
    match self {
      Deepseek(..) => Some(parse_deepseek(json))
      OpenRouter(..) => parse_openrouter(json)
    }
  } catch {
    _ => return BalanceFailed("\{name} answered an unexpected balance format")
  }
  match parsed {
    Some(balance) => BalanceReported(balance)
    None => BalanceUnsupported
  }
}

///|
/// `GET /user/balance`: `is_available` plus one entry per currency, whose
/// amounts are decimal strings.
fn parse_deepseek(json : Json) -> @protocol.ApiBalance raise Malformed {
  guard json
    is {
      "is_available": True
      | False as available,
      "balance_infos": Array(infos),
      ..
    } else {
    raise Malformed
  }
  let amounts : Array[@protocol.ApiBalanceAmount] = []
  for info in infos {
    guard info
      is { "currency": String(currency), "total_balance": String(total), .. } else {
      raise Malformed
    }
    let amount = @string.parse_double(total) catch { _ => raise Malformed }
    amounts.push({ currency, amount, })
  }
  { available: available is True, amounts, }
}

///|
/// `GET /api/v1/key`: `limit_remaining` is what the key may still spend in
/// USD, or null when the key has no cap — then the remaining spend is the
/// account's credit, which an inference key cannot read.
fn parse_openrouter(json : Json) -> @protocol.ApiBalance? raise Malformed {
  guard json is { "data": Object(data), .. } else { raise Malformed }
  match data.get("limit_remaining") {
    None | Some(Null) => None
    Some(Number(remaining, ..)) =>
      Some({
        available: remaining > 0.0,
        amounts: [{ currency: "USD", amount: remaining, }],
      })
    Some(_) => raise Malformed
  }
}
