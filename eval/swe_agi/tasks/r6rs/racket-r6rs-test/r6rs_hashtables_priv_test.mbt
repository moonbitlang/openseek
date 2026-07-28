// R6RS Hashtables Tests - extracted from Racket R6RS test suite (private)
// Source: tests/r6rs/hashtables.sls
// Note: Many tests use macros and stateful operations that are difficult to convert directly.
// This file contains simplified tests for basic hashtable operations.

///|
test "r6rs_hashtables/0" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(hashtable? (make-eq-hashtable))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_hashtables/1" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(hashtable? (make-eqv-hashtable))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_hashtables/2" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(hashtable? (make-hashtable (lambda (x) 0) equal?))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_hashtables/3" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(hashtable-size (make-eq-hashtable))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_hashtables/4" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define h (make-eq-hashtable))
          #|  (hashtable-set! h 'a 1)
          #|  (hashtable-ref h 'a 'nope))
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_hashtables/5" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define h (make-eq-hashtable))
          #|  (hashtable-ref h 'a 'nope))
        ),
      ),
    ),
    content="nope",
  )
}

///|
test "r6rs_hashtables/6" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define h (make-eq-hashtable))
          #|  (hashtable-set! h 'a 1)
          #|  (hashtable-contains? h 'a))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_hashtables/7" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define h (make-eq-hashtable))
          #|  (hashtable-contains? h 'a))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_hashtables/8" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define h (make-eq-hashtable))
          #|  (hashtable-set! h 'a 1)
          #|  (hashtable-set! h 'b 2)
          #|  (hashtable-set! h 'c 3)
          #|  (hashtable-size h))
        ),
      ),
    ),
    content="3",
  )
}

///|
test "r6rs_hashtables/9" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define h (make-eq-hashtable))
          #|  (hashtable-set! h 'a 1)
          #|  (hashtable-delete! h 'a)
          #|  (hashtable-contains? h 'a))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_hashtables/10" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define h (make-eq-hashtable))
          #|  (hashtable-set! h 'a 1)
          #|  (hashtable-update! h 'a (lambda (v) (+ v 10)) 0)
          #|  (hashtable-ref h 'a 'nope))
        ),
      ),
    ),
    content="11",
  )
}

///|
test "r6rs_hashtables/11" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define h (make-eq-hashtable))
          #|  (hashtable-update! h 'a (lambda (v) (+ v 10)) 5)
          #|  (hashtable-ref h 'a 'nope))
        ),
      ),
    ),
    content="15",
  )
}

///|
test "r6rs_hashtables/13" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define h (make-eq-hashtable))
          #|  (hashtable-set! h 'a 1)
          #|  (define h2 (hashtable-copy h))
          #|  (hashtable-mutable? h2))
        ),
      ),
    ),
    content="#f",
  )
}

///|
test "r6rs_hashtables/14" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define h (make-eq-hashtable))
          #|  (hashtable-set! h 'a 1)
          #|  (define h2 (hashtable-copy h #t))
          #|  (hashtable-mutable? h2))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_hashtables/15" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define h (make-eq-hashtable))
          #|  (hashtable-set! h 'a 1)
          #|  (hashtable-set! h 'b 2)
          #|  (hashtable-clear! h)
          #|  (hashtable-size h))
        ),
      ),
    ),
    content="0",
  )
}

///|
test "r6rs_hashtables/16" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define h (make-eq-hashtable))
          #|  (hashtable-set! h 'a 1)
          #|  (hashtable-set! h 'b 2)
          #|  (vector-length (hashtable-keys h)))
        ),
      ),
    ),
    content="2",
  )
}

///|
test "r6rs_hashtables/17" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(hashtable? (make-eq-hashtable 10))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_hashtables/18" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(hashtable? (make-eqv-hashtable 10))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_hashtables/19" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(hashtable? (make-hashtable (lambda (x) 0) equal? 10))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_hashtables/20" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define zero (lambda (a) 0))
          #|  (define same? (lambda (a b) #t))
          #|  (define ht (make-hashtable zero same?))
          #|  (eq? (hashtable-equivalence-function ht) same?))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_hashtables/21" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define zero (lambda (a) 0))
          #|  (define same? (lambda (a b) #t))
          #|  (define ht (make-hashtable zero same?))
          #|  (eq? (hashtable-hash-function ht) zero))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_hashtables/22" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (equal-hash "a") (equal-hash (make-string 1 #\a)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_hashtables/24" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (equal-hash '(1 2 3)) (equal-hash (list 1 2 3)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_hashtables/25" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (string-hash "a") (string-hash (make-string 1 #\a)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_hashtables/26" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (string-hash "aaaaa") (string-hash (make-string 5 #\a)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_hashtables/27" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (string-ci-hash "aAaAA") (string-ci-hash (make-string 5 #\a)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_hashtables/28" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (string-ci-hash "aAaAA") (string-ci-hash (make-string 5 #\A)))
        ),
      ),
    ),
    content="#t",
  )
}

///|
test "r6rs_hashtables/29" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(= (symbol-hash 'a) (symbol-hash 'a))
        ),
      ),
    ),
    content="#t",
  )
}

// Tests for immutable hashtable violations

///|
test "r6rs_hashtables/30" {
  let result = try? @r6rs.eval_program(
    (
      #|(begin
      #|  (define h (make-eq-hashtable))
      #|  (hashtable-set! h 'a 1)
      #|  (define h2 (hashtable-copy h))
      #|  (hashtable-set! h2 'a 2))
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected exception")
  }
}

///|
test "r6rs_hashtables/33" {
  let result = try? @r6rs.eval_program(
    (
      #|(begin
      #|  (define h (make-eq-hashtable))
      #|  (hashtable-set! h 'a 1)
      #|  (define h2 (hashtable-copy h))
      #|  (hashtable-clear! h2))
    ),
  )
  match result {
    Err(_) => ()
    Ok(_) => fail("Expected exception")
  }
}

// Tests with eqv-hashtable

///|
test "r6rs_hashtables/34" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define h (make-eqv-hashtable))
          #|  (hashtable-set! h #\a 1)
          #|  (hashtable-ref h #\a 'nope))
        ),
      ),
    ),
    content="1",
  )
}

///|
test "r6rs_hashtables/35" {
  inspect(
    @r6rs.value_to_string(
      @r6rs.eval_program(
        (
          #|(begin
          #|  (define h (make-eqv-hashtable))
          #|  (hashtable-set! h 123456789101112 'big-num)
          #|  (hashtable-ref h 123456789101112 'nope))
        ),
      ),
    ),
    content="big-num",
  )
}
