///|
test "compact job filenames distinguish case and preserve legacy IDs" {
  let upper = "AZTjwQBAeryN7wEjRWeJqw"
  let lower = "AZTjwQBaeryN7wEjRWeJqw"
  assert_true(
    @openseek_protocol.job_storage_name(upper) !=
    @openseek_protocol.job_storage_name(lower),
  )
  for id in [upper, lower, "0194e3c1-2345-7abc-8def-0123456789ab", "bg-1"] {
    let name = @openseek_protocol.job_storage_name(id)
    assert_eq(name, name.to_lower())
    assert_eq(@openseek_protocol.job_id_from_storage(name), id)
    assert_true(@openseek_protocol.valid_job_component(name))
  }
}
