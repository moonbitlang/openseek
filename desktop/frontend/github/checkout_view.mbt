///|
pub fn checkout_notification(
  locale~ : @i18n.Locale,
  state : State,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  guard state.checkout is Some(checkout) else { return @html.nothing }
  let failed = checkout.phase is Failed(_, _)
  let message = match checkout.phase {
    Running =>
      if checkout.updating {
        ui(locale, UpdatingCheckout(checkout.number))
      } else {
        ui(locale, CheckingOut(checkout.number))
      }
    Failed(message, _) => "PR #\{checkout.number}: \{message}"
    Confirming => return @html.nothing
  }
  @html.div(
    class="github-checkout-notification" +
      (if failed { " failed" } else { " pending" }),
    attrs=@html.Attrs::build().role(if failed { "alert" } else { "status" }),
    [
      @html.div(class="github-checkout-message", [
        @icons.icon(if failed { @icons.icon_error } else { @icons.icon_sync }),
        @html.span(message),
        if failed {
          @html.button(
            class="tab-action",
            title=ui(locale, DismissCheckout),
            attrs=@html.Attrs::build().aria_label(ui(locale, DismissCheckout)),
            on_click=emit(DismissCheckout),
            @icons.icon(@icons.icon_close),
          )
        } else {
          @html.nothing
        },
      ]),
      if checkout.phase is Failed(_, Some(details)) {
        @html.div([
          @html.button(
            class="github-more",
            attrs=@html.Attrs::build().aria_expanded(
              checkout.show_details.to_string(),
            ),
            on_click=emit(ToggleCheckoutDetails),
            if checkout.show_details {
              ui(locale, HideDetails)
            } else {
              ui(locale, ShowDetails)
            },
          ),
          if checkout.show_details {
            @html.pre(class="github-checkout-details", details)
          } else {
            @html.nothing
          },
        ])
      } else {
        @html.nothing
      },
    ],
  )
}

///|
pub fn checkout_dialog(
  locale~ : @i18n.Locale,
  state : State,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  guard state.checkout is Some({ phase: Confirming, number, updating, .. }) else {
    return @html.nothing
  }
  @html.div(class="modal-backdrop", on_click=emit(DismissCheckout), [
    @html.div(
      id="github-checkout-dialog",
      class="modal github-checkout-dialog",
      attrs=@html.Attrs::build()
        .role("dialog")
        .aria_modal("true")
        .aria_label(
          if updating {
            ui(locale, UncommittedBeforeUpdate(number))
          } else {
            ui(locale, UncommittedBeforeCheckout(number))
          },
        )
        .on_click(event => {
          event.stop_propagation()
          @cmd.none
        })
        .on_keydown(event => {
          match event.key() {
            "Escape" => {
              event.prevent_default()
              event.stop_propagation()
              emit(DismissCheckout)
            }
            "Tab" => {
              event.prevent_default()
              event.stop_propagation()
              cycle_checkout_focus(event.shift_key())
              @cmd.none
            }
            _ => @cmd.none
          }
        }),
      [
        @html.div(class="modal-title", ui(locale, UncommittedChanges)),
        @html.div(
          class="modal-body",
          ui(
            locale,
            if updating {
              BeforeUpdate(number)
            } else {
              BeforeCheckout(number)
            },
          ),
        ),
        @html.div(class="github-checkout-choices", [
          @html.button(
            class="button primary",
            on_click=emit(ConfirmCheckout(Stash)),
            ui(locale, StashChanges),
          ),
          @html.button(
            class="button secondary github-checkout-discard",
            on_click=emit(ConfirmCheckout(Discard)),
            ui(locale, DiscardChanges),
          ),
          @html.button(
            class="button secondary",
            on_click=emit(ConfirmCheckout(Carry)),
            if updating {
              ui(locale, UpdateAnyway)
            } else {
              ui(locale, CheckoutAnyway)
            },
          ),
          @html.button(
            class="button secondary",
            on_click=emit(DismissCheckout),
            ui(locale, CancelLabel),
          ),
        ]),
      ],
    ),
  ])
}

///|
fn focus_checkout_dialog() -> @cmd.Cmd {
  @cmd.custom_cmd(_ => cycle_checkout_focus(false), kind=@cmd.after_render)
}

///|
extern "js" fn cycle_checkout_focus(backwards : Bool) -> Unit =
  #| backwards => {
  #|   const dialog = document.getElementById('github-checkout-dialog');
  #|   if (!dialog) return;
  #|   const buttons = [...dialog.querySelectorAll('button:not(:disabled)')];
  #|   const index = buttons.indexOf(document.activeElement);
  #|   buttons[(index + (backwards ? buttons.length - 1 : 1)) % buttons.length]?.focus();
  #| }

///|
fn focus_checkout_action(number : Int) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => restore_checkout_focus(number), kind=@cmd.after_render)
}

///|
extern "js" fn restore_checkout_focus(number : Int) -> Unit =
  #| number => [...document.querySelectorAll(`.github-review-update, .github-checkout[data-pr-number="${number}"]`)].find(element => element.getClientRects().length)?.focus()
