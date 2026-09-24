///|
test "equal paths from different sources have independent component keys" {
  let live = @project.Id(
    source="openseek.projects",
    channel="local",
    root="/work/openseek",
  )
  let archived = @project.Id(
    source="openseek.archived",
    channel="local",
    root="/work/openseek",
  )
  assert_true(live != archived)
  assert_true(live.key() != archived.key())
}
