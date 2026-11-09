///|
/// Always mount the native HTML dialog at a stable position. showModal gives
/// it keyboard focus containment, Escape dismissal, and focus restoration
/// without adding DOM bindings or letting background controls receive clicks.
pub fn Model::view(
  locale~ : @i18n.Locale = English,
  self : Model,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let children = if self.content is Some(content) {
    let file = content.source is File(_)
    let busy = content.operation.busy()
    let header = @rui.dialog_header([
      @rui.dialog_title(
        id=self.id_prefix + "-title",
        ui(locale, if file { ShareFile } else { ExportConversation }),
      ),
    ])
    let actions = @rui.dialog_footer([
      if file {
        @html.nothing
      } else {
        @html.button(
          class="button secondary export-download",
          disabled=busy,
          on_click=emit(Download),
          if content.operation is Downloading {
            ui(locale, SavingLabel)
          } else {
            ui(locale, DownloadLabel)
          },
        )
      },
      @html.button(
        class="button primary",
        disabled=busy || content.publication is Some(_),
        on_click=emit(Share),
        if content.operation is Sharing(_) {
          ui(locale, SharingLabel)
        } else {
          ui(locale, ShareLabel)
        },
      ),
    ])
    let status = match content.operation {
      Ready => @html.nothing
      Downloading => @html.span(ui(locale, ChooseSavePath))
      Sharing(progress) =>
        if file {
          @html.span(ui(locale, SharingLabel))
        } else {
          share_progress_view(locale, progress)
        }
      SigningIn =>
        @html.div(class="account-sign-in", [
          @html.span(ui(locale, CompleteBrowserSignIn)),
          @html.button(
            class="button secondary",
            on_click=emit(Close),
            ui(locale, CancelSignIn),
          ),
        ])
      SignInRequired =>
        @html.div([
          @html.p(
            ui(
              locale,
              if file {
                FileSignInDescription
              } else {
                SignInDescription
              },
            ),
          ),
          @html.button(
            class="button primary",
            on_click=emit(SignIn),
            ui(locale, SignInLabel),
          ),
        ])
      SignInFailed(message) =>
        @html.div([
          @html.p(
            class="export-error",
            if file {
              message
            } else {
              dynamic_text(locale, DSignInFailure(message.to_string()))
            },
          ),
          @html.button(
            class="button primary",
            on_click=emit(SignIn),
            ui(locale, RetrySignIn),
          ),
        ])
      Failed(message) => @html.div(class="export-error", message)
      Saved(path~, opened~) =>
        @html.div(
          if opened {
            dynamic_text(locale, DSaved(path.to_string()))
          } else {
            dynamic_text(locale, DSavedNotOpened(path.to_string()))
          },
        )
    }
    let publication = if content.publication is Some(publication) {
      let { url, copy, } = publication
      [
        @html.div(
          class="export-status",
          attrs=@html.Attrs::build().aria_live("polite"),
          @html.div([
            @html.div(class="export-link-row", [
              @html.input(
                value=url,
                read_only=true,
                attrs=@html.Attrs::build().aria_label(ui(locale, ShareLink)),
              ),
              @html.button(
                class=if copy is Copied {
                  "button secondary export-copy-success"
                } else {
                  "button secondary"
                },
                title=ui(locale, CopyClipboard),
                // Keep success feedback in the icon; the accessible name
                // also reports it without adding visible status text.
                attrs=@html.Attrs::build().aria_label(
                  if copy is Copied {
                    ui(locale, LinkCopied)
                  } else {
                    ui(locale, CopyShareLink)
                  },
                ),
                on_click=@clipboard.copy(
                  Text(url),
                  copied=emit(
                    ClipboardFinished(generation=self.generation, Ok(())),
                  ),
                  failed=message => {
                    emit(
                      ClipboardFinished(
                        generation=self.generation,
                        Err(message),
                      ),
                    )
                  },
                ),
                @icons.icon(
                  if copy is Copied {
                    @icons.icon_check
                  } else {
                    @icons.icon_copy
                  },
                ),
              ),
              if file {
                @html.a(
                  href=url,
                  target=Blank,
                  rel="noopener noreferrer",
                  escape=true,
                  class="button secondary",
                  title=ui(locale, OpenShareLink),
                  attrs=@html.Attrs::build().aria_label(
                    ui(locale, OpenShareLink),
                  ),
                  @icons.icon_link_external(),
                )
              } else {
                @html.nothing
              },
            ]),
            match copy {
              Available | Copied => @html.nothing
              Failed(_) =>
                @html.div(class="export-error", ui(locale, CannotCopy))
            },
          ]),
        ),
      ]
    } else {
      []
    }
    [
      header,
      @html.div(
        [
          ..match content.source {
            File(HostFile(_, payload)) =>
              [@rui.dialog_description(payload.path)]
            File(CloudFile(path~, ..)) => [@rui.dialog_description(path)]
            _ => []
          },
          @rui.dialog_description(
            id=self.id_prefix + "-description",
            ui(
              locale,
              if file {
                FileShareDescription
              } else {
                ExportDescription
              },
            ),
          ),
          @html.div(
            class="export-status",
            attrs=@html.Attrs::build().aria_live("polite"),
            status,
          ),
          ..publication,
        ],
      ),
      actions,
    ]
  } else {
    []
  }
  @rui.dialog(
    id=self.id_prefix + "-dialog",
    class="dialog-size-medium",
    close_label=ui(
      locale,
      if self.content is Some({ source: File(_), .. }) {
        CloseLabel
      } else {
        CloseDialog
      },
    ),
    on_close=_ => emit(Close),
    on_cancel=emit(Close),
    attrs=@html.Attrs::build()
      .aria_labelledby(self.id_prefix + "-title")
      .aria_describedby(self.id_prefix + "-description"),
    children,
  )
}

///|
fn share_progress_view(
  locale : @i18n.Locale,
  progress : @protocol.ShareProgress,
) -> @html.Html {
  let label = match progress {
    Preparing => ui(locale, PreparingConversation)
    Connecting(attempt~) =>
      ui(locale, if attempt > 1 { RetryingShare } else { ConnectingShare })
    Uploading(attempt~) =>
      ui(
        locale,
        if attempt > 1 {
          RetryingShare
        } else {
          UploadingConversation
        },
      )
    Waiting(attempt~) =>
      if attempt > 1 {
        "\{ui(locale, RetryingShare)} \{ui(locale, WaitingForShare)}"
      } else {
        ui(locale, WaitingForShare)
      }
  }
  @html.div(class="export-progress", [
    @html.span(label),
    @html.div(
      class="update-progress-track",
      attrs=@html.Attrs::build().role("progressbar").aria_label(label),
      [@html.div(class="update-progress-fill indeterminate", "")],
    ),
  ])
}
