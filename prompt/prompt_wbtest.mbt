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
  assert_true(prompt.contains("`analysis:` block"))
  assert_true(prompt.contains("repeated unbound value identifiers"))
  assert_true(prompt.contains("much faster than"))
  assert_true(prompt.contains("primary"))
  assert_true(prompt.contains("`...` body"))
  assert_true(prompt.contains("Warning (todo): unfinished code"))
  assert_true(prompt.contains("generic `todo` helper"))
  assert_true(prompt.contains("parse_key(text : String, line~ : Int)"))
  assert_true(prompt.contains("parse_value(text : String, line~ : Int)"))
  assert_true(prompt.contains("Parser::insert_path"))
  assert_true(prompt.contains("```mbt nocheck"))
  assert_true(prompt.contains("Create `moon.mod` before running `moon info`"))
  assert_true(prompt.contains("`moon.mod` is the module manifest"))
  assert_true(prompt.contains("module-level dependency versions"))
  assert_true(prompt.contains("`moon.pkg` is the package manifest"))
  assert_true(prompt.contains("package imports, import aliases"))
  assert_true(
    prompt.contains("Do not put package imports or aliases in `moon.mod`"),
  )
  assert_true(
    prompt.contains("do\n  not put module dependency versions in `moon.pkg`"),
  )
  assert_true(prompt.contains("Plain `fn` is private"))
  assert_true(prompt.contains("_test.mbt` files are black-box tests"))
  assert_true(prompt.contains("Use `suberror` for custom errors"))
  assert_true(prompt.contains("Pattern matching error constructors is"))
  assert_true(
    prompt.contains("valid. When matching errors from another package"),
  )
  assert_true(prompt.contains("catch { @pkga.A => ...; @pkga.B => ... }"))
  assert_true(
    prompt.contains("Parameter and receiver bindings cannot be `mut`"),
  )
  assert_true(
    prompt.contains("not `fn f(mut x : Int)` or\n  `fn T::m(mut self : T)`"),
  )
  assert_true(prompt.contains("fn f(mut x : Int)"))
  assert_true(prompt.contains("fn T::m(mut self : T)"))
  assert_true(prompt.contains("Use `let mut x = ...` only for local rebinding"))
  assert_true(prompt.contains("Use `mut field : T` only on struct fields"))
  assert_true(prompt.contains("small focused"))
  assert_true(prompt.contains("moonbitlang/core/argparse"))
  assert_true(prompt.contains("@stdio.stdin.read_all().text()"))
  assert_true(prompt.contains("@stdio.stderr.write(...)"))
  assert_true(prompt.contains("@sys.exit(1)"))
  assert_true(prompt.contains("let x : UInt16 = 0"))
  assert_true(prompt.contains("s[i] == '='"))
  assert_true(prompt.contains("without allocating `Some(ch)`"))
  assert_true(prompt.contains("s.get_char(i) is Some(c) && c == ch"))
  assert_true(
    prompt.contains("lowercase names in patterns bind a new variable"),
  )
  assert_true(prompt.contains("Do not write constructor-style casts"))
  assert_true(prompt.contains("UInt16(92)"))
  assert_true(prompt.contains("s[:4]"))
  assert_true(prompt.contains("Raw multi-line strings use `#|`"))
  assert_true(prompt.contains("Interpolated multi-line strings use `$|`"))
  assert_true(prompt.contains("Prefer `moon run - <<'EOF'`"))
  assert_true(prompt.contains("moon run --target native - <<'EOF'"))
  assert_true(prompt.contains("Use checked errors for ordinary parser"))
  assert_true(
    prompt.contains("Json::number(n.to_double(), repr=text.to_owned())"),
  )
  assert_true(prompt.contains("Do not create JSON with `Json::Object(...)`"))
  assert_true(prompt.contains("Use `map.get(key)` for `T?`"))
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
