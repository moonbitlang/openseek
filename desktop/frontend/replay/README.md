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
