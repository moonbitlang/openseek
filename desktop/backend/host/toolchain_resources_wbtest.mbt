///|
#cfg(not(platform="windows"))
async test "language and semantic tools execute the explicit host toolchain" {
  let root = @pathx.Path(@fs.tmpdir(prefix="host-toolchain-")).resolve()
  defer @fs.rmdir(root.to_string(), recursive=true)
  let seed = root.join("explicit seed")
  let runtime = root.join("runtime")
  let payload = runtime.join("toolchains/moonbit/linux-x64")
  @fs.mkdir(seed.to_string(), recursive=true)
  @fs.write_file(
    seed.join(".openseek-moonbit-seed-version").to_string(),
    "fixture",
    create_mode=CreateOrTruncate,
  )
  for
    name in [
      "bin/moon", "bin/moonc", "lib/core/_build/native/release/bundle/prelude/prelude.mi",
      "lib/core/_build/wasm-gc/release/bundle/prelude/prelude.mi",
    ] {
    let file = payload.join(name)
    @fsx.ensure_dir(file.to_path().dirname())
    @fs.write_file(
      file.to_string(),
      "#!/bin/sh\nprintf 'selected-toolchain'\n",
      create_mode=CreateOrTruncate,
      permission=0o755,
    )
  }
  @fs.write_file(
    payload.join(".openseek-moonbit-bundle-version").to_string(),
    "version=fixture",
    create_mode=CreateOrTruncate,
  )
  guard @moonbit.bundled_source(
      platform="linux-x64",
      host_platform="Linux-x86_64",
      seed_dir=seed.to_string(),
    )
    is Some(source) else {
    fail("test fixture seed marker is missing")
  }
  let state = new_host_state(
    "unbundled-engine",
    runtime_dir=runtime.to_path(),
    resources={ ..HostResources::from_path(), moonbit: source, },
  )
  guard state.moon.resolve_command() is Some(cli) else {
    fail("explicit language toolchain was lost")
  }
  let expected = payload.join("bin/moon").to_string()
  assert_eq(cli.command, expected)
  assert_eq(state.moon.run_moon([], root), Some((0, "selected-toolchain", "")))
  let ide = moonide_spawn_config(state)
  assert_eq(ide.executable, expected)
  let (code, stdout, _) = @processx.collect_output_no_stdin(
    ide.executable,
    [],
    inherit_env=false,
    extra_env?=ide.extra_env,
  )
  assert_eq(code, 0)
  assert_eq(stdout.text(), "selected-toolchain")
  guard state.semantic_provider() is Some(provider) else {
    fail("expected moonx provider")
  }
  let env : Map[String, String] = {
    "MOON_HOME": "registry-home",
    "PATH": "/unrelated",
  }
  let selected = provider.resolve(env~)
  assert_eq(selected.command, payload.join("bin/moonx").to_string())
  assert_eq(selected.environment["MOON_HOME"], "registry-home")
  let (code, stdout, _) = @processx.collect_output_no_stdin(
    selected.command,
    semantic_provider_prefix_args(selected.command),
    inherit_env=false,
    extra_env=selected.environment,
  )
  assert_eq(code, 0)
  assert_eq(stdout.text(), "selected-toolchain")
  // Reuse the prepared payload and the moonx alias without replacing either.
  let again = provider.resolve(env~)
  assert_eq(again.command, selected.command)
  // A selected seed that disappears must not fall back to this machine's moon.
  @fs.remove(seed.join(".openseek-moonbit-seed-version").to_string())
  let fresh = new_host_state(
    "unbundled-engine",
    runtime_dir=runtime.to_path(),
    resources={ ..HostResources::from_path(), moonbit: source, },
  )
  assert_true(fresh.moon.resolve_command() is None)
  try moonide_spawn_config(fresh) catch {
    _ => ()
  } noraise {
    _ => fail("IDE fell back after losing the selected seed")
  }
  try provider.resolve() catch {
    _ => ()
  } noraise {
    _ => fail("semantic provider fell back after losing the selected seed")
  }
}

///|
test "explicitly absent semantic provider remains disabled" {
  let disabled = new_host_state("unused", resources={
    ..HostResources::from_path(),
    moongrep: None,
  })
  assert_true(disabled.semantic_provider() is None)
}
