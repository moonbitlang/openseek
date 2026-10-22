# Desktop Agent Notes

## Frontend And Host Compatibility

- The desktop frontend and host are versioned and shipped together. Target a
  matching frontend and host version, and evolve protocol payloads and both
  implementations in the same change. Support for mixed versions is a separate
  product requirement when explicitly requested.
- The relay serves one current browser frontend to every host. When a host
  command, reply or event changes incompatibly, increment
  `HostProtocolRevision` in `protocol/desktop_messages.mbt` (and the E2E
  harness's `hostProtocol`). The host sends it in every `agent.connected`.
  A browser starts its automatic resync only after a matching revision; on a
  mismatch it closes the socket without retrying and shows the host as
  unavailable on every non-Cloud page. Requests are not gated at the
  transport, so a manual read in the moment between the socket opening and
  `agent.connected` (opening Skills or Scheduled, say) can still reach a
  mismatched host before the gate covers the page. Keep `agent.connected`
  decodable for every host: add fields, but never require one beyond
  `protocol`.

## Module Boundary

- `desktop/backend` is a library whose direct and transitive dependencies are
  independent of Proton and window toolkits. Code that needs Proton belongs in
  `desktop/app`; when shared code needs a fact only Proton knows, the window
  host passes it in as a value (`@resources.Resources`).
- `desktop/app` is the only module that depends on Proton. It is left out of
  the root `moon.work` and builds in its own `desktop/app/moon.work`, so root
  Moon commands (and the CI rows that run them) need no Proton runtime. Keep
  Proton imports in this module; `proton_contract` is the exception, being
  target-neutral types with no native setup.
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

## Validation By Change Scope

Apply the [root scope and expansion rules](../AGENTS.md#validation-by-change-scope).

| Change | Targeted checks |
| --- | --- |
| CSS or presentation assets | Rebuild the browser bundle and preview affected UI or run a focused Playwright spec. |
| Frontend MoonBit source | JS checks and relevant model/package tests; browser cases for changed rendering, events, or user workflows. |
| Protocol/codecs or backend behavior | Owning package and affected consumer checks/tests; exercise changed frontend/backend flows. |
| Proton window host or contracts it consumes | Check/test affected packages from `app/moon.work`; validate host-dependent behavior in the packaged development app. |
| Build scripts or packaging | Affected script syntax/tests or build-package checks, then inspect the affected artifact. |

Command details: [browser tests](e2e/README.md), [host checks](README.md), and
[packaging](package/README.md). Browser fixtures replace HTTP/WebSocket sources;
use real backend/host checks when those layers change.

Full entries from the repository root: `just desktop-test-browser`,
`just desktop-app-check`, `just desktop-app-test`, and
`just desktop-build-scripts-check`, when justified or explicitly required.

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

- For a one-shot command that collects stdout and stderr and expects EOF on
  stdin, use `@processx.collect_output_no_stdin` from
  `desktop/backend/internal/processx`.
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
