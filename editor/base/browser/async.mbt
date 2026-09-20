///|
/// Wait for a browser callback using the Promise runtime shared with Rabbita.
/// Registration runs synchronously; completion resumes on a Promise microtask.
pub async fn[T] wait_callback(register : ((T) -> Unit) -> Unit) -> T {
  let promise_ctor : @js.Value = @js.globalThis.get_with_string("Promise")
  let promise : @js.Promise[T] = promise_ctor.new([
    (resolve : (T) -> Unit, _reject : (@js.Value) -> Unit) => register(resolve),
  ])
  promise.wait()
}
