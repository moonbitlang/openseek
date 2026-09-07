## Latest revision: D — Quiet ending

D preserves the original user bubble and unboxed assistant prose. It removes
the experimental Completed footer and puts a subtle line in the existing copy
action row. The prompt-to-response gap is 14px, with additional space before
the next prompt. A/B/C remain for comparison. This is a visual prototype,
not an accepted production change.

# Message layout prototypes

Three layouts on the real desktop replay route, selected by `?variant=A|B|C`
and the bottom switcher. Switching preserves the live application state.
A uses separate soft message surfaces; B uses a labeled reading column;
C groups prompt and answer visually into an exchange card. All hide the
prompt separator and show a completion line below a confirmed final answer.

Run `just replay` from desktop, select Task A, Start A, Finish A. Compare the
three layouts with the bottom buttons or left/right arrows outside inputs.
This branch changes the actual MoonBit assistant renderer to include the
experimental completion footer, plus replay-only CSS. It is not a production
fix. The host fixture now commits the terminal event so completion comes from
the real transcript mapper. This visual comparison has been checked with a
short successful exchange; long transcripts and other outcomes need further
review before choosing a production design. No design has been selected.

# Current review: chat separator

The user deprioritized the covered-transcript edge case below. The current
review concerns the horizontal rule between the user prompt and assistant
answer. Open A, Start A, Finish A; restore or hide the file panel to see both.
The production shared transcript renderer deliberately inserts `TurnRule`
after user messages, with an optional send time. This fixture omits timestamps,
so the line is bare. No separator styling or production behavior has changed.

The earlier panel scenario now has explicit in-page instructions naming both
Show panel / Show files and Expand panel, including the visible checkpoint
that the messages disappear. Future scenarios must list each required UI
transition instead of assuming the user knows the setup.

# Selecting a covered task

This throwaway replay uses unchanged production code from main `8b00cad`
(including merged PR #1337). The previous status replay is preserved by tag
`desktop-status-replay-1337`. The controller and host fixture remain on the
existing replay branch, outside production changes.

Question: should selecting a task acknowledge its outcome when the expanded
file panel still hides its transcript?

Run `just replay` from `desktop/`. Choose OpenSeek or Codex using the links.

1. Open Task A, then press **Start A**.
2. Select Task B; show the file panel and expand it.
3. Press **Finish A**. A now has a completed, unread sidebar cue.
4. Select Task A without restoring the panel. Move the pointer off the row
   so its hover-only archive action does not obscure the status.
5. Restore the panel to expose A's transcript.
6. Switch provider and repeat. Reset between outcomes; **Fail A** is available
   for the analogous failure scenario.

Observed on this baseline with completion: OpenSeek loses its unread cue at
step 4, while its transcript remains hidden. Codex retains the cue until the
transcript becomes visible. OpenSeek's `Model::activate` directly marks the
conversation read when focused, bypassing `transcript_is_visible`. This is a
missed navigation path in the prior fix, whose editor regression scenarios
covered completion while already selected.

The MoonBit controller injects synthetic protocol events. The application
mounts production `frontend.boot()` in its own iframe viewport, with production
CSS, navigation, decoders, update handlers, and components. No fixture writes
application selection, sidebar status, or approval markup. Host list/history
responses reflect delivered events; OpenSeek outcomes also commit a synthetic
durable transcript event. No real agent command executes.

These are synthetic protocol inputs, not a captured production trace. This
scenario does not establish behavior for native notifications, reconnects,
stale responses, browser focus transitions, or narrow layouts. The existing
approval controls remain available for exploratory comparisons.
