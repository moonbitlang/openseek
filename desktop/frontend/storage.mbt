///|
fn load_saved_settings(dispatch : @cmd.Dispatch[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    scheduler.add(
      dispatch(
        SettingsLoaded(
          js_load_setting(ApiProviderStorageKey),
          js_load_setting(CustomApiUrlStorageKey),
          js_load_setting(ApiKeyStorageKey),
        ),
      ),
    )
  })
}

///|
fn save_api_key(api_key : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => js_save_setting(ApiKeyStorageKey, api_key))
}

///|
fn save_api_provider(provider : ApiProvider) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => js_save_setting(ApiProviderStorageKey, provider.wire()))
}

///|
fn save_custom_api_url(url : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => js_save_setting(CustomApiUrlStorageKey, url))
}

///|
extern "js" fn js_load_setting(storage_key : String) -> String =
  #| (storageKey) => {
  #|   try {
  #|     const storage = globalThis.localStorage;
  #|     return storage ? String(storage.getItem(storageKey) || "") : "";
  #|   } catch (_) {
  #|     return "";
  #|   }
  #| }

///|
extern "js" fn js_save_setting(storage_key : String, value : String) =
  #| (storageKey, value) => {
  #|   try {
  #|     const storage = globalThis.localStorage;
  #|     if (storage) storage.setItem(storageKey, String(value || ""));
  #|   } catch (_) {}
  #| }
