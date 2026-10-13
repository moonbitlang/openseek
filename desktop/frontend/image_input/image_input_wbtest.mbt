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

///|
extern "js" fn BrowserFile::fixture(
  name : String,
  bytes : Bytes,
  path : @js.Nullable[String],
) -> BrowserFile =
  #| (name, bytes, path) => {
  #|   const file = new File([bytes], name);
  #|   if (path !== null) file.path = path;
  #|   return file;
  #| }

///|
test "native browser file paths use the resource path form on Windows" {
  let file = BrowserFile::fixture(
    "report.pdf",
    b"%PDF",
    @js.Nullable::from_option(Some("C:\\Users\\test\\report.pdf")),
  )
  assert_eq(file.native_path().to_option(), Some("/c:/Users/test/report.pdf"))
  let file = BrowserFile::fixture("report.pdf", b"%PDF", @js.Nullable::null())
  assert_eq(file.native_path().to_option(), None)
}
