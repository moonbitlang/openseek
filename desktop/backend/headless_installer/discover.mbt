///|
/// Find the newest installed managed runtime. This never downloads code,
/// changes an existing host, or guesses an external release URL. A host with
/// no managed installation reports a setup error and can use package setup.
pub async fn discover(destination : String) -> (String, String, String) {
  let source =
    #|import json, os, pathlib, sys
    #|try:
    #|    home = pathlib.Path.home().resolve()
    #|    root = home / '.local/share/seekmoon/host-packages/versions'
    #|    candidates = []
    #|    for path in root.glob('*/*/manifest.json'):
    #|        value = json.loads(path.read_text())
    #|        launcher = path.parent / 'bin/openseek'
    #|        if value.get('protocol_version') == int(sys.argv[1]) and launcher.is_file() and os.access(launcher, os.X_OK):
    #|            candidates.append((path.stat().st_mtime_ns, str(launcher), value['build_id']))
    #|    if not candidates:
    #|        raise RuntimeError('No managed SeekMoon runtime found. Open Advanced and prepare this host from a local headless package.')
    #|    _, launcher, build = max(candidates)
    #|    print(json.dumps({'launcher': launcher, 'build_id': build, 'data_dir': str(home / '.local/share/seekmoon/remote-host')}))
    #|except Exception as error:
    #|    print(json.dumps({'ok': False, 'stage': 'discover', 'error': str(error)}))
    #|    sys.exit(1)
  let result = ssh_command(
    destination,
    "python3 -c " +
    quote(source) +
    " " +
    @host_control.ProtocolVersion.to_string(),
    ssh="/usr/bin/ssh",
    timeout_ms=30000,
  )
  guard result
    is {
      "launcher": String(launcher),
      "build_id": String(build),
      "data_dir": String(data),
      ..
    } &&
    launcher.has_prefix("/") &&
    data.has_prefix("/") &&
    !build.is_blank() else {
    raise InstallError("discover", "Invalid managed runtime metadata")
  }
  (launcher, build, data)
}
