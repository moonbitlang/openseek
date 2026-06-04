///|
test "submitted input marks prompt and shell command" {
  let input = @composer.Model::new("")
  let shell = @composer.Model::new("")
  shell.insert_user_text("!")
  assert_true(submitted_input("hello", input.mode()) == Prompt("hello"))
  assert_true(submitted_input("pwd ", shell.mode()) == Command("pwd"))
  assert_true(submitted_input("", shell.mode()) == Command(""))
}
