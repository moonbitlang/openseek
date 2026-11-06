// Size limits of the built-in file viewer, shared by every op that loads or
// routes a file to it.

///|
/// Keep routing and loading on the same size boundary. Larger files cannot be
/// displayed by the built-in viewer, even when their bytes happen to be text.
pub const MaxEditorFileBytes = 1048576

///|
/// Office packages and PDFs need their original bytes for the read-only
/// document viewer. Keep their limit separate from the
/// text editor limit so a normal document is not rejected merely because its
/// embedded media makes the package larger than one megabyte.
// Keep the decoded package below the 32 MiB remote JSON frame limit after
// base64 expansion and JSON overhead.
pub const MaxOfficeFileBytes : Int32 = 20 * 1024 * 1024
