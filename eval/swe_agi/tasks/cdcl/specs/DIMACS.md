# DIMACS CNF Syntax Specification (SAT Solver Input)

> DIMACS CNF is one of the most common SAT solver inputs and encodes Boolean formulas in **CNF** (Conjunctive Normal Form).

---

## 1 Basic definitions

- **Variable:** identified by a positive integer `1..N`.
- **Literal:**
  - `k` (positive integer) denotes variable `x_k`
  - `-k` (negative integer) denotes variable `¬x_k`
- **Clause:** a disjunction (OR) of literals, e.g. `(x1 ∨ ¬x3 ∨ x10)`.
- **CNF formula:** a conjunction (AND) of clauses, e.g. `C1 ∧ C2 ∧ ... ∧ Cm`.

DIMACS CNF encodes the CNF formula using:

- A single **problem/header line**: `p cnf N M`
- Followed by `M` clauses, each clause being a list of integers (literals) terminated by the integer `0`

---

## 2 Lexical specification

### 2.1 Character set and encoding

- In practice, DIMACS CNF files are usually **ASCII** or **UTF-8**.
- Avoid a BOM (Byte Order Mark); some parsers do not support BOM.

### 2.2 Whitespace

The following characters MUST be treated as whitespace separators (token separators):

- Space `SP`
- Tab `TAB`
- Line feed `LF`
- Carriage return `CR` (often appears as `CRLF`)

Rules:

- Tokens MUST be separated by at least one whitespace character.
- Any amount of consecutive whitespace is equivalent.
- Clauses may span multiple lines: **newlines are only whitespace**. Clause boundaries are determined by the terminating `0`.

### 2.3 Empty lines

- Empty lines (lines containing only whitespace or having zero length) are allowed.

### 2.4 Comment lines

- A comment line begins with `c`.
- From `c` to the end of the line is comment text and MUST be ignored by the parser.

Recommended (more compatible) rule:

- If the **first non-whitespace character** of a line is `c`, treat the line as a comment line.

Comment lines typically appear before the problem line, but many parsers also allow comments after it.

---

## 3 Syntax specification

### 3.1 Problem line (header)

The header line declares the type, variable count, and clause count:

```text
p cnf <num_vars> <num_clauses>
```

- The keywords `p` and `cnf` MUST appear in this order.
- `<num_vars>` and `<num_clauses>` are non-negative decimal integers (most solvers require them to be positive; see semantic constraints).

### 3.2 Clause data (clause stream)

After the header comes the clause data as a stream of integer tokens.

- Each clause is encoded as: `<lit1> <lit2> ... <litk> 0`
- `0` is the **clause terminator** and is not part of the clause.
- A clause may be empty: a single `0`, which denotes the **empty clause** (making the entire CNF immediately UNSAT).

### 3.3 Literals

- Each literal is a non-zero decimal integer.
- `abs(literal)` is the variable index.

---

## 4 EBNF (implementation reference)

> Note: Because clauses may span lines, a purely line-based grammar is insufficient. The following gives a practical EBNF/pseudogrammar combining line structure with token-stream parsing.

### 4.1 Line-level structure (including comments/empty lines)

```ebnf
file           ::= preamble header clause_part EOF
preamble       ::= { empty_line | comment_line }
header         ::= 'p' wsp+ 'cnf' wsp+ uint wsp+ uint line_end
clause_part    ::= { empty_line | comment_line | clause_tokens }*
comment_line   ::= wsp* 'c' { any_char_except_line_end } line_end
empty_line     ::= wsp* line_end
```

### 4.2 Token stream parsing (for clause_tokens)

From `clause_part`, extract integer tokens from all **non-comment** lines (split by whitespace), forming a token stream.

```ebnf
clauses        ::= clause clause ... (repeat num_clauses times)
clause         ::= { literal wsp+ }* '0'
literal        ::= ['-'] uint_nonzero
uint           ::= digit {digit}
uint_nonzero   ::= nonzero_digit {digit}
wsp            ::= ' ' | '\t' | '\r' | '\n'   (implementations typically treat any whitespace as a separator)
```

---

## 5 Semantic constraints

### 5.1 Header counts

- `N = num_vars`: the maximum declared variable index (the variable set is `1..N`).
- `M = num_clauses`: the declared number of clauses.

Recommended strict constraints:

- The parser MUST read **exactly** `M` clauses (each terminated by `0`).
- If the number of parsed clauses differs from `M`, treat it as a format error.

Common permissive behavior (compatibility; you must define your policy):

- If clauses parsed are more than `M`: error, or ignore extra clauses.
- If clauses parsed are fewer than `M`: usually error (or fail at EOF).

### 5.2 Literal / variable range

Each literal in each clause MUST satisfy:

- `literal != 0`
- `1 <= abs(literal) <= N`

If `abs(literal) > N` appears:

- A strict implementation MUST report an error.
- A permissive implementation MAY auto-extend `N`, but this contradicts the header and is not recommended.

### 5.3 Redundancy and special clauses

- Duplicate literals inside a clause (e.g., `1 1 0`) are allowed; semantically, duplicates can be ignored.
- A clause containing both `k` and `-k` (e.g., `1 -1 0`) is a tautology and always true; it can be removed during preprocessing.
- The empty clause `0` makes the entire CNF immediately UNSAT.

---

## 6 Examples

### 6.1 Minimal example

Encodes `(x1)`:

```dimacs
p cnf 1 1
1 0
```

### 6.2 Example with comments

Encodes `(x1 ∨ ¬x2) ∧ (x2) ∧ (¬x1 ∨ x3)`:

```dimacs
c Example CNF
c (x1 OR ~x2) AND (x2) AND (~x1 OR x3)
p cnf 3 3
1 -2 0
2 0
-1 3 0
```

### 6.3 Clauses spanning lines (still valid)

A single clause may be written across multiple lines as long as it ends with `0`:

```dimacs
p cnf 3 1
1 -2
3 0
```