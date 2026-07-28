# jq Specification Reference

## Official Documentation

- [jq Manual](https://stedolan.github.io/jq/manual/) - Complete reference for jq syntax and built-in functions
- [jq Wiki](https://github.com/stedolan/jq/wiki) - Community documentation and examples
- [jq Cookbook](https://github.com/stedolan/jq/wiki/Cookbook) - Common patterns and recipes
- [jq GitHub Repository](https://github.com/stedolan/jq) - Source code and issues

## Language Overview

jq is a lightweight and flexible command-line JSON processor. It allows you to
slice, filter, map, and transform structured data with the same ease that sed,
awk, grep, and friends let you manipulate text.

### Basic Filters

| Filter | Description |
|--------|-------------|
| `.` | Identity - returns input unchanged |
| `.foo` | Object field access |
| `.foo.bar` | Nested field access |
| `.[2]` | Array index (0-based) |
| `.[-1]` | Negative index (from end) |
| `.[2:4]` | Array slice |
| `.[]` | Iterate over array/object values |

### Operators

| Operator | Description |
|----------|-------------|
| `\|` | Pipe - send output of left to input of right |
| `,` | Comma - output results from both expressions |
| `+`, `-`, `*`, `/`, `%` | Arithmetic |
| `==`, `!=`, `<`, `<=`, `>`, `>=` | Comparison |
| `and`, `or`, `not` | Logical |
| `//` | Alternative (null coalescing) |
| `\|=`, `=`, `+=`, `-=`, etc. | Update operators |

### Types

jq operates on JSON values:
- `null`
- `boolean` (true, false)
- `number` (integers and floats)
- `string`
- `array`
- `object`

The `type` built-in returns the type name as a string.

### Control Flow

```jq
if condition then expr else expr end
if cond1 then expr1 elif cond2 then expr2 else expr3 end
try expr catch handler
```

### Variables and Reduce

```jq
expr as $var | ...           # Bind value to variable
reduce .[] as $x (init; update)  # Reduce array to single value
foreach .[] as $x (init; update) # Running totals
```

### User-defined Functions

```jq
def name: body;              # Simple function
def name(arg): body;         # Function with argument
def name(a; b): body;        # Multiple arguments (semicolon-separated)
```

### Format Strings

| Format | Description |
|--------|-------------|
| `@base64` | Base64 encode |
| `@base64d` | Base64 decode |
| `@uri` | URI/URL encode |
| `@json` | JSON encode |
| `@text` | Convert to string |
| `@csv` | CSV format |
| `@html` | HTML escape |

## Test Categories

Tests in this module are organized by category:

### Valid tests
- `valid/identity/*` - Identity and literal tests
- `valid/field/*` - Field access tests
- `valid/array/*` - Array operation tests
- `valid/ops/*` - Operator tests
- `valid/builtins/*` - Built-in function tests
- `valid/string/*` - String operation tests
- `valid/object/*` - Object operation tests
- `valid/control/*` - Control flow tests
- `valid/vars/*` - Variable and reduce tests
- `valid/advanced/*` - Advanced features
- `valid/update/*` - Update operator tests
- `valid/format/*` - Format string tests
- `valid/functions/*` - User-defined function tests
- `valid/interpolation/*` - String interpolation tests
- `valid/regex/*` - Regex operation tests
- `valid/iteration/*` - Iteration helper tests
- `valid/predicates/*` - Predicate tests
- `valid/misc/*` - Miscellaneous tests

### Invalid tests
- `invalid/parse/*` - Parse error tests
- `invalid/eval/*` - Evaluation error tests

## Implementation Notes

### Multiple Outputs

jq produces multiple outputs for certain operations (e.g., `.[]` on arrays).
The `run` function returns `Array[Json]` collecting all results.

### Error Handling

The `run` function uses `raise` to signal errors:
- Parse errors (invalid syntax)
- Evaluation errors (type mismatches, missing keys, etc.)
