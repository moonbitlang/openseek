///|
fn load_saved_api_key(dispatch : @cmd.Dispatch[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    scheduler.add(dispatch(ApiKeyLoaded(js_load_api_key(ApiKeyStorageKey))))
  })
}

///|
fn save_api_key(api_key : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => js_save_api_key(ApiKeyStorageKey, api_key))
}

///|
extern "js" fn js_load_api_key(storage_key : String) -> String =
  #| (storageKey) => {
  #|   try {
  #|     const storage = globalThis.localStorage;
  #|     return storage ? String(storage.getItem(storageKey) || "") : "";
  #|   } catch (_) {
  #|     return "";
  #|   }
  #| }

///|
extern "js" fn js_save_api_key(storage_key : String, api_key : String) =
  #| (storageKey, apiKey) => {
  #|   try {
  #|     const storage = globalThis.localStorage;
  #|     if (storage) storage.setItem(storageKey, String(apiKey || ""));
  #|   } catch (_) {}
  #| }
