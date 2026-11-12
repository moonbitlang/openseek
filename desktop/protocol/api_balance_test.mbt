///|
test "balance replies survive the wire in every state" {
  let replies : Array[@protocol.ApiBalanceReply] = [
    BalanceReported({
      available: true,
      amounts: [{ currency: "CNY", amount: 110.5, }],
    }),
    BalanceUnsupported,
    BalanceFailed("DeepSeek answered HTTP 401"),
  ]
  for reply in replies {
    let decoded : @protocol.ApiBalanceReply = @json.from_json(reply.to_json())
    assert_eq(decoded, reply)
  }
}
