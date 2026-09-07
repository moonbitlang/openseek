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
