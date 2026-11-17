///|
test "balances read as money in the provider's currency" {
  assert_eq(
    format_balance_amount({ currency: "CNY", amount: 110.0, }),
    "¥110.00",
  )
  assert_eq(format_balance_amount({ currency: "USD", amount: 0.054, }), "$0.05")
  assert_eq(
    format_balance_amount({ currency: "EUR", amount: 3.1, }),
    "3.10 EUR",
  )
}

///|
test "the composer warns only when the balance is exhausted or nearly so" {
  assert_true(
    balance_warning(
      { available: false, amounts: [{ currency: "CNY", amount: 50.0, }], },
      "DeepSeek",
    )
    is Some(ExhaustedBalanceNotice("DeepSeek")),
  )
  assert_true(
    balance_warning(
      { available: true, amounts: [{ currency: "CNY", amount: 1.5, }], },
      "DeepSeek",
    )
    is Some(LowBalanceNotice("DeepSeek", "¥1.50")),
  )
  assert_true(
    balance_warning(
      {
        available: true,
        amounts: [
          { currency: "CNY", amount: 1.5, },
          { currency: "USD", amount: 5.0, },
        ],
      },
      "DeepSeek",
    )
    is None,
  )
}

///|
test "one settings save asks for the balance once and drops superseded replies" {
  let settings = host_settings(provider="deepseek", has_deepseek_key=true)
  let base = test_model().map_host_settings(Local, _ => {
    HostSettingsMirror::loading()
  })
  let (_, loaded) = update_dev(
    test_dispatch(),
    HostSettingsLoaded(
      settings,
      connection_generation=Some(base.focused_connection_generation()),
    ),
    base,
  )
  assert_true(loaded.api_balance.loading)
  let first = loaded.api_balance.request
  // The broadcast echo of the same revision does not ask again.
  let (_, echoed) = update_dev(
    test_dispatch(),
    HostSettingsLoaded(settings, connection_generation=None),
    loaded,
  )
  assert_eq(echoed.api_balance.request, first)
  let (_, refreshed) = update(test_dispatch(), RefreshApiBalance, echoed)
  let stale : @protocol.ApiBalanceReply = BalanceReported({
    available: true,
    amounts: [{ currency: "CNY", amount: 9.0, }],
  })
  let (_, ignored) = update_dev(
    test_dispatch(),
    ApiBalanceLoaded(stale, request=first),
    refreshed,
  )
  assert_true(ignored.api_balance.reply is None && ignored.api_balance.loading)
  let (_, applied) = update_dev(
    test_dispatch(),
    ApiBalanceLoaded(
      BalanceReported({
        available: false,
        amounts: [{ currency: "CNY", amount: 0.0, }],
      }),
      request=refreshed.api_balance.request,
    ),
    ignored,
  )
  assert_false(applied.api_balance.loading)
  assert_true(applied.balance_notice() is Some(BalanceNotice(..)))
}

///|
test "providers without a balance query never ask" {
  let base = test_model().map_host_settings(Local, _ => {
    HostSettingsMirror::loading()
  })
  let (_, loaded) = update_dev(
    test_dispatch(),
    HostSettingsLoaded(
      host_settings(provider="glm", has_glm_key=true),
      connection_generation=Some(base.focused_connection_generation()),
    ),
    base,
  )
  assert_false(loaded.api_balance.loading)
  assert_true(loaded.api_balance.reply is None)
}

///|
test "a reply in flight when the host was left never lands after returning" {
  let (_, pending) = update(test_dispatch(), RefreshApiBalance, test_model())
  let sent = pending.api_balance.request
  // Leaving the host (or reconnecting) forgets its balance; returning keeps
  // the cached settings, so no new request replaces the old one.
  let returned = pending.reset_api_setup()
  let (_, late) = update_dev(
    test_dispatch(),
    ApiBalanceLoaded(
      BalanceReported({
        available: false,
        amounts: [{ currency: "CNY", amount: 0.0, }],
      }),
      request=sent,
    ),
    returned,
  )
  assert_true(late.api_balance.reply is None)
  assert_true(late.balance_notice() is None)
}
