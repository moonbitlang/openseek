///|
test "external link opener is absent from the relay method catalog" {
  let state = @api.ApiState(engine="unused")
  let connection = @host.HostConnection()
  assert_false(
    @api.endpoints(state, connection).any(endpoint => {
      endpoint.name() == @commands.shell_open_external.name()
    }),
  )
}
