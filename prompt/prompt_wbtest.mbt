///|
test "flash prompt keeps core MoonBit guidance" {
  let prompt = flash_prompt()
  assert_true(
    prompt.contains("MoonBit coding agent focused on implementing user tasks"),
  )
  assert_true(prompt.contains("Do not emit JSON action plans"))
  assert_true(prompt.contains("Run `moon check` through `shell`"))
  assert_true(prompt.contains("moon check:"))
  assert_true(prompt.contains("failures include `exit=<code>`"))
  assert_true(prompt.contains("exit=cancelled"))
  assert_true(prompt.contains(".mbt.md"))
  assert_true(prompt.contains("module-root `moon check --diagnostic-limit 1`"))
  assert_true(prompt.contains("much faster than"))
  assert_true(prompt.contains("primary"))
  assert_true(prompt.contains("Create `moon.mod` before running `moon info`"))
  assert_true(prompt.contains("small focused"))
  assert_true(prompt.contains("moonbitlang/core/argparse"))
  assert_true(prompt.contains("@stdio.stdin.read_all().text()"))
  assert_true(prompt.contains("s[:4]"))
  assert_true(prompt.contains("Raw multi-line strings use `#|`"))
  assert_true(prompt.contains("Interpolated multi-line strings use `$|`"))
  assert_true(prompt.contains("Prefer `moon run - <<'EOF'`"))
  assert_true(prompt.contains("moon run --target native - <<'EOF'"))
  assert_true(prompt.contains("Use checked errors for ordinary parser"))
  assert_true(
    prompt.contains("Json::number(n.to_double(), repr=text.to_owned())"),
  )
  assert_true(
    prompt.contains("Do not implement ordinary file/stdin IO with C FFI"),
  )
  assert_true(
    prompt.contains("moon run --target native cmd/tomljson -- /tmp/input.toml"),
  )
}

///|
test "flash prompt omits obsolete guidance" {
  let prompt = flash_prompt()
  assert_false(prompt.contains("check_daemon"))
  assert_false(prompt.contains("moon_ide"))
  assert_false(prompt.contains("moon_cmd"))
  assert_false(prompt.contains("try?"))
  assert_false(prompt.contains("try!"))
  assert_false(prompt.contains("@string.parse_int"))
  assert_false(prompt.contains("Spec-driven Development"))
  assert_false(prompt.contains("proof_invariant"))
  assert_false(prompt.contains("Loop Invariants"))
}

///|
test "default prompt uses the flash prompt for all DeepSeek V4 models" {
  assert_eq(system_prompt_for_model(V4Flash), flash_prompt())
  assert_eq(system_prompt_for_model(V4Pro), flash_prompt())
}
