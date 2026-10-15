"""Check the packaged CLI, clean-home setup, and offline reuse on each host."""
import functools
import http.server
import json
import os
from pathlib import Path
import shutil
import ssl
import subprocess
import sys
import tarfile
import tempfile
import threading


def run(binary, assets, platform):
    binary, assets = Path(binary).resolve(), Path(assets).resolve()
    windows = platform == "windows-x64"
    suffix = ".exe" if windows else ""
    cli_name = "openseek" + suffix
    archive = f"openseek-deps-{platform}.tar.gz"
    with tarfile.open(assets / archive) as bundle:
        names = {name.removeprefix("./") for name in bundle.getnames()}
        assert not any(name.startswith("bin/openseek") for name in names), names
        assert "bin/rg" + suffix in names and "share/workflow/read.mbtx" in names

    with tempfile.TemporaryDirectory(prefix="openseek-release-smoke-") as temporary:
        root = Path(temporary)
        home = root / "home"
        home.mkdir()
        (home / ".bashrc").write_text("# existing shell profile\n")
        (home / ".moon").mkdir()
        (home / ".moon/marker").write_text("existing SDK")
        (home / "registry").mkdir()
        (home / "registry/marker").write_text("existing registry")
        cli = root / "bootstrap/bin" / cli_name
        cli.parent.mkdir(parents=True)
        resources = home / ".openseek/share"
        resources.mkdir(parents=True)
        (resources / "user-resource").write_text("existing resources")
        shutil.copyfile(binary, cli)
        cli.chmod(0o755)
        cert, key = root / "cert.pem", root / "key.pem"
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                        "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1",
                        "-keyout", str(key), "-out", str(cert)], check=True, capture_output=True)
        downloads = root / "downloads"
        downloads.mkdir()
        shutil.copyfile(assets / archive, downloads / archive)
        handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(downloads))
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        origin = f"https://127.0.0.1:{server.server_port}"
        sums = dict(line.split("  ", 1)[::-1] for line in (assets / f"SHA256SUMS-{platform}").read_text().splitlines())
        manifest = downloads / "desktop/releases/latest.json"
        manifest.parent.mkdir(parents=True)
        manifest.write_text(json.dumps({"version": "0.1.9", "platforms": {
            f"cli-deps-{platform}": {"url": f"{origin}/{archive}", "sha256": sums[archive]}
        }}))
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        ca_bundle = root / "ca-bundle.pem"
        cafile = ssl.get_default_verify_paths().cafile
        roots = Path(cafile).read_bytes() if cafile else b""
        if windows:
            roots += b"".join(ssl.DER_cert_to_PEM_cert(data).encode()
                              for data, encoding, _ in ssl.enum_certificates("ROOT")
                              if encoding == "x509_asn")
        ca_bundle.write_bytes(roots + cert.read_bytes())
        # A curl config works with Schannel too, which ignores CURL_CA_BUNDLE.
        (home / ".curlrc").write_text(f'cacert = "{ca_bundle.as_posix()}"\n')
        system_path = os.pathsep.join([
            str(Path(os.environ["SystemRoot"]) / "System32"),
            str(Path(os.environ["SystemRoot"]) / "System32/WindowsPowerShell/v1.0"),
        ]) if windows else "/usr/bin:/bin:/usr/sbin:/sbin"
        environment = {**os.environ, "HOME": str(home), "USERPROFILE": str(home), "XDG_DATA_HOME": str(home / "data"),
                       "MOON_HOME": str(home / "registry"), "PATH": system_path, "OPENSEEK_API_ORIGIN": origin,
                       "CURL_HOME": str(home), "CURL_CA_BUNDLE": str(ca_bundle), "NO_PROXY": "127.0.0.1,localhost", "no_proxy": "127.0.0.1,localhost"}
        def invoke(args, timeout=1000, env=None):
            result = subprocess.run([str(cli), *args], env=environment if env is None else env, cwd=root, capture_output=True, text=True, timeout=timeout)
            assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
            return result
        try:
            invoke(["--help"])
            # Checking an MCP configuration does not require an installation.
            mcp_config = root / "mcp.json"
            mcp_config.write_text('{"mcpServers": {}}\n')
            assert "no servers configured" in invoke(["mcp", "--mcp-config", str(mcp_config)]).stdout
            events = [json.loads(line) for line in invoke(["setup", "--json"]).stdout.splitlines()]
            ready = events[-1]
            assert ready["event"] == "ready" and not ready["reused"], events
            assert Path(ready["bin_dir"]) == home / ".openseek/bin", ready
            assert Path(ready["share_dir"]) == resources, ready
            assert (resources / "doc/moonbit/index.md").is_file()
            assert (home / ".openseek/bin" / cli_name).is_file()
            cli = home / ".openseek/bin" / cli_name
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
        # No download server is running. Idempotence must not depend on network.
        reused = [json.loads(line) for line in invoke(["setup", "--json"]).stdout.splitlines()]
        assert reused[-1]["event"] == "ready" and reused[-1]["reused"], reused
        assert (home / ".bashrc").read_text() == "# existing shell profile\n"
        assert (home / ".moon/marker").read_text() == "existing SDK"
        assert (home / "registry/marker").read_text() == "existing registry"
        assert (resources / "user-resource").read_text() == "existing resources"
        source = root / "sample.mbtx"
        source.write_text('fn main { println("CLI-SETUP-OK") }\n')
        tools_env = {**environment, "PATH": os.pathsep.join([str(home / ".moon/bin"), str(home / ".openseek/bin"), system_path])}
        program = subprocess.run([str(home / ".moon/bin" / ("moon" + suffix)), "run", str(source)], env=tools_env,
                                 cwd=root, text=True, capture_output=True, timeout=120)
        assert program.returncode == 0 and "CLI-SETUP-OK" in program.stdout, (program.stdout, program.stderr)
        subprocess.run([shutil.which("rg", path=tools_env["PATH"]), "CLI-SETUP-OK", str(source)], check=True, capture_output=True)

        print(json.dumps({"platform": platform, "setup": "passed", "reuse": "passed"}))

if __name__ == "__main__":
    run(*sys.argv[1:])
