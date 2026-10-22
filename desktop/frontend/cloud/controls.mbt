///|
/// A local submission remains recoverable until the server confirms its fate.
/// Queue contents themselves always come from the control snapshot.
pub struct ControlInput {
  task_id : String
  key : String
  operation : ControlOperation
  draft : @composer.Draft?
  source : @composer.Draft?
  attachments : Array[@protocol.AttachmentSource]
  acknowledged : Bool
  unknown : Bool
} derive(Eq)

///|
fn control_draft(content : @wire.Content) -> @composer.Draft {
  let images : Array[@composer.Image] = content
    .iter()
    .filter_map(part => {
      match part {
        Text(_) => None
        Image(image) => {
          let image : @composer.Image = {
            name: "Image",
            url: image.data_url(),
          }
          Some(image)
        }
      }
    })
    .collect()
  let text = content.text()
  match @mention_context.parse(text) {
    Some(parsed) =>
      {
        task: parsed.task,
        mentions: parsed.mentions.map(ref_ => { ref_, range: None, }),
        images,
      }
    None => { task: text, mentions: [], images, }
  }
}

///|
fn ControlInput::content(self : ControlInput) -> String {
  match self.operation {
    Steer(content~, ..) | QueueAdd(content~, ..) | QueueEdit(content~, ..) =>
      content.text()
    _ => self.draft.map_or("", draft => draft.prompt())
  }
}

///|
/// HTTP callback keys are local; queue and steer receipts use the input ID.
fn ControlInput::submission_id(self : ControlInput) -> String {
  match self.operation {
    Steer(submission_id~, ..) => submission_id
    QueueAdd(id~, ..)
    | QueueEdit(id~, ..)
    | QueueWithdraw(id~)
    | QueueSteer(id~) => id
    Stop => self.key
  }
}

///|
pub fn Conversation::control_primary_action(
  self : Conversation,
  default_submit : @composer.RunningSubmit,
) -> @composer.PrimaryAction {
  guard self.control is Some(control) &&
    self.watch_status == Watching &&
    self.stream is Some({ active: true, .. }) &&
    self.last_seq is Some(_) else {
    return @composer.Send(available=false)
  }
  let pending = self.control_inputs.any(input => {
    Some(input.task_id) == self.task && !input.acknowledged
  })
  if self.queue_edit is Some(_) && control.status == Idle {
    return @composer.SaveQueuedInput(
      available=control.paused && self.task is Some(_) && !pending,
    )
  }
  guard control.active_task_id is Some(_) else {
    return @composer.Send(available=false)
  }
  let stopping = control.status == Stopping ||
    self.control_inputs.any(input => {
      Some(input.task_id) == control.active_task_id && input.operation is Stop
    })
  @composer.Running(
    steer_available=!stopping && !pending,
    can_stop=!stopping,
    submit=if self.queue_edit is Some(_) {
      @composer.SaveQueue
    } else {
      default_submit
    },
    queue_available=!stopping && !pending,
  )
}

///|
pub fn Conversation::control_context(
  self : Conversation,
) -> Array[@composer.ContextComponent] {
  let context : Array[@composer.ContextComponent] = []
  let pending : Array[@composer.PendingSteerInput] = []
  for input in self.control_inputs {
    if input.operation is (Steer(..) | QueueSteer(..)) {
      pending.push({ id: input.submission_id(), content: input.content(), })
    }
  }
  if !pending.is_empty() {
    context.push(@composer.PendingSteerPanel(items=pending))
  }
  if self.control is Some(control) {
    let enabled = self.stream is Some({ active: true, .. }) &&
      self.watch_status == Watching &&
      self.last_seq is Some(_) &&
      (
        (control.status == Running && control.active_task_id is Some(_)) ||
        (control.status == Idle && control.paused && self.task is Some(_))
      ) &&
      !self.control_inputs.any(input => {
        Some(input.task_id) == self.task &&
        (input.operation is Stop || !input.acknowledged)
      })
    let queue : Array[@composer.QueuedInput] = control.queue.map(item => {
      id: item.id,
      content: item.content.text(),
      state: @composer.Queued(
        editing=self.queue_edit == Some(item.id),
        steer_available=control.status == Running &&
          control.active_task_id is Some(_),
        interactive=enabled &&
          !self.control_inputs.any(input => {
            input.task_id == self.task.unwrap_or("") &&
            input.submission_id() == item.id
          }),
      ),
    })
    for input in self.control_inputs {
      if input.operation is QueueAdd(..) &&
        !control.queue.any(item => item.id == input.submission_id()) {
        queue.push({
          id: input.key,
          content: input.content(),
          state: @composer.Queueing,
        })
      }
    }
    if !queue.is_empty() {
      context.push(@composer.QueuedInputPanel(items=queue, enabled~))
    }
  }
  context
}

///|
fn Conversation::acknowledge_control(
  self : Conversation,
  id : String,
) -> Conversation {
  guard self.control_inputs.iter().find_first(input => input.key == id)
    is Some(input) &&
    !input.acknowledged else {
    return self
  }
  let consumes_draft = input.draft is Some(_) &&
    !(input.operation is QueueSteer(..)) &&
    self.task == Some(input.task_id)
  {
    ..self,
    control_inputs: self.control_inputs.map(input => {
      if input.key == id {
        { ..input, acknowledged: true, unknown: false, }
      } else {
        input
      }
    }),
    submission_sequence: self.submission_sequence +
    (if consumes_draft { 1 } else { 0 }),
    initial_submission: if consumes_draft &&
      self.initial_submission == input.source {
      None
    } else {
      self.initial_submission
    },
    initial_attachments: if consumes_draft &&
      self.initial_submission == input.source {
      []
    } else {
      self.initial_attachments
    },
    queue_edit: if consumes_draft && input.operation is QueueEdit(..) {
      None
    } else {
      self.queue_edit
    },
  }
}

///|
fn Conversation::reject_control(
  self : Conversation,
  id : String,
  notice : String?,
) -> Conversation {
  guard self.control_inputs.iter().find_first(input => input.key == id)
    is Some(input) else {
    return self
  }
  let recovered = if input.acknowledged || input.operation is QueueSteer(..) {
    input.draft
  } else {
    None
  }
  let recovered = match (recovered, self.initial_submission) {
    (Some(draft), Some(current)) if current != draft &&
      self.initial_submission != input.source => {
      let mut merged = {
        ..draft,
        task: if draft.task.is_empty() {
          current.task
        } else if current.task.is_empty() {
          draft.task
        } else {
          draft.task + "\n\n" + current.task
        },
        images: [..draft.images, ..current.images],
      }
      for mention in current.mentions {
        merged = merged.with_mention(mention)
      }
      Some(merged)
    }
    (recovered, _) => recovered
  }
  {
    ..self,
    control_inputs: self.control_inputs.filter(input => input.key != id),
    initial_submission: if recovered is Some(_) {
      recovered
    } else {
      self.initial_submission
    },
    initial_attachments: if recovered is Some(_) {
      input.attachments
    } else {
      self.initial_attachments
    },
    notice: if notice is Some(_) {
      notice
    } else {
      self.notice
    },
  }
}

///|
fn Conversation::control_receipt(
  self : Conversation,
  event : Event,
) -> Conversation {
  if event.kind == "task_started" {
    let next = {
      ..self,
      control_inputs: self.control_inputs.filter(input => {
        !(input.operation is Stop) || input.task_id == event.task_id
      }),
    }
    if event.data
      is {
        "submission_id": String(id),
        "previous_task_id": String(previous),
        ..
      } &&
      next.control_inputs
      .iter()
      .find_first(input => {
        input.submission_id() == id &&
        input.task_id == previous &&
        input.operation is QueueAdd(..)
      })
      is Some(input) {
      let acknowledged = next.acknowledge_control(input.key)
      return {
        ..acknowledged,
        control_inputs: acknowledged.control_inputs.filter(value => {
          value.key != input.key
        }),
      }
    }
    return next
  }
  if event.kind == "task_finished" {
    return {
      ..self,
      control_inputs: self.control_inputs.filter(input => {
        input.task_id != event.task_id || !(input.operation is Stop)
      }),
      queue_edit: if self.task == Some(event.task_id) {
        None
      } else {
        self.queue_edit
      },
    }
  }
  guard event.kind is ("steer_applied" | "steer_dropped") &&
    event.data is { "submission_id": String(id), .. } &&
    self.control_inputs
    .iter()
    .find_first(input => {
      input.submission_id() == id && input.task_id == event.task_id
    })
    is Some(input) else {
    return self
  }
  let next = self.acknowledge_control(input.key)
  if event.kind == "steer_dropped" {
    next.reject_control(
      input.key,
      Some("The additional input was not applied."),
    )
  } else {
    {
      ..next,
      control_inputs: next.control_inputs.filter(value => value.key != input.key),
    }
  }
}

///|
fn Conversation::control_snapshot(
  self : Conversation,
  task : String?,
  data : ControlState,
) -> Conversation {
  let mut next = { ..self, control: Some(data), }
  for input in self.control_inputs {
    if Some(input.task_id) != task {
      continue
    }
    if data.steers
      .iter()
      .find_first(receipt => receipt.submission_id == input.submission_id())
      is Some(receipt) {
      match receipt.status {
        Applied => {
          next = next.acknowledge_control(input.key)
          next = {
            ..next,
            control_inputs: next.control_inputs.filter(value => {
              value.key != input.key
            }),
          }
        }
        Dropped =>
          next = next
            .acknowledge_control(input.key)
            .reject_control(
              input.key,
              Some("The additional input was not applied."),
            )
        Pending | Unknown => next = next.acknowledge_control(input.key)
      }
    } else if input.operation is (QueueAdd(..) | QueueEdit(..)) &&
      data.queue.any(item => {
        item.id == input.submission_id() &&
        (match input.operation {
          QueueAdd(content~, ..) | QueueEdit(content~, ..) =>
            item.content == content
          _ => false
        })
      }) {
      next = next.acknowledge_control(input.key)
      next = {
        ..next,
        control_inputs: next.control_inputs.filter(value => {
          value.key != input.key
        }),
      }
    } else if input.operation is QueueWithdraw(..) &&
      !data.queue.any(item => item.id == input.submission_id()) {
      next = {
        ..next,
        control_inputs: next.control_inputs.filter(value => {
          value.key != input.key
        }),
      }
    } else if input.operation is Stop && data.status == Idle {
      next = {
        ..next,
        control_inputs: next.control_inputs.filter(value => {
          value.key != input.key
        }),
      }
    }
  }
  next
}

///|
fn State::begin_control(
  self : State,
  session : String,
  task_id : String,
  operation : ControlOperation,
  emit : @cmd.Emit[Msg],
  token : String,
  draft? : @composer.Draft,
  attachments~ : Array[@protocol.AttachmentSource] = [],
) -> (State, @cmd.Cmd) {
  let conversation = self.conversations[session]
  let key = match operation {
    Steer(submission_id~, ..) => submission_id
    QueueAdd(id~, ..) => id
    _ => @uuid.mint()
  }
  let input : ControlInput = {
    task_id,
    key,
    operation,
    draft,
    source: conversation.initial_submission,
    attachments,
    acknowledged: false,
    unknown: false,
  }
  let next = self.replace(session, {
    ..conversation,
    control_inputs: [..conversation.control_inputs, input],
    initial_attachments: if input.draft is Some(_) &&
      !(input.operation is QueueSteer(..)) {
      input.attachments
    } else {
      conversation.initial_attachments
    },
    notice: None,
  })
  let command = @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Msg = try {
        let operation = match (input.operation, input.draft) {
          (Steer(..) | QueueAdd(..) | QueueEdit(..), Some(draft)) => {
            let prepared = prepare_submission(
              token,
              session,
              draft,
              input.attachments,
              conversation.uploads,
              (source, path) => {
                scheduler.add(
                  emit(
                    ControlAttachmentStored(
                      self.epoch,
                      session,
                      input.task_id,
                      input.key,
                      source,
                      path,
                    ),
                  ),
                )
              },
            )
            let content = prompt_content(prepared)
            scheduler.add(
              emit(
                ControlPrepared(
                  self.epoch,
                  session,
                  input.task_id,
                  input.key,
                  prepared,
                  content,
                ),
              ),
            )
            match input.operation {
              Steer(..) => Steer(submission_id=input.key, content~)
              QueueAdd(..) => QueueAdd(id=input.key, content~)
              QueueEdit(id~, ..) => QueueEdit(id~, content~)
              _ => input.operation
            }
          }
          _ => input.operation
        }
        ControlFinished(
          self.epoch,
          session,
          input.task_id,
          input.key,
          control(token, session, input.task_id, operation),
        ) catch {
          @cloud_client.RequestError(failure) =>
            ControlFailed(
              self.epoch,
              session,
              input.task_id,
              input.key,
              failure,
            )
          _ =>
            ControlFailed(
              self.epoch,
              session,
              input.task_id,
              input.key,
              Unreachable,
            )
        }
      } catch {
        @cloud_client.RequestError(failure) =>
          ControlPreparationFailed(
            self.epoch,
            session,
            input.task_id,
            input.key,
            failure,
          )
        _ =>
          ControlPreparationFailed(
            self.epoch,
            session,
            input.task_id,
            input.key,
            Unreachable,
          )
      }
      scheduler.add(emit(result))
    })
    |> ignore
  })
  (next, command)
}

///|
fn control_target(message : Msg) -> (Int32, String, String, String)? {
  match message {
    ControlAttachmentStored(epoch, session, task, id, _, _)
    | ControlPrepared(epoch, session, task, id, _, _)
    | ControlFinished(epoch, session, task, id, _)
    | ControlFailed(epoch, session, task, id, _)
    | ControlPreparationFailed(epoch, session, task, id, _) =>
      Some((epoch, session, task, id))
    _ => None
  }
}

///|
/// Handle composer controls before the ordinary-message submission branch.
fn State::update_control(
  self : State,
  message : Msg,
  emit : @cmd.Emit[Msg],
  token : String?,
) -> (State, @cmd.Cmd)? {
  if message is ControlChecked(epoch, session, task, snapshot) {
    guard epoch == self.epoch &&
      snapshot.session_id == session &&
      snapshot.task_id == Some(task) &&
      self.conversations.get(session) is Some(conversation) &&
      conversation.watch_status == Watching &&
      conversation.stream is Some({ active: true, .. }) &&
      conversation.last_seq is Some(_) else {
      return Some((self, @cmd.none))
    }
    if conversation.task == snapshot.task_id &&
      snapshot.seq < conversation.last_seq.unwrap_or(0) {
      return Some((self, @cmd.none))
    }
    let mut changed = conversation.control_snapshot(
      snapshot.task_id,
      snapshot.data,
    )
    // HTTP can prove acceptance, but the session stream still owns the queue.
    // Keep an acknowledged add visible until its canonical queue row arrives.
    for input in conversation.control_inputs {
      if input.operation is QueueAdd(..) &&
        !changed.control_inputs.any(value => value.key == input.key) &&
        !conversation.control.map_or(false, control => {
          control.queue.any(item => item.id == input.submission_id())
        }) &&
        snapshot.data.queue.any(item => item.id == input.submission_id()) {
        changed = {
          ..changed,
          control_inputs: [
            ..changed.control_inputs,
            { ..input, acknowledged: true, unknown: false, },
          ],
        }
      }
    }
    return Some(
      (
        self.replace(session, { ..changed, control: conversation.control, }),
        @cmd.none,
      ),
    )
  }
  if control_target(message) is Some((epoch, session, task, id)) {
    guard epoch == self.epoch &&
      self.conversations.get(session) is Some(conversation) &&
      conversation.control_inputs.any(input => {
        input.key == id && input.task_id == task
      }) else {
      return Some((self, @cmd.none))
    }
    let changed = match message {
      ControlAttachmentStored(_, _, _, _, source, path) =>
        {
          ..conversation,
          uploads: if conversation.uploads.any(upload => upload.source == source) {
            conversation.uploads
          } else {
            [..conversation.uploads, { source, path, }]
          },
        }
      ControlPrepared(_, _, _, _, _, content) =>
        {
          ..conversation,
          control_inputs: conversation.control_inputs.map(input => {
            if input.key == id {
              let operation = match input.operation {
                Steer(..) => Steer(submission_id=id, content~)
                QueueAdd(..) => QueueAdd(id~, content~)
                QueueEdit(id=target, ..) => QueueEdit(id=target, content~)
                operation => operation
              }
              { ..input, operation, }
            } else {
              input
            }
          }),
        }
      ControlFinished(_, _, _, _, Accepted) => {
        let next = conversation.acknowledge_control(id)
        let input = next.control_inputs
          .iter()
          .find_first(input => input.key == id)
          .unwrap()
        if input.operation is QueueWithdraw(..) {
          {
            ..next,
            control_inputs: next.control_inputs.filter(input => input.key != id),
          }
        } else {
          next
        }
      }
      ControlFinished(_, _, _, _, Rejected(reason)) =>
        conversation.reject_control(
          id,
          Some("Cloud rejected the operation: " + reason + "."),
        )
      ControlPreparationFailed(_, _, _, _, failure) =>
        conversation.reject_control(id, Some(failure.label()))
      ControlFailed(_, _, _, _, failure) if failure
        is (Unauthorized | Http(400 | 404)) =>
        conversation.reject_control(id, Some(failure.label()))
      ControlFailed(_, _, _, _, failure) =>
        {
          ..conversation,
          control_inputs: conversation.control_inputs.map(input => {
            if input.key == id {
              { ..input, unknown: true, }
            } else {
              input
            }
          }),
          notice: Some(failure.label()),
        }
      _ => conversation
    }
    let command = if message is ControlFailed(_, _, _, _, failure) &&
      !(failure is (Unauthorized | Http(400 | 404))) &&
      token is Some(token) {
      @cmd.custom_cmd(scheduler => {
        @js.Promise::from_async(() => {
          try {
            let snapshot = read_control(token, session)
            scheduler.add(emit(ControlChecked(epoch, session, task, snapshot)))
          } catch {
            // The original operation remains unknown until an authoritative
            // snapshot or receipt reaches this client.
            _ => ()
          }
        })
        |> ignore
      })
    } else {
      @cmd.none
    }
    let state = self.replace(session, changed)
    let state = match message {
      ControlFailed(_, _, _, _, Unauthorized)
      | ControlPreparationFailed(_, _, _, _, Unauthorized) =>
        { ..state, needs_sign_in: true, }
      _ => state
    }
    return Some((state, command))
  }
  let owner = match message {
    ControlAction(owner, _) => owner
    Submit(owner, _) | SubmitAttachments(owner, _, _) => {
      guard owner is @interop.Cloud(session~, ..) &&
        self.conversations.get(session) is Some({ queue_edit: Some(_), .. }) else {
        return None
      }
      owner
    }
    _ => return None
  }
  guard owner is @interop.Cloud(account~, session~) &&
    self.user_id == Some(account) &&
    self.can_compose(session) &&
    !self.deletions.contains(session) &&
    !(self.metadata_saves.get(session) is Some({ edit: Archive(true), .. })) &&
    token is Some(token) &&
    self.conversations.get(session) is Some(conversation) &&
    conversation.stream is Some({ active: true, .. }) &&
    conversation.watch_status == Watching &&
    conversation.last_seq is Some(_) &&
    conversation.control is Some(control) &&
    conversation.task is Some(task) else {
    return Some((self, @cmd.none))
  }
  let running = control.status == Running &&
    control.active_task_id == Some(task)
  let queue_editable = running ||
    (control.status == Idle && control.paused && control.active_task_id is None)
  let locked = conversation.control_inputs.any(input => {
    input.task_id == task && (!input.acknowledged || input.operation is Stop)
  })
  let id = @uuid.mint()
  let (operation, draft, attachments) = match message {
    ControlAction(_, @composer.StopRequested(..)) => {
      guard running &&
        !conversation.control_inputs.any(input => input.operation is Stop) else {
        return Some((self, @cmd.none))
      }
      (Stop, None, [])
    }
    ControlAction(
      _,
      @composer.FollowupSubmitted(draft~, choice~, attachments~, ..)
    ) => {
      guard running && !locked && (!draft.is_blank() || !attachments.is_empty()) else {
        return Some((self, @cmd.none))
      }
      let content = prompt_content(draft) catch {
        @cloud_client.RequestError(failure) =>
          return Some(
            (
              self.replace(session, {
                ..conversation,
                notice: Some(failure.label()),
              }),
              @cmd.none,
            ),
          )
      }
      let operation = match choice {
        @composer.SteerNow => Steer(submission_id=id, content~)
        @composer.QueueNext => QueueAdd(id~, content~)
      }
      (operation, Some(draft), attachments)
    }
    ControlAction(_, @composer.QueuedInputEditRequested(id~, ..)) => {
      guard queue_editable &&
        !locked &&
        !conversation.control_inputs.any(input => {
          input.task_id == task && input.submission_id() == id
        }) &&
        control.queue.iter().find_first(item => item.id == id) is Some(item) else {
        return Some((self, @cmd.none))
      }
      return Some(
        (
          self.replace(session, {
            ..conversation,
            queue_edit: Some(id),
            initial_submission: Some(control_draft(item.content)),
            initial_attachments: [],
          }),
          @cmd.none,
        ),
      )
    }
    ControlAction(_, @composer.QueuedInputDeleteRequested(id~, ..)) => {
      guard queue_editable &&
        !locked &&
        !conversation.control_inputs.any(input => {
          input.task_id == task && input.submission_id() == id
        }) &&
        control.queue.any(item => item.id == id) else {
        return Some((self, @cmd.none))
      }
      return Some(
        self.begin_control(session, task, QueueWithdraw(id~), emit, token),
      )
    }
    ControlAction(_, @composer.QueuedInputSteerRequested(id~, ..)) => {
      guard running &&
        !locked &&
        !conversation.control_inputs.any(input => {
          input.task_id == task && input.submission_id() == id
        }) &&
        control.queue.iter().find_first(item => item.id == id) is Some(item) else {
        return Some((self, @cmd.none))
      }
      return Some(
        self.begin_control(
          session,
          task,
          QueueSteer(id~),
          emit,
          token,
          draft=control_draft(item.content),
        ),
      )
    }
    Submit(_, draft) | SubmitAttachments(_, draft, _) => {
      guard queue_editable &&
        !locked &&
        conversation.queue_edit is Some(edit) &&
        control.queue.any(item => item.id == edit) else {
        return Some((self, @cmd.none))
      }
      let attachments = match message {
        SubmitAttachments(_, _, attachments) => attachments
        _ => []
      }
      guard !draft.is_blank() || !attachments.is_empty() else {
        return Some((self, @cmd.none))
      }
      let content = prompt_content(draft) catch {
        @cloud_client.RequestError(failure) =>
          return Some(
            (
              self.replace(session, {
                ..conversation,
                notice: Some(failure.label()),
              }),
              @cmd.none,
            ),
          )
      }
      return Some(
        self.begin_control(
          session,
          task,
          QueueEdit(id=edit, content~),
          emit,
          token,
          draft~,
          attachments~,
        ),
      )
    }
    _ => return Some((self, @cmd.none))
  }
  Some(
    self.begin_control(
      session,
      task,
      operation,
      emit,
      token,
      draft?,
      attachments~,
    ),
  )
}

///|
pub extend ControlInput with Eq::{equal, not_equal}
