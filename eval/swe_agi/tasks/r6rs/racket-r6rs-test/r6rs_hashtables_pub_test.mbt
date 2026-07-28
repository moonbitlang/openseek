// R6RS Hashtables Tests - extracted from Racket R6RS test suite (public)
// Source: tests/r6rs/hashtables.sls
// Note: Many tests use macros and stateful operations that are difficult to convert directly.
// This file contains simplified tests for basic hashtable operations.

///|
test "r6rs_hashtables/12" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(hashtable-mutable? (make-eq-hashtable))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_hashtables/23" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (equal-hash 1024) (equal-hash (expt 2 10)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_hashtables/31" {
  let result = try? @r6rs.eval_program(
    (
      #|(begin
      #|  (define h (make-eq-hashtable))
      #|  (hashtable-set! h 'a 1)
      #|  (define h2 (hashtable-copy h))
      #|  (hashtable-delete! h2 'a))
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected exception")
  }
}

///|
test "r6rs_hashtables/32" {
  let result = try? @r6rs.eval_program(
    (
      #|(begin
      #|  (define h (make-eq-hashtable))
      #|  (hashtable-set! h 'a 1)
      #|  (define h2 (hashtable-copy h))
      #|  (hashtable-update! h2 'a (lambda (v) v) 'none))
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected exception")
  }
}
