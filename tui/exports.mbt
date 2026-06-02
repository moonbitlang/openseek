// The semantic model types live in tui/core; re-export them so the tui package
// remains the single public facade for consumers (e.g. cmd/tui) that construct
// inputs and transcript items.

///|
pub using @core {type Input, type Event, type ToolStatus, type TranscriptItem}
