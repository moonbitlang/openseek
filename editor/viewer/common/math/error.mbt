///|
fn math_error_message(error : @katex.ParseFailure) -> String {
  match error {
    UnexpectedCharacter(message~, ..)
    | InvalidArgument(message~, ..)
    | InternalInvariant(message~) => message
    ExpectedToken(expected~, actual~) =>
      "Expected \{expected}, got \{actual.text}"
    UndefinedControlSequence(name~, ..) => "Undefined control sequence: \{name}"
    DoubleSuperscript(..) => "Double superscript"
    DoubleSubscript(..) => "Double subscript"
    ExpectedGroupAfter(symbol~, ..) => "Expected a group after \{symbol}"
    FunctionNotAllowed(func_name~, context~, ..) =>
      "\{func_name} is not allowed in \{context}"
    MissingFunctionHandler(func_name~, ..) =>
      "Unsupported function: \{func_name}"
    TooManyExpansions(limit~) => "Too many macro expansions (limit: \{limit})"
  }
}
