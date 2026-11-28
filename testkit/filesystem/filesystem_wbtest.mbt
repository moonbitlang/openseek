///|
/// Whitebox test of the now package-private `validate()`: the rejection it
/// raises is the contract `from_json()` relies on.
test "json fixture rejects non-string contents" {
  let files = FileSystem({ "src/count.txt": 1 })
  let _ = files.validate() catch {
    error => {
      assert_true("\{error}".contains("must be a string"))
      return
    }
  }
  fail("non-string content accepted")
}
