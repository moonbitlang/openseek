"""Opt-in real SSH/wasm Agent validation. Uses only its own temporary data.

Run after manually staging bin/openseek and lib/openseek.wasm:
  python3 -B tests/host_server/test_remote.py HOST INSTALL BUILD_ID ROOT
Set OPENSEEK_P2_SCENARIOS to a comma-separated subset for a focused rerun.
Set OPENSEEK_REMOTE_MODEL_FIXTURE to a separately staged remote model_fixture.py
when testing a verified immutable package.
The model is scripted, but the remote engine, tools, durable store, followers,
SSH client and service are production implementations.
"""
import json
import os
import select
from pathlib import Path
import shlex
import signal
import subprocess
import sys
import time
import textwrap
from test_client import JsonlClient
from test_foreground import NATIVE

host, install, build, root = sys.argv[1:]
launcher = install + "/bin/openseek"
model_fixture = os.environ.get("OPENSEEK_REMOTE_MODEL_FIXTURE", install + "/tests/model_fixture.py")
data_dir = root + "/data"
project = root + "/project"
scenarios = os.environ.get("OPENSEEK_P2_SCENARIOS", "disconnect,blackhole,drain,crash").split(",")
assert scenarios and set(scenarios) <= {"disconnect", "blackhole", "drain", "crash"}
clients = []
fixture = None
frozen_ssh = None


def ssh(args, **kw):
    return subprocess.run(["ssh", "-T", "-o", "BatchMode=yes", host, shlex.join(args)], capture_output=True, timeout=kw.pop("timeout", 30), **kw)


def python(code):
    result = ssh(["python3", "-c", code])
    if result.returncode:
        raise AssertionError(result.stderr.decode())
    return result.stdout.decode()


def control(action, *args):
    result = ssh([launcher, "app-server", "daemon", action, "--data-dir", data_dir, *args], timeout=80)
    if result.returncode:
        raise AssertionError(result.stderr.decode())
    return json.loads(result.stdout)


def identity(pid):
    # Test-only Linux identity oracle for safely cleaning up fixture processes.
    # Production intentionally has no OS process-identity inspection.
    code = """import json
from pathlib import Path
try:
    stat = Path('/proc/PID/stat').read_text().rsplit(')', 1)[1].split()
    print(json.dumps(None if stat[0] in ('Z', 'X') else {'pid': PID, 'boot_id': Path('/proc/sys/kernel/random/boot_id').read_text().strip(), 'start_time': stat[19]}))
except FileNotFoundError:
    print('null')
""".replace('PID', str(pid))
    return json.loads(python(code))


def connect(expected=None):
    args = [str(NATIVE), "app-server", "remote", "--host", host, "--launcher", launcher,
            "--data-dir", data_dir, "--build-id", build]
    if expected:
        args += ["--expected-server-id", expected]
    client = JsonlClient(args, os.environ.copy())
    clients.append(client)
    # Send before bootstrap: real OpenSSH must not steal the client input.
    ident = client.send("server.status", {})
    response = client.response(ident, 40)
    assert "result" in response, response
    return client, response["result"]


def read_file(client, path):
    reply = client.response(client.send("fs.read_file", {"path": path}))
    if "error" in reply:
        if "no such file" in reply["error"]["message"].lower() or "ENOENT" in reply["error"]["message"]:
            return None
        raise AssertionError(reply)
    return reply["result"]["content"]


def wait_file(client, path, timeout=180):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = read_file(client, path)
        if value is not None:
            return value
        # Surface real engine failures rather than silently waiting for a file.
        for event in client.events:
            if event.get("method") == "agent.finished" and event.get("params", {}).get("status") != "finished":
                raise AssertionError(event)
        time.sleep(0.1)
    raise TimeoutError("remote file never arrived: " + path + "\n" + json.dumps(client.events[-12:], ensure_ascii=False))


def release(scenario):
    python("from pathlib import Path; Path(" + repr(project + "/" + scenario + ".release") + ").write_text('release')")


def start(client, scenario):
    result = client.request("agent.start", {"images": [], "task": "P2_SCENARIO:" + scenario,
        "session": "p2-" + scenario, "workspace": project, "max_steps": 20, "thinking": "no"})
    assert result["status"] == "accepted", result
    wait_file(client, project + "/" + scenario + ".started")
    print("real remote tool started:", scenario, result["run_id"], flush=True)
    return result["run_id"]


def finished(client, scenario, timeout=120):
    expected = "远端工具 " + scenario + "\n"
    assert wait_file(client, project + "/" + scenario + ".result", timeout) == expected
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        snapshot = client.request("session.load", {"session": "p2-" + scenario, "workspace": project})
        events = snapshot["session"].get("events", [])
        terminal = next((event for event in events
                         if event["item"].get("kind") == "terminal"
                         and event["item"].get("payload", {}).get("kind") == "finished"
                         and event["item"]["payload"].get("message") == "REMOTE-FINISHED " + scenario), None)
        if terminal is not None:
            assert snapshot.get("watermark") is not None and snapshot["watermark"] >= terminal["sequence"], snapshot
            print("durable session and follower settled:", scenario, flush=True)
            return snapshot
        time.sleep(0.1)
    raise TimeoutError("missing durable final answer: " + scenario)


def wait_gone(info, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if identity(info["pid"]) != info:
            return
        time.sleep(0.1)
    raise AssertionError("owned process did not exit: " + str(info))


try:
    python("from pathlib import Path; Path(" + repr(root) + ").mkdir(mode=0o700, parents=True, exist_ok=True); Path(" + repr(project) + ").mkdir(exist_ok=True)")
    fixture = subprocess.Popen(["ssh", "-T", "-o", "BatchMode=yes", host,
        shlex.join(["python3", model_fixture, root])],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert select.select([fixture.stdout], [], [], 15)[0], "model fixture startup deadline"
    endpoint = json.loads(fixture.stdout.readline())
    client, original = connect()
    stable_id = original["server_id"]
    assert original["status"] == "ready"
    assert original["platform"].startswith("Linux-")
    client.request("settings.set", {"provider": "custom", "custom_api_url": "http://127.0.0.1:" + str(endpoint["port"]) + "/chat/completions", "custom_api_key": "p2-fixture"})
    attached = client.request("workspace.add", {"path": project})
    assert "error" not in attached, attached
    python("from pathlib import Path; Path(" + repr(root + "/remote.txt") + ").write_text('remote-only 文件')")
    assert read_file(client, root + "/remote.txt") == "remote-only 文件"
    assert not Path(root + "/remote.txt").exists(), "remote path was accidentally materialized locally"

    current = original
    if 'disconnect' in scenarios:
        # Disconnect leaves the real Agent/tool alive.
        start(client, "disconnect")
        client.close()
        client, current = connect(stable_id)
        assert current["instance_id"] == original["instance_id"]
        assert read_file(client, project + "/disconnect.result") is None
        release("disconnect")
        finished(client, "disconnect")
        print("PASS remote file / disconnect continuation", flush=True)

    if 'blackhole' in scenarios:
        # Freeze only this connection's SSH process: transport TCP stays established,
        # but neither endpoint can receive a matching WebSocket pong.
        start(client, "blackhole")
        children = subprocess.check_output(["pgrep", "-P", str(client.process.pid)]).decode().split()
        assert len(children) == 1, children
        frozen_ssh = int(children[0])
        assert Path(subprocess.check_output(["ps", "-p", str(frozen_ssh), "-o", "comm="]).decode().strip()).name == "ssh"
        began = time.monotonic()
        os.kill(frozen_ssh, signal.SIGSTOP)
        print("blackhole injection active; waiting for production 60s pong budget", flush=True)
        client.process.wait(timeout=85)
        assert client.process.returncode != 0
        elapsed = time.monotonic() - began
        assert 45 <= elapsed < 85
        frozen_ssh = None
        client, current = connect(stable_id)
        assert current["instance_id"] == original["instance_id"]
        assert read_file(client, project + "/blackhole.result") is None
        release("blackhole")
        finished(client, "blackhole")
        print("PASS blackhole bounded teardown and Agent survival:", round(elapsed, 2), "seconds", flush=True)

    if 'drain' in scenarios:
        # Controlled stop rejects new mutations, still accepts reads, and waits for
        # the already admitted real Agent and durable follower within one grace.
        start(client, "drain")
        stopper = subprocess.Popen(["ssh", "-T", "-o", "BatchMode=yes", host,
            shlex.join([launcher, "app-server", "daemon", "stop", "--data-dir", data_dir, "--shutdown-grace-seconds", "10"])],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        deadline = time.monotonic() + 5
        while client.request("server.status", {})["status"] != "draining":
            assert time.monotonic() < deadline
            time.sleep(0.05)
        rejected = client.response(client.send("workspace.add", {"path": root + "/must-not-write"}))
        assert "error" in rejected, rejected
        assert read_file(client, root + "/remote.txt") == "remote-only 文件"
        release("drain")
        output, error = stopper.communicate(timeout=25)
        assert stopper.returncode == 0, error.decode()
        assert not json.loads(output)["recovery_required"], output
        client.close()
        client, current = connect(stable_id)
        assert current["instance_id"] != original["instance_id"]
        finished(client, "drain")
        print("PASS drain admission / settlement / follower join / restart", flush=True)

    if 'crash' in scenarios:
        # Kill only the daemon while a real tool is in flight. The engine may exit
        # on control-pipe EOF; that does not prove all external effects settled.
        crash_run = start(client, "crash")
        previous = current
        committed = client.request("session.load", {"session": "p2-crash", "workspace": project})["session"]["events"]
        owner = json.loads(python("from pathlib import Path; print(Path(" + repr(data_dir + "/owner.json") + ").read_text())"))
        assert owner["instance_id"] == previous["instance_id"]
        daemon_pid = json.loads(python("from pathlib import Path; print(Path(" + repr(data_dir + "/daemon-process.json") + ").read_text())"))["pid"]
        assert identity(daemon_pid) is not None
        records = json.loads(python("import json; from pathlib import Path; p=Path(" + repr(data_dir + "/recovery/" + previous["instance_id"]) + "); print(json.dumps([json.loads(f.read_text()) for f in p.glob('*.intent.json')]))"))
        assert any(record["run_id"] == [crash_run] for record in records), records
        # Snapshot the fixture-owned process tree, including the actual tool, before
        # killing the daemon. Identity checks later distinguish exit from PID reuse.
        tree_code = textwrap.dedent("""
    from pathlib import Path
    import json
    parents = {}
    for directory in Path('/proc').iterdir():
        if not directory.name.isdigit(): continue
        try:
            stat = (directory / 'stat').read_text().rsplit(')', 1)[1].split()
            parents[int(directory.name)] = int(stat[1])
        except (FileNotFoundError, ProcessLookupError): pass
    owned = {ROOT_PID}
    while True:
        expanded = owned | {pid for pid, parent in parents.items() if parent in owned}
        if expanded == owned: break
        owned = expanded
    print(json.dumps(sorted(owned - {ROOT_PID})))
    """).replace("ROOT_PID", str(daemon_pid))
        owned_children = [info for pid in json.loads(python(tree_code)) if (info := identity(pid)) is not None]
        assert owned_children, "expected a real engine/tool process tree"
        python("import os, signal; os.kill(" + str(daemon_pid) + ", signal.SIGKILL)")
        client.close()
        client, recovering = connect(stable_id)
        assert recovering["status"] == "recovery_required", recovering
        report = client.request("server.recovery", {})
        unresolved = next(x for x in report["unsettled_instances"] if x["instance_id"] == previous["instance_id"])
        assert unresolved["execution_outcome"] == "requires_inspection", unresolved
        blocked = client.response(client.send("agent.start", {"images": [], "task": "must not replay", "session": "forbidden", "workspace": project}))
        assert "error" in blocked
        refused = client.response(client.send("server.recover", {"instance_id": previous["instance_id"], "confirm_external_tools_stopped": False}))
        assert "error" in refused
        assert unresolved["process_inspection"] == "unavailable"
        release("crash")
        for child in owned_children:
            wait_gone(child, 120)
        effect_before_recovery = python("import json; from pathlib import Path; p=Path(" + repr(project + "/crash.result") + "); print(json.dumps(p.read_text() if p.exists() else None))")
        client.request("server.recover", {"instance_id": previous["instance_id"], "confirm_external_tools_stopped": True})
        client.close()
        control("restart", "--shutdown-grace-seconds", "0")
        client, current = connect(stable_id)
        assert current["status"] == "ready"
        recovered = client.request("session.load", {"session": "p2-crash", "workspace": project})["session"]["events"]
        assert recovered[:len(committed)] == committed, (committed, recovered)
        assert read_file(client, root + "/remote.txt") == "remote-only 文件"
        effect_after_recovery = python("import json; from pathlib import Path; p=Path(" + repr(project + "/crash.result") + "); print(json.dumps(p.read_text() if p.exists() else None))")
        assert effect_after_recovery == effect_before_recovery, "recovery replayed a mutation"
        print("PASS real Agent hard crash / blocked admission / owned tools exited / explicit acknowledgement / durable history", flush=True)
    print(json.dumps({"server_id": stable_id, "platform": current["platform"], "build_id": build, "data_dir": data_dir}), flush=True)
finally:
    if frozen_ssh is not None:
        try:
            os.kill(frozen_ssh, signal.SIGCONT)
        except ProcessLookupError:
            pass
    # Release only this fixture's owned tools before stopping its service.
    for scenario in scenarios:
        try:
            release(scenario)
        except Exception:
            pass
    for client in clients:
        client.close()
    try:
        print("cleanup:", control("stop", "--shutdown-grace-seconds", "10"), flush=True)
    finally:
        if fixture is not None:
            fixture.stdin.close()
            try:
                fixture.wait(timeout=10)
            except subprocess.TimeoutExpired:
                fixture.kill()
                fixture.wait()
            errors = fixture.stderr.read().decode()
            if errors:
                print("model fixture diagnostics:", errors, file=sys.stderr)
            fixture.stdout.close()
            fixture.stderr.close()
