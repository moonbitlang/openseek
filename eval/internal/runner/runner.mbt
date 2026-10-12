// Shared plumbing for the eval harnesses (file_edit, prompt_task): the
// bounded-concurrency trial runner and the standard on-disk run layout.

///|
/// Run `run(index)` for every index in `0..<count`, at most `concurrency` at
/// a time, returning the results in index order.
pub async fn[X] run_indexed_with_concurrency(
  count : Int32,
  concurrency : Int32,
  run : async (Int32) -> X,
) -> Array[X] {
  let limit = @async.Semaphore(concurrency)
  @async.all(
    [
      for index in 0..<count => {
        () => {
          limit.acquire()
          defer limit.release()
          run(index)
        }
      }
    ],
  )
}

///|
/// Reset `out_dir` to the standard eval-run layout — empty `workspaces/` and
/// `logs/` directories — removing any previous run's artifacts first.
pub async fn prepare_output_dir(out_dir : String) -> Unit {
  if @fs.exists(out_dir) {
    @fs.rmdir(out_dir, recursive=true)
  }
  @fs.mkdir("\{out_dir}/workspaces", recursive=true)
  @fs.mkdir("\{out_dir}/logs", recursive=true)
}

///|
/// Two-digit zero-padded trial index, for stable artifact file names.
pub fn padded_index(value : Int32) -> String {
  value.to_string().pad_start(2, '0')
}
