#lang racket

;; R6RS Test Verification Script
;; Extracts input/output from MoonBit test cases and verifies against Racket R6RS
;;
;; Usage:
;;   racket verify-r6rs-tests.rkt [options]
;;
;; Options:
;;   --dir PATH       Directory with .mbt files (default: current dir)
;;   --verbose        Show all test results
;;   --only-failures  Show only failures
;;   --filter PATTERN Only run matching tests

(require racket/cmdline
         racket/format
         racket/string
         racket/match
         racket/port
         racket/file)

;; ============================================================================
;; Configuration and CLI
;; ============================================================================

(define current-dir (make-parameter "."))
(define verbose? (make-parameter #f))
(define only-failures? (make-parameter #f))
(define filter-pattern (make-parameter #f))

;; ANSI color codes
(define (color-green s) (format "\033[32m~a\033[0m" s))
(define (color-red s) (format "\033[31m~a\033[0m" s))
(define (color-yellow s) (format "\033[33m~a\033[0m" s))
(define (color-cyan s) (format "\033[36m~a\033[0m" s))
(define (color-bold s) (format "\033[1m~a\033[0m" s))

;; ============================================================================
;; Test Result Types
;; ============================================================================

(struct test-result (name type status expected actual message) #:transparent)

;; Test types
(define TEST-NORMAL 'normal)
(define TEST-EXCEPTION 'exception)
(define TEST-UNSPECIFIED 'unspecified)
(define TEST-MULTI-VALUES 'multi-values)

;; Test status
(define STATUS-PASS 'pass)
(define STATUS-FAIL 'fail)
(define STATUS-SKIP 'skip)
(define STATUS-ERROR 'error)

;; ============================================================================
;; Parsing Module - Extract tests from .mbt files
;; ============================================================================

;; Read entire .mbt file as string
(define (read-mbt-file path)
  (file->string path))

;; Extract all test blocks from file content
;; Returns list of (test-name test-body)
(define (extract-tests content)
  ;; Match test blocks: test "name" { ... }
  ;; Need to handle nested braces
  (define test-start-rx #px"test\\s+\"([^\"]+)\"\\s*\\{")

  (let loop ([pos 0] [tests '()])
    (define match (regexp-match-positions test-start-rx content pos))
    (if (not match)
        (reverse tests)
        (let* ([name-match (regexp-match test-start-rx (substring content (caar match)))]
               [test-name (cadr name-match)]
               [body-start (cdar match)]
               [body-end (find-matching-brace content body-start)]
               [test-body (if body-end
                              (substring content body-start body-end)
                              "")])
          (loop (or body-end (+ pos 1))
                (cons (list test-name test-body) tests))))))

;; Find matching closing brace
(define (find-matching-brace content start)
  (let loop ([pos start] [depth 1])
    (cond
      [(>= pos (string-length content)) #f]
      [(char=? (string-ref content pos) #\{)
       (loop (+ pos 1) (+ depth 1))]
      [(char=? (string-ref content pos) #\})
       (if (= depth 1)
           pos
           (loop (+ pos 1) (- depth 1)))]
      [else (loop (+ pos 1) depth)])))

;; Classify test type based on body content
(define (classify-test test-body)
  (cond
    ;; Exception test: uses try? and match for Err/Ok
    [(and (regexp-match? #rx"try\\?" test-body)
          (regexp-match? #rx"Err\\(_\\)" test-body))
     TEST-EXCEPTION]
    ;; Unspecified test: let _ = @r6rs.eval_program without inspect
    [(and (regexp-match? #rx"let\\s+_\\s*=" test-body)
          (not (regexp-match? #rx"inspect" test-body)))
     TEST-UNSPECIFIED]
    ;; Multiple values test: uses eval_program_all
    [(regexp-match? #rx"eval_program_all" test-body)
     TEST-MULTI-VALUES]
    ;; Normal test: uses inspect with content=
    [else TEST-NORMAL]))

;; Extract Scheme code from #|... lines
(define (parse-scheme-code test-body)
  ;; Find all #|... patterns and extract content after #|
  (define lines (regexp-match* #px"#\\|([^\n]*)" test-body #:match-select cadr))
  (if (null? lines)
      #f
      (string-join lines "\n")))

;; Extract expected output from content="..."
;; Handles escaped quotes inside the string
(define (parse-expected-output test-body)
  ;; Find content= and extract the string, handling escaped quotes
  (define content-start (regexp-match-positions #px"content\\s*=\\s*\"" test-body))
  (if (not content-start)
      #f
      (let* ([str-start (cdar content-start)]
             [str-end (find-string-end test-body str-start)])
        (if str-end
            (unescape-moonbit-string (substring test-body str-start str-end))
            #f))))

;; Find the end of a MoonBit string, handling escaped characters
(define (find-string-end str start)
  (let loop ([pos start])
    (cond
      [(>= pos (string-length str)) #f]
      [(char=? (string-ref str pos) #\\)
       ;; Escape sequence, skip next char
       (loop (+ pos 2))]
      [(char=? (string-ref str pos) #\")
       pos]
      [else (loop (+ pos 1))])))

;; Extract expected multi-value output from content="val1, val2, ..."
(define (parse-multi-value-expected test-body)
  (define match (regexp-match #px"content\\s*=\\s*\"([^\"]*)\"" test-body))
  (if match
      (string-split (unescape-moonbit-string (cadr match)) ", ")
      #f))

;; Unescape MoonBit string escapes
;; Process character by character to correctly handle escape sequences
;; In MoonBit: \\ = backslash, \n = newline, \t = tab, \r = return, \" = quote
;; Also handles MoonBit Unicode escapes.
(define (unescape-moonbit-string str)
  (let loop ([chars (string->list str)] [result '()])
    (cond
      [(null? chars) (list->string (reverse result))]
      [(and (char=? (car chars) #\\) (pair? (cdr chars)))
       (let ([next (cadr chars)])
         (cond
           [(char=? next #\\) (loop (cddr chars) (cons #\\ result))]
           [(char=? next #\n) (loop (cddr chars) (cons #\newline result))]
           [(char=? next #\t) (loop (cddr chars) (cons #\tab result))]
           [(char=? next #\r) (loop (cddr chars) (cons #\return result))]
           [(char=? next #\") (loop (cddr chars) (cons #\" result))]
           ;; Deprecated MoonBit byte-style hex escape.
           [(char=? next #\x)
            (let ([hex-result (parse-fixed-hex-escape (cddr chars) 2)])
              (if hex-result
                  (loop (cdr hex-result) (cons (integer->char (car hex-result)) result))
                  ;; Invalid hex escape - keep as literal
                  (loop (cddr chars) (cons next (cons #\\ result)))))]
           ;; \uFFFF or \u{HEX} Unicode escape.
           [(char=? next #\u)
            (let ([hex-result (parse-moonbit-unicode-escape (cddr chars))])
              (if hex-result
                  (loop (cdr hex-result) (cons (integer->char (car hex-result)) result))
                  ;; Invalid hex escape - keep as literal
                  (loop (cddr chars) (cons next (cons #\\ result)))))]
           ;; Unknown escape - keep both characters
           [else (loop (cddr chars) (cons next (cons #\\ result)))]))]
      [else (loop (cdr chars) (cons (car chars) result))])))

;; Parse an R6RS-style hex escape: expects chars after \x, ending at ;
;; Returns (value . remaining-chars) or #f.
(define (parse-hex-escape chars)
  (let loop ([cs chars] [hex-chars '()])
    (cond
      [(null? cs) #f]  ; No terminating semicolon
      [(char=? (car cs) #\;)
       (if (null? hex-chars)
           #f  ; Empty hex
           (let ([hex-str (list->string (reverse hex-chars))])
             (let ([val (string->number hex-str 16)])
               (if val
                   (cons val (cdr cs))
                   #f))))]
      [(or (char<=? #\0 (car cs) #\9)
           (char<=? #\a (car cs) #\f)
           (char<=? #\A (car cs) #\F))
       (loop (cdr cs) (cons (car cs) hex-chars))]
      [else #f])))

;; Parse fixed-width MoonBit escapes like \xNN and \uFFFF.
(define (parse-fixed-hex-escape chars len)
  (let loop ([cs chars] [remaining len] [hex-chars '()])
    (cond
      [(= remaining 0)
       (let* ([hex-str (list->string (reverse hex-chars))]
              [val (string->number hex-str 16)])
         (and val (cons val cs)))]
      [(null? cs) #f]
      [(or (char<=? #\0 (car cs) #\9)
           (char<=? #\a (car cs) #\f)
           (char<=? #\A (car cs) #\F))
       (loop (cdr cs) (- remaining 1) (cons (car cs) hex-chars))]
      [else #f])))

;; Parse MoonBit Unicode escapes: \uFFFF or \u{HEX}.
(define (parse-moonbit-unicode-escape chars)
  (cond
    [(and (pair? chars) (char=? (car chars) #\{))
     (let loop ([cs (cdr chars)] [hex-chars '()])
       (cond
         [(null? cs) #f]
         [(char=? (car cs) #\})
          (if (null? hex-chars)
              #f
              (let* ([hex-str (list->string (reverse hex-chars))]
                     [val (string->number hex-str 16)])
                (and val (cons val (cdr cs)))))]
         [(or (char<=? #\0 (car cs) #\9)
              (char<=? #\a (car cs) #\f)
              (char<=? #\A (car cs) #\F))
          (loop (cdr cs) (cons (car cs) hex-chars))]
         [else #f]))]
    [else (parse-fixed-hex-escape chars 4)]))

;; ============================================================================
;; Evaluation Module - Run Scheme code in R6RS environment
;; ============================================================================

;; Convert mutable list to immutable list
(define (mlist->ilist lst)
  (cond
    [(null? lst) '()]
    [(mpair? lst) (cons (mcar lst) (mlist->ilist (mcdr lst)))]
    [else lst]))

;; Helper function for creating bytevectors from lists (handles mutable lists from R6RS)
(define (make-bytevector-from-list lst)
  (apply bytes (mlist->ilist lst)))

;; Create R6RS evaluation namespace
(define (make-r6rs-namespace)
  (define ns (make-base-namespace))
  (parameterize ([current-namespace ns])
    ;; Add our helper function
    (namespace-set-variable-value! 'make-bytevector-from-list make-bytevector-from-list)
    ;; Import R6RS libraries
    (namespace-require 'rnrs/base-6)
    (namespace-require 'rnrs/lists-6)
    (namespace-require 'rnrs/unicode-6)
    (namespace-require 'rnrs/bytevectors-6)
    (namespace-require 'rnrs/sorting-6)
    (namespace-require 'rnrs/control-6)
    (namespace-require 'rnrs/records/syntactic-6)
    (namespace-require 'rnrs/records/procedural-6)
    (namespace-require 'rnrs/exceptions-6)
    (namespace-require 'rnrs/conditions-6)
    (namespace-require 'rnrs/io/simple-6)
    (namespace-require 'rnrs/io/ports-6)
    (namespace-require 'rnrs/arithmetic/fixnums-6)
    (namespace-require 'rnrs/arithmetic/flonums-6)
    (namespace-require 'rnrs/arithmetic/bitwise-6)
    (namespace-require 'rnrs/syntax-case-6)
    (namespace-require 'rnrs/hashtables-6)
    (namespace-require 'rnrs/enums-6)
    (namespace-require 'rnrs/eval-6)
    (namespace-require 'rnrs/mutable-pairs-6)
    (namespace-require 'rnrs/mutable-strings-6)
    (namespace-require 'rnrs/r5rs-6)
    (namespace-require 'rnrs/records/inspection-6)
    (namespace-require 'rnrs/programs-6)
    ns))

;; Global namespace for evaluations
(define r6rs-ns (make-r6rs-namespace))

;; Convert R6RS #\xNN hex char to Racket #\uNNNN or #\UNNNNNNNN format
(define (convert-char-hex match)
  (define hex-str (string-upcase (cadr match)))
  (define len (string-length hex-str))
  (cond
    ;; 5+ digits need #\U with 8 hex digits
    [(> len 4)
     (format "#\\U~a" (string-append (make-string (- 8 len) #\0) hex-str))]
    ;; 4 or fewer digits use #\u with 4 hex digits
    [else
     (format "#\\u~a" (string-append (make-string (- 4 len) #\0) hex-str))]))

;; Convert R6RS string hex escape \xNNNN; to Racket \uNNNN format
(define (convert-string-hex-escapes code)
  (define matches (regexp-match-positions* #rx"\\\\x([0-9a-fA-F]+);" code))
  (if (null? matches)
      code
      (let loop ([pos 0] [ms matches] [result ""])
        (if (null? ms)
            (string-append result (substring code pos))
            (let* ([m (car ms)]
                   [start (car m)]
                   [end (cdr m)]
                   [matched-str (substring code start end)]
                   [hex-match (regexp-match #rx"\\\\x([0-9a-fA-F]+);" matched-str)]
                   [hex-str (string-upcase (cadr hex-match))]
                   [len (string-length hex-str)]
                   ;; Racket uses \uNNNN for BMP, \UNNNNNNNN for supplementary
                   [replacement (cond
                                  [(> len 4)
                                   (format "\\U~a" (string-append (make-string (- 8 len) #\0) hex-str))]
                                  [else
                                   (format "\\u~a" (string-append (make-string (- 4 len) #\0) hex-str))])])
              (loop end (cdr ms) (string-append result (substring code pos start) replacement)))))))

;; Pre-process Scheme code to handle R6RS-specific syntax
(define (preprocess-scheme-code code-str)
  (let* ([code code-str]
         ;; Convert R6RS string hex escapes \xNNNN; to Racket \uNNNN
         [code (convert-string-hex-escapes code)]
         ;; Convert #vu8(...) to (bytes ...) but not when quoted
         ;; First handle quoted case: '#vu8(...) -> (quote-bv ...)
         ;; Then handle unquoted: #vu8(...) -> (bytes ...)
         [code (regexp-replace* #rx"'#vu8\\(([^)]*)\\)" code "(make-bytevector-from-list (list \\1))")]
         [code (regexp-replace* #rx"#vu8\\(([^)]*)\\)" code "(bytes \\1)")]
         ;; Convert R6RS character hex syntax #\xNN to Racket #\uNNNN
         ;; Use match-select to get all matches and process manually
         [matches (regexp-match-positions* #rx"#\\\\x([0-9a-fA-F]+)" code)]
         [code (if (null? matches)
                   code
                   (let loop ([pos 0] [ms matches] [result ""])
                     (if (null? ms)
                         (string-append result (substring code pos))
                         (let* ([m (car ms)]
                                [start (car m)]
                                [end (cdr m)]
                                [matched-str (substring code start end)]
                                [hex-match (regexp-match #rx"#\\\\x([0-9a-fA-F]+)" matched-str)]
                                [replacement (convert-char-hex hex-match)])
                           (loop end (cdr ms) (string-append result (substring code pos start) replacement))))))])
    code))

;; Evaluate R6RS code and return result
;; Returns (list 'ok value) or (list 'error message)
(define (eval-r6rs code-str)
  (with-handlers ([exn:fail? (lambda (e) (list 'error (exn-message e)))])
    (define processed-code (preprocess-scheme-code code-str))
    (define expr (read (open-input-string processed-code)))
    (define result (eval expr r6rs-ns))
    (list 'ok result)))

;; Evaluate R6RS code expecting multiple values
(define (eval-r6rs-multi code-str)
  (with-handlers ([exn:fail? (lambda (e) (list 'error (exn-message e)))])
    (define processed-code (preprocess-scheme-code code-str))
    (define expr (read (open-input-string processed-code)))
    (define results (call-with-values (lambda () (eval expr r6rs-ns)) list))
    (list 'ok results)))

;; Convert Racket value to string (matching MoonBit expected format)
(define (value->string v)
  (cond
    [(eq? v (void)) "#<void>"]
    [(eq? v #t) "#t"]
    [(eq? v #f) "#f"]
    [(null? v) "()"]
    [(symbol? v) (symbol->string v)]
    [(char? v) (char->r6rs-string v)]
    [(string? v) (format "~s" v)]  ; with quotes for string values
    [(number? v) (number->r6rs-string v)]
    [(vector? v) (format "#(~a)" (string-join (map value->string (vector->list v)) " "))]
    [(bytes? v) (format "#vu8(~a)" (string-join (map number->string (bytes->list v)) " "))]
    [(mpair? v) (mpair->string v)]  ; mutable pairs
    [(pair? v) (pair->string v)]
    [(procedure? v) "#<procedure>"]
    [else (format "~s" v)]))

;; Convert character to R6RS representation
(define (char->r6rs-string c)
  (define code (char->integer c))
  (cond
    [(char=? c #\space) "#\\space"]
    [(char=? c #\newline) "#\\newline"]
    [(char=? c #\tab) "#\\tab"]
    [(char=? c #\return) "#\\return"]
    [(= code 7) "#\\alarm"]       ; BEL
    [(= code 8) "#\\backspace"]   ; BS
    [(= code 12) "#\\page"]       ; FF (form feed)
    [(= code 127) "#\\delete"]    ; DEL
    [(= code 27) "#\\esc"]        ; ESC
    [(= code 0) "#\\nul"]         ; NUL
    [(= code 11) "#\\vtab"]       ; VT
    [(and (>= code 33) (<= code 126))  ; printable ASCII
     (format "#\\~a" c)]
    [else
     (format "#\\x~a" (string-upcase (number->string code 16)))]))

;; Convert number to R6RS string representation
(define (number->r6rs-string n)
  (cond
    [(and (inexact? n) (infinite? n))
     (if (positive? n) "+inf.0" "-inf.0")]
    [(and (inexact? n) (nan? n))
     "+nan.0"]
    [(and (inexact? n) (real? n))
     ;; Format floating point - try to match expected format
     (let ([s (number->string n)])
       ;; Remove trailing .0 for whole numbers if needed
       s)]
    [(exact? n)
     (number->string n)]
    [else (number->string n)]))

;; Convert pair/list to string
(define (pair->string p)
  (if (list? p)
      (format "(~a)" (string-join (map value->string p) " "))
      ;; Improper list
      (let loop ([curr p] [parts '()])
        (cond
          [(null? curr)
           (format "(~a)" (string-join (reverse parts) " "))]
          [(pair? curr)
           (loop (cdr curr) (cons (value->string (car curr)) parts))]
          [else
           (format "(~a . ~a)"
                   (string-join (reverse parts) " ")
                   (value->string curr))]))))

;; Check if mutable pair is a proper list
(define (mlist? v)
  (cond
    [(null? v) #t]
    [(mpair? v) (mlist? (mcdr v))]
    [else #f]))

;; Convert mutable pair to immutable list
(define (mlist->list mp)
  (if (null? mp)
      '()
      (cons (mcar mp) (mlist->list (mcdr mp)))))

;; Convert mutable pair/list to string (uses () not {})
(define (mpair->string p)
  (if (mlist? p)
      (format "(~a)" (string-join (map value->string (mlist->list p)) " "))
      ;; Improper mutable list
      (let loop ([curr p] [parts '()])
        (cond
          [(null? curr)
           (format "(~a)" (string-join (reverse parts) " "))]
          [(mpair? curr)
           (loop (mcdr curr) (cons (value->string (mcar curr)) parts))]
          [else
           (format "(~a . ~a)"
                   (string-join (reverse parts) " ")
                   (value->string curr))]))))

;; ============================================================================
;; Comparison Module - Compare actual vs expected results
;; ============================================================================

;; Normalize output for comparison
(define (normalize-output str)
  (string-trim str))

;; Compare results (returns #t if match)
(define (compare-results actual expected)
  (equal? (normalize-output actual) (normalize-output expected)))

;; ============================================================================
;; Runner Module - Execute tests
;; ============================================================================

;; Run a single test case
(define (run-test test-name test-body)
  (define test-type (classify-test test-body))
  (define scheme-code (parse-scheme-code test-body))

  (cond
    ;; Skip if no scheme code found
    [(not scheme-code)
     (test-result test-name test-type STATUS-SKIP #f #f "No Scheme code found")]

    ;; Unspecified test - just check it runs
    [(eq? test-type TEST-UNSPECIFIED)
     (define eval-result (eval-r6rs scheme-code))
     (match eval-result
       [(list 'ok _)
        (test-result test-name test-type STATUS-SKIP #f #f "unspecified behavior")]
       [(list 'error msg)
        (test-result test-name test-type STATUS-SKIP #f #f
                     (format "unspecified (error: ~a)" (truncate-string msg 50)))])]

    ;; Exception test - expect error
    [(eq? test-type TEST-EXCEPTION)
     (define eval-result (eval-r6rs scheme-code))
     (match eval-result
       [(list 'error _)
        (test-result test-name test-type STATUS-PASS "exception" "exception" #f)]
       [(list 'ok v)
        (test-result test-name test-type STATUS-FAIL "exception"
                     (value->string v) "Expected exception but got value")])]

    ;; Multiple values test
    [(eq? test-type TEST-MULTI-VALUES)
     (define expected (parse-multi-value-expected test-body))
     (define eval-result (eval-r6rs-multi scheme-code))
     (match eval-result
       [(list 'error msg)
        (test-result test-name test-type STATUS-ERROR expected #f msg)]
       [(list 'ok values)
        (define actual-strs (map value->string values))
        (define actual-combined (string-join actual-strs ", "))
        (define expected-combined (if expected (string-join expected ", ") ""))
        (if (compare-results actual-combined expected-combined)
            (test-result test-name test-type STATUS-PASS expected-combined actual-combined #f)
            (test-result test-name test-type STATUS-FAIL expected-combined actual-combined #f))])]

    ;; Normal test - compare output
    [else
     (define expected (parse-expected-output test-body))
     (define eval-result (eval-r6rs scheme-code))
     (match eval-result
       [(list 'error msg)
        (test-result test-name test-type STATUS-ERROR expected #f msg)]
       [(list 'ok value)
        (define actual (value->string value))
        (if (not expected)
            (test-result test-name test-type STATUS-SKIP actual #f "No expected output")
            (if (compare-results actual expected)
                (test-result test-name test-type STATUS-PASS expected actual #f)
                (test-result test-name test-type STATUS-FAIL expected actual #f)))])]))

;; Truncate string with ellipsis
(define (truncate-string str max-len)
  (if (<= (string-length str) max-len)
      str
      (string-append (substring str 0 (- max-len 3)) "...")))

;; Run all tests in a file
(define (run-file path)
  (define content (read-mbt-file path))
  (define tests (extract-tests content))
  (define filter-rx (if (filter-pattern)
                        (regexp (filter-pattern))
                        #f))

  (for/list ([test tests]
             #:when (or (not filter-rx)
                        (regexp-match? filter-rx (car test))))
    (run-test (car test) (cadr test))))

;; Run all .mbt files in directory
(define (run-directory dir)
  (define files (directory-list dir))
  (define mbt-files (filter (lambda (f)
                              (regexp-match? #rx"\\.mbt$" (path->string f)))
                            files))
  (for/list ([file mbt-files])
    (cons file (run-file (build-path dir file)))))

;; ============================================================================
;; Reporter Module - Output results
;; ============================================================================

;; Print single test result
(define (print-result result)
  (match-define (test-result name type status expected actual message) result)
  (define status-str
    (case status
      [(pass) (color-green "[PASS]")]
      [(fail) (color-red "[FAIL]")]
      [(skip) (color-yellow "[SKIP]")]
      [(error) (color-red "[ERROR]")]))

  (cond
    [(and (eq? status STATUS-PASS) (not (verbose?)))
     (void)]  ; Silent for passing tests unless verbose
    [(and (eq? status STATUS-SKIP) (only-failures?))
     (void)]  ; Skip skipped tests in only-failures mode
    [else
     (printf "  ~a ~a" status-str name)
     (when message
       (printf " (~a)" message))
     (newline)
     (when (and (eq? status STATUS-FAIL) expected actual)
       (printf "    Expected: ~s~n" expected)
       (printf "    Actual:   ~s~n" actual))
     (when (eq? status STATUS-ERROR)
       (printf "    Error: ~a~n" message))]))

;; Print file results
(define (print-file-results filename results)
  (printf "~nTesting ~a...~n" (color-cyan (path->string filename)))
  (for ([result results])
    (print-result result)))

;; Print summary
(define (print-summary all-results)
  (define flat-results (apply append (map cdr all-results)))
  (define total (length flat-results))
  (define passed (length (filter (lambda (r) (eq? (test-result-status r) STATUS-PASS)) flat-results)))
  (define failed (length (filter (lambda (r) (eq? (test-result-status r) STATUS-FAIL)) flat-results)))
  (define skipped (length (filter (lambda (r) (eq? (test-result-status r) STATUS-SKIP)) flat-results)))
  (define errors (length (filter (lambda (r) (eq? (test-result-status r) STATUS-ERROR)) flat-results)))

  (printf "~n~a~n" (color-bold "============ Summary ============"))
  (printf "Total:   ~a~n" total)
  (printf "~a~n" (color-green (format "Passed:  ~a (~a%)" passed (if (> total 0) (~r (* 100 (/ passed total)) #:precision 1) 0))))
  (printf "~a~n" (color-red (format "Failed:  ~a (~a%)" failed (if (> total 0) (~r (* 100 (/ failed total)) #:precision 1) 0))))
  (printf "~a~n" (color-red (format "Errors:  ~a (~a%)" errors (if (> total 0) (~r (* 100 (/ errors total)) #:precision 1) 0))))
  (printf "~a~n" (color-yellow (format "Skipped: ~a (~a%)" skipped (if (> total 0) (~r (* 100 (/ skipped total)) #:precision 1) 0)))))

;; ============================================================================
;; Main
;; ============================================================================

(define (main)
  (command-line
   #:program "verify-r6rs-tests"
   #:once-each
   [("--dir" "-d") dir "Directory with .mbt files" (current-dir dir)]
   [("--verbose" "-v") "Show all test results" (verbose? #t)]
   [("--only-failures" "-f") "Show only failures" (only-failures? #t)]
   [("--filter" "-p") pattern "Only run matching tests" (filter-pattern pattern)])

  (printf "~a~n" (color-bold "R6RS Test Verification"))
  (printf "Directory: ~a~n" (current-dir))

  (define results (run-directory (current-dir)))

  (for ([file-results results])
    (print-file-results (car file-results) (cdr file-results)))

  (print-summary results)

  ;; Exit with error code if any failures
  (define flat-results (apply append (map cdr results)))
  (define has-failures? (ormap (lambda (r)
                                  (or (eq? (test-result-status r) STATUS-FAIL)
                                      (eq? (test-result-status r) STATUS-ERROR)))
                                flat-results))
  (exit (if has-failures? 1 0)))

(module+ main
  (main))
