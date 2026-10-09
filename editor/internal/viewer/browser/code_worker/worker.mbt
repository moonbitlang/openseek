///|
pub(all) enum CodeWorkerFailure {
  Unavailable
  Computation
  InvalidResponse
  TimedOut
} derive(Eq, Debug)

///|
pub extend CodeWorkerFailure with Eq::{equal, not_equal}

///|
pub extend CodeWorkerFailure with Debug::{to_repr}

///|
/// Cancellation terminates the actual worker, not just its result callback.
/// A main-thread timeout likewise preempts a running synchronous diff. Worker
/// errors are explicit; they never masquerade as an empty successful diff.
pub fn compute(
  request : @protocol.CodeWorkerRequest,
  callback : (Result[@protocol.CodeWorkerResponse, CodeWorkerFailure]) -> Unit,
  max_time_ms? : Int = 1000,
) -> @base_common.Disposable? {
  if !available() {
    return None
  }
  let payload = stringify_wire_json(request.to_json()) catch {
    _ =>
      return Some(
        @base_common.Disposable::from(
          defer_failure(() => callback(Err(InvalidResponse))),
        ),
      )
  }
  let cancel = start_worker(
    payload,
    max_time_ms,
    data => {
      let response : @protocol.CodeWorkerResponse? = Some(
        @json.from_json(parse_wire_json(data)),
      ) catch {
        _ => None
      }
      match response {
        Some(Failed) => callback(Err(Computation))
        Some(response) => callback(Ok(response))
        None => callback(Err(InvalidResponse))
      }
    },
    status => callback(Err(if status == 2 { TimedOut } else { Unavailable })),
  )
  Some(@base_common.Disposable::from(cancel))
}

///|
pub extern "js" fn available() -> Bool = "() => typeof Worker === 'function' && typeof document !== 'undefined'"

///|
extern "js" fn defer_failure(callback : () -> Unit) -> () -> Unit =
  #| callback => { const timer = setTimeout(callback, 0); return () => clearTimeout(timer); }

///|
extern "js" fn start_worker(
  payload : String,
  timeout_ms : Int,
  success : (String) -> Unit,
  failure : (Int) -> Unit,
) -> () -> Unit =
  #| (payload, timeoutMs, success, failure) => {
  #|   let worker;
  #|   let done = false;
  #|   let timer;
  #|   const finish = callback => {
  #|     if (done) return;
  #|     done = true;
  #|     clearTimeout(timer);
  #|     worker?.terminate();
  #|     callback();
  #|   };
  #|   try {
  #|     worker = new Worker(new URL('editor-code-worker.js', document.baseURI));
  #|     worker.onmessage = event => finish(() => success(event.data));
  #|     worker.onerror = event => { event.preventDefault(); finish(() => failure(1)); };
  #|     timer = setTimeout(() => finish(() => failure(2)), timeoutMs);
  #|     worker.postMessage(payload);
  #|   } catch (_) {
  #|     // Keep completion asynchronous even when Worker construction fails.
  #|     timer = setTimeout(() => finish(() => failure(1)), 0);
  #|   }
  #|   return () => { done = true; clearTimeout(timer); worker?.terminate(); };
  #| }
