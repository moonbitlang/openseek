# Transcript minimal mode

Status: implemented and validated.

## Agreed behavior

- Add an optional minimal mode for both OpenSeek and Codex conversations,
  enabled by default. It is an application-wide display preference.
- Tool calls show brief / description text, without raw parameters or output.
  Activity groups with readable edit / multi-edit diffs open by default; manual
  folding survives result updates, and successful turns still collapse the
  overall process. The calls show single-column diffs with file and
  line anchors, reusing detailed mode decoding, diff generation, and styles.
  These compare requested old/new snippets, not confirmed filesystem changes;
  pending and failed states remain visible. Unreadable or oversized payloads
  retain their caption; omitted batch entries are explicitly indicated.
- Keep assistant progress messages visible while a turn is running, with
  consecutive tool activity collapsed between those messages.
- While a tool group contains pending calls, its collapsed label shows the
  most recently started pending call's description. Once all calls settle,
  switch to the activity categories. Completed-turn disclosures always show
  accumulated activity categories. Keep the ordered call history expandable.
- Background runtime notices belong inside the same activity disclosure as
  surrounding tool calls, in their original order. They never split the group
  or count as tool-call failures. Between turns, a notice has its own collapsed
  activity disclosure; it does not move ahead of a final answer. Job waiting,
  output retrieval, stopping, and notifications stay in the expanded history
  but contribute no category to the activity summary. Pending job waits use
  recorded job descriptions (falling back to IDs), for example `Wait for job
  "Run the pr tests" to complete`. Successful wait calls disappear from the
  expanded history once settled; failed waits remain visible and counted.
  Removing a wait does not claim that its targets succeeded, since user input
  can also end the wait. Detailed mode retains the full wait history.
- Context checkpoint summaries have their own collapsed "Context summary"
  disclosure, using a chevron and rendering Markdown when expanded. Preserve
  their event order and keep terminal guidance visible beside them.
- Describe the kinds of activity performed without numerical counts. The
  reference image uses subdued activity descriptions between assistant messages.
- Completed activity summaries list each activity category once. Expanding
  a summary shows individual calls' brief / description text in original order.
- Classify known tools by activity. Group tools whose activity cannot be
  determined under "Other tool calls". Expanded calls prefer brief, then
  description, then the tool name when neither description is available. Do
  not infer activity from arguments, script contents, or output. For mbtx,
  prefer its description over the result brief so completion does not replace
  the purpose of a script with only an exit code.
- Hide reasoning in minimal mode for this version. Assistant progress messages
  remain visible during execution.
- All user messages remain visible, including messages submitted during an
  executing turn. They split process disclosure regions to preserve order;
  a disclosure never spans a user message.
- After normal completion with a final assistant message, collapse the preceding
  process and leave the final assistant message visible.
- The completed-turn disclosure title shows the activity summary. Elapsed-time
  display is excluded from this version, per the user's later scope decision.
- Activity summaries report the number of failed tool calls, for example
  "2 tool calls failed". This failure count is distinct from activity categories,
  which remain uncounted.
- If execution completes without a final assistant message, retain the process.
- When execution stops or fails, retain the process and show the corresponding
  state instead of automatically collapsing it.

## Additional agreed behavior

- Put a Codicon info toggle on the right of both conversation titlebars,
  with info off for minimal mode and info on for the full transcript. Default
  to info off. Clicking toggles whether details are shown. Remember the choice
  using the existing local appearance-preference
  mechanism, including explicit opt-outs. Apply it to current and historical
  conversations; there is no duplicate switch in the Settings page.
- Use neutral activity labels such as "Read files" and "Execute scripts" so
  a pending call is not described as successfully completed. Pending calls use
  the same description-then-name fallback until a brief is available.
- Use the application chevron icon for disclosures instead of the native
  triangle marker, retaining native keyboard interaction.
- Do not create an empty process disclosure when a turn contains only its final
  assistant message.

## Out of scope

- Elapsed-time display and new persisted start markers added solely for timing.
- Raw tool parameters and output within minimal mode. Full editor widgets and
  side-by-side diff layouts are excluded; edit previews use static HTML.
- Reasoning display within minimal mode.

These are reversible presentation choices. No ADR is warranted at this stage.

## Source findings

- OpenSeek can finish successfully without final text: the finish tool accepts
  an empty answer (`agent_tool/finish/internal/decode/decode.mbt`), and
  `finish_turn` writes `Terminal(Finished(answer))` without a nonempty check
  (`agent/turn_loop.mbt`). This is a reachable code path, not an observed
  occurrence in user logs. Codex's local adapter accepts completed turns with
  no assistant message, but external producer behavior has not been established.
- A generic User record is not an unambiguous turn-start marker: idle shell
  command context and in-turn steering are also persisted as User records
  (`cmd/openseek/serve.mbt`, `agent/turn_loop.mbt`). Do not select the first User
  after a terminal event without distinguishing the actual starting prompt.
- UserMessage currently contains content and an optional submission_id
  (`agent_session/types.mbt`). The identifier helps reconcile current Desktop
  submissions, but legitimate starts from other entry points and automatic
  continuation can lack it. Its absence cannot establish that a User is not
  a starting prompt. No durable turn-start marker currently resolves this for
  all entry points.
- Existing application appearance preferences are stored locally for the
  current browser or webview profile.

## Validation

- `just check` and `just build` passed for native and JS targets.
- `just test` passed: 3,272 native tests, 3,237 JS tests, 24 offline cram
  cases, and both real-CLI turn lifecycle scenarios. The test process used
  `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false`
  so temporary fixture commits did not inherit personal signing settings;
  local TCP access was enabled for loopback tests. Global Git settings were
  not changed.
- The transcript browser suite passed all 15 tests, including the four new
  minimal-mode scenarios. After tightening Codex's raw-command fallback, all
  four minimal-mode browser tests and all 74 Codex package tests passed again.
- Browser tests cover keyboard disclosure, custom chevrons, stable expansion
  during tool updates, failure counts, input boundaries, empty/stopped/failed
  turns, absent tool descriptions, default-on behavior, preference persistence, full-mode restore,
  and both conversation sources. Screenshots were visually inspected.
- `moon info` and `moon fmt` completed. These frontend packages are JS-only,
  so their checked-in interfaces were refreshed from the JS `.mbti` output
  generated by `moon info --target js`. This also restored a few pre-existing
  public declarations omitted from the older checked-in interfaces.
