///|
/// The chat endpoint of the frontend's OpenRouter preset. The host stores
/// OpenRouter as a custom endpoint; this URL is what identifies it on both
/// sides.
pub const OpenRouterChatCompletionsUrl : String = "https://openrouter.ai/api/v1/chat/completions"

///|
/// One currency's spendable amount on the provider account (or, for a key
/// with its own spending cap, what is left under that cap).
#derive(Debug, Eq)
pub(all) struct ApiBalanceAmount {
  currency : String
  amount : Double
}

///|
/// What the provider reports for the configured key. `available` is the
/// provider's own verdict on whether requests can still be paid for; the
/// amounts are what Settings displays.
#derive(Debug, Eq)
pub(all) struct ApiBalance {
  available : Bool
  amounts : Array[ApiBalanceAmount]
}

///|
/// The `settings.balance` reply. A failed query is a typed reply rather than
/// a raised error so its reason survives transports that redact raised
/// errors.
#derive(Debug, Eq)
pub(all) enum ApiBalanceReply {
  BalanceReported(ApiBalance)
  // The selected provider (or this key) has no balance query: GLM, a
  // generic custom endpoint, an OpenRouter key without a spending cap, or
  // no key at all.
  BalanceUnsupported
  BalanceFailed(String)
}

///|
pub impl FromJson for ApiBalanceAmount with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "API balance amount")
  {
    currency: object.required_string("currency"),
    amount: @json.from_json(
      object.required_json("amount"),
      path=path.add_key("amount"),
    ),
  }
}

///|
pub impl ToJson for ApiBalanceAmount with fn to_json(self) {
  { "currency": Json(self.currency), "amount": Json(self.amount) }
}

///|
pub impl FromJson for ApiBalanceReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "API balance reply")
  match object.required_string("status") {
    "reported" =>
      BalanceReported({
        available: object.required_bool("available"),
        amounts: object.required_array_of("amounts"),
      })
    "unsupported" => BalanceUnsupported
    "failed" => BalanceFailed(object.required_string("message"))
    _ =>
      raise JsonDecodeError(
        (path.add_key("status"), "expected reported, unsupported or failed"),
      )
  }
}

///|
pub impl ToJson for ApiBalanceReply with fn to_json(self) {
  match self {
    BalanceReported(balance) =>
      {
        "status": "reported",
        "available": Json(balance.available),
        "amounts": Json(balance.amounts.map(amount => amount.to_json())),
      }
    BalanceUnsupported => { "status": "unsupported" }
    BalanceFailed(message) => { "status": "failed", "message": Json(message) }
  }
}

///|
pub extend ApiBalanceAmount with Debug::{to_repr}

///|
pub extend ApiBalanceAmount with Eq::{equal, not_equal}

///|
pub extend ApiBalanceAmount with FromJson::{from_json}

///|
pub extend ApiBalanceAmount with ToJson::{to_json}

///|
pub extend ApiBalance with Debug::{to_repr}

///|
pub extend ApiBalance with Eq::{equal, not_equal}

///|
pub extend ApiBalanceReply with Debug::{to_repr}

///|
pub extend ApiBalanceReply with Eq::{equal, not_equal}

///|
pub extend ApiBalanceReply with FromJson::{from_json}

///|
pub extend ApiBalanceReply with ToJson::{to_json}
