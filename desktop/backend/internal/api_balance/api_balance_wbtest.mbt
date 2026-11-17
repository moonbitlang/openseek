///|
test "DeepSeek balance reports every currency and the availability verdict" {
  let balance = parse_deepseek({
    "is_available": true,
    "balance_infos": [
      {
        "currency": "CNY",
        "total_balance": "110.00",
        "granted_balance": "10.00",
        "topped_up_balance": "100.00",
      },
    ],
  })
  assert_eq(balance, {
    available: true,
    amounts: [{ currency: "CNY", amount: 110.0, }],
  })
}

///|
test "DeepSeek reports an exhausted account as unavailable" {
  let balance = parse_deepseek({
    "is_available": false,
    "balance_infos": [{ "currency": "USD", "total_balance": "0.00" }],
  })
  assert_eq(balance, {
    available: false,
    amounts: [{ currency: "USD", amount: 0.0, }],
  })
}

///|
test "a malformed DeepSeek amount fails instead of reading as zero" {
  let result = Ok(
    parse_deepseek({
      "is_available": true,
      "balance_infos": [{ "currency": "CNY", "total_balance": "n/a" }],
    }),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(Malformed))
}

///|
test "an OpenRouter key with a cap reports what is left under it" {
  let balance = parse_openrouter({
    "data": {
      "label": "k",
      "limit": 10.0,
      "usage": 7.5,
      "limit_remaining": 2.5,
    },
  })
  assert_eq(
    balance,
    Some({ available: true, amounts: [{ currency: "USD", amount: 2.5, }], }),
  )
}

///|
test "an uncapped OpenRouter key has no readable balance" {
  let balance = parse_openrouter({
    "data": {
      "label": "k",
      "limit": null,
      "usage": 7.5,
      "limit_remaining": null,
    },
  })
  assert_eq(balance, None)
}
