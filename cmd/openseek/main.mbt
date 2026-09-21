///|
/// Keep the legacy package coordinate runnable while pointing users to the root.
async fn main {
  @stdio.stderr.write(
    "Warning: moonbitlang/openseek/cmd/openseek is deprecated; use moonx moonbitlang/openseek instead.\n",
  ) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
  @app.run_cli()
}
