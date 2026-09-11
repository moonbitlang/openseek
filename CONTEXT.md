# OpenSeek

OpenSeek's language for conversations between a user and an assistant.

## Language

**Minimal mode**:
A transcript presentation that emphasizes assistant messages and brief descriptions of tool activity, without raw tool parameters or output. Activity groups containing readable edit / multi-edit changes open by default and show their requested changes as a single-column diff with file and line anchors. After a turn completes normally with a final assistant message, its earlier activity is collapsed; stopped or failed turns retain their process. It is an application-wide preference switched from Settings, on by default.
_Avoid_: Summary mode (which could imply rewriting message content)

**Activity summary**:
A short list of the kinds of tool activity within a portion of a conversation. Each kind appears once, without a count; individual tool descriptions remain available by expanding the summary.
_Avoid_: Activity count, file count
