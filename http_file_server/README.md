# HTTP file server

`moonbitlang/http_file_server` is a native MoonBit library for serving files
from a fixed directory, with a loopback CLI. It depends only on `async`,
`x/path` and the core library; it has no SeekMoon or Proton dependency.
The module is prepared for publication but has not been published.

## Library

Create a directory once and use it in an existing HTTP request handler:

```mbt
let files = @http_file_server.Directory("public")
// In the handler, after authentication, Host validation and routing:
files.serve(request, connection)
```

Both calls are asynchronous. The directory is canonicalized when opened.
Each request decodes its URL path once, normalizes it under that root, checks
the resolved target and reads the current regular file in chunks. Relative
CSS, scripts, modules, images, fonts and static fetches use normal browser
requests. No dependency scan, HTML rewriting or directory listing occurs.

`Directory::serve` accepts these optional named arguments:

- `path`: a raw URL path after the host removes its route prefix. Defaults to
  the request path. Queries are ignored; percent escapes are decoded once.
- `index`: serve a directory's `index.html`; defaults to `false`.
- `cache_control`: the response's Cache-Control value; defaults to `no-store`.
- `active`: a synchronous callback, defaulting to true, checked after opening
  the file and before body chunks. An owner can use it to revoke a response
  while filesystem operations are pending. Revocation before headers returns
  404; after headers, the owning handler closes the incomplete response.

GET and HEAD are supported. Unsupported methods receive 405; missing or
non-regular files receive 404; paths or symlinks escaping the root receive
403. Other filesystem failures and connection failures raise to the owning
handler. Symlinks pointing inside the root are allowed. Responses include
Content-Length, a filename-based Content-Type, nosniff and no-referrer.

The caller owns connection closure, request timeouts, Host validation,
authentication and routing. This library adds no command endpoints or native
bridge. Keep executable untrusted content on an origin isolated from an
application's privileged UI and command endpoints.

## CLI

From the repository root:

```sh
moon run --target native http_file_server/cli -- ./public --port 0
```

The directory defaults to the current directory. The port defaults to `0`,
letting the OS choose a free port. The CLI prints the bound URL, serves files
and directory index.html documents, and validates Host against that URL.
It listens only on `127.0.0.1`. Stop the process to close the listener.

Use `--help` for arguments. The executable returns a nonzero exit status for
an invalid port, missing root or bind failure. It provides neither uploads
nor a backend runtime, authentication, live reload, range requests or a
directory listing. Refresh reads the current saved files.

The executable examples in [the CLI guide](../tests/cram/http-file-server.md)
cover its argument and exit-status contract. Library behavior is exercised
through real HTTP requests in `directory_test.mbt`.

## Validation

```sh
moon check --target native http_file_server
moon test --target native http_file_server
moon cram test tests/cram/http-file-server.md --shell bash
```
