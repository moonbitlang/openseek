///|
/// An empty object fails if command construction accidentally reads File APIs.
extern "js" fn BrowserFile::dummy() -> BrowserFile =
  #| () => ({})

///|
test "file handles are read only when the command executes" {
  let selection = Selection([BrowserFile::dummy()])
  let emit : @cmd.Emit[Event] = @cmd.Emit(_ => @cmd.none)
  ignore(selection.read(emit))
  ignore(selection.read(emit))
}
