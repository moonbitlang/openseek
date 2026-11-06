# Serving a directory over loopback HTTP

The standalone `moonbitlang/http_file_server` module provides the file-serving
implementation shared by embedded hosts and its CLI. These examples exercise
the CLI's arguments, HTTP listener, Host check and process lifetime. The
module's native package tests cover file response and confinement behavior.

Build the executable from this checkout:

```mooncram
$ PROJECT="$TESTDIR/../.."
```

```mooncram
$ moon -C "$PROJECT" build --target native http_file_server/cli >/dev/null 2>&1
```

```mooncram
$ CLI="$PROJECT/_build/native/debug/build/moonbitlang/http_file_server/cli/cli.exe"
```

The directory defaults to the current directory and port 0 asks the OS for
a free port. The listener is always restricted to `127.0.0.1`:

```mooncram
$ "$CLI" --help
Usage: http-file-server [options] [directory]

Serve a directory read-only on 127.0.0.1. Prints the bound URL; stop the process to close it.

Arguments:
  directory  Directory to serve. [default: .]

Options:
  -h, --help     Show help information.
  --port <port>  TCP port; 0 asks the OS for a free port. [default: 0]
```

An invalid port fails before opening a listener:

```mooncram
$ "$CLI" --port 70000 2>&1
http-file-server: Port must be between 0 and 65535
[1]
```

The following probe starts the real CLI with a directory containing a space,
reads the printed ephemeral URL, and closes its own child process afterward.
The resulting page can load ordinary relative resources; it has no app API.

```mooncram
$ mkdir 'public files'
```

```mooncram
$ printf '<h1>Saved page</h1>' > 'public files/index.html'
```

```mooncram
$ python3 - "$CLI" <<'PY'
> import subprocess, sys, urllib.request, urllib.error
> server = subprocess.Popen([sys.argv[1], 'public files'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
> try:
>     url = server.stdout.readline().strip()
>     assert url.startswith('http://127.0.0.1:')
>     with urllib.request.urlopen(url, timeout=5) as response:
>         print(response.read().decode())
>         print(response.headers['Content-Type'])
>     for request in [urllib.request.Request(url, headers={'Host': 'foreign.example'}), urllib.request.Request(url, data=b'write')]:
>         try:
>             urllib.request.urlopen(request, timeout=5)
>             raise AssertionError('request unexpectedly allowed')
>         except urllib.error.HTTPError as error:
>             print(error.code)
> finally:
>     server.terminate()
>     server.wait(timeout=5)
> PY
<h1>Saved page</h1>
text/html; charset=utf-8
403
405
```

For embedded use and the module's ownership contract, see the
[library guide](../../http_file_server/README.md).
