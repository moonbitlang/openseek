# Quiet transcript replay

The chosen D direction, using actual OpenSeek transcript components with
experimental CSS: no prompt separator, a line beside the existing final-answer
copy action, and closer spacing within exchanges. No extra completion label.

Run `just replay` from desktop. Open **Transcript review** in the real sidebar.
Two durable exchanges include prose, a list, code and a table. Then:

1. Start next exchange (a durable user message and real run-start event).
2. Show tool activity (durable assistant tool call and corresponding result).
3. Stream next chunk; repeat to advance manually.
4. Finish or Fail. Inspect whether copy/end-line presentation matches the outcome.
5. Start another exchange to compare the other outcome without losing history.
6. Use Narrow viewport to resize the real app to 390px. Hide its sidebar if
   it covers the transcript; switch back with Wide viewport.

The controller is MoonBit. The simulated host owns only protocol/history;
production decoders, update handlers, tools, markdown and navigation render the
UI. No real command runs. This is not a captured trace. Codex, native transport,
reconnections and notifications are outside this focused replay.

The previous A/B/C/D switcher, approval/background-task fixtures, experimental
Completed footer and covered-panel walkthrough were removed. Prior prototypes
remain in git history, ending at 8c924a7. No production design has been merged.

Browser verification: loaded both initial exchanges, injected and expanded the
real tool activity, advanced streaming chunks, finished one exchange and failed
the next. The provisional and failed output had no final-answer copy action;
confirmed answers did. At 390px, the table and failure text wrapped within the
transcript. The main transcript renderer matches the baseline again; all visual
changes are isolated in transcript.prototype.css.

Latest focused comparison: retain D's exchange ending, remove the composer's
outer top border, and remove the streaming cursor. Existing header/sidebar and
composer activity indicators, step numbers, and responsive input sizing stay
as they were. These changes are isolated to the prototype stylesheet.

Timestamp comparison: initial history has synthetic timestamps spaced two minutes apart, starting ten minutes before page load. New replay events use their injection time. The existing MoonBit completion-time renderer supplies the label beside Copy; no token summary or new timestamp UI was added.

A/B comparison: A uses exact transcript/composer CSS from PR base 42d076f; B uses the PR implementation. Both stylesheets load in the same cascade positions. Switching only changes stylesheet media, preserving app state and events. The URL compare=before|after preserves the choice on reload.

Revised B (not yet in PR): send timestamps appear on prompt hover/focus without
reserving a metadata row. Tool-step ordinals and timestamps are collapsed under
Step details. The prompt is keyboard-focusable. A retains original styling;
B now includes experimental MoonBit disclosure markup, so it is labeled Revised
preview rather than the PR. Verified the tool-step disclosure opens to reveal
its number and timestamp. Reasoning-led steps remain outside this sample.

Revision: B now folds each non-final reasoning/tool activity as a whole. Its summary shows the step, tool count, pending/error status when present, and a CSS-clipped verbatim reasoning or narration preview. Expanding reveals the original activity components; final answers stay outside. Browser-checked the tool fixture collapsed and expanded. No generated summary; still prototype-only.
