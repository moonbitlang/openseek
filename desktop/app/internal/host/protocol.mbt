///|
/// Reply to `open_path`: the route one transcript-referenced path took —
/// `Opened` (system opener), `Editor` (built-in editor, optional position),
/// `Directory` (built-in Files tree), or `Refused` with its user-facing
/// reason. Refusals ride the reply because the local bridge would flatten a
/// raised error to the generic "op ext:openseek/host.open_path failed".
type OpenPathReply = @protocol.OpenPathReply

///|
/// Reply to `host.reveal_path`: the file manager accepted the target, or the
/// host refused it with a user-facing reason.
type RevealPathReply = @protocol.RevealPathReply

///|
/// Reply to `apply_update`: the swap succeeded and the window may close.
type ApplyUpdateReply = @protocol.ApplyUpdateReply

///|
type OpenPathPayload = @protocol.OpenPathPayload
