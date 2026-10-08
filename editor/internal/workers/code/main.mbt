///|
fn main {
  install_worker(input => {
    let response = try {
      let request : @protocol.CodeWorkerRequest = @json.from_json(
        @code_worker.parse_wire_json(input),
      )
      match request {
        Diff(original~, modified~, ignore_trim_whitespace~) =>
          @protocol.encode_diff(
            @diff.LineDocumentDiffProvider().compute_diff(
              TextSnapshot(original),
              TextSnapshot(modified),
              { ignore_trim_whitespace, },
            ),
          )
        Folding(text~, language_id~, off_side~, tab_size~, limit~, outline~) => {
          let (provider, outlined) = @code_widget.compute_prepared_folding(
            text, language_id, off_side, tab_size, limit, outline,
          )
          Folding(
            @protocol.encode_folds(provider),
            if physical_equal(provider, outlined) {
              None
            } else {
              Some(@protocol.encode_folds(outlined))
            },
          )
        }
      }
    } catch {
      _ => Failed
    }
    @code_worker.stringify_wire_json(response.to_json()) catch {
      _ => "\"Failed\""
    }
  })
}

///|
extern "js" fn install_worker(compute : (String) -> String) -> Unit = "(compute) => { globalThis.onmessage = event => globalThis.postMessage(compute(event.data)); }"
