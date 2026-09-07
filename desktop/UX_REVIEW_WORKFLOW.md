# Desktop UX review workflow

Review behavior through a repeatable interaction in the real UI. The user
should be able to inspect the evidence and disagree with the proposed UX
judgment without having to trust a description of the code.

## Define one question

Start with a concrete situation, the user's action, and the observable result.
Name the relevant principle in `UX_GUIDELINES.md`; use `UX_GUARDRAILS.md` and
`DESIGN.md` for interaction and visual constraints. Separate the observed
behavior from the judgment that it needs changing.

For example: after opening a stored Codex task, should an empty OpenSeek
“New chat” draft still occupy a sidebar row? Unsent content must remain
reachable when the user switches tasks.

## Replay the production path

Mount the production MoonBit frontend, or the smallest existing component
that includes the interaction under review. Reuse its state updates,
rendering, styles, and normal navigation. For Desktop-wide interactions,
prefer the full `frontend.boot()` entry point.

Simulate only the external boundary: host responses, notifications, or other
inputs. Reuse the existing browser harness where practical. Do not duplicate
the state machine in JavaScript, manufacture sidebar marks, or substitute a
lookalike UI and present its output as evidence about Desktop.

Provide a small development-only controller, exact input payloads, and reset
to a known starting point. Let the user advance one event at a time and pause
to inspect the real UI. Use the real sidebar or composer for user actions.
Include the nearest counterexample: background versus foreground, success
versus failure, or an empty draft versus one with unsent content.

Identify synthetic fixtures as synthetic. A fixture-driven replay establishes
what the frontend does with those inputs; it does not prove a real host emits
that exact sequence. A captured trace should identify its provenance and
have sensitive data removed. State any omitted surfaces, such as native
notifications, instead of assuming they provide no feedback.

## Establish evidence before changing behavior

Run the sequence and record the exact symptom. Use visible UI and accessible
state to distinguish what is actually rendered from what the code suggests
should render. Trace the narrow path responsible for that result only after
the symptom is reproducible.

Present the observation, its user impact, and the proposed change separately.
For an exploratory review, agree on the desired behavior before implementing
it. An explicit user correction can supply that decision directly.

## Change and compare

Make the smallest production change that implements the agreed behavior.
Replay the same inputs against the changed code; do not modify fixtures just
to make the result look correct. Verify nearby behavior that must survive,
especially drafts, navigation, focus, and reading position.

Follow Desktop's test policy in `README.md`. Run applicable existing checks;
when adding tests is explicitly authorized, protect the agreed user-visible
behavior through the real path rather than freezing incidental markup.
Report blocked checks separately from the behavior verified in the browser.

Leave a runnable replay and concise instructions for the user. A written
claim or screenshot alone is insufficient when the question concerns a
sequence of interactions.

## Keep the process lightweight

Start with one scenario and one command. Reuse the application rather than
changing production APIs solely to accommodate a demo. Expand the harness
only when another concrete review needs it.

Preserve throwaway prototypes on a separate branch, with their question,
observed result, and unresolved limitations. Link that branch from the
implementation issue or review record. Keep only validated product changes
and useful workflow documentation in the main branch.

The first real-component replay is preserved on the
[prototype branch](https://github.com/moonbitlang/openseek/tree/codex/desktop-outcome-replay/desktop/frontend/replay)
(initial prototype commit `2941a16`). It injects Codex start/completion events
through the production
notification decoder, root and Codex updates, and complete component tree.
Its README records the observed behavior; the UX verdict on outcome cues
remains separate from that evidence.

The empty “New chat” row observed during this replay was subsequently
addressed by `a48977c` (`fix(desktop): clarify project new chat`). The
prototype commit predates that fix; use its original revision to reproduce
the old behavior and the same inputs on current code to inspect the correction.

## Background task status contract

Run the same scenario for OpenSeek and Codex: open A, start it, switch to B,
then deliver an approval request or a terminal outcome for A. Neither event
should navigate away from B. A pending decision takes priority over running;
opening A reveals the real decision controls without acknowledging the request.
After a response is accepted, continuing work returns to the running cue.

Completion and failure remain unread until the terminal turn is actually
visible in a focused window. A retained selection on another screen is not a
read receipt. Expanded editor panels and narrow-layout editor overlays also
keep outcomes unread; restoring or closing the panel acknowledges the outcome
only when it reveals the transcript. Refreshing an idle catalog must not erase the outcome, and stale
snapshots must not revive a completed run. Cancellation is labeled as stopped,
not failed. Status meaning must remain distinguishable without color or motion.

Keep this contract and its visual priority in the shared conversation module.
The provider adapters translate their own lifecycle and approval evidence;
protocol-specific snapshot ordering and recovery stay with those adapters.
