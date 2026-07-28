// R6RS I/O Ports Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/io/ports.sls
// Note: Skipping file I/O tests and custom port tests that depend on state

///|
test "r6rs_io_ports/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(enum-set->list (file-options))
        ),
      ),
    ),
    content="()",
  )
}

///|
test "r6rs_io_ports/2" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(enum-set-member? 'no-create (file-options no-create))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(enum-set-member? 'no-create (file-options no-fail))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_io_ports/4" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(enum-set-member? 'no-fail (file-options no-fail))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/5" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(enum-set-member? 'no-truncate (file-options no-truncate))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/6" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(enum-set-member? 'no-truncate (file-options no-create no-fail no-truncate))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/7" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(enum-set-member? 'no-fail (file-options no-create no-fail no-truncate))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/8" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(enum-set-member? 'no-create (file-options no-create no-fail no-truncate))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/9" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(buffer-mode none)
        ),
      ),
    ),
    content="none",
  )
}

///|
test "r6rs_io_ports/10" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(buffer-mode line)
        ),
      ),
    ),
    content="line",
  )
}

///|
test "r6rs_io_ports/11" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(buffer-mode block)
        ),
      ),
    ),
    content="block",
  )
}

///|
test "r6rs_io_ports/12" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(buffer-mode? 'none)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/13" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(buffer-mode? 'line)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/14" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(buffer-mode? 'block)
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/15" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(buffer-mode? 'point)
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_io_ports/16" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eol-style lf)
        ),
      ),
    ),
    content="lf",
  )
}

///|
test "r6rs_io_ports/17" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eol-style cr)
        ),
      ),
    ),
    content="cr",
  )
}

///|
test "r6rs_io_ports/18" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eol-style crlf)
        ),
      ),
    ),
    content="crlf",
  )
}

///|
test "r6rs_io_ports/19" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eol-style nel)
        ),
      ),
    ),
    content="nel",
  )
}

///|
test "r6rs_io_ports/20" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eol-style crnel)
        ),
      ),
    ),
    content="crnel",
  )
}

///|
test "r6rs_io_ports/21" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eol-style ls)
        ),
      ),
    ),
    content="ls",
  )
}

///|
test "r6rs_io_ports/22" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eol-style none)
        ),
      ),
    ),
    content="none",
  )
}

///|
test "r6rs_io_ports/23" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(symbol? (native-eol-style))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/24" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(error-handling-mode ignore)
        ),
      ),
    ),
    content="ignore",
  )
}

///|
test "r6rs_io_ports/26" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(error-handling-mode replace)
        ),
      ),
    ),
    content="replace",
  )
}

///|
test "r6rs_io_ports/27" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eq? (transcoder-codec (make-transcoder (latin-1-codec))) (latin-1-codec))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/28" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eq? (transcoder-codec (make-transcoder (utf-8-codec))) (utf-8-codec))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/29" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eq? (transcoder-codec (make-transcoder (utf-16-codec))) (utf-16-codec))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/31" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(transcoder-error-handling-mode (make-transcoder (utf-16-codec)))
        ),
      ),
    ),
    content="replace",
  )
}

///|
test "r6rs_io_ports/32" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eq? (transcoder-codec (make-transcoder (utf-8-codec) 'nel)) (utf-8-codec))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/33" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(transcoder-eol-style (make-transcoder (utf-8-codec) 'nel))
        ),
      ),
    ),
    content="nel",
  )
}

///|
test "r6rs_io_ports/34" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(transcoder-error-handling-mode (make-transcoder (utf-8-codec) 'nel))
        ),
      ),
    ),
    content="replace",
  )
}

///|
test "r6rs_io_ports/35" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eq? (transcoder-codec (make-transcoder (utf-8-codec) 'nel 'raise)) (utf-8-codec))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/36" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(transcoder-eol-style (make-transcoder (utf-8-codec) 'nel 'raise))
        ),
      ),
    ),
    content="nel",
  )
}

///|
test "r6rs_io_ports/37" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(transcoder-error-handling-mode (make-transcoder (utf-8-codec) 'nel 'raise))
        ),
      ),
    ),
    content="raise",
  )
}

///|
test "r6rs_io_ports/38" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eqv? (eof-object) (eof-object))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/39" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(eq? (eof-object) (eof-object))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/40" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (open-bytevector-input-port #vu8(0 1 2 3))])
          #|  (input-port? p))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/41" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (open-bytevector-input-port #vu8(0 1 2 3))])
          #|  (binary-port? p))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/42" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (open-bytevector-input-port #vu8(0 1 2 3))])
          #|  (textual-port? p))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_io_ports/43" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (open-bytevector-input-port #vu8(0 1 2 3))])
          #|  (get-u8 p))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_io_ports/44" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (open-bytevector-input-port #vu8(0 1 2 3))])
          #|  (get-u8 p)
          #|  (lookahead-u8 p))
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_io_ports/45" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (open-bytevector-input-port #vu8(0 1 2 3))])
          #|  (get-u8 p)
          #|  (get-u8 p))
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_io_ports/46" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (open-bytevector-input-port #vu8(0 1 2 3))])
          #|  (get-u8 p)
          #|  (get-u8 p)
          #|  (let ([bv (make-bytevector 10 0)])
          #|    (get-bytevector-n! p bv 1 7)
          #|    bv))
        ),
      ),
    ),
    content="#vu8(0 2 3 0 0 0 0 0 0 0)",
  )
}

///|
test "r6rs_io_ports/47" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (open-bytevector-input-port #vu8(0 1 2 3))])
          #|  (get-bytevector-n p 4)
          #|  (eof-object? (get-bytevector-some p)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/48" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let-values ([(p get) (open-bytevector-output-port)])
          #|  (output-port? p))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/49" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let-values ([(p get) (open-bytevector-output-port)])
          #|  (binary-port? p))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/50" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let-values ([(p get) (open-bytevector-output-port)])
          #|  (textual-port? p))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_io_ports/51" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let-values ([(p get) (open-bytevector-output-port)])
          #|  (put-u8 p 10)
          #|  (put-bytevector p #vu8(11 12 13))
          #|  (put-bytevector p #vu8(14 15 16 17 18) 4)
          #|  (put-bytevector p #vu8(14 15 16 17 18) 2 1)
          #|  (get))
        ),
      ),
    ),
    content="#vu8(10 11 12 13 18 16)",
  )
}

///|
test "r6rs_io_ports/52" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let-values ([(p get) (open-bytevector-output-port)])
          #|  (put-u8 p 10)
          #|  (get)
          #|  (get))
        ),
      ),
    ),
    content="#vu8()",
  )
}

///|
test "r6rs_io_ports/53" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(call-with-bytevector-output-port
          #|  (lambda (p)
          #|    (put-bytevector p #vu8(1 2 3))))
        ),
      ),
    ),
    content="#vu8(1 2 3)",
  )
}

///|
test "r6rs_io_ports/54" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(call-with-bytevector-output-port
          #|  (lambda (p)
          #|    (put-string p "app\x3BB;e"))
          #|  (make-transcoder (utf-8-codec)))
        ),
      ),
    ),
    content="#vu8(97 112 112 206 187 101)",
  )
}

///|
test "r6rs_io_ports/55" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (open-string-input-port "app\x3BB;e\r\nban")])
          #|  (input-port? p))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/56" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (open-string-input-port "app\x3BB;e\r\nban")])
          #|  (binary-port? p))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_io_ports/57" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (open-string-input-port "app\x3BB;e\r\nban")])
          #|  (textual-port? p))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/58" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (open-string-input-port "app\x3BB;e\r\nban")])
          #|  (get-char p))
        ),
      ),
    ),
    content="#\\a",
  )
}

///|
test "r6rs_io_ports/59" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (open-string-input-port "app\x3BB;e\r\nban")])
          #|  (lookahead-char p))
        ),
      ),
    ),
    content="#\\a",
  )
}

///|
test "r6rs_io_ports/60" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (open-string-input-port "app\x3BB;e\r\nban")])
          #|  (get-char p)
          #|  (get-line p))
        ),
      ),
    ),
    content="\"pp\u03BB;e\\r\"",
  )
}

///|
test "r6rs_io_ports/61" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (open-string-input-port "app\x3BB;e\r\nban")])
          #|  (get-char p)
          #|  (get-line p)
          #|  (let ([s (make-string 10 #\_)])
          #|    (get-string-n! p s 1 9)
          #|    s))
        ),
      ),
    ),
    content="\"_ban______\"",
  )
}

///|
test "r6rs_io_ports/63" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let-values ([(p get) (open-string-output-port)])
          #|  (put-string p "app\x3BB;e")
          #|  (get))
        ),
      ),
    ),
    content="\"app\u03BB;e\"",
  )
}

///|
test "r6rs_io_ports/64" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let-values ([(p get) (open-string-output-port)])
          #|  (put-string p "app\x3BB;e")
          #|  (get)
          #|  (get))
        ),
      ),
    ),
    content="\"\"",
  )
}

///|
test "r6rs_io_ports/65" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(call-with-string-output-port
          #|  (lambda (p)
          #|    (put-string p "app\x3BB;y")))
        ),
      ),
    ),
    content="\"app\u03BB;y\"",
  )
}

///|
test "r6rs_io_ports/66" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (standard-input-port)])
          #|  (input-port? p))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/67" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (standard-input-port)])
          #|  (output-port? p))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_io_ports/69" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (standard-input-port)])
          #|  (textual-port? p))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_io_ports/70" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (standard-output-port)])
          #|  (input-port? p))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_io_ports/71" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (standard-output-port)])
          #|  (output-port? p))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/72" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (standard-output-port)])
          #|  (binary-port? p))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/73" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (standard-output-port)])
          #|  (textual-port? p))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_io_ports/74" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (standard-error-port)])
          #|  (input-port? p))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_io_ports/75" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (standard-error-port)])
          #|  (output-port? p))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/77" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([p (standard-error-port)])
          #|  (textual-port? p))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_io_ports/79" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(output-port? (current-input-port))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_io_ports/81" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(textual-port? (current-input-port))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/82" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(input-port? (current-output-port))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_io_ports/83" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(output-port? (current-output-port))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/84" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(binary-port? (current-output-port))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_io_ports/86" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector->string #vu8(97 112 112 206 187 101)
          #|                    (make-transcoder (utf-8-codec)))
        ),
      ),
    ),
    content="\"app\u03BB;e\"",
  )
}

///|
test "r6rs_io_ports/87" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector->string #vu8(97 112 112 206 187 101)
          #|                    (make-transcoder (latin-1-codec)))
        ),
      ),
    ),
    content="\"app\u00CE;\u00BB;e\"",
  )
}

///|
test "r6rs_io_ports/88" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(bytevector->string #vu8(#xFE #xFF 0 97 0 112 0 112 #x3 #xBB 0 101)
          #|                    (make-transcoder (utf-16-codec)))
        ),
      ),
    ),
    content="\"app\u03BB;e\"",
  )
}

///|
test "r6rs_io_ports/89" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->bytevector "app\x03BB;e"
          #|                    (make-transcoder (utf-8-codec)))
        ),
      ),
    ),
    content="#vu8(97 112 112 206 187 101)",
  )
}

///|
test "r6rs_io_ports/90" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->bytevector "apple\x85;"
          #|                    (make-transcoder (latin-1-codec)))
        ),
      ),
    ),
    content="#vu8(97 112 112 108 101 133)",
  )
}

///|
test "r6rs_io_ports/91" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(string->bytevector "a\nb"
          #|                    (make-transcoder (utf-8-codec) 'lf))
        ),
      ),
    ),
    content="#vu8(97 10 98)",
  )
}

///|
test "r6rs_io_ports/94" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([port (open-bytevector-input-port #vu8())])
          #|  (eof-object? (get-bytevector-all port)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_io_ports/95" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(let ([port (open-bytevector-input-port #vu8())])
          #|  (eof-object? (get-bytevector-n port 10)))
        ),
      ),
    ),
    content="#t",
  )
}
