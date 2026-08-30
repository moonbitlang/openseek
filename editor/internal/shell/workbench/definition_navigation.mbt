///|
priv enum PreviewResourceLifecycle {
  PreviewResourceOpen
  PreviewResourceClosing
  PreviewResourceDisposed
} derive(Eq)

///|
/// Host-owned state for one cross-resource Peek preview. The remote document
/// cache is URI-keyed, while each `TextModelReference` is a local lease over
/// the one model created from the returned snapshot.
priv struct PreviewResourceState {
  uri : @base_common.Uri
  mut model : @model.TextModel?
  mut in_flight : Int
  mut leases : Int
  mut lifecycle : PreviewResourceLifecycle
}

///|
let preview_resources : Map[String, PreviewResourceState] = Map([])

///|
/// Viewer disposal is terminal for this composition root. Set this at the
/// `on_did_dispose` boundary, before Viewer-owned contributions release their
/// nested preview leases, so reentrant resolver calls cannot create new work.
let preview_resources_shutdown : Ref[Bool] = Ref(false)

///|
fn is_workbench_resource(uri : @base_common.Uri) -> Bool {
  uri.scheme == "readonly-remote" && uri.authority == "workspace"
}

///|
fn workbench_location_opener() -> @navigation_api.LocationOpenerHandle {
  LocationOpenerHandle(open=request => {
    match request.mode {
      Side => false
      Current =>
        if !is_workbench_resource(request.location.uri) ||
          workbench_dispatch.val is None {
          false
        } else {
          dispatch_workbench_msg(OpenDefinitionLocation(request.location))
          true
        }
    }
  })
}

///|
fn workbench_text_model_resolver() -> @navigation_api.TextModelResolverHandle {
  TextModelResolverHandle(resolve=(resource, token) => {
    resolve_preview_model(resource, token)
  })
}

///|
async fn resolve_preview_model(
  resource : @base_common.Uri,
  token : @language.CancellationToken,
) -> @navigation_api.TextModelReference? noraise {
  if preview_resources_shutdown.val ||
    token.is_cancellation_requested() ||
    !is_workbench_resource(resource) ||
    protocol_send.val is None {
    return None
  }
  let key = resource.to_string()
  let state = match preview_resources.get(key) {
    Some(state) => {
      if state.lifecycle != PreviewResourceOpen {
        return None
      }
      match state.model {
        Some(model) if !model.is_disposed() =>
          return Some(acquire_preview_reference(state, model))
        Some(_) => {
          state.model = None
          state.in_flight += 1
          state
        }
        None => {
          state.in_flight += 1
          state
        }
      }
    }
    None => {
      let state : PreviewResourceState = {
        uri: resource,
        model: None,
        in_flight: 1,
        leases: 0,
        lifecycle: PreviewResourceOpen,
      }
      preview_resources[key] = state
      state
    }
  }
  let result = read_remote_document(resource, token~) catch {
    _ =>
      DocumentReadFailed(
        DocumentError(
          Unavailable,
          "Definition preview open failed.",
          uri=resource,
        ),
      )
  }
  if state.in_flight > 0 {
    state.in_flight -= 1
  }
  if preview_resources_shutdown.val {
    begin_preview_resource_shutdown(state)
    return None
  }
  if state.lifecycle != PreviewResourceOpen || token.is_cancellation_requested() {
    retire_preview_resource_if_unused(state)
    return None
  }
  match result {
    DocumentLoaded(document) =>
      if document.uri.to_string() != key {
        retire_preview_resource_if_unused(state)
        None
      } else {
        let model = match state.model {
          Some(model) if !model.is_disposed() => model
          _ => {
            let model = document_to_text_model(document)
            state.model = Some(model)
            model
          }
        }
        Some(acquire_preview_reference(state, model))
      }
    DocumentNotFound(_) | DocumentReadFailed(_) => {
      retire_preview_resource_if_unused(state)
      None
    }
  }
}

///|
fn acquire_preview_reference(
  state : PreviewResourceState,
  model : @model.TextModel,
) -> @navigation_api.TextModelReference {
  state.leases += 1
  TextModelReference(model, release=() => {
    if state.leases > 0 {
      state.leases -= 1
    }
    retire_preview_resource_if_unused(state)
  })
}

///|
fn retire_preview_resource_if_unused(state : PreviewResourceState) -> Unit {
  if state.lifecycle == PreviewResourceDisposed ||
    state.in_flight > 0 ||
    state.leases > 0 {
    return
  }
  state.lifecycle = PreviewResourceDisposed
  let key = state.uri.to_string()
  match preview_resources.get(key) {
    Some(current) if physical_equal(current, state) =>
      preview_resources.remove(key)
    _ => ()
  }
  match state.model {
    Some(model) => {
      state.model = None
      if !model.is_disposed() {
        model.dispose()
      }
    }
    None => ()
  }
  if !is_active_document_resource(state.uri) {
    document_provider.close(state.uri)
  }
}

///|
/// Active-document teardown consults this before closing the shared remote
/// document cache entry. The final preview lease performs the deferred close.
fn preview_resource_retains_remote_document(uri : @base_common.Uri) -> Bool {
  match preview_resources.get(uri.to_string()) {
    Some(state) => state.in_flight > 0 || state.leases > 0
    None => false
  }
}

///|
/// Starts terminal preview-cache shutdown without fabricating ownership
/// counters. Existing nested Viewers keep their models alive until their real
/// references release, and late reads retire only after their real in-flight
/// count reaches zero.
fn shutdown_preview_resources() -> Unit {
  preview_resources_shutdown.val = true
  let states : Array[PreviewResourceState] = []
  for _key, state in preview_resources {
    states.push(state)
  }
  for state in states {
    begin_preview_resource_shutdown(state)
  }
}

///|
fn begin_preview_resource_shutdown(state : PreviewResourceState) -> Unit {
  if state.lifecycle == PreviewResourceOpen {
    state.lifecycle = PreviewResourceClosing
  }
  retire_preview_resource_if_unused(state)
}
