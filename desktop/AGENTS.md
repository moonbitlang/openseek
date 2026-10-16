# Desktop Agent Notes

## Frontend And Host Compatibility

- The desktop frontend and host are versioned and shipped together. Target a
  matching frontend and host version, and evolve protocol payloads and both
  implementations in the same change. Support for mixed versions is a separate
  product requirement when explicitly requested.

## Module Boundary

- `desktop/backend` is a library whose direct and transitive dependencies are
  independent of Proton and window toolkits. Code that needs Proton belongs in
  `desktop/app`; when shared code needs a fact only Proton knows, the window
  host passes it in as a value (`@resources.Resources`).
- `desktop/app` is a thin host of the backend. Put services required by every
  backend host in `desktop/backend` (`ApiState::start_services`); keep window
  initialization in the app's entry point.
- Packages the window host imports sit at the top of `desktop/backend`; the
  rest stay under `desktop/backend/internal`. Moon allows an `internal` import
  only inside one module, so moving a package out of `internal` is what
  exposes it to another module. Make that move when the task requires a public
  host-facing package contract.

## Development Builds

- The supported development build is the packaged `.dev` application
  (`package/build.mjs` with the development project config, e.g.
  `dist/SeekMoonDev.app`). It runs the same packaged layout as a release —
  `seekmoon/web` for the frontend, the per-user runtime dir for state — and
  differs only by its identity suffix and the development-only behavior gated
  on it.
- For behavior that depends on the Desktop host or packaging, reproduce and
  validate it in the packaged development app. Unpackaged launch paths are
  historical; their removal belongs to a task that includes that cleanup.

## UI Pull Requests

- For PRs with visible Desktop UI changes, include screenshots in the PR
  description showing the affected UI from the changed build. Include
  before-and-after comparisons when useful, and a short recording when the
  change is best demonstrated through interaction.
- Upload UI screenshots and recordings as PR attachments. Keep local captures
  outside the repository or in an ignored directory.
- Prefer demo data when capturing screenshots or recordings. Before uploading,
  remove or redact personal information, real conversations, private project
  names and paths, credentials, and other sensitive content, including content
  in sidebars, terminals, and notifications.
- Inspect the final images or recording before uploading to confirm that
  sensitive content is removed and the UI change remains clear. If visual
  evidence cannot be captured, explain the limitation in the PR description.

## Child Processes

- For a one-shot command that collects stdout and stderr but must not read
  input, use `@processx.collect_output_no_stdin` from
  `desktop/backend/processx` instead of `@process.collect_output`.
- `collect_output_no_stdin` gives the child a valid stdin handle that is
  already at EOF and always suppresses creation of a console window. Both are
  required for Windows GUI builds: inheriting a missing standard-input handle
  makes process creation fail, while launching a console application without
  suppression flashes a visible console window.
- Interactive commands and long-lived protocol processes use their owning
  lifecycle APIs and the stdin pipe, file, or PTY required by their protocol.

## JSON Protocol Codecs

- When adding a JSON type or changing its JSON contract under `desktop/`, write
  explicit `FromJson` and/or `ToJson` implementations for the serialization
  directions it uses. Update the affected codecs in the same change.
- A decoder defines the treatment of required, missing, `null`, malformed, and
  unknown fields. An encoder defines which optional fields are omitted. Follow
  the owning protocol's field semantics and error behavior.

## Command Validation

- Use typed requests and responses to check payload shape and expose schema
  drift. Enforce the affected command's documented product constraints.
- For additional guards against user mistakes or concurrent operations,
  identify the supported UI actions that reach the state, the defined
  constraint they would violate, and the expected UI result. Include multiple
  browser clients and hosts when those actions can reach the same data.
  Implement the guard within the requested feature's scope.

## Desktop Trust And Security Model

- The local user, processes running as that user, and authenticated Desktop
  frontends share the user's command authority, including terminal and shell
  access. This covers the Proton renderer, authenticated relay clients, and
  code the user deliberately builds or executes. Workspace and path checks
  express product scope within that authority.
- Authenticate frontends before granting a Desktop command channel. Keep
  unauthenticated peers, unrelated web origins, and content processed as data
  outside that authority. Rendered Markdown, diffs, file previews, tool output,
  and model output remain data, including when they originate in a checkout.
  Distinguish deliberate code execution from displaying or parsing a file.
- A security finding identifies the less-trusted principal, the boundary it
  crosses, and the new capability it gains. Evaluate these boundaries
  independently of which controls the normal UI exposes.
- Release and development builds use the same trust model. For the development
  loopback console, preserve the launch token, session cookie, and `Origin`
  check that fence web origins; loopback binding controls reachability only.
