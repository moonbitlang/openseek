// The browser page owns its questions for the signed-in account. Session sockets
// can reconnect while the same page retains its cards and delayed answers.

///|
priv struct BrowserCloudQuestions {
  questions : @question_service.Service
}

///|
fn BrowserCloudQuestions::BrowserCloudQuestions() -> BrowserCloudQuestions {
  { questions: @question_service.Service(), }
}

///|
impl Eq for BrowserCloudQuestions with fn equal(a, b) {
  physical_equal(a, b)
}

///|
fn BrowserCloudQuestions::answer(
  self : BrowserCloudQuestions,
  account : String,
  answer : @protocol.UserQuestionAnswer,
  dispatch : @cmd.Emit[Msg],
  emit : @cmd.Emit[@user_questions.Msg],
) -> @cmd.Cmd {
  self.questions.answer(answer) catch {
    error =>
      return emit(
        @user_questions.Failed(request=answer.id, error=error.to_string()),
      )
  }
  let commands = [emit(@user_questions.Snapshot(self.questions.snapshot()))]
  for (session, text, id) in self.questions.take_inputs() {
    commands.push(
      dispatch(
        CloudAction(@cloud.QuestionInput(account~, session~, text~, id~)),
      ),
    )
  }
  @cmd.batch(commands)
}
