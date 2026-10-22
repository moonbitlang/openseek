# Agent Notes

## Start Here

- Architecture and dependency rules: `docs/architecture.md`
- Package contracts: the owning package's `README.md` and
  `pkg.generated.mbti`
- Commands and test-layer selection: `docs/harness.md`
- Validation selection and conformance-test rules: `docs/quality.md`
- Style: `docs/styles.md`
- Active cross-package plans and planning rules: `docs/exec-plans/`
- Monaco/CodeMirror source maps: `docs/references/{monaco,codemirror}.md`

## UI Development Loop

OpenSeek's desktop file editor (`../desktop/frontend/fileeditor`) is the primary
downstream, user-facing host. `internal/shell` is the fast development and E2E
host for the editor. Use it for the routine editor UI build-and-preview loop.

- For a visual or behavioral improvement to existing Viewer UI, implement and
  preview it in `internal/shell`, keep the existing public host seam stable, and
  expect OpenSeek to receive the change with at most a small adapter change.
  When broader adaptation appears necessary, inspect the coupling before
  expanding either host API.
- For a new editor UI intended for OpenSeek, inspect
  `../desktop/frontend/fileeditor/{editor_panel,viewer_services}.mbt` and the
  relevant provider/capability adapters before finalizing the public contract.
  New user-facing Viewer features target OpenSeek by default; an explicit
  editor-only exploration has its stated scope. Build the generic editor
  surface and its `internal/shell` preview first, then complete the OpenSeek
  adapter required by the feature in the same implementation task. Separate
  coherent commits are fine.
- Keep OpenSeek product policy, host RPC, storage, and workspace behavior under
  `../desktop/**`. Keep the editor API host-neutral, and use `ViewerServices`
  and the public `viewer/common/**` capability handles as the integration seam.
- Select checks using `docs/quality.md`. For OpenSeek adapter changes, check
  touched MoonBit packages for JS and exercise the affected integration path.
  Validate OpenSeek-specific layout in its UI; follow `../desktop/AGENTS.md`
  when behavior depends on the window host or packaging.

## Architecture Changes

For dependency or public API changes, follow `docs/architecture.md`, review the
affected `moon.pkg` files, and inspect the owning `pkg.generated.mbti`. Introduce
architecture automation when the same concrete boundary violation has recurred;
make the check express that boundary independently of current method or type
names.

## Reference Ports

Follow `docs/exec-plans/_PORT_PLAYBOOK.md` for Monaco/VS Code or CodeMirror
ports. Use the selected upstream behavior as the oracle and choose MoonBit
representations to implement that contract. Within the selected port scope:

1. Choose and state the port mode: behavior port by default, algorithm-fidelity
   port for sensitive arithmetic/state machines, or full source audit only when
   explicitly requested.
2. Account for observable behavior, boundary cases, algorithmic invariants, and
   intentional exclusions at the behavior or branch-cluster level. Use a
   per-member ledger when the selected full-audit mode requires it.
3. Preserve exact control flow and constants only where they affect the selected
   algorithm-fidelity contract. Otherwise prefer MoonBit-native concrete types,
   enums, handles, callback records, and ownership.
4. Link each claimed behavior to focused evidence or mark it `DEFERRED (reason)`
   / `N-A (reason)`. Use repository checks for integration and focused evidence
   for the claimed behavioral parity.

## Execution Plan Continuation

When the user asks to execute a checked-in plan, carry its agreed scope through
inventory, review, implementation, validation, and milestone commits. Treat
the plan's review gates as internal quality checkpoints: produce the required
artifact, review it against the plan and current source, record the result,
and continue.

Pause only when the user explicitly requests a review stop or when the gate
reveals a material choice that the plan and current repository evidence cannot
resolve without changing scope, public API, or behavior.

## Version Control

- For implementation tasks, commit each coherent, validated milestone as part
  of delivery.
- Preserve existing history by default. Rewrite or revert it when the user has
  authorized that operation.
