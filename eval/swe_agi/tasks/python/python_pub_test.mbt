///|
// GENERATED FILE; DO NOT EDIT BY HAND.
//
// Contents:
// - `check_syntax_file(...)` tests for every `test_*.py` module
// - Extracted assertions from `unittest.TestCase` methods, using
//   `Vm::exec_program(...)` with a conservative statement prelude when possible.
//
// This is intentionally only a subset of CPython assertions: anything that
// depends on imports/stdlib/IO/framework internals is recorded in the report.

///|
// Test provenance:
// - CPython v3.12.2 `Lib/test/test_grammar.py` (TokenTests + GrammarTests snippets)
// - CPython v3.12.2 `Lib/test/test_bool.py` (selected semantics)

///|
fn eval_json(vm : @python.Vm, expr : StringView) -> Json raise {
  vm.eval_expr(expr).to_test_json()
}

///|
fn assert_expr_json(expr : StringView, expected : Json) -> Unit raise {
  let vm = @python.Vm::new()
  json_inspect(eval_json(vm, expr), content=expected)
}

///|
test "python/ref/syntax/test__interpchannels.py" {
  @python.check_syntax_file("reference_pub_test/test__interpchannels.py")
}

///|
test "python/ref/syntax/test__locale.py" {
  @python.check_syntax_file("reference_pub_test/test__locale.py")
}

///|
test "python/ref/syntax/test__opcode.py" {
  @python.check_syntax_file("reference_pub_test/test__opcode.py")
}

///|
test "python/ref/syntax/test_abc.py" {
  @python.check_syntax_file("reference_pub_test/test_abc.py")
}

///|
test "python/ref/syntax/test_abstract_numbers.py" {
  @python.check_syntax_file("reference_pub_test/test_abstract_numbers.py")
}

///|
test "python/ref/syntax/test_annotationlib.py" {
  @python.check_syntax_file("reference_pub_test/test_annotationlib.py")
}

///|
test "python/ref/syntax/test_apple.py" {
  @python.check_syntax_file("reference_pub_test/test_apple.py")
}

///|
test "python/ref/syntax/test_asyncgen.py" {
  @python.check_syntax_file("reference_pub_test/test_asyncgen.py")
}

///|
test "python/ref/syntax/test_augassign.py" {
  @python.check_syntax_file("reference_pub_test/test_augassign.py")
}

///|
test "python/ref/syntax/test_bigaddrspace.py" {
  @python.check_syntax_file("reference_pub_test/test_bigaddrspace.py")
}

///|
test "python/ref/syntax/test_bigmem.py" {
  @python.check_syntax_file("reference_pub_test/test_bigmem.py")
}

///|
test "python/ref/syntax/test_binascii.py" {
  @python.check_syntax_file("reference_pub_test/test_binascii.py")
}

///|
test "python/ref/syntax/test_binop.py" {
  @python.check_syntax_file("reference_pub_test/test_binop.py")
}

///|
test "python/ref/syntax/test_bisect.py" {
  @python.check_syntax_file("reference_pub_test/test_bisect.py")
}

///|
test "python/ref/syntax/test_call.py" {
  @python.check_syntax_file("reference_pub_test/test_call.py")
}

///|
test "python/ref/syntax/test_charmapcodec.py" {
  @python.check_syntax_file("reference_pub_test/test_charmapcodec.py")
}

///|
test "python/ref/syntax/test_class.py" {
  @python.check_syntax_file("reference_pub_test/test_class.py")
}

///|
test "python/ref/syntax/test_cmath.py" {
  @python.check_syntax_file("reference_pub_test/test_cmath.py")
}

///|
test "python/ref/syntax/test_code.py" {
  @python.check_syntax_file("reference_pub_test/test_code.py")
}

///|
test "python/ref/syntax/test_code_module.py" {
  @python.check_syntax_file("reference_pub_test/test_code_module.py")
}

///|
test "python/ref/syntax/test_codeccallbacks.py" {
  @python.check_syntax_file("reference_pub_test/test_codeccallbacks.py")
}

///|
test "python/ref/syntax/test_codecencodings_cn.py" {
  @python.check_syntax_file("reference_pub_test/test_codecencodings_cn.py")
}

///|
test "python/ref/syntax/test_codecencodings_hk.py" {
  @python.check_syntax_file("reference_pub_test/test_codecencodings_hk.py")
}

///|
test "python/ref/syntax/test_codecencodings_iso2022.py" {
  @python.check_syntax_file("reference_pub_test/test_codecencodings_iso2022.py")
}

///|
test "python/ref/syntax/test_codecencodings_jp.py" {
  @python.check_syntax_file("reference_pub_test/test_codecencodings_jp.py")
}

///|
test "python/ref/syntax/test_codecencodings_kr.py" {
  @python.check_syntax_file("reference_pub_test/test_codecencodings_kr.py")
}

///|
test "python/ref/syntax/test_codecencodings_tw.py" {
  @python.check_syntax_file("reference_pub_test/test_codecencodings_tw.py")
}

///|
test "python/ref/syntax/test_codecmaps_cn.py" {
  @python.check_syntax_file("reference_pub_test/test_codecmaps_cn.py")
}

///|
test "python/ref/syntax/test_codecmaps_hk.py" {
  @python.check_syntax_file("reference_pub_test/test_codecmaps_hk.py")
}

///|
test "python/ref/syntax/test_codecmaps_jp.py" {
  @python.check_syntax_file("reference_pub_test/test_codecmaps_jp.py")
}

///|
test "python/ref/syntax/test_codecmaps_kr.py" {
  @python.check_syntax_file("reference_pub_test/test_codecmaps_kr.py")
}

///|
test "python/ref/syntax/test_codecmaps_tw.py" {
  @python.check_syntax_file("reference_pub_test/test_codecmaps_tw.py")
}

///|
test "python/ref/syntax/test_codeop.py" {
  @python.check_syntax_file("reference_pub_test/test_codeop.py")
}

///|
test "python/ref/syntax/test_collections.py" {
  @python.check_syntax_file("reference_pub_test/test_collections.py")
}

///|
test "python/ref/syntax/test_colorsys.py" {
  @python.check_syntax_file("reference_pub_test/test_colorsys.py")
}

///|
test "python/ref/syntax/test_compare.py" {
  @python.check_syntax_file("reference_pub_test/test_compare.py")
}

///|
test "python/ref/syntax/test_compiler_codegen.py" {
  @python.check_syntax_file("reference_pub_test/test_compiler_codegen.py")
}

///|
test "python/ref/syntax/test_complex.py" {
  @python.check_syntax_file("reference_pub_test/test_complex.py")
}

///|
test "python/ref/syntax/test_contains.py" {
  @python.check_syntax_file("reference_pub_test/test_contains.py")
}

///|
test "python/ref/syntax/test_context.py" {
  @python.check_syntax_file("reference_pub_test/test_context.py")
}

///|
test "python/ref/syntax/test_contextlib_async.py" {
  @python.check_syntax_file("reference_pub_test/test_contextlib_async.py")
}

///|
test "python/ref/syntax/test_copy.py" {
  @python.check_syntax_file("reference_pub_test/test_copy.py")
}

///|
test "python/ref/syntax/test_copyreg.py" {
  @python.check_syntax_file("reference_pub_test/test_copyreg.py")
}

///|
test "python/ref/syntax/test_coroutines.py" {
  @python.check_syntax_file("reference_pub_test/test_coroutines.py")
}

///|
test "python/ref/syntax/test_crossinterp.py" {
  @python.check_syntax_file("reference_pub_test/test_crossinterp.py")
}

///|
test "python/ref/syntax/test_csv.py" {
  @python.check_syntax_file("reference_pub_test/test_csv.py")
}

///|
test "python/ref/syntax/test_datetime.py" {
  @python.check_syntax_file("reference_pub_test/test_datetime.py")
}

///|
test "python/ref/syntax/test_decorators.py" {
  @python.check_syntax_file("reference_pub_test/test_decorators.py")
}

///|
test "python/ref/syntax/test_defaultdict.py" {
  @python.check_syntax_file("reference_pub_test/test_defaultdict.py")
}

///|
test "python/ref/syntax/test_deque.py" {
  @python.check_syntax_file("reference_pub_test/test_deque.py")
}

///|
test "python/ref/syntax/test_descr.py" {
  @python.check_syntax_file("reference_pub_test/test_descr.py")
}

///|
test "python/ref/syntax/test_descrtut.py" {
  @python.check_syntax_file("reference_pub_test/test_descrtut.py")
}

///|
test "python/ref/syntax/test_dict.py" {
  @python.check_syntax_file("reference_pub_test/test_dict.py")
}

///|
test "python/ref/syntax/test_dictcomps.py" {
  @python.check_syntax_file("reference_pub_test/test_dictcomps.py")
}

///|
test "python/ref/syntax/test_dictviews.py" {
  @python.check_syntax_file("reference_pub_test/test_dictviews.py")
}

///|
test "python/ref/syntax/test_docxmlrpc.py" {
  @python.check_syntax_file("reference_pub_test/test_docxmlrpc.py")
}

///|
test "python/ref/syntax/test_dynamic.py" {
  @python.check_syntax_file("reference_pub_test/test_dynamic.py")
}

///|
test "python/ref/syntax/test_dynamicclassattribute.py" {
  @python.check_syntax_file("reference_pub_test/test_dynamicclassattribute.py")
}

///|
test "python/ref/syntax/test_enumerate.py" {
  @python.check_syntax_file("reference_pub_test/test_enumerate.py")
}

///|
test "python/ref/syntax/test_errno.py" {
  @python.check_syntax_file("reference_pub_test/test_errno.py")
}

///|
test "python/ref/syntax/test_except_star.py" {
  @python.check_syntax_file("reference_pub_test/test_except_star.py")
}

///|
test "python/ref/syntax/test_exception_group.py" {
  @python.check_syntax_file("reference_pub_test/test_exception_group.py")
}

///|
test "python/ref/syntax/test_exception_variations.py" {
  @python.check_syntax_file("reference_pub_test/test_exception_variations.py")
}

///|
test "python/ref/syntax/test_extcall.py" {
  @python.check_syntax_file("reference_pub_test/test_extcall.py")
}

///|
test "python/ref/syntax/test_finalization.py" {
  @python.check_syntax_file("reference_pub_test/test_finalization.py")
}

///|
test "python/ref/syntax/test_flufl.py" {
  @python.check_syntax_file("reference_pub_test/test_flufl.py")
}
