///|
async test "a scratch lab is created canonical and removed on request" {
  let lab = new_scratch_lab("openseek-lab-test-")
  assert_eq(lab, @fs.realpath(lab))
  assert_true(@fs.exists(lab))
  remove_scratch_lab(lab)
  assert_false(@fs.exists(lab))
}
