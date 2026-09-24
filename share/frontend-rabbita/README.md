# Rabbita Frontend and Full-Stack Applications

Use Rabbita for MoonBit browser UIs unless the project or user selects another
framework. Start with the project's README, `moon.mod`, and entry packages.
Frontend API notes use Rabbita 0.16.3; CLI commands were checked with Warren
0.4.0. Inspect the project's installed interfaces with `moon ide doc "@rabbita"`
before adapting examples.

## Start a project

Use [Warren] for scaffolding, browser preview, and release builds:

```sh
moon install moonbit-community/warren
warren new my-app
cd my-app
warren dev --browser-entry main
# Release output: dist/
warren build --browser-entry main
```

Warren defaults to `cmd/browser`; the browser-only template above uses `main`.
Read the generated README and `warren <command> --help` for the installed version.

## State, views, and effects

- Build components as functions returning `Val[Html]`. Use
  `create_pure_state(initial, update=(model, msg) => new_model)` for pure state,
  or `create_state(initial, update=(model, msg, emit) => (new_model, cmd))`
  for effects. Both return `(Val[Model], Emit[Msg])` and require `Model : Eq`.
  Keep state immutable; use derived values instead of duplicating state. See
  the [introduction] and [API signatures].
- Render with `model.view(...)` and `moonbit-community/rabbita/html` helpers.
  Bind messages through handlers such as `on_click=emit(Clicked)`;
  `emit(msg)` produces a `Cmd`. Return commands from updates or attach them to
  handlers: constructing and discarding a command does not execute it.
  Keep rendering free of side effects. See [commands].
- Mount a client-rendered app with `@rabbita.new(app).mount("app")`; the host
  HTML must contain an element with that id. Prefer library APIs over raw JS
  FFI, and keep callbacks, commands, and requests out of the model, following
  the [upstream guidance].
- Use `moonbit-community/rabbita/http` for requests. Complete a request with
  `expect_text`, `expect_json`, or `expect_empty`, and return its command from
  the update. Callbacks should send result messages; updates handle loading,
  success, and failure. Use `with_json` for JSON request bodies. See [HTTP].

## Full-stack applications

Start from [fullstack-moonbit], a Rabbita + Moonback Todo app with SSR and
hydration. Preserve its pinned dependencies and read its README first:

```sh
git clone https://github.com/moonbit-community/fullstack-moonbit.git my-app
cd my-app
warren dev
# Build browser assets and a native server into dist/
warren build --server-target native
```

Follow its package boundaries: `cmd/browser` targets `js`; `cmd/server` and
`shared/api` target `native+wasm`; `shared/components` supports all three.
The server passes the shared root component and API routes to `rabbita/server`;
the browser calls `@rabbita.new(@components.app).hydrate()` for that component.
Use this paired setup for SSR (experimental), rather than replacing hydration
with a fresh DOM mount. Put shared data types and validation in packages both
sides can import; validate again on the server, as shown in the bundled
[validation tutorial](../doc/moonbit/tutorial/fullstack-one-project.md).
Keep browser-only and server-only IO out of shared UI/domain packages.
For native desktop hosting, also read [Proton](../desktop-proton/README.md).

Run `moon check --target js`, check the backend's target when present, and test
changed state/validation logic. Build with the selected Warren entries, then
check rendering, interactions, and request success/failure in a browser.

[Warren]: https://github.com/moonbit-community/rabbita/blob/d31819b4b59653550af5fcd3c1bc5c424caae64a/warren/README.md
[introduction]: https://github.com/moonbit-community/rabbita/blob/d31819b4b59653550af5fcd3c1bc5c424caae64a/doc/001_intro/readme.mbt.md
[API signatures]: https://github.com/moonbit-community/rabbita/blob/d31819b4b59653550af5fcd3c1bc5c424caae64a/rabbita/pkg.generated.mbti
[commands]: https://github.com/moonbit-community/rabbita/blob/d31819b4b59653550af5fcd3c1bc5c424caae64a/doc/004_using_command/readme.mbt.md
[HTTP]: https://github.com/moonbit-community/rabbita/blob/d31819b4b59653550af5fcd3c1bc5c424caae64a/doc/005_http/readme.mbt.md
[upstream guidance]: https://github.com/moonbit-community/rabbita/blob/d31819b4b59653550af5fcd3c1bc5c424caae64a/skills/rabbita.md
[fullstack-moonbit]: https://github.com/moonbit-community/fullstack-moonbit/tree/ad1759d6209af97523679ac58b25b407847de1e6
