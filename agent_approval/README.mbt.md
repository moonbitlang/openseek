# Approval review (`agent_approval`)

`agent_approval` is the reviewer behind `--approval review`. When a tool asks
for a permission the sandbox does not grant on its own — `mbtx` running
outside the sandbox, a deletion, a write outside the allowed scope — a
reviewer subagent answers instead of a person. Its one question: did the
user's request authorize this exact action, and is it safe to grant once?

## The contract

The `approval` kind (`openseek run --kind approval`) takes a `ReviewRequest`:

```json
{
  "tool_name": "remove",
  "detail": "notes/ (deletion requires approval)",
  "body": "{\"path\": \"notes/\"}",
  "intent": ["delete the notes directory"]
}
```

`tool_name`, `detail`, and `body` are the tool's `ApprovalAsk`, verbatim.
`intent` is the user's most recent messages (and the standing goal, when one
stands), oldest first: the only source of authorization the reviewer accepts.

It reports a `Verdict`:

```json
{ "decision": "allow | deny | escalate", "reason": "what was checked and what it showed" }
```

`Verdict::parse` holds both the child's `submit_verdict` tool and the parent's
trust boundary to the same check.

## How the parent acts on it

`internal/openseek/execution` spawns the child through `run_subrun` for each
question, then:

| verdict | outcome |
| --- | --- |
| `allow` | `AllowedOnce` |
| `deny` | `Rejected` |
| `escalate`, or no verdict (timeout, no report, spawn failure) | the controller is asked under `serve`; `Rejected` under `run` |

Only an escalated question reaches the controller; a decided one is not
announced, and the reviewer's own session records the verdict. The child is
delegated, so its own approval policy is `never`: a reviewer can never ask
for anything.

## Read-only, and no experiments

The toolset is read-only `mbtx` and `submit_verdict`. Unlike the other
read-only kinds there is no scratch lab, and the prompt forbids running the
operation under review: running it is the harm the review exists to prevent,
and the read-only profile is a best-effort guard on workspace sources, not a
process sandbox. Nor does the reviewer take instructions from its launcher
while it works: the agent whose request is under review is the one that
would be posting them.
