///|
/// Always mount the native HTML dialog at a stable position. showModal gives
/// it keyboard focus containment, Escape dismissal, and focus restoration
/// without adding DOM bindings or letting background controls receive clicks.
pub fn Model::view(self : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let children : Array[@html.Html] = []
  if self.content is Some(content) {
    let busy = content.operation.busy()
    children.push(
      @html.div(class="export-dialog-header", [
        @html.div(
          id="conversation-export-title",
          class="modal-title",
          "Export conversation",
        ),
        @html.button(
          class="export-dialog-close",
          title="Close",
          on_click=emit(Close),
          attrs=@html.Attrs::build().aria_label("Close export dialog"),
          @icons.icon(@icons.icon_close),
        ),
      ]),
    )
    // The source title stays in the export metadata; the dialog only presents
    // the actions, without repeating the conversation heading behind it.
    children.push(
      @html.div(
        id="conversation-export-description",
        class="modal-body",
        "Download saves an HTML file. Share uploads HTML and JSON, including tool inputs and outputs. Anyone with the link can view it for 7 days, preview HTML, and download both files. Check for private information before sharing.",
      ),
    )
    children.push(
      @html.div(class="modal-actions", [
        @html.button(
          class="button secondary",
          disabled=busy,
          on_click=emit(Download),
          if content.operation is Downloading {
            "Saving…"
          } else {
            "Download"
          },
        ),
        @html.button(
          class="button primary",
          disabled=busy || content.publication is Some(_),
          on_click=emit(Share),
          if content.operation is Sharing {
            "Sharing…"
          } else {
            "Share"
          },
        ),
      ]),
    )
    let status = match content.operation {
      Ready => @html.nothing
      Downloading => @html.span("Choose where to save the HTML file.")
      Sharing => @html.span("Uploading conversation…")
      SigningIn =>
        @html.span("Complete sign-in in your browser, then click Share.")
      SignInRequired =>
        @html.div([
          @html.p("Sign in to your OpenSeek server to share this conversation."),
          @html.button(class="button primary", on_click=emit(SignIn), "Sign in"),
        ])
      SignInFailed(message) =>
        @html.div([
          @html.p(
            class="export-error",
            "\{message} You can try signing in again, or download this conversation.",
          ),
          @html.button(
            class="button primary",
            on_click=emit(SignIn),
            "Try signing in again",
          ),
        ])
      Failed(message) => @html.div(class="export-error", message)
      Saved(path~, opened~) =>
        @html.div(
          if opened {
            "Saved to \{path}."
          } else {
            "Saved to \{path}, but couldn't open it automatically."
          },
        )
    }
    children.push(
      @html.div(
        class="export-status",
        attrs=@html.Attrs::build().aria_live("polite"),
        status,
      ),
    )
    if content.publication is Some(publication) {
      let { url, copy, } = publication
      children.push(
        @html.div(
          class="export-status",
          attrs=@html.Attrs::build().aria_live("polite"),
          @html.div([
            @html.div(class="export-link-row", [
              @html.input(
                value=url,
                read_only=true,
                attrs=@html.Attrs::build().aria_label("Share link"),
              ),
              @html.button(
                class=if copy is Copied {
                  "button secondary export-copy-success"
                } else {
                  "button secondary"
                },
                title="Copy to clipboard",
                // Keep success feedback in the icon; the accessible name
                // also reports it without adding visible status text.
                attrs=@html.Attrs::build().aria_label(
                  if copy is Copied {
                    "Share link copied"
                  } else {
                    "Copy share link"
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
            ]),
            match copy {
              Available | Copied => @html.nothing
              Failed(_) =>
                @html.div(
                  class="export-error",
                  "Could not copy. Select the link and copy it manually.",
                )
            },
          ]),
        ),
      )
    }
  }
  @html.dialog(
    id=DialogId,
    class="modal export-dialog",
    on_cancel=emit(Close),
    attrs=@html.Attrs::build()
      .aria_labelledby("conversation-export-title")
      .aria_describedby("conversation-export-description"),
    children,
  )
}
