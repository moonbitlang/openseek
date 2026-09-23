///|
const LanguageStorageKey : String = "openseek.language"

///|
fn browser_languages() -> Array[String] {
  browser_language_values().iter().collect()
}

///|
fn read_language_preference() -> Result[@i18n.Preference?, String] {
  match @base_browser.local_storage_get(LanguageStorageKey) {
    Ok(stored) => Ok(stored.bind(@i18n.Preference::parse))
    Err(Unavailable) => Err("Language preference storage is unavailable")
    Err(AccessFailed(message)) => Err(message)
  }
}

///|
fn save_language(
  is_desktop~ : Bool,
  language : @i18n.Preference,
  dispatch : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  if is_desktop {
    return @cmd.custom_cmd(scheduler => {
      @js.Promise::from_async(() => {
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
      |> ignore
    })
  }
  @cmd.custom_cmd(scheduler => {
    match @base_browser.local_storage_set(LanguageStorageKey, language.wire()) {
      Ok(_) => ()
      Err(Unavailable) =>
        scheduler.add(
          dispatch(
            LanguageStorageFailed("Language preference storage is unavailable"),
          ),
        )
      Err(AccessFailed(message)) =>
        scheduler.add(dispatch(LanguageStorageFailed(message)))
    }
  })
}

///|
fn load_language(is_desktop~ : Bool, dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    if is_desktop {
      @js.Promise::from_async(() => {
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
      |> ignore
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
fn apply_language(
  is_desktop~ : Bool,
  dispatch : @cmd.Emit[Msg],
  locale : @i18n.Locale,
) -> @cmd.Cmd {
  @cmd.batch([
    @fileeditor.apply_language(locale),
    if is_desktop {
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
