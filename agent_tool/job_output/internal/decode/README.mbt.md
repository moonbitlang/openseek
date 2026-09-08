# Job output arguments

The decoder validates `job_output` arguments independently of the model-facing
schema. It returns the required `job_id` and an optional character `offset`.

| Field | Type | Meaning |
| --- | --- | --- |
| `job_id` | string, required | Background job to read. |
| `offset` | number, optional | Zero or positive character offset from the start. Absent/null selects the recent tail. |

`job_output` no longer accepts `wait_ms`, including null or zero. Older callers
receive an error directing them to `job_wait` with `job_ids`. Reading and waiting
are separate operations; this decoder never selects a wait duration.

```mbt check
///|
test "decode an immediate tail read" {
  let input = @decode.decode({ "job_id": "bg-3" })
  assert_eq(input.job_id, "bg-3")
  assert_eq(input.offset, None)
}

///|
test "decode an earlier output window" {
  assert_eq(
    @decode.decode({ "job_id": "bg-3", "offset": 12000 }).offset,
    Some(12000),
  )
}
```
