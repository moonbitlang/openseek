///|
/// A brace-delimited top-level MoonBit function body. The declaration prefix
/// through `body_start_line_number` remains visible when its outline is
/// collapsed; the fold hides the following body lines and closing brace.
priv struct MoonbitFunctionBodyFold {
  declaration_start_line_number : Int
  body_start_line_number : Int
  body_end_line_number : Int
}

///|
/// A run of two or more consecutive top-level plain `//` comment lines —
/// typically a copyright or file-header block. The first line stays visible
/// when the run is collapsed; the fold hides the continuation lines.
priv struct MoonbitCommentRunFold {
  start_line_number : Int
  end_line_number : Int
}

///|
/// The lexical scan's combined result over one snapshot: brace-bodied
/// top-level function bodies and top-level plain-comment runs, each array in
/// document order and every construct mutually disjoint.
priv struct MoonbitSourceFolds {
  function_bodies : Array[MoonbitFunctionBodyFold]
  comment_runs : Array[MoonbitCommentRunFold]
}

///|
/// Marks a host-computed fold over a run of plain `//` comment lines. Unlike
/// `OUTLINE_BODY_FOLDING_RANGE_TYPE`, a collapsed comment run keeps the
/// ordinary trailing ellipsis after its first line.
const COMMENT_RUN_FOLDING_RANGE_TYPE : String = "editor.commentRun"

///|
fn is_moonbit_outline_identifier_start(code : Int) -> Bool {
  (code >= 'a' && code <= 'z') ||
  (code >= 'A' && code <= 'Z') ||
  code == '_' ||
  code >= 0x80
}

///|
fn is_moonbit_outline_identifier_continue(code : Int) -> Bool {
  is_moonbit_outline_identifier_start(code) || (code >= '0' && code <= '9')
}

///|
/// Whether a top-level line ending in `code` leaves a binding lexically
/// unfinished — `let header =` or a trailing binary operator — so following
/// lines continue the same construct. Postfix markers (`?` in `-> Item?`,
/// `~` labels) end a construct and are not continuations. A continuation
/// line that instead begins with its operator (a leading-dot method chain,
/// a split `-> Int` return clause) is invisible to this tail check;
/// `is_moonbit_leading_continuation_line` catches those when a run is
/// flushed.
fn is_moonbit_expression_continuation_code(code : Int) -> Bool {
  match code {
    '='
    | '+'
    | '-'
    | '*'
    | '/'
    | '%'
    | '<'
    | '>'
    | '&'
    | '|'
    | '^'
    | ':'
    | ','
    | '.'
    | '!' => true
    _ => false
  }
}

///|
/// Whether a line's first token continues the construct above it — a
/// leading binary operator, `->` return clause, `.` method chain, a
/// deferred initializer `=`, an opening delimiter (`(`, `[`, `{` never
/// start a top-level construct), or a continuation keyword (`else`, `catch`,
/// `noraise`, `raise`, `is`, `as`, `derive` — none of which can start a
/// top-level construct). A comment run terminated by such a line sits inside
/// that construct rather than at the top level. Leading `//` and `/*` are
/// comments, and `*/` closes one; none of those continue an expression.
fn is_moonbit_leading_continuation_line(line : String) -> Bool {
  let mut index = 0
  while index < line.length() {
    let code = line[index].to_int()
    if code == ' ' || code == '\t' || code == 0xFEFF {
      index += 1
      continue
    }
    let next = if index + 1 < line.length() {
      line[index + 1].to_int()
    } else {
      0
    }
    if code == '/' && next == '*' {
      // A closed block-comment prefix (`/* rationale */ else`) is trivia
      // before the first real token; an unclosed one makes the whole line
      // trivia and never reaches this classifier.
      let mut scan = index + 2
      let mut depth = 1
      while scan < line.length() && depth > 0 {
        let scan_code = line[scan].to_int()
        let scan_next = if scan + 1 < line.length() {
          line[scan + 1].to_int()
        } else {
          0
        }
        if scan_code == '/' && scan_next == '*' {
          depth += 1
          scan += 2
        } else if scan_code == '*' && scan_next == '/' {
          depth -= 1
          scan += 2
        } else {
          scan += 1
        }
      }
      if depth > 0 {
        return false
      }
      index = scan
      continue
    }
    if is_moonbit_outline_identifier_start(code) {
      let mut end = index + 1
      while end < line.length() &&
            is_moonbit_outline_identifier_continue(line[end].to_int()) {
        end += 1
      }
      let word = line[index:end].to_owned()
      return word == "else" ||
        word == "catch" ||
        word == "noraise" ||
        word == "raise" ||
        word == "is" ||
        word == "as" ||
        word == "with" ||
        word == "derive"
    }
    return match code {
      '/' => next != '/'
      '*' => next != '/'
      '(' | '[' | '{' => true
      '=' | '+' | '-' | '%' | '<' | '>' | '&' | '|' | '^' | ':' | ',' | '.' =>
        true
      _ => false
    }
  }
  false
}

///|
/// Whether the line's last meaningful token is a keyword operator that must
/// be followed by an operand, leaving the construct unfinished. `raise` and
/// `noraise` are excluded: they can validly end a bodyless signature
/// (`declare fn f() -> Int raise`). The scan records the first character of
/// the last token, so the word is read forward from `last_code_index`.
fn moonbit_line_ends_with_continuation_word(
  line : String,
  last_code : Int,
  last_code_index : Int,
) -> Bool {
  if !is_moonbit_outline_identifier_start(last_code) {
    return false
  }
  let mut end = last_code_index + 1
  while end < line.length() &&
        is_moonbit_outline_identifier_continue(line[end].to_int()) {
    end += 1
  }
  let word = line[last_code_index:end].to_owned()
  word == "is" ||
  word == "as" ||
  word == "with" ||
  word == "else" ||
  word == "try" ||
  word == "match" ||
  word == "if" ||
  word == "in" ||
  word == "catch"
}

///|
/// Whether a line's first token is a plain `//` line comment. Doc comments
/// (`///`, including the `///|` block delimiter) document the adjacent
/// declaration and never join a comment run. A byte-order mark — present on
/// a BOM-prefixed file's first line — is ignorable like whitespace.
fn is_moonbit_plain_comment_line(line : String) -> Bool {
  for index in 0..<line.length() {
    let code = line[index].to_int()
    if code == ' ' || code == '\t' || code == 0xFEFF {
      continue
    }
    return code == '/' &&
      index + 1 < line.length() &&
      line[index + 1].to_int() == '/' &&
      !(index + 2 < line.length() && line[index + 2].to_int() == '/')
  }
  false
}

///|
/// Finds brace-bodied top-level MoonBit functions and top-level plain-comment
/// runs without treating braces in comments, strings, interpolations, or raw
/// lines as source delimiters. The function scan is intentionally
/// declaration-specific: `declare` and `=`-backed functions have no MoonBit
/// body, while qualified methods and formatted `impl ... with fn ...`
/// declarations are included. Comment runs require the line-start lexical
/// state to be top level, so lines inside block comments, brace/paren/bracket
/// constructs, or unfinished binding continuations never join a run, and a
/// run flushed by a leading-operator line is discarded as part of that
/// construct. One accepted boundary: a declaration keyword split from its
/// whole body by comments (`typealias` / comments / `Int as Id`) has no
/// lexical terminator to track, so those comments still fold.
fn moonbit_source_folds(snapshot : @model.TextSnapshot) -> MoonbitSourceFolds {
  let folds : Array[MoonbitFunctionBodyFold] = []
  let comment_runs : Array[MoonbitCommentRunFold] = []
  let mut comment_run_start_line = 0
  let deferred_comment_runs : Array[MoonbitCommentRunFold] = []
  let mut block_comment_depth = 0
  let mut brace_depth = 0
  let mut function_keyword_line = 0
  let mut function_keyword_bracket_depth = 0
  let mut pending_function_prefix_line = 0
  let mut pending_function_prefix_paren_depth = 0
  let mut pending_impl_start_line = 0
  let mut pending_impl_saw_with = false
  let mut pending_bodyless_declaration = false
  let mut pending_bodyless_saw_fn = false
  let mut pending_binding_declaration = false
  let mut pending_extern_declaration = false
  let mut declaration_start_line = 0
  let mut body_start_line = 0
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut expression_nesting_depth = 0
  let mut pending_expression_continuation = false
  for line_number in 1..<=snapshot.line_count() {
    let line = snapshot.get_line_content(line_number)
    // Comment lines inside an in-progress declaration (between a formatted
    // signature's lines, or between `pub`/`impl` prefixes and their `fn`),
    // inside an unclosed paren/bracket continuation (a multi-line array or
    // argument list), or after a line that leaves a binding unfinished
    // (`let header =`, a trailing `+`) stay with their construct: folding
    // them would nest a comment run inside another fold's span and break
    // the disjoint document-order invariant of the host-fold list.
    let joins_comment_run = block_comment_depth == 0 &&
      brace_depth == 0 &&
      expression_nesting_depth == 0 &&
      !pending_expression_continuation &&
      declaration_start_line == 0 &&
      function_keyword_line == 0 &&
      pending_function_prefix_line == 0 &&
      pending_impl_start_line == 0 &&
      !pending_bodyless_declaration &&
      !pending_binding_declaration &&
      !pending_extern_declaration &&
      is_moonbit_plain_comment_line(line)
    let mut index = 0
    let mut quote = 0
    let mut escaped = false
    let mut interpolation_depth = 0
    let interpolation_resume_depths : Array[Int] = []
    let mut line_saw_equals = false
    let mut line_last_code = 0
    let mut line_last_code_index = -1
    while index < line.length() {
      let code = line[index].to_int()
      let next = if index + 1 < line.length() {
        line[index + 1].to_int()
      } else {
        0
      }
      // The line's last meaningful character, ignoring whitespace, block
      // comments, trailing `//` comments, and raw-line markers, feeds the
      // binding-continuation heuristic below.
      if block_comment_depth == 0 &&
        code != ' ' &&
        code != '\t' &&
        !(quote == 0 && code == '/' && (next == '/' || next == '*')) &&
        !(quote == 0 && (code == '#' || code == '$') && next == '|') {
        line_last_code = code
        line_last_code_index = index
      }
      if block_comment_depth > 0 {
        if code == '/' && next == '*' {
          block_comment_depth += 1
          index += 2
        } else if code == '*' && next == '/' {
          block_comment_depth -= 1
          index += 2
        } else {
          index += 1
        }
      } else if quote != 0 {
        if escaped {
          escaped = false
        } else if quote == '"' && code == '\\' && next == '{' {
          interpolation_depth += 1
          interpolation_resume_depths.push(interpolation_depth)
          quote = 0
          index += 2
        } else if code == '\\' {
          escaped = true
        } else if code == quote {
          quote = 0
        }
        if !(quote == 0 &&
          interpolation_depth > 0 &&
          code == '\\' &&
          next == '{') {
          index += 1
        }
      } else if interpolation_depth > 0 {
        if code == '/' && next == '/' {
          break
        } else if code == '/' && next == '*' {
          block_comment_depth = 1
          index += 2
        } else if code == '"' || code == '\'' {
          quote = code
          escaped = false
          index += 1
        } else if code == '{' {
          interpolation_depth += 1
          index += 1
        } else if code == '}' {
          if interpolation_resume_depths is [.., resume_depth] &&
            resume_depth == interpolation_depth {
            interpolation_resume_depths.pop() |> ignore
            interpolation_depth -= 1
            quote = '"'
          } else {
            interpolation_depth -= 1
          }
          index += 1
        } else {
          index += 1
        }
      } else if code == '/' && next == '/' {
        break
      } else if (code == '#' || code == '$') && next == '|' {
        function_keyword_line = 0
        pending_function_prefix_line = 0
        pending_function_prefix_paren_depth = 0
        pending_impl_start_line = 0
        pending_impl_saw_with = false
        // A raw `#|`/`$|` line can validly end its multi-line literal, so it
        // completes any unfinished top-level binding.
        if brace_depth == 0 && expression_nesting_depth == 0 {
          pending_expression_continuation = false
        }
        break
      } else if code == '/' && next == '*' {
        block_comment_depth = 1
        index += 2
      } else if code == '"' || code == '\'' {
        function_keyword_line = 0
        pending_function_prefix_line = 0
        pending_function_prefix_paren_depth = 0
        pending_impl_start_line = 0
        pending_impl_saw_with = false
        quote = code
        escaped = false
        index += 1
      } else if is_moonbit_outline_identifier_start(code) {
        let start = index
        index += 1
        while index < line.length() &&
              is_moonbit_outline_identifier_continue(line[index].to_int()) {
          index += 1
        }
        let word = line[start:index].to_owned()
        if brace_depth == 0 && declaration_start_line == 0 {
          if word == "extern" {
            // An `extern "abi"` prefix may be split from its `fn`; the
            // state survives the quoted ABI and the next word releases it.
            pending_extern_declaration = true
            pending_function_prefix_line = 0
            pending_function_prefix_paren_depth = 0
          } else if word == "declare" {
            pending_bodyless_declaration = true
            pending_bodyless_saw_fn = false
            pending_function_prefix_line = 0
            pending_function_prefix_paren_depth = 0
            pending_impl_start_line = 0
            pending_impl_saw_with = false
          } else if pending_bodyless_declaration &&
            !pending_bodyless_saw_fn &&
            word == "fn" {
            // Keep the bodyless state through `fn` so comments split from
            // the declared name stay inside the declaration; the word after
            // `fn` — the name — releases it below. Words inside a generic
            // parameter list (`fn[T]`) are skipped, so the release happens
            // at the declared name itself.
            pending_bodyless_saw_fn = true
          } else if pending_bodyless_declaration &&
            !pending_bodyless_saw_fn &&
            (
              word == "pub" ||
              word == "priv" ||
              word == "all" ||
              word == "open" ||
              word == "async"
            ) {
            ()
          } else if pending_bodyless_declaration &&
            expression_nesting_depth == 0 {
            pending_bodyless_declaration = false
            pending_bodyless_saw_fn = false
          } else if pending_bodyless_declaration {
            ()
          } else if function_keyword_line > 0 &&
            function_keyword_bracket_depth == 0 {
            declaration_start_line = function_keyword_line
            function_keyword_line = 0
            paren_depth = 0
            bracket_depth = 0
          } else if word == "pub" || word == "priv" || word == "async" {
            if pending_function_prefix_line == 0 {
              pending_function_prefix_line = line_number
            }
          } else if pending_function_prefix_line > 0 &&
            pending_function_prefix_paren_depth > 0 &&
            (word == "all" || word == "open") {
            ()
          } else if word == "impl" {
            pending_impl_start_line = if pending_function_prefix_line > 0 {
              pending_function_prefix_line
            } else {
              line_number
            }
            pending_impl_saw_with = false
            pending_function_prefix_line = 0
            pending_function_prefix_paren_depth = 0
          } else if pending_impl_start_line > 0 && word == "with" {
            pending_impl_saw_with = true
          } else if pending_impl_start_line > 0 &&
            pending_impl_saw_with &&
            word == "async" {
            ()
          } else if pending_impl_start_line > 0 && word == "fn" {
            function_keyword_line = if pending_impl_saw_with {
              pending_impl_start_line
            } else {
              line_number
            }
            function_keyword_bracket_depth = 0
            pending_impl_start_line = 0
            pending_impl_saw_with = false
          } else if !line_saw_equals && word == "fn" {
            function_keyword_line = if pending_function_prefix_line > 0 {
              pending_function_prefix_line
            } else {
              line_number
            }
            function_keyword_bracket_depth = 0
            pending_function_prefix_line = 0
            pending_function_prefix_paren_depth = 0
          } else if word == "let" || word == "const" {
            // These declarations always take an initializer, so they stay
            // pending — keeping split forms like `let x` + later `= 1` out
            // of comment runs — until their `=` is reached. Bare-completable
            // forms (`type X`, `typealias Int as Id`, tuple structs) are
            // excluded: with no `=` or `{` to release them the state would
            // never clear.
            pending_binding_declaration = true
            pending_function_prefix_line = 0
            pending_function_prefix_paren_depth = 0
          } else {
            pending_function_prefix_line = 0
            pending_function_prefix_paren_depth = 0
          }
        }
        if word != "extern" {
          pending_extern_declaration = false
        }
      } else {
        if function_keyword_line > 0 {
          match code {
            '[' => function_keyword_bracket_depth += 1
            ']' if function_keyword_bracket_depth > 0 =>
              function_keyword_bracket_depth -= 1
            '@' if function_keyword_bracket_depth == 0 => ()
            _ if code != ' ' &&
              code != '\t' &&
              function_keyword_bracket_depth == 0 => {
              function_keyword_line = 0
              function_keyword_bracket_depth = 0
            }
            _ => ()
          }
        }
        if pending_function_prefix_line > 0 && function_keyword_line == 0 {
          match code {
            '(' => pending_function_prefix_paren_depth += 1
            ')' if pending_function_prefix_paren_depth > 0 =>
              pending_function_prefix_paren_depth -= 1
            _ if code != ' ' && code != '\t' => {
              pending_function_prefix_line = 0
              pending_function_prefix_paren_depth = 0
            }
            _ => ()
          }
        }
        if pending_impl_start_line > 0 && function_keyword_line == 0 {
          match code {
            '=' | ';' | '{' => {
              pending_impl_start_line = 0
              pending_impl_saw_with = false
            }
            _ => ()
          }
        }
        if declaration_start_line > 0 && body_start_line == 0 {
          match code {
            '(' => paren_depth += 1
            ')' => if paren_depth > 0 { paren_depth -= 1 }
            '[' => bracket_depth += 1
            ']' => if bracket_depth > 0 { bracket_depth -= 1 }
            '=' if paren_depth == 0 && bracket_depth == 0 => {
              declaration_start_line = 0
              pending_function_prefix_line = 0
              pending_function_prefix_paren_depth = 0
              pending_impl_start_line = 0
              pending_impl_saw_with = false
              line_saw_equals = true
            }
            _ => ()
          }
        } else if code == '=' && brace_depth == 0 {
          line_saw_equals = true
          pending_binding_declaration = false
        }
        // Unlike `paren_depth`/`bracket_depth`, which only track an
        // in-progress function signature, this counts every lexical
        // paren/bracket so comment-run detection can see multi-line
        // continuations of non-function declarations.
        match code {
          '(' | '[' => expression_nesting_depth += 1
          ')' | ']' =>
            if expression_nesting_depth > 0 {
              expression_nesting_depth -= 1
            }
          _ => ()
        }
        if code == '{' {
          if brace_depth == 0 &&
            declaration_start_line > 0 &&
            body_start_line == 0 &&
            paren_depth == 0 &&
            bracket_depth == 0 {
            body_start_line = line_number
          }
          if brace_depth == 0 && declaration_start_line == 0 {
            pending_bodyless_declaration = false
            pending_bodyless_saw_fn = false
            pending_binding_declaration = false
            pending_extern_declaration = false
            pending_function_prefix_line = 0
            pending_function_prefix_paren_depth = 0
            pending_impl_start_line = 0
            pending_impl_saw_with = false
          }
          brace_depth += 1
        } else if code == '}' && brace_depth > 0 {
          brace_depth -= 1
          if brace_depth == 0 && body_start_line > 0 {
            folds.push({
              declaration_start_line_number: declaration_start_line,
              body_start_line_number: body_start_line,
              body_end_line_number: line_number,
            })
            function_keyword_line = 0
            function_keyword_bracket_depth = 0
            pending_function_prefix_line = 0
            pending_function_prefix_paren_depth = 0
            pending_impl_start_line = 0
            pending_impl_saw_with = false
            declaration_start_line = 0
            body_start_line = 0
            paren_depth = 0
            bracket_depth = 0
          }
        }
        index += 1
      }
    }
    if joins_comment_run {
      if comment_run_start_line == 0 {
        comment_run_start_line = line_number
      }
    } else if line_last_code == 0 {
      // A trivia line — blank, doc-comment-only, or block-comment-only —
      // ends the run but defers the accept/discard decision until the next
      // meaningful line: every queued run before a continuation line (an
      // `else` arm after a commented gap) belongs to that construct.
      if comment_run_start_line > 0 && line_number - 1 > comment_run_start_line {
        deferred_comment_runs.push({
          start_line_number: comment_run_start_line,
          end_line_number: line_number - 1,
        })
      }
      comment_run_start_line = 0
    } else {
      // A run terminated by a leading-operator line (`-> Int`, `.chain()`,
      // `= 1`) sits inside that continued construct and is discarded, along
      // with every run queued across the trivia gap above it — the previous
      // line's tail cannot reveal this kind of split.
      let continues_construct = is_moonbit_leading_continuation_line(line)
      if !continues_construct {
        for deferred_run in deferred_comment_runs {
          comment_runs.push(deferred_run)
        }
      }
      deferred_comment_runs.clear()
      if comment_run_start_line > 0 &&
        line_number - 1 > comment_run_start_line &&
        !continues_construct {
        comment_runs.push({
          start_line_number: comment_run_start_line,
          end_line_number: line_number - 1,
        })
      }
      comment_run_start_line = 0
    }
    // Only a line that ends at the top level updates the continuation
    // state; lines ending inside braces or brackets leave it untouched, and
    // blank or comment-only lines carry it forward. A line ending inside a
    // block comment still updates from its pre-comment tail — in
    // `let value = /* explanation` the `=` is the meaningful signal.
    if line_last_code != 0 && brace_depth == 0 && expression_nesting_depth == 0 {
      pending_expression_continuation = is_moonbit_expression_continuation_code(
          line_last_code,
        ) ||
        moonbit_line_ends_with_continuation_word(
          line, line_last_code, line_last_code_index,
        )
    }
  }
  for deferred_run in deferred_comment_runs {
    comment_runs.push(deferred_run)
  }
  if comment_run_start_line > 0 &&
    snapshot.line_count() > comment_run_start_line {
    comment_runs.push({
      start_line_number: comment_run_start_line,
      end_line_number: snapshot.line_count(),
    })
  }
  { function_bodies: folds, comment_runs, }
}

///|
/// Whether the regions already carry host-computed MoonBit outline folds —
/// function bodies or comment runs — meaning the outline transform has been
/// applied to this generation of ranges.
fn has_moonbit_outline_folding_ranges(
  regions : @folding_browser.FoldingRegions,
) -> Bool {
  for index in 0..<regions.length() {
    if regions.get_type(index) is Some(range_type) &&
      (
        range_type == @folding_browser.OUTLINE_BODY_FOLDING_RANGE_TYPE ||
        range_type == COMMENT_RUN_FOLDING_RANGE_TYPE
      ) {
      return true
    }
  }
  false
}

///|
/// One host-computed outline fold in document order. Function bodies protect
/// their declaration lines and fold from the opening-brace line; comment runs
/// protect only their own span and fold from their first line.
priv struct MoonbitOutlineFold {
  /// First line of the protected construct. Provider ranges reaching into
  /// `protected_start_line_number..=fold_end_line_number` are replaced by the
  /// host fold unless they sit strictly inside the folded span.
  protected_start_line_number : Int
  fold_start_line_number : Int
  fold_end_line_number : Int
  range_type : String
}

///|
fn MoonbitCommentRunFold::to_outline_fold(
  self : MoonbitCommentRunFold,
) -> MoonbitOutlineFold {
  {
    protected_start_line_number: self.start_line_number,
    fold_start_line_number: self.start_line_number,
    fold_end_line_number: self.end_line_number,
    range_type: COMMENT_RUN_FOLDING_RANGE_TYPE,
  }
}

///|
/// Merges the two document-ordered, mutually disjoint scan results into one
/// document-ordered host-fold list.
fn moonbit_outline_folds(
  source_folds : MoonbitSourceFolds,
) -> Array[MoonbitOutlineFold] {
  let outline_folds : Array[MoonbitOutlineFold] = []
  let mut comment_index = 0
  for body_fold in source_folds.function_bodies {
    while comment_index < source_folds.comment_runs.length() &&
          source_folds.comment_runs[comment_index].start_line_number <
          body_fold.declaration_start_line_number {
      outline_folds.push(
        source_folds.comment_runs[comment_index].to_outline_fold(),
      )
      comment_index += 1
    }
    outline_folds.push({
      protected_start_line_number: body_fold.declaration_start_line_number,
      fold_start_line_number: body_fold.body_start_line_number,
      fold_end_line_number: body_fold.body_end_line_number,
      range_type: @folding_browser.OUTLINE_BODY_FOLDING_RANGE_TYPE,
    })
  }
  while comment_index < source_folds.comment_runs.length() {
    outline_folds.push(
      source_folds.comment_runs[comment_index].to_outline_fold(),
    )
    comment_index += 1
  }
  outline_folds
}

///|
/// Replaces provider folds that would hide a function header or split a
/// plain-comment run with host folds: bodies fold from the opening-brace
/// line, comment runs from their first comment line. Ordinary ranges outside
/// each construct and nested ranges strictly inside a folded span retain
/// their current state.
fn moonbit_outline_folding_regions(
  snapshot : @model.TextSnapshot,
  regions : @folding_browser.FoldingRegions,
  limit : Int,
) -> @folding_browser.FoldingRegions {
  let outline_folds = moonbit_outline_folds(moonbit_source_folds(snapshot))
  if outline_folds.length() == 0 || has_moonbit_outline_folding_ranges(regions) {
    return regions
  }
  let capped_limit = limit.max(0).min(@folding_browser.MAX_FOLDING_REGIONS)
  if capped_limit == 0 && regions.length() == 0 {
    return regions
  }
  let retained_ranges : Array[@folding_browser.FoldRange] = []
  let mut outline_index = 0
  for index in 0..<regions.length() {
    let range = regions.to_fold_range(index)
    while outline_index < outline_folds.length() &&
          outline_folds[outline_index].fold_end_line_number <
          range.start_line_number() {
      outline_index += 1
    }
    // Retain the provider range only when every host fold it overlaps
    // agrees: nested strictly inside the folded span, or — for comment runs
    // only — strictly containing the whole run, so a wider provider range
    // (a region-marker style block) keeps its body with the run nested
    // beneath it. Ranges that reach into a function's protected span or
    // cross a fold boundary are replaced by the host folds.
    let mut retain = true
    let mut scan_index = outline_index
    while scan_index < outline_folds.length() &&
          outline_folds[scan_index].protected_start_line_number <=
          range.end_line_number() {
      let outline_fold = outline_folds[scan_index]
      if range.start_line_number() > outline_fold.fold_start_line_number &&
        range.end_line_number() <= outline_fold.fold_end_line_number {
        break
      }
      // Containment requires a strictly earlier start: a provider range
      // sharing the run's first line would pair two folds on one start
      // line, and `sanitize_and_merge` matches prior state by start line.
      let contains_comment_run = outline_fold.range_type ==
        COMMENT_RUN_FOLDING_RANGE_TYPE &&
        range.start_line_number() < outline_fold.protected_start_line_number &&
        range.end_line_number() >= outline_fold.fold_end_line_number
      if !contains_comment_run {
        retain = false
        break
      }
      scan_index += 1
    }
    if retain {
      retained_ranges.push(range)
    }
  }

  let foldable_outline_folds : Array[MoonbitOutlineFold] = []
  for outline_fold in outline_folds {
    if outline_fold.fold_end_line_number > outline_fold.fold_start_line_number {
      foldable_outline_folds.push(outline_fold)
    }
  }
  // Both inputs are already in document order. Merge them directly and stop
  // at the configured/provider limit instead of sorting or allowing host
  // ranges to bypass the limit enforced by the indentation provider. A body
  // that closes on its opening-brace line protects the signature above but
  // contributes no zero-height replacement range here.
  let ranges : Array[@folding_browser.FoldRange] = []
  let mut retained_index = 0
  outline_index = 0
  while ranges.length() < capped_limit &&
        (
          retained_index < retained_ranges.length() ||
          outline_index < foldable_outline_folds.length()
        ) {
    let take_outline = if outline_index == foldable_outline_folds.length() {
      false
    } else if retained_index == retained_ranges.length() {
      true
    } else {
      let outline_fold = foldable_outline_folds[outline_index]
      let retained = retained_ranges[retained_index]
      outline_fold.fold_start_line_number < retained.start_line_number() ||
      (
        outline_fold.fold_start_line_number == retained.start_line_number() &&
        outline_fold.fold_end_line_number >= retained.end_line_number()
      )
    }
    if take_outline {
      let outline_fold = foldable_outline_folds[outline_index]
      ranges.push(
        FoldRange(
          outline_fold.fold_start_line_number,
          outline_fold.fold_end_line_number,
          type_=outline_fold.range_type,
        ),
      )
      outline_index += 1
    } else {
      ranges.push(retained_ranges[retained_index])
      retained_index += 1
    }
  }
  @folding_browser.FoldingRegions::from_fold_ranges(ranges)
}
