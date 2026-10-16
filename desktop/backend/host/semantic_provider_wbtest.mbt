///|
async test "pattern validation executes the selected provider with its tool environment" {
  if @env.path_sep == ";" {
    return
  }
  let dir = @fs.tmpdir(prefix="openseek-pattern-provider-")
  defer @fs.rmdir(dir, recursive=true)
  let provider_path = "\{dir}/selected provider"
  @fs.write_file(
    provider_path,
    (
      #|#!/bin/sh
      #|test "$1" = dump && test "$2" = --expr && test "$3" = 'foo()' || exit 11
      #|test "$MOON_HOME" = 'registry identity' || exit 12
      #|test "$(moon)" = prepared || exit 13
    ),
    permission=0o700,
  )
  @fs.write_file(
    "\{dir}/moon",
    "#!/bin/sh\nprintf prepared\n",
    permission=0o700,
  )
  let provider = SemanticProvider::Standalone(provider_path).resolve(env={
    "PATH": dir,
    "MOON_HOME": "registry identity",
  })
  let root = @pathx.Path(dir).to_absolute().unwrap()
  assert_true(
    validate_pattern_repair_candidate(root, "foo()", Some(provider))
    is PatternRepairValid,
  )
}
