///|
const LanguageStorageKey : String = "openseek.language"

///|
/// Browser preferences are read at startup and when a language is selected.
extern "js" fn browser_language_values() -> FixedArray[String] =
  #|() => typeof navigator === 'undefined' ? [] : Array.from(navigator.languages || [navigator.language]).filter(x => typeof x === 'string')

///|
fn browser_languages() -> Array[String] {
  browser_language_values().iter().collect()
}

///|
extern "js" fn language_storage() -> @js.Value =
  #|() => { const storage = globalThis.localStorage; if (!storage) throw new Error('Language preference storage is unavailable'); return storage; }

///|
fn read_language_preference() -> Result[@i18n.Preference?, String] {
  @js.Error_::wrap(
    () => {
      let storage = language_storage()
      storage.apply_with_string("getItem", [
        @js.Value::cast_from(LanguageStorageKey),
      ])
    },
    map_ok=value => {
      let stored : String? = @js.Cast::into(value)
      Ok(stored.bind(value => @i18n.Preference::parse(value)))
    },
  ) catch {
    error => Err(error.to_string())
  }
}

///|
fn save_language(
  language : @i18n.Preference,
  dispatch : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  if @interop.page_channel() is Some(Local) {
    return @cmd.custom_cmd(scheduler => {
      @js.async_run(() => {
        let _reply = @interop.bridge_request_in_order(
          Local,
          @commands.app_language_set,
          { language: Some(language.wire()), },
        ) catch {
          error => {
            scheduler.add(
              dispatch(LanguageStorageFailed(@interop.bridge_error_text(error))),
            )
            return
          }
        }
      })
    })
  }
  @cmd.custom_cmd(scheduler => {
    @js.Error_::wrap(
      () => {
        let storage = language_storage()
        storage.apply_with_string("setItem", [
          @js.Value::cast_from(LanguageStorageKey),
          @js.Value::cast_from(language.wire()),
        ])
      },
      map_ok=_ => (),
    ) catch {
      error => scheduler.add(dispatch(LanguageStorageFailed(error.to_string())))
    }
  })
}

///|
fn load_language(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    if @interop.page_channel() is Some(Local) {
      @js.async_run(() => {
        let saved = @interop.bridge_request_in_order(
          Local,
          @commands.app_language_get,
          @protocol.NoPayload,
        ) catch {
          error => {
            scheduler.add(
              dispatch(LanguageStorageFailed(@interop.bridge_error_text(error))),
            )
            scheduler.add(dispatch(LanguageLoaded(None, browser_languages())))
            return
          }
        }
        scheduler.add(
          dispatch(
            LanguageLoaded(
              saved.language.bind(@i18n.Preference::parse),
              browser_languages(),
            ),
          ),
        )
      })
    } else {
      let saved = match read_language_preference() {
        Ok(value) => value
        Err(message) => {
          scheduler.add(dispatch(LanguageStorageFailed(message)))
          None
        }
      }
      scheduler.add(dispatch(LanguageLoaded(saved, browser_languages())))
    }
  })
}

///|
fn apply_language(dispatch : @cmd.Emit[Msg], locale : @i18n.Locale) -> @cmd.Cmd {
  @cmd.batch([
    @fileeditor.apply_language(locale),
    if @interop.page_channel() is Some(Local) {
      browser_op(
        dispatch,
        @commands.app_language_apply,
        { language: Some(locale.tag()), },
        quiet=false,
      )
    } else {
      @cmd.none
    },
    @cmd.custom_cmd(_ => {
      if @dom.document().get_document_element() is Some(root) {
        root.set_attribute("lang", locale.tag())
      }
    }),
  ])
}

///|
priv suberror LanguageSubscription {
  LanguageSubscription(@cmd.Emit[Msg])
}

///|
fn language_subscription(emit : @cmd.Emit[Msg]) -> @sub.Sub {
  @sub.custom_sub("ui-language", Global, LanguageSubscription(emit), (
    payload,
    scheduler,
  ) => {
    guard payload is LanguageSubscription(emit) else { return None }
    let mut emit = emit
    let window = @dom.window().as_event_target()
    let listener : @dom.Listener = _ => {
      scheduler.add(emit(SystemLanguagesChanged(browser_languages())))
    }
    window.add_event_listener("languagechange", listener)
    Some({
      unload: _ => window.remove_event_listener("languagechange", listener),
      update_tagger: payload => {
        if payload is LanguageSubscription(next) {
          emit = next
        }
      },
    })
  })
}
