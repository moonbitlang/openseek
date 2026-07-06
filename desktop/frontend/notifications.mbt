// Transient error toasts. Failures with no better home in the layout
// (sidebar refreshes, archive and workspace operations) pop up in a
// configurable window corner and dismiss themselves — or sooner, on a click.

///|
/// How long a toast stays up before it dismisses itself.
const NotificationLifetimeMs : Int = 6000

///|
/// One transient toast. `id` pairs the auto-dismiss timer with its toast, so
/// a timer whose toast was already clicked away expires harmlessly instead
/// of touching a newer one. A toast carrying an action is sticky: it never
/// expires on its own, and clicking it performs the action and dismisses.
priv struct Notification {
  id : Int
  message : String
  action : NotificationAction?
}

///|
/// What clicking a sticky toast does: dismiss the announcement (the
/// fallback when this build cannot install the update itself), or swap in
/// the staged update and restart.
priv enum NotificationAction {
  AcknowledgeUpdate
  RestartToUpdate
}

///|
/// The window corner where toasts stack — a Settings choice, persisted under
/// its wire name. An unknown stored value falls back to the default
/// bottom-right, so a missing key and a stale value read the same.
priv enum NotificationCorner {
  TopLeft
  TopRight
  BottomLeft
  BottomRight
}

///|
fn NotificationCorner::parse(value : String) -> NotificationCorner {
  match value {
    "top-left" => TopLeft
    "top-right" => TopRight
    "bottom-left" => BottomLeft
    _ => BottomRight
  }
}

///|
fn NotificationCorner::wire(self : NotificationCorner) -> String {
  match self {
    TopLeft => "top-left"
    TopRight => "top-right"
    BottomLeft => "bottom-left"
    BottomRight => "bottom-right"
  }
}

///|
/// Append an error toast and schedule its expiry. Copy-on-write like the
/// transcript arrays, so `update` stays pure.
fn Model::notify_error(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  message : String,
) -> (@cmd.Cmd, Model) {
  let toast : Notification = {
    id: self.notification_seq,
    message,
    action: None,
  }
  let notifications = self.notifications.copy()
  notifications.push(toast)
  (
    @cmd.delay(dispatch(NotificationExpired(toast.id)), NotificationLifetimeMs),
    { ..self, notification_seq: toast.id + 1, notifications },
  )
}

///|
/// Announce a newer release with a sticky toast: no expiry timer, so a user
/// who is away from the window cannot miss it. One at a time — the check
/// runs once per connection, but a duplicate announcement must not stack a
/// second toast.
fn Model::notify_update(
  self : Model,
  message : String,
  action : NotificationAction,
) -> Model {
  if self.notifications.iter().any(toast => toast.action is Some(_)) {
    return self
  }
  let toast : Notification = {
    id: self.notification_seq,
    message,
    action: Some(action),
  }
  let notifications = self.notifications.copy()
  notifications.push(toast)
  { ..self, notification_seq: toast.id + 1, notifications }
}
