///|
#cfg(not(platform="windows"))
async test "native SSH framing preserves quoting and stderr and rejects nonzero success" {
  let root = @fs.tmpdir(prefix="native-installer-ssh-")
  defer @fs.rmdir(root, recursive=true)
  let ssh = root + "/fake ssh"
  let source =
    #|#!/bin/sh
    #|export SHELL=/bin/sh
    #|HOME=$(dirname "$0"); export HOME
    #|printf 'login banner\n'
    #|for last in "$@"; do :; done
    #|exec /bin/sh -c "$last"
  @fs.write_file(ssh, source)
  @fs.chmod(ssh, 0o700)
  let value : Json = { "path": "/tmp/space ' dollar $HOME" }
  let output = ssh_command(
    "test-host",
    "/bin/sh -c " + quote("printf '%s\\n' " + quote(value.stringify())),
    ssh~,
    timeout_ms=5000,
  )
  assert_eq(output, value)
  let failed = try {
    ignore(
      ssh_command(
        "test-host",
        "/bin/sh -c " +
        quote(
          "printf '%s\\n' '{\"ok\":true}'; printf 'specific failure' >&2; exit 7",
        ),
        ssh~,
        timeout_ms=5000,
      ),
    )
    false
  } catch {
    InstallError(stage, message) =>
      stage == "ssh" &&
      message.contains("exited 7") &&
      message.contains("specific failure")
    error => raise error
  }
  assert_true(failed)
  @fs.write_file(ssh, "#!/bin/sh\nprintf 'Permission denied' >&2\nexit 255\n")
  let denied = try {
    ignore(ssh_command("test-host", "true", ssh~, timeout_ms=5000))
    false
  } catch {
    InstallError(_, message) => message.contains("Permission denied")
    error => raise error
  }
  assert_true(denied)
}

///|
#cfg(not(platform="windows"))
async test "native installer cancellation joins its SSH process" {
  let root = @fs.tmpdir(prefix="native-installer-cancel-")
  defer @fs.rmdir(root, recursive=true)
  let ssh = root + "/ssh"
  let started = root + "/started"
  let stopped = root + "/stopped"
  @fs.write_file(
    ssh,
    "#!/bin/sh\ntrap " +
    quote("printf stopped > " + quote(stopped) + "; exit 0") +
    " TERM\nprintf started > " +
    quote(started) +
    "\nwhile :; do sleep 0.02; done\n",
  )
  @fs.chmod(ssh, 0o700)
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let running = group.spawn(allow_failure=true, () => {
        ssh_command("host", "unused", ssh~, timeout_ms=10000)
      })
      while !@fs.exists(started) {
        @async.sleep(5)
      }
      running.cancel()
      ignore(running.wait()) catch {
        @async.WaitedTaskAlreadyCancelled => ()
        error => raise error
      }
      assert_eq(@fs.read_file(stopped).text(), "stopped")
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "native activation checks returned build and pinned identity and preserves busy" {
  let root = @fs.tmpdir(prefix="native-install-activate-")
  defer @fs.rmdir(root, recursive=true)
  let ssh = root + "/ssh"
  @fs.write_file(
    ssh, "#!/bin/sh\nexport SHELL=/bin/sh\nHOME=$(dirname \"$0\"); export HOME\nfor last in \"$@\"; do :; done\nexec /bin/sh -c \"$last\"\n",
  )
  @fs.chmod(ssh, 0o700)
  let launcher = root + "/launcher ' quoted"
  let record = root + "/argv"
  let reply = root + "/reply"
  @fs.write_file(
    launcher,
    "#!/bin/sh\nprintf '%s\\n' \"$@\" > " +
    quote(record) +
    "\ncat " +
    quote(reply) +
    "\n",
  )
  @fs.chmod(launcher, 0o700)
  let installed : Installation = {
    build_id: "new",
    platform: "linux-x64",
    manifest_sha256: @crypto.bytes_to_hex_string(@crypto.sha256(b"x")),
    launcher,
    home: root,
    reused: true,
  }
  let identity : Json = {
    "server_id": "pinned",
    "instance_id": "instance",
    "build_id": "new",
    "protocol_version": 1,
    "platform": "Linux-x86_64",
    "home": root,
    "data_dir": root,
    "status": "ready",
  }
  @fs.write_file(reply, identity.stringify())
  assert_true(
    activate(
      installed,
      destination="host",
      data_dir=root,
      expected_server_id="pinned",
      ssh~,
    )
    is Ready(_),
  )
  assert_true(
    @fs.read_file(record).text().contains("--expected-server-id\npinned\n"),
  )
  let mismatch = try {
    ignore(
      activate(
        installed,
        destination="host",
        data_dir=root,
        expected_server_id="different",
        ssh~,
      ),
    )
    false
  } catch {
    InstallError(_, message) => message.contains("identity changed")
    error => raise error
  }
  assert_true(mismatch)
  guard identity is Object(fields) else {
    fail("fixture identity must be an object")
  }
  fields["build_id"] = "other-build"
  @fs.write_file(reply, Json(fields).stringify())
  let wrong_build = try {
    ignore(
      activate(
        installed,
        destination="host",
        data_dir=root,
        expected_server_id="pinned",
        ssh~,
      ),
    )
    false
  } catch {
    InstallError(_, message) => message.contains("matching-build")
    error => raise error
  }
  assert_true(wrong_build)
  @fs.write_file(
    reply,
    (
      {
        "status": "busy",
        "target_build_id": "new",
        "running_build_id": "old",
        "instance_id": "old-instance",
        "upgrade_record": root + "/attempt.json",
      } : Json).stringify(),
  )
  assert_true(
    activate(
      installed,
      destination="host",
      data_dir=root,
      expected_server_id="pinned",
      ssh~,
    )
    is Busy(instance_id="old-instance", running_build_id="old", ..),
  )
}

///|
#cfg(not(platform="windows"))
async test "native installer streams a real archive with its exact size and digest" {
  let root = @fs.tmpdir(prefix="native-install-stream-")
  defer @fs.rmdir(root, recursive=true)
  let package_root = root + "/package with space"
  @fs.mkdir(package_root)
  ignore(fixture_package(package_root))
  let ssh = root + "/ssh"
  @fs.write_file(
    ssh, "#!/bin/sh\nexport SHELL=/bin/sh\nHOME=$(dirname \"$0\"); export HOME\nfor last in \"$@\"; do :; done\nexec /bin/sh -c \"$last\"\n",
  )
  @fs.chmod(ssh, 0o700)
  let source =
    #|import hashlib, io, json, sys, tarfile
    #|request = json.loads(sys.argv[1])
    #|if request['action'] == 'probe':
    #|    result = {'platform': 'linux-x64', 'home': '/home/test'}
    #|elif request['action'] == 'inspect':
    #|    result = {'status': 'missing'}
    #|else:
    #|    data = sys.stdin.buffer.read()
    #|    assert len(data) == request['archive_size']
    #|    assert hashlib.sha256(data).hexdigest() == request['archive_sha256']
    #|    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
    #|        names = {(member.name[2:] if member.name.startswith('./') else member.name) for member in archive}
    #|        assert {'manifest.json', 'bin/openseek', 'web/viz/viz_app.js'} <= names
    #|    result = dict(status='installed', build_id=request['build_id'], platform=request['platform'], manifest_sha256=request['manifest_sha256'], launcher=request['root']+'/bin/openseek')
    #|print(json.dumps({'ok': True, 'result': result}))
  let stages : Array[String] = []
  let result = install(
    destination="host",
    directory=package_root,
    bootstrap=source,
    ssh~,
    root="/remote/space ' directory",
    progress=stage => stages.push(stage),
  )
  assert_eq(result.build_id, "test-build")
  assert_eq(result.launcher, "/remote/space ' directory/bin/openseek")
  assert_false(result.reused)
  assert_eq(stages, [
    "verify_local", "probe", "inspect", "archive", "upload", "verified",
  ])
}

///|
async test "installer output is bounded and diagnostics are truncated" {
  for truncate in [true, false] {
    @async.with_task_group(group => {
      let (reader, writer) = @io.pipe()
      defer reader.close()
      group.spawn_bg(() => {
        defer writer.close()
        writer.write(b"12345")
      })
      try bounded_output(reader, 4, truncate~) catch {
        InstallError(_, message) => {
          assert_false(truncate)
          assert_true(message.contains("limit exceeded"))
        }
        error => raise error
      } noraise {
        bytes => {
          assert_true(truncate)
          assert_eq(bytes, b"1234")
        }
      }
    })
  }
}
